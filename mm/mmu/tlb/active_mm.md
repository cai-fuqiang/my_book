```
List:       linux-kernel
Subject:    Re: active_mm
From:       Linus Torvalds <torvalds () transmeta ! com>
Date:       1999-07-30 21:36:24

Cc'd to linux-kernel, because I don't write explanations all that often,
and when I do I feel better about more people reading them.

explanations : 解释; 说明
all that often : 通常?

因为我通常不写解释，并且当我这么做的时候，更多人能读到它我觉得更好。

On Fri, 30 Jul 1999, David Mosberger wrote:
>
> Is there a brief description someplace on how "mm" vs. "active_mm" in
> the task_struct are supposed to be used?  (My apologies if this was
> discussed on the mailing lists---I just returned from vacation and
> wasn't able to follow linux-kernel for a while).

> brief: 简短的
> apologies: 道歉;认错
> vacation : 假期
> for a while : 暂时，有一段时间
>
> 有没有关于task_struct中的“mm”与“active_mm”应该如何使用的简要描述?
> 如果之前在 mail lists中讨论过，我很抱歉 --- 我刚刚从假期回来，并且
> 有一段时间没有跟踪 linux-kernel

Basically, the new setup is:

 - we have "real address spaces" and "anonymous address spaces". The
   difference is that an anonymous address space doesn't care about the
   user-level page tables at all, so when we do a context switch into an
   anonymous address space we just leave the previous address space
   active.

 - 我们有 "real address space" 和 "anonymous address space"。这两者不同
   的是 anonymous address space 根本不关心 user-level page tables，所以
   当我们 context switch 到 一个 anonymous address space 时，我们用之前
   的 address space 就行。
 
   The obvious use for a "anonymous address space" is any thread that
   doesn't need any user mappings - all kernel threads basically fall into
   this category, but even "real" threads can temporarily say that for
   some amount of time they are not going to be interested in user space,
   and that the scheduler might as well try to avoid wasting time on
   switching the VM state around. Currently only the old-style bdflush
   sync does that.

   obvious: 明显的
   category: 类别
   temporarily : 暂时地

   "anonymous address space" 的明显用途是任何不需要 用户映射的线程 - 
   所有的 kernel threads 基本都属于这个类别, 但是 即使是 “real" threads
   也可能暂时的表示，在一段时间内，他们可能将不会对 user space 感兴趣，
   这样 scheduler 也可以尽量避免在切换VM state 上 浪费时间。现在只有 old-style
   bdflush sync 这样做。

 - "tsk->mm" points to the "real address space". For an anonymous process,
   tsk->mm will be NULL, for the logical reason that an anonymous process
   really doesn't _have_ a real address space at all.

   "tsk->mm" 指向 "real address space"。对于 anonymous process, tsk->mm
   都是NULL，处于逻辑原因(?), anonymous process 实际上根本没有 real address
   space。

 - however, we obviously need to keep track of which address space we
   "stole" for such an anonymous user. For that, we have "tsk->active_mm",
   which shows what the currently active address space is.

   然而，我们显然需要跟踪我们为这样一个匿名用户“窃取”了哪个地址空间。
   为此，我们有“tsk->active_mm”，它显示了当前活动的地址空间是什么。

   The rule is that for a process with a real address space (ie tsk->mm is
   non-NULL) the active_mm obviously always has to be the same as the real
   one.

   
   规则是，对于具有实际地址空间的进程（即tsk->mm为非NULL），active_mm显然必
   须与实际地址空间相同。

   For a anonymous process, tsk->mm == NULL, and tsk->active_mm is the
   "borrowed" mm while the anonymous process is running. When the
   anonymous process gets scheduled away, the borrowed address space is
   returned and cleared.

   对于匿名进程，tsk->mm==NULL，而tsk->active_mm是匿名进程运行时"借用"
   的mm。当匿名进程被调度离开时，借用的地址空间将被返回并清除。

To support all that, the "struct mm_struct" now has two counters: a
"mm_users" counter that is how many "real address space users" there are,
and a "mm_count" counter that is the number of "lazy" users (ie anonymous
users) plus one if there are any real users.

为了支持所有这些，"struct mm_struct"现在有两个计数器：一个是"mm_users"计数器，
表示有多少“真实地址空间用户”，另一个是一个“mm_count”计数器，即"lazy"用户（即
匿名用户）的数量加上一（如果有真实用户）。

Usually there is at least one real user, but it could be that the real
user exited on another CPU while a lazy user was still active, so you do
actually get cases where you have a address space that is _only_ used by
lazy users. That is often a short-lived state, because once that thread
gets scheduled away in favour of a real thread, the "zombie" mm gets
released because "mm_count" becomes zero.

in favour of: 赞成;支持;有利于
zombie: 僵尸

通常至少有一个real user，但是可能的情况是 当 lazy user 仍然active时，
real user 在另一个CPU上 exit了，所以实际情况是现在的这个address space 
只用于 lazy users。这是一个很短暂的状态，因为一旦这个 thread （anonymous
thread) 被调度到一个 real thread, 该 "僵尸" mm 将会因为 "mm_count"变成0
被释放。

Also, a new rule is that _nobody_ ever has "init_mm" as a real MM any
more. "init_mm" should be considered just a "lazy context when no other
context is available", and in fact it is mainly used just at bootup when
no real VM has yet been created. So code that used to check

       if (current->mm == &init_mm)

should generally just do

       if (!current->mm)

instead (which makes more sense anyway - the test is basically one of "do
we have a user context", and is generally done by the page fault handler
and things like that).

也就是说,一个新的规则是: 再也没有人将 "init_mm" 作为 "real MM". "init_mm"
应该被认为仅仅是一个 "当没有 available 的 context 时，一个 lazy context",
并且事实上，他主要用在 bootup ，当还没有 "real VM" 被创建的时候。
所以 之前代码用于检查, `if(current->mm == &init_mm) 应该通常替换为仅仅去做
`if (!current->mm)`

(无论如何，这更有意义——这个test(是指判断, 并非测试)基本上是“我们有user 
context吗”，通常由 page fault handler 和类似的东西来完成

Anyway, I put a pre-patch-2.3.13-1 on ftp.kernel.org just a moment ago,
because it slightly changes the interfaces to accommodate the alpha (who
would have thought it, but the alpha actually ends up having one of the
ugliest context switch codes - unlike the other architectures where the MM
and register state is separate, the alpha PALcode joins the two, and you
need to switch both together).

accommodate 容纳 ; 顺应，适应 ; 考虑到 ; 顾及 ; 帮忙

无论如何，我刚才在ftp.kernel.org上放了一个预补丁-2.3.13-1，因为它稍微改变了
接口以适应alpha（谁会想到呢，但alpha实际上最终拥有了最丑陋的上下文切换代码
之一 -- 与其他架构不同，在其他架构中，MM和寄存器状态是分开的，alpha PALcode
将两者连接在一起，你需要一起切换两者）。

(From http://marc.info/?l=linux-kernel&m=93337278602211&w=2)
```
