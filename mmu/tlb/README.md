# LAZY TLB flush

## introduce

> NOTE:
>
> 这里我们仅考虑没有PCID引入的情况，
> 代码也是分析 lazy tlb 引入的前后版本


我们思考下面的问题:
* 内核线程和用户态线程有什么不同
* CR3在什么时候需要切换

### 内核线程 VS 用户线程
* 用户进程可以分为两个映射区间
  + 用户态映射
  + 内核态映射

  而内核线程只有内核空间映射。
* 所有线程有相同的内核空间(包括用户线程和内核线程)

可能大家都了解过，用户线程 `tsk->mm == tsk->active_mm`,
内核线程 `tsk->mm == NULL`, 并且 `!(tsk->active_mm)`,
`tsk->active_mm` 指向调度到该内核线程时, 前一个用户态进程的
`tsk->mm`。

> 关于tsk->active_mm && tsk->mm, linus本人在社区中解释过:
>
> ["mm" vs "active_mm"](./active_mm.md)

### switch CR3
那大家有没有想过，设置`tsk->mm, active_mm`这样做的目的是什么,
其实一个很大的作用就是避免CR3的切换，切换CR3 本身只是
一个指令，没有太大代价，但是该指令会导致invalidate tlb, 这个
代码就比较大了。

手册中描述如下, 来自intel sdm
```
4.10.4.1 Operations that Invalidate TLBs and Paging-Structure Caches
```

> MOV to CR3. The behavior of the instruction depends on the value of
> CR4.PCIDE:
>
> * If CR4.PCIDE = 0, the instruction invalidates all TLB entries associated with
> PCID 000H except those for global pages. It also invalidates all entries in all
> paging-structure caches associated with PCID 000H.
> * If CR4.PCIDE = 1  ...(略)

这里我们假设PCID功能没有开启(CR4.PCIDE=0), 也就相当于所有进程的TLB entries(除了global
page)或者 paging structure cache都是和PCID 000H 联系到一起, 切换CR3会无效所有的条目。
(除了 global page 相关的tlb)。

从上面来看切换CR3的代价还是很大的，我们思考下在下面的情况中需不需要切换CR3。

现在有两个用户态进程 `U1, U2` ，两个内核太进程`K1, K2`, 用户态进程`U1`有两个线程
`Ut1, Ut2`, `U1->U2`表示进程`U1`调度到进程`U2`。

* U1->U2： 用户态空间改变，需要切换
* Ut1->Ut2: 一个进程中的所有的线程具有相同的空间映射，不需要切换
* U1->K1: U1的内核空间和K1相同，所以不需要切换
* U1->K1->U1:
  + U1->K1: 上面提到不需要切换, 所以K1使用U1的CR3
  + K1->U1: 由于上面使用的是U1的CR3, 所以再切会到U1也不需要切换CR3

  > 这里k1_tsk->active_mm == u1_tsk->mm
* U1->K1->K2:
  + U1->K1: 不需要
  + K1->K2: 不需要
* U1->K1->U2:
  + U1->K1: 不需要，这里K1使用U1的CR3
  + K1->U2: 需要。因为上面K1使用的是U1的CR3，U1,U2有不同的用户空间。

上面是我们从用户空间的角度，讨论要不要切换CR3。可以看出，有一些情况是不需要切换
CR3的，例如: U1->K1->U1。这样做可以避免U1的TLB在这个过程中因为switch CR3被
invalidate。

但是在多核的架构上，情况tlb的刷新要更复杂一些。

### TLB shootdown
假设现在有一个用户进程 `U`, 其有两个线程`Ut1`, `Ut2`, 这两个线程分别在CPU0, CPU1
上运行。此时，Ut1 访问虚拟地址`vaddr1` 触发了一个page fault, 内核在处理过程
中为`vaddr1`建立虚拟地址到物理地址的页表映射, 修改完成后，需要去做invalidate
tlb 的操作。那么，实际上CPU0, CPU1 都需要这么做。这个操作在intel sdm 中
```
4.10.5 Propagation of Paging-Structure Changes to Multiple Processors
```
有讲到，被称为`TLB shootdown`。

这个行为更像是CPU0 让CPU1 停下来，去做一些事情(invalidate tlb)。早期
kernel的实现是为该行为定义了一个特殊的IPI vector -- `INVALIDATE_TLB_VECTOR`,
然后让CPU0通过该IPI 通知CPU1 去invalidate tlb。流程大致如下:
```
CPU0:                           CPU1:
flush_tlb_others:
  send_IPI
  spin loop wait
    this things down
                                receive IPIs
                                invalidate TLB
                                mark this things down
  flush tlb others end
```

当然，CPU1在收到`INVALIDATE_TLB_VECTOR`可以直接执行 invalidate TLB 的操作，
但是在某些情况下可以 LAZY 执行。

### LAZY flush tlb

我们假设有两个用户态进程 `U1, U2`, 一个内核态进程`K`, 用户态进程 `U1`,
有两个线程 `Ut1, Ut2`,分别在`CPU0, CPU1`上运行, 考虑下面情况:

1. Ut1->K
2. Ut2 因为用户空间page fault fix, 发起tlb shootdown
3. K : need flush immediately? NO! 该映射与我无瓜,
    1. mark lazy execute tlb flush <br>
    2. Hide imm! I don't want anyone to touch me again because of this matter
4. Ut2 再次因为用户空间page fault fix, 再次发起 tlb shootdown...
    1. Ut2: Where is Ut1? I cannot find it !!!
5. switch to other thread.
    * switch to U2: 进程切换顺序为Ut1->K->U2, must switch CR3 !
    * switch to Ut1: I must to do a tlb flush.

可以看到, 在上面的流程中，`K` 内核线程在标记 有其他线程发起`tlb shootdown`
后，将自己隐藏起来，当下次Ut2再次触发TLB shootdown 后，不再通知Ut1,
然后等K调度回U2, 或者Ut1 时候，再刷新tlb(当然调度到U2切换CR3会无效所有
tlb, 但是该动作目的不是为了invalidate U1的 old TLB entry)。

> 大家可能有疑问? 为什么不在`Ut1->K`时，就`Hide`起来，然后发起者标记上该任务切回时
> 可能要在切回`K->Ut1`时，再刷新tlb，这样都不用接收(Ut2也不用发送) IPI, 这个
> 想法是很好的, 但是可能会有一些race 的问题。我们先看下代码实现，标记下，后续
> 再讨论!!!
> ```
> ++++++++++++++++
> ++++++++++++++++
> 遗留问题标记!!!!
> ++++++++++++++++
> ++++++++++++++++
> ```

# 细节实现
我们采用patch对比的方式查看该功能是如何引入的。首先我们先浏览下
在没有该功能引入之前的代码流程

> 在patch在 2.3.30pre2 patch集中引用，由于本人认知有限，不知道
> 在内核早期，开发者们是如何维护kernel项目(git分支，mail list都未
> 找到。所以，只能找到某些patch集.
>
> NOTE:
>
> patch 集可以在git:
>
> git://git.kernel.org/pub/scm/linux/kernel/git/history/history.git
>
> 找到, 也可以在
>
> https://mirrors.edge.kernel.org/pub/linux/kernel/v2.3/
>
> 找到，推荐从git里面查找，比较方便

## BOFORE LAZY TLB FLUSH

> 以下代码来自: 2.3.30pre1
>
>   2.3.30pre2 的上一个版本
>
>> PS
>>
>> kernel可能在 bdflush 相关的流程中首次引入 lazy tlb,
>> 不过我们暂时先不去看这部分内容

我们首先看下`struct mm_struct`数据结构（和tlb相关的)
```cpp
struct mm_struct {
    ...
    atomic_t mm_users;         /* How many users with user space? */
    atomic_t mm_count;         /* How many references to "struct mm_struct" (users count as 1) */
    ...
    unsigned long cpu_vm_mask;
    ...
};
```

* **mm_users**: 表示该user space 的用户
* **mm_count**: 表示users count 是1 的时候, 有多少人在引用 该"mm_struct"
* **cpu_vm_mask** : 表示当前`mm_struct`在哪些CPU上有引用

我们先不做过多解释, 直接看代码:

* init - mm_users, mm_count

```cpp
struct mm_struct * mm_alloc(void)
{
        struct mm_struct * mm;

        mm = kmem_cache_alloc(mm_cachep, SLAB_KERNEL);
        if (mm) {
                memset(mm, 0, sizeof(*mm));
                atomic_set(&mm->mm_users, 1);
                atomic_set(&mm->mm_count, 1);
                init_MUTEX(&mm->mmap_sem);
                mm->page_table_lock = SPIN_LOCK_UNLOCKED;
                mm->pgd = pgd_alloc();
                if (mm->pgd)
                        return mm;
                kmem_cache_free(mm_cachep, mm);
        }
        return NULL;
}
```
可以看到在分配 `mm_struct`时，`mm_users`, `mm_count`都赋值为1

* INC - mm_users
```cpp
static inline int copy_mm(unsigned long clone_flags, struct task_struct * tsk)
{
    ...
    mm = current->mm;
    if (!mm)
            return 0;

    if (clone_flags & CLONE_VM) {
            atomic_inc(&mm->mm_users);
            goto good_mm;
    }
    ...
}
```
在 `copy_mm`时 增加 `mm_users` (创建线程)

* DEC - mm_users
```cpp
void mmput(struct mm_struct *mm)
{
        if (atomic_dec_and_test(&mm->mm_users)) {
                exit_mmap(mm);
                mmdrop(mm);
        }
}
```
这里会判断 mm_users是否减少为0, 如果减少为0, 则
执行`exit_mmap()(解除映射), 并调用 mmdrop(下面介绍，
该函数会dec mm->mm_count)
* INC - mm
```cpp
asmlinkage void schedule(void)
{
    ...
    prepare_to_switch();
    {
            struct mm_struct *mm = next->mm;
            struct mm_struct *oldmm = prev->active_mm;
            if (!mm) {
                    if (next->active_mm) BUG();
                    //=====(1)=========
                    next->active_mm = oldmm;
                    atomic_inc(&oldmm->mm_count);
            } else {
                    if (next->active_mm != mm) BUG();
                    switch_mm(oldmm, mm, next, this_cpu);
            }
    
            //=====(2)=========
            if (!prev->mm) {
                    prev->active_mm = NULL;
                    mmdrop(oldmm);
            }
     ...
}
```
1. 如果 `next->mm == NULL`, 说明该线程是一个内核线程, 增加`oldmm->mm_count`
将`next->active_mm`赋值为 `oldmm`表示引用前一个的 `mm_struct`,当然引用的
是 `prev->active_mm`, 因为前一个线程可能是内核线程(`prev->mm == NULL, 
prev->active_mm == prev->prev->active_mm`(伪代码)), 然后inc `oldmm->mm_count`
表示有新的tsk引用该 mm

2. `prev->mm == NULL`, 表示是一个内核线程，这时候调度走，则解除对 `tsk->active_mm`
的引用，这时会调用 `mmdrop(oldmm)`
```cpp
static inline void mmdrop(struct mm_struct * mm)
{
        if (atomic_dec_and_test(&mm->mm_count))
                __mmdrop(mm);
}
```
可以看到这里会检测`mm->count`, 结合上面代码看，假设一个进程有多个线程，多个
线程调用 `mmput()`后, 会将 `mm_count--` ,而之后`mm_count`的值就是内核线
程引用的次数(也就是说用户线程占用一个 `mm_count`)。那么假设最后一个内核
线程退出，则会调用 `__mmdrop()`， 释放page table 和相关数据结构(例如mm_struct)
```cpp
inline void __mmdrop(struct mm_struct *mm)
{
        if (mm == &init_mm) BUG();
        pgd_free(mm->pgd);
        destroy_context(mm);
        kmem_cache_free(mm_cachep, mm);
}
```
