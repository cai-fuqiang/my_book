# ORG patch

## filesystem -- mount
我们先来看下 `cgroup`的 `file_system_type`:
```cpp
static struct file_system_type cgroup_fs_type = {
        .name = "cgroup",
        .get_sb = cgroup_get_sb,
        .kill_sb = cgroup_kill_sb,
};
```

该`file_system_type`会在`cgroup_init()`流程中调用
```cpp
int __init cgroup_init(void)
{
        ...
        err = register_filesystem(&cgroup_fs_type);
        if (err < 0)
                goto out;
        ...
}
```

`file_system_type.get_sb`会在下面的流程中调用到:
```
sys_mount
  do_mount
    do_new_mount
      do_kern_mount

do_kern_mount {
   //该函数会通过比较 fstype 和 file_system_type->name, 来判断使用
   //哪个 file_system_type, 如果相应的驱动未加载, 还会自动加载驱动
   struct file_system_type *type = get_fs_type(fstype(TYPE:char)
   type->get_sb()
}
```


### cgroup_get_sb -- PART 1
我们继续看下`cgroup_get_sb`, 代码很多, 我们分开看
```cpp
static int cgroup_get_sb(struct file_system_type *fs_type,
                         int flags, const char *unused_dev_name,
                         void *data, struct vfsmount *mnt)
{
        struct cgroup_sb_opts opts;
        int ret = 0;
        struct super_block *sb;
        struct cgroupfs_root *root;
        struct list_head tmp_cg_links, *l;
        INIT_LIST_HEAD(&tmp_cg_links);
        //====(1)====
        /* First find the desired set of subsystems */
        ret = parse_cgroupfs_options(data, &opts);
        if (ret) {
                if (opts.release_agent)
                        kfree(opts.release_agent);
                return ret;
        }

        //====(2)====
        root = kzalloc(sizeof(*root), GFP_KERNEL);
        if (!root)
                return -ENOMEM;

        //====(3)====
        init_cgroup_root(root);
        root->subsys_bits = opts.subsys_bits;
        root->flags = opts.flags;
        //====(4)====
        if (opts.release_agent) {
                strcpy(root->release_agent_path, opts.release_agent);
                kfree(opts.release_agent);
        }
        //====(5)====
        sb = sget(fs_type, cgroup_test_super, cgroup_set_super, root);

        if (IS_ERR(sb)) {
                kfree(root);
                return PTR_ERR(sb);
        }
        ...
```
1. 解析mount 额外的参数, 初始化为`cgroup_sb_opts`

   `struct cgroup_sb_opts`
   ```cpp
   struct cgroup_sb_opts {
           unsigned long subsys_bits;
           unsigned long flags;
           char *release_agent;
   };
   ```
   * **subsys_bits**: 表示用来挂载哪些 subsys(可能不止一个)

   ***
   <details>
   <summary><code>parse_cgroupfs_options</code>代码: </summary>
   <p><font color="red">=====parse_cgroup_options折叠区=====</font></p>

   ```cpp
   /* Convert a hierarchy specifier into a bitmask of subsystems and
    * flags. */
   static int parse_cgroupfs_options(char *data,
                                        struct cgroup_sb_opts *opts)
   {
           char *token, *o = data ?: "all";
   
           opts->subsys_bits = 0;
           opts->flags = 0;
           opts->release_agent = NULL;
           
           //====(1)====
           while ((token = strsep(&o, ",")) != NULL) {
                   //====(2)====
                   if (!*token)
                           return -EINVAL;
                   //====(3)====
                   if (!strcmp(token, "all")) {
                           opts->subsys_bits = (1 << CGROUP_SUBSYS_COUNT) - 1;
                   //====(4.1)====
                   } else if (!strcmp(token, "noprefix")) {
                           set_bit(ROOT_NOPREFIX, &opts->flags);
                   //====(4.2)====
                   } else if (!strncmp(token, "release_agent=", 14)) {
                           /* Specifying two release agents is forbidden */
                           if (opts->release_agent)
                                   return -EINVAL;
                           opts->release_agent = kzalloc(PATH_MAX, GFP_KERNEL);
                           if (!opts->release_agent)
                                   return -ENOMEM;
                           strncpy(opts->release_agent, token + 14, PATH_MAX - 1);
                           opts->release_agent[PATH_MAX - 1] = 0;
                   //====(5)====
                   } else {
                           struct cgroup_subsys *ss;
                           int i;
                           for (i = 0; i < CGROUP_SUBSYS_COUNT; i++) {
                                   ss = subsys[i];
                                   if (!strcmp(token, ss->name)) {
                    //====(6)====
                                           set_bit(i, &opts->subsys_bits);
                                           break;
                                   }
                           }
                           if (i == CGROUP_SUBSYS_COUNT)
                                   return -ENOENT;
                   }
           }
   
           /* We can't have an empty hierarchy */
           if (!opts->subsys_bits)
                   return -EINVAL;
   
           return 0;
   }   
   ```
   1. `mount -t cgroup` 时, 可支持传入多个参数, E.g.
      ```
      cgroup on /sys/fs/cgroup/rdma type cgroup (rw,nosuid,nodev,noexec,relatime,rdma)
      ```
   2. 不允许参数为空
   3. 如果传入的参数为all, 则表示将所有`subsys`挂载到该目录
   4. 这两个不是挂载 `subsys`, 我们暂时不看
   5. 可能传入的是某个 subsys name, 遍历 `subsys[]`, 循环判断
   6. 如果判断是该subsys, 置相关位 (也就是index i -- subsys_id)

   <p><font color="red">=====parse_cgroup_options折叠区=====</font></p>
   </details>

   ***

2. 因为要执行挂载操作, 就意味这要创建一个新的层级, 这时候需要创建
   一个新的 `cgroupfs_root`
3. `init_cgroup_root`代码, 该代码在[init.md](./init.md) 文章中有讲到,
   大概流程是初始化 `cgroupfs_root`, 并初始化`root->top_cgroup`,
   将其作为该root的根层级
4. 和`release_agent`相关, 我们暂时不看
5. 获取supper block, 我们这里还是简单看下`sget()`代码
   <details>
   <summary><code>sget</code>代码: </summary>
   <p><font color="red">=====sget折叠区=====</font></p>

   ```cpp
   /**
    *      sget    -       find or create a superblock
    *      @type:  filesystem type superblock should belong to
    *      @test:  comparison callback
    *      @set:   setup callback
    *      @data:  argument to each of them
    */
   struct super_block *sget(struct file_system_type *type,
                           int (*test)(struct super_block *,void *),
                           int (*set)(struct super_block *,void *),
                           void *data)
   {
           struct super_block *s = NULL;
           struct super_block *old;
           int err;
   
   retry:
           spin_lock(&sb_lock);
           if (test) {
                   //====(1)====
                   list_for_each_entry(old, &type->fs_supers, s_instances) {
                   //====(2)====
                           if (!test(old, data))
                                   continue;
                   //====(3)====
                           if (!grab_super(old))
                                   goto retry;
                   //====(4)====
                           if (s)
                                   destroy_super(s);
                           return old;
                   }
           }
           if (!s) {
                   spin_unlock(&sb_lock);
                   //====(5)====
                   s = alloc_super(type);
                   if (!s)
                           return ERR_PTR(-ENOMEM);
                   goto retry;
           }
   
           //====(6)====
           err = set(s, data);
           if (err) {
                   spin_unlock(&sb_lock);
                   destroy_super(s);
                   return ERR_PTR(err);
           }
           s->s_type = type;
           //====(7)====
           strlcpy(s->s_id, type->name, sizeof(s->s_id));
           //====(8)====
           list_add_tail(&s->s_list, &super_blocks);
           //====(9)====
           list_add(&s->s_instances, &type->fs_supers);
           spin_unlock(&sb_lock);
           get_filesystem(type);
           return s;
   }
   ```
   1. 遍历该 `file_system_type`所有的 `superblock`, 看看是否有相同的
   2. 判断是否相同, 对应 `cgroup`为`cgroup_test_super`
      <details>
      <summary><code>cgroup_test_super</code>代码: </summary>
      <p><font color="red">=====cgroup_test_super折叠区=====</font></p>

      ```cpp
      static int cgroup_test_super(struct super_block *sb, void *data)
      {
              struct cgroupfs_root *new = data;
              struct cgroupfs_root *root = sb->s_fs_info;
      
              /* First check subsystems */
              if (new->subsys_bits != root->subsys_bits)
                  return 0;
      
              /* Next check flags */
              if (new->flags != root->flags)
                      return 0;
      
              return 1;
      }
      ```

      判断条件有两个, `cgroupfs_root->subsys_bits`和`cgroupfs_root->flags`
      > NOTE
      >
      > 通过`parse_cgroupfs_options()`函数我们可知, 如果参数配置了
      > subsys 就不会设置flags, 反之亦然, 所以这两个分支只会成功一个

      <p><font color="red">=====cgroup_test_super折叠区=====</font></p>
      </details>
   3. `grab_super()` !!!
   4. 如果找到了 相同的 `super_block` 这里调用 `destroy_super()`
   5. 走到这里, 说明`test()`没有成功, 调用 `alloc_super()` 分配 superblock
   6. 这里为`cgroup_set_super()`
      <details>
      <summary><code>cgroup_sete_super</code>代码: </summary>
      <p><font color="red">=====cgroup_set_super折叠区=====</font></p>

      ```cpp
      static int cgroup_set_super(struct super_block *sb, void *data)
      {
              int ret;
              struct cgroupfs_root *root = data;
              //====(1)====
              ret = set_anon_super(sb, NULL);
              if (ret)
                      return ret;
      
              sb->s_fs_info = root;
              root->sb = sb;
      
              //====(2)====
              sb->s_blocksize = PAGE_CACHE_SIZE;
              sb->s_blocksize_bits = PAGE_CACHE_SHIFT;
              sb->s_magic = CGROUP_SUPER_MAGIC;
              //====(3)====
              sb->s_op = &cgroup_ops;
      
              return 0;
      }
      ```
      函数主要流程是初始化`super_block`
      1. 调用`set_anon_super()`表示没有具体的block设备
      2. `sb->s_blocksize`为 page cache size的大小
      3. 设置`super_operations` 为`cgroup_ops` (在 [cgroup_ops](#cgroup_ops)一节中会讲到)
      <p><font color="red">=====cgroup_set_super折叠区=====</font></p>
      </details>
   7. 将`type->name` copy给`super_block->s_id`
   8. 将该`super_block`链入`super_blocks`全局链表
   9. 将该`super_block`琏入`type->fs_supers`(该file_system_type下, 方便
      `file_system_type`查询其下所有的`super_block`

   <p><font color="red">=====sget折叠区=====</font></p>
   </details>
### cgroup_get_sb -- PART 2
```cpp
static int cgroup_get_sb(struct file_system_type *fs_type,
                         int flags, const char *unused_dev_name,
                         void *data, struct vfsmount *mnt)
{

        ...
        /*
         * 上面已经获取到 superblock了, 这里有个分支判断
         *
         * 如果sb->s_fs_info != root, 说明super_block
         * 使用的是old的, 这时, 可以reuse 该super_block
         * 将新申请的释放掉
         */
        if (sb->s_fs_info != root) {
                /* Reusing an existing superblock */
                BUG_ON(sb->s_root == NULL);
                kfree(root);
                root = NULL;
        } else {
                //下面分支是新申请的
                /* New superblock */
                struct cgroup *cgrp = &root->top_cgroup;
                struct inode *inode;

                BUG_ON(sb->s_root != NULL);
                //为 root cgroup 申请 inode / entry
                //====(1)====
                ret = cgroup_get_rootdir(sb);
                if (ret)
                        goto drop_new_super;
                //获取indoe, 主要使用里面的 inode->i_mutex
                inode = sb->s_root->d_inode;
                //使用 inode->i_mutex 加锁
                //====(2)====
                mutex_lock(&inode->i_mutex);
                //全局cgroup的锁
                mutex_lock(&cgroup_mutex);

                /*
                 * We're accessing css_set_count without locking
                 * css_set_lock here, but that's OK - it can only be
                 * increased by someone holding cgroup_lock, and
                 * that's us. The worst that can happen is that we
                 * have some link structures left over
                 *
                 * left over
                 *
                 * 我们这里在没有锁住 css_set_lock访问 css_set_count,
                 * 但是这是可以的 - 这个锁, 只有在某些 持有 cgroup_lock
                 * 的人 increased ??(加锁么) , 并且那就是我们 (??). 可能
                 * 发生更糟糕的事情, 我们还剩下剩下一些 link structure
                 *
                 */
                //====(3)====
                ret = allocate_cg_links(css_set_count, &tmp_cg_links);
                if (ret) {
                        mutex_unlock(&cgroup_mutex);
                        mutex_unlock(&inode->i_mutex);
                        goto drop_new_super;
                }
                //====(4)====
                ret = rebind_subsystems(root, root->subsys_bits);
                if (ret == -EBUSY) {
                        mutex_unlock(&cgroup_mutex);
                        mutex_unlock(&inode->i_mutex);
                        goto drop_new_super;
                }
        ...
}
```
1. `cgroup_get_rootdir`代码
   <details>
   <summary><code>cgroup_get_rootdir</code>代码: </summary>
   <p><font color="red">=====cgroup_get_rootdir折叠区=====</font></p>

   ```cpp
   static int cgroup_get_rootdir(struct super_block *sb)
   {
           struct inode *inode =
                   cgroup_new_inode(S_IFDIR | S_IRUGO | S_IXUGO | S_IWUSR, sb);
           struct dentry *dentry;
   
           if (!inode)
                   return -ENOMEM;
           //初始化 inode
           //我们下面会详细介绍这些operations
           //====(1)====
           //这行代码是搞玩乐么???
           inode->i_op = &simple_dir_inode_operations;
           inode->i_fop = &simple_dir_operations;
           inode->i_op = &cgroup_dir_inode_operations;
           /* directories start off with i_nlink == 2 (for "." entry) */
           //inode->i_nlink++
           inc_nlink(inode);
           //分配 dentry, 并且是 root dentry
           dentry = d_alloc_root(inode);
           if (!dentry) {
                   iput(inode);
                   return -ENOMEM;
           }
           //赋值 sb->s_root
           //====(2)====
           sb->s_root = dentry;
           return 0;
   }
   ```
   该函数主要是 初始化inode (see (1)), 并且赋值`sb->s_root`, 为新申请
   的 rootdir dentry

   > NOTE
   >
   > 做完了这些之后, 是不是mount命令就可以看到挂载点, 并且如果后续
   > 流程没有加锁的情况下, 是不是可以正常访问文件了? 
   >
   > 这个需要在看下后续代码+测试(目前个人感觉还不行, 因为还没有将该 
   > super_block anchor 到vfsmount上
   <p><font color="red">=====cgroup_get_rootdir折叠区=====</font></p>
   </details>

2. 该部分代码由
   ```
   commit 817929ec274bcfe771586d338bb31d1659615686
   Author: Paul Menage <menage@google.com>
   Date:   Thu Oct 18 23:39:36 2007 -0700
   
       Task Control Groups: shared cgroup subsystem group arrays
   ```
   引入, 也是早期的patch之一, 主要是引入 `cg_cgroup_link`, 我们之后单独
   分析下其中的race
3. `allocate_cg_links()` 
   <details>
   <summary><code>allocate_cg_links</code>代码: </summary>
   <p><font color="red">=====rebind_subsystems()折叠区====</font></p>

   ```cpp
   /*
    * allocate_cg_links() allocates "count" cg_cgroup_link structures
    * and chains them on tmp through their cgrp_link_list fields. Returns 0 on
    * success or a negative error
    */
   
   static int allocate_cg_links(int count, struct list_head *tmp)
   {
           struct cg_cgroup_link *link;
           int i;
           INIT_LIST_HEAD(tmp);
           for (i = 0; i < count; i++) {
                   link = kmalloc(sizeof(*link), GFP_KERNEL);
                   if (!link) {
                           while (!list_empty(tmp)) {
                                   link = list_entry(tmp->next,
                                                     struct cg_cgroup_link,
                                                     cgrp_link_list);
                                   list_del(&link->cgrp_link_list);
                                   kfree(link);
                           }
                           return -ENOMEM;
                   }
                   list_add(&link->cgrp_link_list, tmp);
           }
           return 0;
   }
   ```
   <p><font color="red">=====rebind_subsystems折叠区=====</font></p>
   </details>
4. `rebind_subsystems()`代码
   <a name="rebind_subsystems"> </a>
   <details>
   <summary><code>rebind_subsystems</code>代码: </summary>
   <p><font color="red">=====rebind_subsystems折叠区=====</font></p>

   ```cpp
   static int rebind_subsystems(struct cgroupfs_root *root,
                                 unsigned long final_bits)
   {
           unsigned long added_bits, removed_bits;
           struct cgroup *cgrp = &root->top_cgroup;
           int i;
           /*
            * 这个函数有三个调用路径
            *   + cgroup_get_sb
            *   + cgroup_kill_sb
            *   + cgroup_remount
            *
            * 而执行 cgroup_remount, 这里有可能进行rebind, 也就是
            * 之前 root下面有一些subsys, 但是subsys可能有变动
            *
            * removed_bits: 表示需要移除的subsys
            * add_bits: 表示增加的subsys
            */
           removed_bits = root->actual_subsys_bits & ~final_bits;
           added_bits = final_bits & ~root->actual_subsys_bits;
           /* Check that any added subsystems are currently free */
           for (i = 0; i < CGROUP_SUBSYS_COUNT; i++) {
                   unsigned long long bit = 1ull << i;
                   struct cgroup_subsys *ss = subsys[i];
                   if (!(bit & added_bits))
                           continue;
                   /*
                    * 走到这里就是 需要add的
                    * 这里需要判断ss->root 是否是rootnode, 
                    * 如果是rootnode, 则表示该subsys可能还没有
                    * 挂载过, 或者挂载之后又umount了, 如果不是,
                    * 说明还在其他cgroup 下有挂载, 则报错.
                    *
                    * ====(1)====
                    */
                   if (ss->root != &rootnode) {
                           /* Subsystem isn't free */
                           return -EBUSY;
                   }
           }
   
           /* Currently we don't handle adding/removing subsystems when
            * any child cgroups exist. This is theoretically supportable
            * but involves complex error handling, so it's being left until
            * later */
           /*
            * theoretically [ˌθɪəˈretɪkli]: 理论上
            *
            * 当存在任何child cgroup, 当前我们不处理 adding/removing subsystem, 
            * 这理论上是可以支持的, 但是会设计复杂的 error handling, 所以它要
            * 留到之后在引入.
            */
           if (!list_empty(&cgrp->children))
                   return -EBUSY;
           // 处理每一个subsystem
           /* Process each subsystem */
           for (i = 0; i < CGROUP_SUBSYS_COUNT; i++) {
                   struct cgroup_subsys *ss = subsys[i];
                   unsigned long bit = 1UL << i;
                   if (bit & added_bits) {
                           /* We're binding this subsystem to this hierarchy */
                           BUG_ON(cgrp->subsys[i]);
                           BUG_ON(!dummytop->subsys[i]);
                           BUG_ON(dummytop->subsys[i]->cgroup != dummytop);
                           //如果是add的话, 将cgrp->subsys[i]设置为 dummytop->subsys[i]
                           //see (1)
                           cgrp->subsys[i] = dummytop->subsys[i];
                           cgrp->subsys[i]->cgroup = cgrp;
                           //琏入 root->subsys_list
                           list_add(&ss->sibling, &root->subsys_list);
                           rcu_assign_pointer(ss->root, root);
                           //如果有 bind() 调用 bind(), 但会memory cgroup 没有
                           if (ss->bind)
                                   ss->bind(ss, cgrp);
   
                   } else if (bit & removed_bits) {
                           /* We're removing this subsystem */
                           //remove路径, 我们需要将该cgroup 绑定到 dummytop 上
                           BUG_ON(cgrp->subsys[i] != dummytop->subsys[i]);
                           BUG_ON(cgrp->subsys[i]->cgroup != cgrp);
                           if (ss->bind)
                                   ss->bind(ss, dummytop);
                           dummytop->subsys[i]->cgroup = dummytop;
                           //将subsys[i] 置为 NULL
                           cgrp->subsys[i] = NULL;
                           rcu_assign_pointer(subsys[i]->root, &rootnode);
                           list_del(&ss->sibling);
                   } else if (bit & final_bits) {
                           //如果传入的subsys 不需要删, 也不需要加, 那一定
                           //是在当前的 cgrp 下了
                           /* Subsystem state should already exist */
                           BUG_ON(!cgrp->subsys[i]);
                   } else {
                           //这种情况时, 没有传入该subsys, 并且subsys也不需要
                           //删, 那一定是不在 subsys下
                           /* Subsystem state shouldn't exist */
                           BUG_ON(cgrp->subsys[i]);
                   }
           }
           root->subsys_bits = root->actual_subsys_bits = final_bits;
           synchronize_rcu();
   
           return 0;
   }
   ```
   <p><font color="red">=====rebind_subsystems折叠区=====</font></p>
   </details>

### cgroup_get_sb -- PART 3
```cpp
static int cgroup_get_sb(struct file_system_type *fs_type,
                         int flags, const char *unused_dev_name,
                         void *data, struct vfsmount *mnt)
{
        ...
        if (sb->s_fs_info != root) {
                ...
        } else {
                ...
                //已经完成了 rebind_subsystems()
                /* EBUSY should be the only error here */
                BUG_ON(ret);

                //琏入 roots全局链表
                list_add(&root->root_list, &roots);
                root_count++;

                //赋值 sb->s_root (实际上是root dentry)的 d_fsdata(私有数据)
                sb->s_root->d_fsdata = &root->top_cgroup;
                //赋值 root cgroup 的 dentry
                root->top_cgroup.dentry = sb->s_root;

                /* Link the top cgroup in this hierarchy into all
                 * the css_set objects */
                //接下来要遍历 init_css_set, 并且可能执行删除操作, 所以要加写锁
                write_lock(&css_set_lock);
                /*
                 * 我们来思考下, 这边可能要做什么?
                 *
                 * 现在是分配好了一个新的cgroupfs_root, 一个新的cgroup, 包括该
                 * cgroup的subsys也初始化好了, 但是缺少什么呢?
                 *
                 * 新的cgroup 和css_set的关系, 是通过`cg_cgroup_link`来绑定.
                 * 正常来说,我们应该遍历oldcgroup->css_sets, 来找到oldcgroup
                 * 绑定的所有css_set, 然后将其绑定到newcgroup
                 *
                 * 但是这里考虑到是对 root cgroup 的操作, oldcgroup(dummytop)
                 * 绑定了全部的css_set, 并且都在 `init_css_set.list`链表中
                 */
                l = &init_css_set.list;
                do {
                        struct css_set *cg;
                        struct cg_cgroup_link *link;
                        //获取 css_set
                        cg = list_entry(l, struct css_set, list);
                        BUG_ON(list_empty(&tmp_cg_links));
                        //获取cg_cgroup_link
                        link = list_entry(tmp_cg_links.next,
                                          struct cg_cgroup_link,
                                          cgrp_link_list);
                        //删除和 oldcgroup 绑定关系
                        list_del(&link->cgrp_link_list);
                        link->cg = cg;
                        //增加和newcgroup绑定关系
                        list_add(&link->cgrp_link_list,
                                 &root->top_cgroup.css_sets);
                        list_add(&link->cg_link_list, &cg->cg_links);
                        l = l->next;
                } while (l != &init_css_set.list);
                write_unlock(&css_set_lock);

                free_cg_links(&tmp_cg_links);

                BUG_ON(!list_empty(&cgrp->sibling));
                BUG_ON(!list_empty(&cgrp->children));
                BUG_ON(root->number_of_cgroups != 1);

                cgroup_populate_dir(cgrp);
                mutex_unlock(&inode->i_mutex);
                mutex_unlock(&cgroup_mutex);
        }

        return simple_set_mnt(mnt, sb);

 drop_new_super:
        up_write(&sb->s_umount);
        deactivate_super(sb);
        free_cg_links(&tmp_cg_links);
        return ret;
}
```
***

看完了mount的流程, 我们在来看下 `cgroup_ops`
## cgroup_ops
```cpp
static struct super_operations cgroup_ops = {
        .statfs = simple_statfs,
        .drop_inode = generic_delete_inode,
        .show_options = cgroup_show_options,
        .remount_fs = cgroup_remount,
};
```

主要关注下 `cgroup_remount()`
```cpp
static int cgroup_remount(struct super_block *sb, int *flags, char *data)
{
        int ret = 0;
        struct cgroupfs_root *root = sb->s_fs_info;
        struct cgroup *cont = &root->top_cgroup;
        struct cgroup_sb_opts opts;

        mutex_lock(&cont->dentry->d_inode->i_mutex);
        mutex_lock(&cgroup_mutex);

        //调用 parse_cgroupfs_options() 获取mount参数
        /* See what subsystems are wanted */
        ret = parse_cgroupfs_options(data, &opts);
        if (ret)
                goto out_unlock;

        //注意 remount 流程不能改变flags
        /* Don't allow flags to change at remount */
        if (opts.flags != root->flags) {
                ret = -EINVAL;
                goto out_unlock;
        }
        //但是能改变subsystem
        ret = rebind_subsystems(root, opts.subsys_bits);

        /* (re)populate subsystem files */
        /*
         * populate: 生活于;居住于; 迁移;移居; (给文件)增添数据, 输入数据
         *
         * 这里感觉是填充 dir 的意思, 也就是给当前的cgroup dentry填充文件
         * 这部分我们暂时不展开, 我们在下面的流程中, 会讲道
         */
        if (!ret)
                cgroup_populate_dir(cont);

        if (opts.release_agent)
                strcpy(root->release_agent_path, opts.release_agent);
 out_unlock:
        if (opts.release_agent)
                kfree(opts.release_agent);
        mutex_unlock(&cgroup_mutex);
        mutex_unlock(&cont->dentry->d_inode->i_mutex);
        return ret;
}
```
`cgroup_remount()`流程主要是解析remount的参数, 然后根据变动后
的subsys, 更改该层级下的文件

> NOTE
>
> 关于`rebind_subsystems()`见[rebind_subsystems](#rebind_subsystems), 
> 其中讲到当执行`rebind_subsystems()`时, 目前的代码,只允许该
> root下只有一个根 cgroup, 不能有 child cgroup, 所以这里
> `cgroup_poplulate_dir()`执行不需要递归

## cgroup  inode op
从上面了解可知,对应 root 层级cgroup 的 inode的
* **i_op** : `cgroup_dir_inode_operations`
* **i_fop** : `simple_dir_operations`

我们主要来看下`i_op` -- `cgroup_dir_inode_operations`
```cpp
static struct inode_operations cgroup_dir_inode_operations = {
        .lookup = simple_lookup,
        .mkdir = cgroup_mkdir,
        .rmdir = cgroup_rmdir,
        .rename = cgroup_rename,
};
```
对应的特殊操作, 有三个 `mkdir`, `rmdir`, `rename`,
我们分别来看下

### cgroup_mkdir
代码如下:
```cpp
static int cgroup_mkdir(struct inode *dir, struct dentry *dentry, int mode)
{
        struct cgroup *c_parent = dentry->d_parent->d_fsdata;

        /* the vfs holds inode->i_mutex already */
        return cgroup_create(c_parent, dentry, mode | S_IFDIR);
}
```
可以看到 对cgroup 文件系统的mkdir操作, 是要去创建cgroup层级, 而`dentry->d_fsdata`
指向的是当前`dentry`代表的`cgroup`

<!--
   <details>
   <summary><code>init_cgroup_root</code>代码</summary>

   </details>
-->
