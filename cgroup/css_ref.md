# ORG patch 
最初patch在执行`cgroup_rmdir()`时, 操作是这样
```cpp
/*
commit ddbcc7e8e50aefe467c01cac3dec71f118cd8ac2
Author: Paul Menage <menage@google.com>
Date:   Thu Oct 18 23:39:30 2007 -0700

    Task Control Groups: basic task cgroup framework
*/
static int cgroup_rmdir(struct inode *unused_dir, struct dentry *dentry)
{
    struct cgroup *cont = dentry->d_fsdata;
    struct dentry *d;
    struct cgroup *parent;
    struct cgroup_subsys *ss;
    struct super_block *sb;
    struct cgroupfs_root *root;
    int css_busy = 0;
    
    /* the vfs holds both inode->i_mutex already */
    
    mutex_lock(&cgroup_mutex);
    //========(1)==========
    if (atomic_read(&cont->count) != 0) {
            mutex_unlock(&cgroup_mutex);
            return -EBUSY;
    }
    //========(2)==========
    if (!list_empty(&cont->children)) {
            mutex_unlock(&cgroup_mutex);
            return -EBUSY;
    }
    
    parent = cont->parent;
    root = cont->root;
    sb = root->sb;
    
    /* Check the reference count on each subsystem. Since we
     * already established that there are no tasks in the
     * cgroup, if the css refcount is also 0, then there should
     * be no outstanding references, so the subsystem is safe to
     * destroy 
     * 
     * established: <adj> 确定的
     *              <v>   确定, 确立
     *
     * 检测每一个子系统的 subsystem. 因为我们已经确定这个cgroup中
     * 没有tasks了, 如果 css refcount 也是0, 然后应该就没有outstanding
     * outstanding references, 所以该 subsystem 可以安全的destroy
     */
    //========(3)==========
    for_each_subsys(root, ss) {
            struct cgroup_subsys_state *css;
            css = cont->subsys[ss->subsys_id];
            if (atomic_read(&css->refcnt)) {
                    css_busy = 1;
                    break;
            }
    }
    if (css_busy) {
            mutex_unlock(&cgroup_mutex);
            return -EBUSY;
    }
    ...

    mutex_unlock(&cgroup_mutex);
    ...
}
```
检测其是否被占用, 主要有三个地方:
1. `cgroup->count`是否为0
2. 是否有`cgroup->children`
3. 检测每一个子系统的`css->refcnt`

做完这三个步骤, 基本上就可以确定, 没有outstanding references了.
(详细原因请看注释), 而且整个的过程, 也会在`cgroup_mutex`锁的保护下

# 早期代码
早期在执行`cgroup_rmdir()`时, 操作是这样
```cpp
static inline int cgroup_has_css_refs(struct cgroup *cgrp)
{
        /* Check the reference count on each subsystem. Since we
         * already established that there are no tasks in the
         * cgroup, if the css refcount is also 0, then there should
         * be no outstanding references, so the subsystem is safe to
         * destroy. We scan across all subsystems rather than using
         * the per-hierarchy linked list of mounted subsystems since
         * we can be called via check_for_release() with no
         * synchronization other than RCU, and the subsystem linked
         * list isn't RCU-safe */
        int i;
        for (i = 0; i < CGROUP_SUBSYS_COUNT; i++) {
                struct cgroup_subsys *ss = subsys[i];
                struct cgroup_subsys_state *css;
                /* Skip subsystems not in this hierarchy */
                if (ss->root != cgrp->root)
                        continue;
                css = cgrp->subsys[ss->subsys_id];
                /* When called from check_for_release() it's possible
                 * that by this point the cgroup has been removed
                 * and the css deleted. But a false-positive doesn't
                 * matter, since it can only happen if the cgroup
                 * has been deleted and hence no longer needs the
                 * release agent to be called anyway. */
                if (css && atomic_read(&css->refcnt))
                        return 1;
        }
        return 0;
}

static int cgroup_rmdir(struct inode *unused_dir, struct dentry *dentry)
{
        ...
        if (cgroup_has_css_refs(cgrp)) {
                mutex_unlock(&cgroup_mutex);
                return -EBUSY;
        }
        ...
}
```
# TMP
```
commit d3daf28da16a30af95bfb303189a634a87606725 (HEAD -> percpu_ref_kill_and_confirm_cgroup)
Author: Tejun Heo <tj@kernel.org>
Date:   Thu Jun 13 19:39:16 2013 -0700

    cgroup: use percpu refcnt for cgroup_subsys_states

    A css (cgroup_subsys_state) is how each cgroup is represented to a
    controller.  As such, it can be used in hot paths across the various
    subsystems different controllers are associated with.

    One of the common operations is reference counting, which up until now
    has been implemented using a global atomic counter and can have
    significant adverse impact on scalability.  For example, css refcnt
    can be gotten and put multiple times by blkcg for each IO request.
    For highops configurations which try to do as much per-cpu as
    possible, the global frequent refcnting can be very expensive.

    In general, given the various and hugely diverse paths css's end up
    being used from, we need to make it cheap and highly scalable.  In its
    usage, css refcnting isn't very different from module refcnting.

    This patch converts css refcnting to use the recently added
    percpu_ref.  css_get/tryget/put() directly maps to the matching
    percpu_ref operations and the deactivation logic is no longer
    necessary as percpu_ref already has refcnt killing.

    The only complication is that as the refcnt is per-cpu,
    percpu_ref_kill() in itself doesn't ensure that further tryget
    operations will fail, which we need to guarantee before invoking
    ->css_offline()'s.  This is resolved collecting kill confirmation
    using percpu_ref_kill_and_confirm() and initiating the offline phase
    of destruction after all css refcnt's are confirmed to be seen as
    killed on all CPUs.  The previous patches already splitted destruction
    into two phases, so percpu_ref_kill_and_confirm() can be hooked up
    easily.

    This patch removes css_refcnt() which is used for rcu dereference
    sanity check in css_id().  While we can add a percpu refcnt API to ask
    the same question, css_id() itself is scheduled to be removed fairly
    soon, so let's not bother with it.  Just drop the sanity check and use
    rcu_dereference_raw() instead.
```
