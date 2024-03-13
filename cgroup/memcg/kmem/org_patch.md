# PATCH 0 COMMIT message

> FROM
>
> [\[PATCH v6 00/29\] kmem controller for memcg.](https://lore.kernel.org/all/1351771665-11076-1-git-send-email-glommer@parallels.com/)

```
The kernel memory limitation mechanism for memcg concerns itself with
disallowing potentially non-reclaimable allocations to happen in exaggerate
quantities by a particular set of tasks (cgroup). Those allocations could
create pressure that affects the behavior of a different and unrelated set of
tasks.

> exaggerate /ɪɡˈzædʒəreɪt/ : v. 夸张;夸大;言过其实
> quantities /ˈkwɑntətiz/ : 数量;量;大量;数目;
>
> memcg 的 kernel memory limitation 机制 关注的是 不允许特定的 set of task (cgroup)
> 以夸张的数量进行不可回收分配. 这些分配可能会产生压力, 影响不同且不相关的 任务集

Its basic working mechanism consists in annotating interesting allocations with
the _GFP_KMEMCG flag. When this flag is set, the current task allocating will
have its memcg identified and charged against. When reaching a specific limit,
further allocations will be denied.

> annotating  /ˈænəteɪtɪŋ/ : 给…作注解
> denied: deny /dɪˈnaɪ/: 否认;拒绝
>
> 主要的工作机制包括使用 _GFP_KMEMCG flag 注释感兴趣的allocations. 当该flag被设置,
> current task 的分配将标识其 memcg, 并且对其(memcg) charge. 当达到指定的 limit时,
> 未来的分配将会被拒绝

As of this work, pages allocated on behalf of the slab allocator, and stack
memory are tracked. Other kinds of memory, like spurious calls to
__get_free_pages, vmalloc, page tables, etc are not tracked. Besides the memcg
cost that may be present with those allocations - that other allocations may
rightfully want to avoid - memory need to be somehow traceable back to a task
in order to be accounted by memcg. This may be trivial - as in the stack - or a
bit complicated, requiring extra work to be done - as in the case of the slab.
IOW, which memory to track is always a complexity tradeoff. We believe stack +
slab provides enough coverage of the relevant kernel memory most of the time.

> as of : 在...时
> spurious [ˈspjʊəriəs] : 虚假的,伪造的
> rightfully: 正当地；正直地
> IOW: in other world
> tradeoff: 权衡;协调;交易;交换
>
> 在其工作时, 代表slab 分配起分配的页面 和 stack memory 将会被跟踪. 其他类型的内存,
> 例如 spurious calls(没翻译懂) __get_free_pages, vmalloc, page tables, 等等都不会
> 被跟踪. 除了这些分配可能存在memcg 的成本(其他的分配理所当然的想避免)之外, 内存
> 还需要以某种方式追溯到该任务, 一般又 memcg 进行 account. 这可能是微不足道的
> --就像在堆栈中的一样-- 或许有些复杂, 需要完成额外的工作 -- 就像slab中的一样.
> 换句话说, 跟踪哪个内存始终是一个复杂性的权衡. 我们相信 stack + slab 在大多数情况下
> 都能提供足够的相关kernel memory 的覆盖.

Tracking accuracy depends on how well we can track memory back to a specific
task. Memory allocated for the stack is always accurately tracked, since stack
memory trivially belongs to a task and is never shared. For the slab, the
accuracy depends on the amount of object-sharing existing between tasks in
different cgroups (like memcg does for shmem, the kernel memory controller
operates in a first-touch basis). Workloads, such as OS containers, usually
have a very low amount of sharing, and will therefore present high accuracy.

> accuracy: [ˈækjərəsi] : 精确
> how well : 如何;程度;多好;怎样;多么好;
> trivially: /tIVIəlI/ 平凡地;平凡;琐细地;一般的
>
> track 的精确程序依赖我们能将memory 跟踪到特定的task的能力. 对于stack的内存分配
> 总是能够精确的追踪, 因为 stack memory 一般属于一个task 并且从来不共享.对于slab,
> 精确读主要以来 在该不同cgroup的task之间, object-share 存在的数量(就像memcg对
> shmem 所做的那样, kernel memory controller 以 first-touch basis 为基础进行操作).
> 工作负载, 例如操作系统容器, 因为共享量非常低, 因此准确率很高.

One example of problematic pressure that can be prevented by this work is
a fork bomb conducted in a shell. We prevent it by noting that tasks use a
limited amount of stack pages. Seen this way, a fork bomb is just a special
case of resource abuse. If the offender is unable to grab more pages for the
stack, no new tasks can be created.


> problematic [ˌprɑːbləˈmætɪk]: 成问题的,造成困难的,疑难的
> conducted : 实施, 组织,执行
> Seen this way : 这样看..
> abuse /əˈbjuːs/: 滥用;虐待
> offender [əˈfendər] : 罪犯;违法者
>
> 这样工作可以防止一个难以解决的pressure 是 shell 中发起的 fork bomb. 我们通过标记
> tasks 使用stack pages 总量的limited来防止他. 这样看,  fork bomb 仅仅是资源滥用
> 的一个特例. 如果 犯罪者不能为 stack 获取更多的page, 没有新的task可以创建

There are also other things the general mechanism protects against. For
example, using too much of pinned dentry and inode cache, by touching files an
leaving them in memory forever.

> 该通用机制还可以防止一些其他的事情. 例如, 使用太多的 pinned dentry 和 inode cache, 
> 通过创建文件让其永远保留在内存中.

In fact, a simple:

> 实际上, 很简单: 

while true; do mkdir x; cd x; done

can halt your system easily because the file system limits are hard to reach
(big disks), but the kernel memory is not. Those are examples, but the list
certainly don't stop here.

> don't stop here : 不止如此
>
> 能够很轻松的 halt 你的 system 因为 file system 的限制很难达到(big disks), 但是
> kernel memory 则不是. 尽管这只是一个例子, 但list 绝不只如此.

An important use case for all that, is concerned with people offering hosting
services through containers. In a physical box we can put a limit to some
resources, like total number of processes or threads. But in an environment
where each independent user gets its own piece of the machine, we don't want a
potentially malicious user to destroy good users' services.

> 一个

This might be true for systemd as well, that now groups services inside
cgroups. They generally want to put forward a set of guarantees that limits the
running service in a variety of ways, so that if they become badly behaved,
they won't interfere with the rest of the system.

There is, of course, a cost for that. To attempt to mitigate that, static
branches are used. This code will only be enabled after the first user of this
service configures any kmem limit, guaranteeing near-zero overhead even if a
large number of (non-kmem limited) memcgs are deployed.

Behavior depends on the values of memory.limit_in_bytes (U), and
memory.kmem.limit_in_bytes (K):

    U != 0, K = unlimited:
    This is the standard memcg limitation mechanism already present before kmem
    accounting. Kernel memory is completely ignored.

    U != 0, K < U:
    Kernel memory is a subset of the user memory. This setup is useful in
    deployments where the total amount of memory per-cgroup is overcommited.
    Overcommiting kernel memory limits is definitely not recommended, since the
    box can still run out of non-reclaimable memory.
    In this case, the admin could set up K so that the sum of all groups is
    never greater than the total memory, and freely set U at the cost of his
    QoS.

    U != 0, K >= U:
    Since kmem charges will also be fed to the user counter and reclaim will be
    triggered for the cgroup for both kinds of memory. This setup gives the
    admin a unified view of memory, and it is also useful for people who just
    want to track kernel memory usage.
```
