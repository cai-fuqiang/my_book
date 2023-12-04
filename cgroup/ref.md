# 简介
我们这篇文章主要来看下, cgroup 和 css 的 refcount相关演进.

# ORG patch

我们来看下,最开始的patch

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

## REFCOUNT type of `cgroup` && `cgroup_subsys_state`

最初的 `cgroup`以及`css`其`refcount`类型都是 atomic, 我们来看下
```cpp
struct cgroup {
        ...
        atomic_t count;
        ...
};

/* Per-subsystem/per-cgroup state maintained by the system. */
struct cgroup_subsys_state {
        ...

        /* State maintained by the cgroup system to allow
         * subsystems to be "busy". Should be accessed via css_get()
         * and css_put() */

        atomic_t refcnt;
        ...
};
```
css 注释中也提到了, 允许 subsystem 是 "busy"的状态, 应该通过`css_get()`,
和`css_put()`来操作引用计数. 

那么下面, 我们就详细看下关于两者的引用计数相关代码


## 代码流程

我们首先来看cgroup 的相关流程
* init

  cgroup框架通过`cgroup_create()`函数来创建一个新的 cgroup, 该函数
  没有明显的 refcount init流程, 我们来看 `cgroup_create()`代码:
  ```cpp
  static long cgroup_create(struct cgroup *parent, struct dentry *dentry,
                             int mode)
  {
      ...
      struct cgroup *cont;
      ...
      cont = kzalloc(sizeof(*cont), GFP_KERNEL);
      if (!cont)
          return -ENOMEM;
      ...
  }
  ```

  cgroup内存空间的申请, 是通过 `kzalloc()`申请的, 在该函数返回之前,
  没有在改变过 `cgroup->count`的值, 所以该值被初始化为`0`

* 
