# 简介
我们这里看下cgroup struct

# ORG patch
> NOTE
>
> cgroup的patch 和maillist比较乱,我们暂时以下面的patch,
> 作为 ORG patch的最后一个patch
>
> ```
> commit 8707d8b8c0cbdf4441507f8dded194167da896c7
> Author: Paul Menage <menage@google.com>
> Date:   Thu Oct 18 23:40:22 2007 -0700
> 
>     Fix cpusets update_cpumask
> ```
>
> 关于css的相关代码分析, 我们以`memory cgroup`为例子

我们首先来看下相关数据结构
## 数据结构
### cgroup
`struct cgroup`用来描述cgroup的层级
```cpp
struct cgroup {
        unsigned long flags;            /* "unsigned long" so bitops work */

        /* count users of this cgroup. >0 means busy, but doesn't
         * necessarily indicate the number of tasks in the
         * cgroup */
        atomic_t count;

        /*
         * We link our 'sibling' struct into our parent's 'children'.
         * Our children link their 'sibling' into our 'children'.
         */
        struct list_head sibling;       /* my parent's children */
        struct list_head children;      /* my children */

        struct cgroup *parent;  /* my parent */
        struct dentry *dentry;          /* cgroup fs entry */

        /* Private pointers for each registered subsystem */
        struct cgroup_subsys_state *subsys[CGROUP_SUBSYS_COUNT];

        struct cgroupfs_root *root;
        struct cgroup *top_cgroup;

        /*
         * List of cg_cgroup_links pointing at css_sets with
         * tasks in this cgroup. Protected by css_set_lock
         */
        struct list_head css_sets;

        /*
         * Linked list running through all cgroups that can
         * potentially be reaped by the release agent. Protected by
         * release_list_lock
         */
        struct list_head release_list;
};
```
* **dentry** : 早期还没有kernfs
* **sibling**, **children**, **parent**: 三者共同建立起cgroup 的层级树
* **subsys**: 才层级下的 subsystem
* **css_sets**: 用于链接 `cg_cgroup_link`, 我们下面会讲道 (`cg_cgroup_link->cont_link_list`)
* **release_list**: 我们稍后看 !!!!!

### cgroupfs_root
```cpp
/*
 * A cgroupfs_root represents the root of a cgroup hierarchy,
 * and may be associated with a superblock to form an active
 * hierarchy
 */
struct cgroupfs_root {
        struct super_block *sb;

        /*
         * The bitmask of subsystems intended to be attached to this
         * hierarchy
         */
        unsigned long subsys_bits;

        /* The bitmask of subsystems currently attached to this hierarchy */
        unsigned long actual_subsys_bits;

        /* A list running through the attached subsystems */
        struct list_head subsys_list;

        /* The root cgroup for this hierarchy */
        struct cgroup top_cgroup;

        /* Tracks how many cgroups are currently defined in hierarchy.*/
        int number_of_cgroups;

        /* A list running through the mounted hierarchies */
        struct list_head root_list;

        /* Hierarchy-specific flags */
        unsigned long flags;

        /* The path to use for release notifications. No locking
         * between setting and use - so if userspace updates this
         * while child cgroups exist, you could miss a
         * notification. We ensure that it's always a valid
         * NUL-terminated string */
        char release_agent_path[PATH_MAX];
};
```
该数据结构主要使用来描述 cgroup 层级的 root, 可能会联系 superblock
来表示一个active hierarchy

* **subsys_bits**: 用于描述打算attach到该层级的 subsystem
* **actual_subsys_bits**: 用于描述当前attach 到该层级的 subsystem
* **subsys_list**: ???
* **top_cgroup**: 根层级的cgroup
* **root_list**: 链接所有的 `cgroupfs_root`

### cgroup_subsys_state

```cpp
/* Per-subsystem/per-cgroup state maintained by the system. */
struct cgroup_subsys_state {
        /* The cgroup that this subsystem is attached to. Useful
         * for subsystems that want to know about the cgroup
         * hierarchy structure */
        struct cgroup *cgroup;

        /* State maintained by the cgroup system to allow
         * subsystems to be "busy". Should be accessed via css_get()
         * and css_put() */

        atomic_t refcnt;

        unsigned long flags;
};
```
注释中描写的很清楚, `cgroup_subsys_state` 用来表示 `per-subsystem/per-cgroup state`
也就是用来描述一个cgroup中的一个subsysteem的状态
* **cgroup** : 该subsystem所attach的cgroup. 该成员主要用于 subsystem 来找
           他所在的cgroup 层级
* **refcnt**: 引用计数
* **flags**

### css_set
```cpp
/* A css_set is a structure holding pointers to a set of
 * cgroup_subsys_state objects. This saves space in the task struct
 * object and speeds up fork()/exit(), since a single inc/dec and a
 * list_add()/del() can bump the reference count on the entire
 * cgroup set for a task.
 */
struct css_set {

        /* Reference count */
        struct kref ref;

        /*
         * List running through all cgroup groups. Protected by
         * css_set_lock
         */
        struct list_head list;

        /*
         * List running through all tasks using this cgroup
         * group. Protected by css_set_lock
         */
        struct list_head tasks;

        /*
         * List of cg_cgroup_link objects on link chains from
         * cgroups referenced from this css_set. Protected by
         * css_set_lock
         */
        struct list_head cg_links;

        /*
         * Set of subsystem states, one for each subsystem. This array
         * is immutable after creation apart from the init_css_set
         * during subsystem registration (at boot time).
         */
        struct cgroup_subsys_state *subsys[CGROUP_SUBSYS_COUNT];

};
```
> immutable : [ɪ'mjuːtəbl] adj.不可变的；不变的<br/>
> apart: adv.相距；分开地；分别地 adj.分开的；分离的 <br/>
> apart from: 除了...之外

`css_set` 保存了一组 `cgroup_subsys_state object`的指针. 他保存在
`task_struct` object中 并且用来加速 `fork()`/`exit()`, 因此 single 
inc/dec 和 single list_add()/del() 可以 bump 整个的 对于一个task的
整个的 cgroup set的ref count.

* **ref**: refcount, 注意这里使用的是 `struct kref`
* **list** : 链接所有的 `css_set`, (链接到`init_css_set`) (这里的cgroup group
         指的就是`css_set`)
* **task** : 链接所有的 使用该 `css_set` 的task
* **cg_links**: 链接 `cg_cgroup_link`  (`cg_cgroup_link->cg_link_list`)
* **subsys**: 一组 subsystem state, 每一个成员对应一个subsystem. 该
          数组在创建之后是不变的, 除了 init_css_set(这也是一个css_set),
          其在 subsystem regsiteration时候(at boot time)
* 

### cg_cgroup_link 
```cpp
/* Link structure for associating css_set objects with cgroups */
struct cg_cgroup_link {
        /*
         * List running through cg_cgroup_links associated with a
         * cgroup, anchored on cgroup->css_sets
         */
        struct list_head cont_link_list;
        /*
         * List running through cg_cgroup_links pointing at a
         * single css_set object, anchored on css_set->cg_links
         */
        struct list_head cg_link_list;
        struct css_set *cg;
};
```

> anchored: ['æŋkəd] adj.抛锚的 v.抛锚, 停泊, 使固定

这种类型数据结构很常用, 多用于连接多对多关系的数据结构, 而实际上`css_set`
和 `cgroup` 之间是多对多的关系, `css_set` 中的每个subsystem 可以挂在不同
的cgroup层级上, 而每个`cgroup`层级中的subsystem ,也可能有多个`css_set`
在使用.

一个 `cg_cgroup_link`对象, 能够表示唯一的`(cgroup, css_set)`关系, 
该数据结构用于方便查询, 例如, 可以通过`cgroup` 查询其层级下
所有的`css_set`

> NOTE
>
> 可以看到其数据结构中, 只有`css_set`指针, 没有`cgroup`指针, 这也就
> 说明, 目前cgroup框架中,只有通过`cgroup` 查询`css_set`的需求,但是
> 没有通过`css_set`查询所有的`cgroup`的需求

* **cont_link_list**: 链接在 `cgroup->css_set`
* **cg_link_list** : 链接在 `css_set->cg_links`
* **cg**: 指向`css_set`

### cftype 
```cpp
/* struct cftype:
 *
 * The files in the cgroup filesystem mostly have a very simple read/write
 * handling, some common function will take care of it. Nevertheless some cases
 * (read tasks) are special and therefore I define this structure for every
 * kind of file.
 *
 *
 * When reading/writing to a file:
 *      - the cgroup to use in file->f_dentry->d_parent->d_fsdata
 *      - the 'cftype' of the file is file->f_dentry->d_fsdata
 */
struct cftype {
        /* By convention, the name should begin with the name of the
         * subsystem, followed by a period */
        char name[MAX_CFTYPE_NAME];
        int private;
        int (*open) (struct inode *inode, struct file *file);
        ssize_t (*read) (struct cgroup *cont, struct cftype *cft,
                         struct file *file,
                         char __user *buf, size_t nbytes, loff_t *ppos);
        /*
         * read_uint() is a shortcut for the common case of returning a
         * single integer. Use it in place of read()
         */
        u64 (*read_uint) (struct cgroup *cont, struct cftype *cft);
        ssize_t (*write) (struct cgroup *cont, struct cftype *cft,
                          struct file *file,
                          const char __user *buf, size_t nbytes, loff_t *ppos);

        /*
         * write_uint() is a shortcut for the common case of accepting
         * a single integer (as parsed by simple_strtoull) from
         * userspace. Use in place of write(); return 0 or error.
         */
        int (*write_uint) (struct cgroup *cont, struct cftype *cft, u64 val);

        int (*release) (struct inode *inode, struct file *file);
};
```
该数据结构, 主要是用于层级的 dentry的一些回调, 不再赘述

### cgroup_subsys
```cpp
struct cgroup_subsys {
        struct cgroup_subsys_state *(*create)(struct cgroup_subsys *ss,
                                                  struct cgroup *cont);
        void (*destroy)(struct cgroup_subsys *ss, struct cgroup *cont);
        int (*can_attach)(struct cgroup_subsys *ss,
                          struct cgroup *cont, struct task_struct *tsk);
        void (*attach)(struct cgroup_subsys *ss, struct cgroup *cont,
                        struct cgroup *old_cont, struct task_struct *tsk);
        void (*fork)(struct cgroup_subsys *ss, struct task_struct *task);
        void (*exit)(struct cgroup_subsys *ss, struct task_struct *task);
        int (*populate)(struct cgroup_subsys *ss,
                        struct cgroup *cont);
        void (*post_clone)(struct cgroup_subsys *ss, struct cgroup *cont);
        void (*bind)(struct cgroup_subsys *ss, struct cgroup *root);
        int subsys_id;
        int active;
        int early_init;
#define MAX_CGROUP_TYPE_NAMELEN 32
        const char *name;

        /* Protected by RCU */
        struct cgroupfs_root *root;

        struct list_head sibling;

        void *private;
};
```
该数据结构主要用于描述 subsys 的一些行为, 在这里先不描述...
### task_struct (change)
```cpp
struct task_struct {
        ...
#ifdef CONFIG_CGROUPS
        /* Control Group info protected by css_set_lock */
        struct css_set *cgroups;
        /* cg_list protected by css_set_lock and tsk->alloc_lock */
        struct list_head cg_list;
#endif
        ...
};
```
* **cgroups** : 指向当前task的 `css_set`
