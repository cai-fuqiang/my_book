# ORG patch
cgroup init 函数有两个
* cgroup_init_early()
* cgroup_init()
这两个函数都是在`start_kernel()`函数中,其中`cgroup_init()`调用
更晚一些.我们来看这两个函数都干了啥

在看这些之前, 我们先列举一些全局变量

## global vars 
* css_set 相关
  ```cpp
  /* The default css_set - used by init and its children prior to any
   * hierarchies being mounted. It contains a pointer to the root state
   * for each subsystem. Also used to anchor the list of css_sets. Not
   * reference-counted, to improve performance when child cgroups
   * haven't been created.
   */
  /*
   * anchor [ˈæŋkə(r)] : n. 支柱, 靠山, 锚, v.把...系住, 使固定
   *
   * 默认的css_set - 在任何层级在被mount之前, 被 init 和他的 chhidren task
   * 使用. 它包括了
   *   一个指向每个subsystem root state的指针 (css_set->subsys[])
   *   用于串联(其他)css_set 的链表
   *   不计算引用, 以在尚未创建 child cgroup 时, 提高性能
   */
  static struct css_set init_css_set;
  static struct cg_cgroup_link init_css_set_link;
  
  /* css_set_lock protects the list of css_set objects, and the
   * chain of tasks off each css_set.  Nests outside task->alloc_lock
   * due to cgroup_iter_start() */
  /*
   * css_set_lock 保护 css_set objects 的 list, 以及每个 css_set 的tasks
   * 链. 由于 cgroup_iter_start()在外部会嵌套 task->alloc_lock
   */
  static DEFINE_RWLOCK(css_set_lock);
  static int css_set_count;
  ```
  + **css_set**: 请见注释
  + **init_css_set_link**: 链接 `init_css_set` && `dummytop`(下面会介绍)
  + **css_set_lock**: 见注释
  + **css_set_count**: css_set的个数
<a name="global_vars_cgroup_roots"></a>
* cgroupfs_root相关
```cpp
/*
 * The "rootnode" hierarchy is the "dummy hierarchy", reserved for the
 * subsystems that are otherwise unattached - it never has more than a
 * single cgroup, and all tasks are part of that cgroup.
 */
/*
 * "rootnode" 层级是一个 "dummy hierarchy"(假的), 预留给那些还没有任何
 * attached 的subsystem - 他只有一个 cgroup, 并且所有task 都是cgroup的
 * 一部分
 */
static struct cgroupfs_root rootnode;

/* The list of hierarchy roots */

static LIST_HEAD(roots);
static int root_count;

/* dummytop is a shorthand for the dummy hierarchy's top cgroup */
#define dummytop (&rootnode.top_cgroup)
```
* **rootnode**: 这里提到这是一个dummy 层级, 为何是 dummy的, 因为
            该层级只有一层 -- root, 其中只有一个cgroup, 所以
            并不能起到层级的作用.<br/>
            当某个subsystem mount之后, 该subsystem root 就脱离
            了这个层级
* **roots**: `cgroupfs_root`链表
* **root_count**: `cgroupfs_root`的数量
* **dummytop**: 根层级的cgroup, 注释中也说了, 是个缩写, 全称为
            `dummy hierarchy's top cgroup`

## cgroup_init_early
```cpp
/**
 * cgroup_init_early - initialize cgroups at system boot, and
 * initialize any subsystems that request early init.
 */
int __init cgroup_init_early(void)
{
        int i;
        //========(1)==========
        kref_init(&init_css_set.ref);
        kref_get(&init_css_set.ref);
        INIT_LIST_HEAD(&init_css_set.list);
        INIT_LIST_HEAD(&init_css_set.cg_links);
        INIT_LIST_HEAD(&init_css_set.tasks);
        css_set_count = 1;
        //========(2)==========
        init_cgroup_root(&rootnode);
        //========(2.1)==========
        list_add(&rootnode.root_list, &roots);
        root_count = 1;
        //========(1.1)==========
        init_task.cgroups = &init_css_set;

        //========(3)==========
        init_css_set_link.cg = &init_css_set;
        list_add(&init_css_set_link.cgrp_link_list,
                 &rootnode.top_cgroup.css_sets);
        list_add(&init_css_set_link.cg_link_list,
                 &init_css_set.cg_links);

        //========(4)==========
        for (i = 0; i < CGROUP_SUBSYS_COUNT; i++) {
                struct cgroup_subsys *ss = subsys[i];

                BUG_ON(!ss->name);
                BUG_ON(strlen(ss->name) > MAX_CGROUP_TYPE_NAMELEN);
                BUG_ON(!ss->create);
                BUG_ON(!ss->destroy);
                //========(4)==========
                if (ss->subsys_id != i) {
                        printk(KERN_ERR "cgroup: Subsys %s id == %d\n",
                               ss->name, ss->subsys_id);
                        BUG();
                }

                //========(5)==========
                if (ss->early_init)
                        cgroup_init_subsys(ss);
        }
        return 0;
}
```
1. 初始化`init_css_set()`, 我们知道`css_set`是和task绑定的, 可能有一个
   或者多个task, 而(1.1)中将`init_task`绑定了`init_css_set`
2. 初始化`rootnode`(type  `cgroupfs_root`)
   ```cpp
   static void init_cgroup_root(struct cgroupfs_root *root)
   {
           //=====(1)=====
           struct cgroup *cgrp = &root->top_cgroup;
           INIT_LIST_HEAD(&root->subsys_list);
           INIT_LIST_HEAD(&root->root_list);
           root->number_of_cgroups = 1;
           //=====(1.1)=====
           cgrp->root = root;
           cgrp->top_cgroup = cgrp;
           INIT_LIST_HEAD(&cgrp->sibling);
           INIT_LIST_HEAD(&cgrp->children);
           INIT_LIST_HEAD(&cgrp->css_sets);
           INIT_LIST_HEAD(&cgrp->release_list);
   }
   ```
   1. 每个`cgroupfs_root`中都有一个`cgroup`, 表示默认的root层级 --
      `cgroupfs_root->top_cgroup`, 在(1.1)中也将`cgrp->root`赋值
      为它.



   ***

   (2.1) 中会将`rootnode.root_list`链接到全局链表`roots`
3. 初始化 `init_css_set_link`(type `cg_cgroup_link`), 该类型用于链接
   `cgroup`和`css_set`. (see [struct.md](./struct.md))
4. 遍历所有的`subsystem`

   > NOTE
   >
   > subsys[] 是在编译是初始化好的
   > 

   >
   > ```cpp
   > #define SUBSYS(_x) &_x ## _subsys,
   > static struct cgroup_subsys *subsys[] = {
   > #include <linux/cgroup_subsys.h>
   > }
   >
   > //FILE=====linux/cgroup_subsys.h===
   > #ifdef CONFIG_CPUSETS
   > SUBSYS(cpuset)
   > #endif
   > 
   > /* */
   > 
   > #ifdef CONFIG_CGROUP_DEBUG
   > SUBSYS(debug)
   > #endif
   > ...
   > ```
   > 这里使用了模板的方法, 通过定义`SUBSYS`宏定义, 在
   > `linux/cgroup_subsyss.h` 可以展开为不同的数据结构类型
   >
   > 这里就是通过该方法, 得到了所有subsystem 的 cgroup_subsys
   > 类型的指针

4. 需要注意的是, 每一个`subsystem`都有一个唯一的id, 该id也用作
   在`subsys[]`中的位置
5. 在early init流程中, 只初始化`ss->early_init`为真的subsystem

> NOTE
>
> 关于cgroup_init_subsys() 我们在cgroup_init()之后, 在讲解

## cgroup_init
```cpp
/**
 * cgroup_init - register cgroup filesystem and /proc file, and
 * initialize any subsystems that didn't request early init.
 */
int __init cgroup_init(void)
{
        int err;
        int i;
        struct proc_dir_entry *entry;

        err = bdi_init(&cgroup_backing_dev_info);
        if (err)
                return err;
        //====(1)====
        for (i = 0; i < CGROUP_SUBSYS_COUNT; i++) {
                struct cgroup_subsys *ss = subsys[i];
                if (!ss->early_init)
                        cgroup_init_subsys(ss);
        }

        //====(2)====
        err = register_filesystem(&cgroup_fs_type);
        if (err < 0)
                goto out;

        //====(3)====
        entry = create_proc_entry("cgroups", 0, NULL);
        if (entry)
                entry->proc_fops = &proc_cgroupstats_operations;

out:
        if (err)
                bdi_destroy(&cgroup_backing_dev_info);

        return err;
}
```
1. 遍历所有的 `subsys[]`, 为所有 `ss->early_init` 为 false的subsystem
   调用`cgroup_init_subsys()`
2. 注册 filesystem
3. 创建`/proc/cgroups`文件, 其read op 我们来看下
   ```cpp
   /* Display information about each subsystem and each hierarchy */
   static int proc_cgroupstats_show(struct seq_file *m, void *v)
   {
           int i;
   
           seq_puts(m, "#subsys_name\thierarchy\tnum_cgroups\n");
           mutex_lock(&cgroup_mutex);
           for (i = 0; i < CGROUP_SUBSYS_COUNT; i++) {
                   struct cgroup_subsys *ss = subsys[i];
                   seq_printf(m, "%s\t%lu\t%d\n",
                              ss->name, ss->root->subsys_bits,
                              ss->root->number_of_cgroups);
           }
           mutex_unlock(&cgroup_mutex);
           return 0;
   }
   ```
   可以看到该函数会遍历所有的subsystem, 打印
   * `subsys_name`: subsystem 名称
   * `ss->root->subsys_bits`: 当前ss的根层级下绑定的subsystem
   * `ss->root->number_of_cgroups`: 当前ss的所在的根层级下所有的cgroup

   读取该文件,输出示例如下:
   ```
   #subsys_name    hierarchy       num_cgroups     enabled
   cpuset  8       1       1
   cpu     5       103     1
   cpuacct 5       103     1
   blkio   3       104     1
   memory  6       251     1
   devices 9       103     1
   freezer 7       1       1
   net_cls 2       1       1
   perf_event      4       1       1
   net_prio        2       1       1
   hugetlb 10      1       1
   pids    12      128     1
   rdma    11      1       1
   ```

   > NOTE
   >
   > 这个是比较新的kernel的输出(`4.18.0-372`), 会多一列 `enabled`

我们接下来看下, `cgroup_init_subsys()`代码

## cgroup_init_subsys
```cpp
static void cgroup_init_subsys(struct cgroup_subsys *ss)
{
        struct cgroup_subsys_state *css;
        struct list_head *l;

        printk(KERN_INFO "Initializing cgroup subsys %s\n", ss->name);

        //====(1)====
        /* Create the top cgroup state for this subsystem */
        ss->root = &rootnode;
        //====(2)====
        css = ss->create(ss, dummytop);
        /* We don't handle early failures gracefully */
        BUG_ON(IS_ERR(css));
        //====(3)====
        init_cgroup_css(css, ss, dummytop);

        /* Update all cgroup groups to contain a subsys
         * pointer to this state - since the subsystem is
         * newly registered, all tasks and hence all cgroup
         * groups are in the subsystem's top cgroup. */
        write_lock(&css_set_lock);
        //====(4)====
        l = &init_css_set.list;
        do {
                struct css_set *cg =
                        list_entry(l, struct css_set, list);
                cg->subsys[ss->subsys_id] = dummytop->subsys[ss->subsys_id];
                l = l->next;
        } while (l != &init_css_set.list);
        write_unlock(&css_set_lock);

        /* If this subsystem requested that it be notified with fork
         * events, we should send it one now for every process in the
         * system */
        //====(5)====
        if (ss->fork) {
                struct task_struct *g, *p;

                read_lock(&tasklist_lock);
                do_each_thread(g, p) {
                        ss->fork(ss, p);
                } while_each_thread(g, p);
                read_unlock(&tasklist_lock);
        }

        need_forkexit_callback |= ss->fork || ss->exit;

        //====(6)====
        ss->active = 1;
}
```
1. 赋值`ss->root`为 `rootnode`
2. 创建css -- (调用ss->create()), 参数为`(ss, dummytop)`, `dummytop`为宏, 
   宏定义请见 [dummytop](#global_vars_cgroup_roots)

   实际上就是根层级的cgroup

   我们接下来会分析mem_cgroup的 ss->create()
3. 初始化css -- `init_cgroup_css()`
   ```cpp
   static void init_cgroup_css(struct cgroup_subsys_state *css,
                                  struct cgroup_subsys *ss,
                                  struct cgroup *cgrp)
   {
           css->cgroup = cgrp;
           atomic_set(&css->refcnt, 0);
           css->flags = 0;
           if (cgrp == dummytop)
                   set_bit(CSS_ROOT, &css->flags);
           BUG_ON(cgrp->subsys[ss->subsys_id]);
           cgrp->subsys[ss->subsys_id] = css;
   }
   ```
   这里, 我们关心`css->refcnt`此时 赋值为0

   > NOTE
   >
   > `ss->create()`和 `init_cgroup_css()`貌似一个是创建,一个是init
   > 那为什么不能合并呢? 
   >
   > 两者关心的东西不同. `ss->create()`虽然分配了css的内存,但是
   > 其主要是创建/初始化 subsystem的一些东西, 而`init_cgroup_css()`
   > 则是初始化通用的`cgroup_subsys_state`数据结构, 以及`cgroup->subsys[]`

4. 这里我们需要找到所有的`css_set`, 赋值`cg->subsys[]`, 注释中也提到, 
   因为该 subsystem是新注册的, 所以需要所有的`css_set`都在subsystem的根层级中.
   当然,也需要赋值全部的`css_set->subsys[]`
5. `fork()`我们暂时不看 !!!!
6. 将active置为1, 表示已经该subsystem已经是活跃状态.


## mem_cgroup subsys create
```cpp
struct cgroup_subsys mem_cgroup_subsys = {
        .name = "memory",
        .subsys_id = mem_cgroup_subsys_id,
        .create = mem_cgroup_create,
        .destroy = mem_cgroup_destroy,
        .populate = mem_cgroup_populate,
        .attach = mem_cgroup_move_task,
        .early_init = 1,
}
```

可以看到 `early_init`为1, 我们来看下create回调
```cpp
//====(1)====
static struct mem_cgroup init_mem_cgroup;

static struct cgroup_subsys_state *
mem_cgroup_create(struct cgroup_subsys *ss, struct cgroup *cont)
{
        struct mem_cgroup *mem;

        //====(1.1)====
        if (unlikely((cont->parent) == NULL)) {
                mem = &init_mem_cgroup;
                init_mm.mem_cgroup = mem;
        } else
                mem = kzalloc(sizeof(struct mem_cgroup), GFP_KERNEL);

        if (mem == NULL)
                return NULL;

        //====(2)====
        res_counter_init(&mem->res);
        //====(3)====
        INIT_LIST_HEAD(&mem->active_list);
        INIT_LIST_HEAD(&mem->inactive_list);
        spin_lock_init(&mem->lru_lock);
        mem->control_type = MEM_CGROUP_TYPE_ALL;
        return &mem->css;
}
```
1. 该变量是一个全局变量, 表示`mem_cgroup`的根层级, 在(1.1)也可以看出来,
   如果`cont->parent`是空(表示根), 则使用`init_mem_cgroup`, 否则
   则`zalloc`一个
2. 初始化 `mem->res` (res_counter)
   ```cpp
   void res_counter_init(struct res_counter *counter)
   {
           spin_lock_init(&counter->lock);
           counter->limit = (unsigned long long)LLONG_MAX;
   }
   ```
   设置`counter->limit`为`LLONG_MAX`表示不受限
3. 初始化`lru`
