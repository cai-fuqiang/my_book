# ORG patch

## global vars
* cgroupfs_root: 
  ```cpp
  /*
   * The "rootnode" hierarchy is the "dummy hierarchy", reserved for the
   * subsystems that are otherwise unattached - it never has more than a
   * single cgroup, and all tasks are part of that cgroup.
   */
  /*
   * 该 "rootnode" 层级是一个 "dummy hierarchy"(假的), 主要预留给那些
   * 没有任何attach的subsystem - 它从来没有超过一个cgroup, 所有的tasks
   * 都是该cgorup的一部分
   */
  static struct cgroupfs_root rootnode;
  ```

### mount
我们先看下, mount相关的代码流程
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
        //========(1)=========
        /* See what subsystems are wanted */
        ret = parse_cgroupfs_options(data, &opts);
        if (ret)
                goto out_unlock;

        /* Don't allow flags to change at remount */
        if (opts.flags != root->flags) {
                ret = -EINVAL;
                goto out_unlock;
        }

        ret = rebind_subsystems(root, opts.subsys_bits);

        /* (re)populate subsystem files */
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
1. 用于态通过`data`参数传过来一些字符串, 供mount流程解析, 最终
   保存在 `cgroup_sb_opts` 结构中
   ```cpp
   struct cgroup_sb_opts {
         unsigned long subsys_bits;
         unsigned long flags;
         char *release_agent;
   };
   ```
   * **subsys_bits**: 表示想要attach的subsys
   *
   
   然后, 我们来看下该函数:
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
           //循环获取各个字段
           while ((token = strsep(&o, ",")) != NULL) {
                   if (!*token)
                           return -EINVAL;
                   if (!strcmp(token, "all")) {
                           opts->subsys_bits = (1 << CGROUP_SUBSYS_COUNT) - 1;
                   } else if (!strcmp(token, "noprefix")) {
                           set_bit(ROOT_NOPREFIX, &opts->flags);
                   } else if (!strncmp(token, "release_agent=", 14)) {
                           /* Specifying two release agents is forbidden */
                           if (opts->release_agent)
                                   return -EINVAL;
                           opts->release_agent = kzalloc(PATH_MAX, GFP_KERNEL);
                           if (!opts->release_agent)
                                   return -ENOMEM;
                           strncpy(opts->release_agent, token + 14, PATH_MAX - 1);
                           opts->release_agent[PATH_MAX - 1] = 0;
                   } else {
                           //和各个 subsys的name去比较, 如果相同, 则置位
                           //opts->subsys_bits
                           struct cgroup_subsys *ss;
                           int i;
                           for (i = 0; i < CGROUP_SUBSYS_COUNT; i++) {
                                   ss = subsys[i];
                                   if (!strcmp(token, ss->name)) {
                                           set_bit(i, &opts->subsys_bits);
                                           break;
                                   }
                           }
                           if (i == CGROUP_SUBSYS_COUNT)
                                   return -ENOENT;
                   }
           }
   
           /* We can't have an empty hierarchy */
           //这里必须绑定一个subsys
           if (!opts->subsys_bits)
                   return -EINVAL;
   
           return 0;
   }
   ```
2. 
