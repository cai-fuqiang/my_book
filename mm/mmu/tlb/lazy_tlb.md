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


### mm_users && mm_count

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

### cpu_vm_mask

* CLEAR && SET BIT - cpu_vm_mask
```cpp
asmlinkage void schedule(void)
{
        ...
        {
                struct mm_struct *mm = next->mm;
                struct mm_struct *oldmm = prev->active_mm;
                //===========(1)==============
                if (!mm) {
                        if (next->active_mm) BUG();
                        next->active_mm = oldmm;
                        atomic_inc(&oldmm->mm_count);
                } else {
                        //============(2)============
                        if (next->active_mm != mm) BUG();
                        switch_mm(oldmm, mm, next, this_cpu);
                }

                if (!prev->mm) {
                        prev->active_mm = NULL;
                        mmdrop(oldmm);
                }
        }
        ...
}
static inline void switch_mm(struct mm_struct *prev, struct mm_struct *next, struct task_struct *tsk, unsigned cpu)
{

        //=============(3)================
        if (prev != next) {
                /*
                 * Re-load LDT if necessary
                 */
                if (prev->segments != next->segments)
                        load_LDT(next);

                /* Re-load page tables */
                asm volatile("movl %0,%%cr3": :"r" (__pa(next->pgd)));
                clear_bit(cpu, &prev->cpu_vm_mask);
        }
        //=============(4)================
        set_bit(cpu, &next->cpu_vm_mask);
}
```
1. 这里会判断 `next->mm`, 如果是`NULL`的话，说明`next`进程是一个内核线程，
需要更新 `next->active_mm` 为 上一个进程的 `mm`, 并增加 `mm_count`
上面讲过
2. 如果 `next->mm` 不为空，说明是一个用户线程，调用`switch_mm()`
3. 可能是下面情况之一
    + 用户线程A->用户线程B
    + 内核线程(active_mm = 用户线程A) -> 用户线程B

    那么现在mm 不同，切换 ldt 和pgd,并且清除 该cpu的`prev->cpu_vm_mask`, 表示 
    该cpu 没有使用此`mm`(这里先暂时这么理解，我们结合下面代码看下)。
4. 设置该cpu的`prev->cpu_vm_mask`, 表示该cpu是用 `prev mm`

### check and clean -  cpu_vm_mask
在 发起 flush tlb 动作的接口中会调用到:
例如 `flush_tlb_mm`

```cpp
void flush_tlb_mm(struct mm_struct * mm)
{
        //===========(1)=============
        unsigned long vm_mask = 1 << current->processor;
        unsigned long cpu_mask = mm->cpu_vm_mask & ~vm_mask;

        //===========(2)=============
        mm->cpu_vm_mask = 0;
        //===========(3)=============
        if (current->active_mm == mm) {
                mm->cpu_vm_mask = vm_mask;
                local_flush_tlb();
        }
        //===========(4)=============
        flush_tlb_others(cpu_mask);
}
```

1. 获取`current->processor` 的mask(`vm_mask`), 并且 在 `cpu_vm_mask`
清除，并获取一个mask，实际上是，除了当前cpu的其他mask。也是为了
flush tlb others 做准备（通知其他cpu flush tlb)

2. 将 `cpu_vm_mask` 清除 (在 `flush_tlb_others`中会详细讲解原因)
3. 如果 `current->active_mm == mm` , 说明flush 的 mm 就是
当前mm，不flush的话会对当前cpu有影响，会将`mm->cpu_vm_mask`
赋值为 缺少当前cpu的 mask, 并且刷新 本cpu的 tlb
4. flush 其他cpu的tlb

我们先看下 `local_flush_tlb`的代码:
```cpp
#define local_flush_tlb() \
        __flush_tlb()

#define __flush_tlb() \
do { 
    unsigned long tmpreg;
    __asm__ __volatile__("movl %%cr3,%0\n\tmovl %0,%%cr3"
        :"=r" (tmpreg) : :"memory"); } while (0)
```

可以看到是使用切换cr3到一个随机值，然后在切回来。

我们来看下flush_tlb_others代码
```cpp
/*
 * This is fraught with deadlocks. Probably the situation is not that
 * bad as in the early days of SMP, so we might ease some of the
 * paranoia here.
 */
static void flush_tlb_others(unsigned int cpumask)
{
        int cpu = smp_processor_id();
        int stuck;
        unsigned long flags;

        /*
         * it's important that we do not generate any APIC traffic
         * until the AP CPUs have booted up!
         */
         //==========(1)============
        cpumask &= cpu_online_map;
        if (cpumask) {
                //==========(1.1)============
                atomic_set_mask(cpumask, &smp_invalidate_needed);

                /*
                 * Processors spinning on some lock with IRQs disabled
                 * will see this IRQ late. The smp_invalidate_needed
                 * map will ensure they don't do a spurious flush tlb
                 * or miss one.
                 */
                //==========(2)============
                __save_flags(flags);
                __cli();

                send_IPI_allbutself(INVALIDATE_TLB_VECTOR);

                /*
                 * Spin waiting for completion
                 */

                //==========(3)============
                stuck = 50000000;
                while (smp_invalidate_needed) {
                        /*
                         * Take care of "crossing" invalidates
                         */
                        //==========(4)=============
                        if (test_bit(cpu, &smp_invalidate_needed)) {
                                struct mm_struct *mm = current->mm;
                                clear_bit(cpu, &smp_invalidate_needed);
                                if (mm)
                                        atomic_set_mask(1 << cpu, &mm->cpu_vm_mask);
                                local_flush_tlb();
                        }
                        --stuck;
                        if (!stuck) {
                                printk("stuck on TLB IPI wait (CPU#%d)\n",cpu);
                                break;
                        }
                }
                __restore_flags(flags);
        }
}
```

1. 和 online cpu map 进行与操作，避免等待offline的cpu
2. 在关中断的情况下进行。
3. 这里的设计很巧妙，`smp_invalidate_needed`是一个全局变量，会让所有的 tlb flush 
others的发起者都是用该变量，所以我们看到在(1.1)这个地方会使用 `atomic_set`。
而 `local_flush_tlb`上面也展开了，就是通过切换cr3 flush 所有的tlb.(不引入 PCID
的情况下)
4. `smp_invalidate_needed` 会保证所有的flush tlb的请求都会被处理，可以看到，
如果当前cpu在关中断的情况下，等待别的cpu回应，但是此时也受到了flush tlb的请求
的话，在 spin waiting中也会处理该请求。并且会将 `mm->cpu_vm_mask`置位。通过
在发起时清`mm->cpu_vm_mask`, 在接收该请求时置位`mm->cpu_vm_mask`, 从而避免了
后续的cpu发起flush tlb再等待该处理比较慢的cpu。（发起一次就够了，让最开始发起
的cpu等待就行。毕竟flush tlb 也是flush 全部的tlb entries)


> NOTE
>
> 这里没有搞懂:<br/>
> 为什么要关中断 ?
> ``` ++++++++++++++++
> ++++++++++++++++
> 遗留问题标记!!!!
> ++++++++++++++++
> ++++++++++++++++
> ```

中断处理函数
```cpp
void init init_IRQ(void)
{
    ...
    set_intr_gate(INVALIDATE_TLB_VECTOR, invalidate_interrupt);
    ...
}
asmlinkage void smp_invalidate_interrupt(void)
{
        struct task_struct *tsk = current;
        unsigned int cpu = tsk->processor;

        if (test_and_clear_bit(cpu, &smp_invalidate_needed)) {
                struct mm_struct *mm = tsk->mm;
                if (mm)
                        atomic_set_mask(1 << cpu, &mm->cpu_vm_mask);
                local_flush_tlb();
        }
        ack_APIC_irq();

}
```
代码比较简单，不解释。

### 总结
在没有 lazy tlb的情况下, 内核线程在收到 flush tlb ipi 时，会立即
flush tlb, 并且将 `mm->cpu_vm_mask`置位，下次再有flush tlb ipi 时，
也会去处理这样的请求。发起者也会去等待该cpu处理。


## LAZY tlb --first indroduce
我们来想，如果实现这一目的，需要在内核线程运行时收到的 flush tlb 的请求记录下来，
然后在 switch_mm()流程中进行实际的flush 操作。我们来看相关patch

> 以下代码来自于 2.3.30pre2 的patch

#### cpu_tlbbad[]
```cpp
+unsigned int cpu_tlbbad[NR_CPUS]; /* flush before returning to user space */
```
增加`cpu_tlbbad[NR_CPUS]`全局变量数组，用来存储在内核线程运行时，是否收到过 flush 
tlb 的请求。

#### mask cpu_tlbbad

```diff
+static inline void do_flush_tlb_local(void)
+{
+       unsigned long cpu = smp_processor_id();
+       struct mm_struct *mm = current->mm;
+
+       clear_bit(cpu, &smp_invalidate_needed);
+       if (mm) {
+               set_bit(cpu, &mm->cpu_vm_mask);
+               local_flush_tlb();
+       } else {
+               cpu_tlbbad[cpu] = 1;
+       }
+}

 asmlinkage void smp_invalidate_interrupt(void)
 {
-       struct task_struct *tsk = current;
-       unsigned int cpu = tsk->processor;
+       if (test_bit(smp_processor_id(), &smp_invalidate_needed))
+               do_flush_tlb_local();

-       if (test_and_clear_bit(cpu, &smp_invalidate_needed)) {
-               struct mm_struct *mm = tsk->mm;
-               if (mm)
-                       atomic_set_mask(1 << cpu, &mm->cpu_vm_mask);
-               local_flush_tlb();
-       }
        ack_APIC_irq();

 }
```
在收到 flush tlb ipi 请求后，在`do_flush_tlb_local()`中会检查是否是
内核线程，如果是内核线程，则不再将 clear 的 `mm->cpu_vm_mask`的cpu
置位。将`cpu_tlbbad[cpu]`赋值为1。这样在`switch_mm()`调用之前(下面
讲到)，如果再有其他cpu发起tlb ipi request, 该cpu 不再 flush tlb, 
其他cpu也不会等待该cpu flush完成。

#### check && unmask cpu_tlbbad
```diff
+#ifdef __SMP__
+extern unsigned int cpu_tlbbad[NR_CPUS];
+#endif
+
 static inline void switch_mm(struct mm_struct *prev, struct mm_struct *next, struct task_struct *tsk, unsigned cpu)
 {
-
        if (prev != next) {
                /*
                 * Re-load LDT if necessary
@@ -24,6 +28,13 @@ static inline void switch_mm(struct mm_struct *prev, struct mm_struct *next, str
                asm volatile("movl %0,%%cr3": :"r" (__pa(next->pgd)));
                clear_bit(cpu, &prev->cpu_vm_mask);
        }
+#ifdef __SMP__
+       else {
+               if(cpu_tlbbad[cpu])
+                       local_flush_tlb();
+       }
+       cpu_tlbbad[cpu] = 0;
+#endif
        set_bit(cpu, &next->cpu_vm_mask);
 }
```

在`switch_mm()`流程中，如果`prev == next`, 这时候说明mm一样，不需要切换`cr3`, 但是
假如说，之前标记过 `cpu_tlbbad()`， 说明之前收到过flush tlb的请求，需要
flush tlb

## race -- between `smp_invalidate_interrupt` && `context_switch`

> 下面代码来自2.3.43pre2 由于diff显示不太好，我们直接展示部分代码

### 问题描述
```cpp
/*
 *
 * The flush IPI assumes that a thread switch happens in this order:
 * 1) set_bit(cpu, &new_mm->cpu_vm_mask);
 * 2) update cpu_tlbstate
 * [now the cpu can accept tlb flush request for the new mm]
 * 3) change cr3 (if required, or flush local tlb,...)
 * 4) clear_bit(cpu, &old_mm->cpu_vm_mask);
 * 5) switch %%esp, ie current
 *
 * The interrupt must handle 2 special cases:
 * - cr3 is changed before %%esp, ie. it cannot use current->{active_,}mm.
 * - the cpu performs speculative tlb reads, i.e. even if the cpu only
 *   runs in kernel space, the cpu could load tlb entries for user space
 *   pages.
 *
 * The good news is that cpu_tlbstate is local to each cpu, no
 * write/read ordering problems.
 */

/*
 * TLB flush IPI:
 *
 * 1) Flush the tlb entries if the cpu uses the mm that's being flushed.
 * 2) Leave the mm if we are in the lazy tlb mode.
 * We cannot call mmdrop() because we are in interrupt context,
 * instead update cpu_tlbstate.
 */
asmlinkage void smp_invalidate_interrupt(void)
```

这个注视可能写的有问题，竞争顺序有可能这样:
```
cpu 0: context_switch                               cpu 1: TLB flush others
clear_bit(cpu, &old_mm->cpu_vm_mask);
update cpu_tlbstate
change cr3
set_bit(cpu, &new_mm->cpu_vm_mask);
                                                    send IPI
    interrupt stack
    //此时esp还没有切换，用的是
    //上一个old_mm的esp
    //所以不能使用current
    smp_invalidate_interrupt  {
        do_flush_tlb_local {
             ...
             struct mm_struct *mm = current->mm;
             ...
             set_bit(cpu, &mm->cpu_vm_mask);
             ...
        }

    }
switch %%esp, ie current
```

所以不能访问通过`current`访问 `mm`

kernel引入一个全局变量:
```diff
-extern unsigned int cpu_tlbbad[NR_CPUS];
+#define TLBSTATE_OK    1
+#define TLBSTATE_LAZY  2
+#define TLBSTATE_OLD   3

+struct tlb_state
+       struct mm_struct *active_mm;
+       int state;
+};

+struct tlb_state cpu_tlbstate[NR_CPUS];
```

删除 `cpu_tlbbad`全局变量，增加 `cpu_tlbstate`全局变量，
其中包括 `state`字段和 `active_mm`字段，其中`state`
字段一共有三个值, 这是一个状态机:
```
OK->LAZY : 在switch_mm()时，发现切换的目的线程是内核线程

LAZY->OLD: 在leave_mm()调用时（flush_tlb代码会调用到), 发现为!OK状态,
会将 LAZY状态改为 OLD状态

OLD：在switch_mm()时，如果发现为 OLD 然后 prev->mm == next->mm时，
会flush tlb, 并将状态置位 OK
```

`active_mm` 字段保存当前cpu运行的 `active_mm`, 从而避免了在
flush tlb ipi 中断上下文中访问 current

我们来看下相关代码

###  switch_mm
```cpp
static inline void switch_mm(struct mm_struct *prev, struct mm_struct *next, struct task_struct *tsk, unsigned cpu)
{
        set_bit(cpu, &next->cpu_vm_mask);
        if (prev != next) {
                /*
                 * Re-load LDT if necessary
                 */
                if (prev->segments != next->segments)
                        load_LDT(next);
#ifdef CONFIG_SMP
                cpu_tlbstate[cpu].state = TLBSTATE_OK;
                cpu_tlbstate[cpu].active_mm = next;
#endif
                /* Re-load page tables */
                asm volatile("movl %0,%%cr3": :"r" (__pa(next->pgd)));
                clear_bit(cpu, &prev->cpu_vm_mask);
        }
#ifdef __SMP__
        else {  //prev == next
                int old_state = cpu_tlbstate[cpu].state;
                cpu_tlbstate[cpu].state = TLBSTATE_OK;
                if(cpu_tlbstate[cpu].active_mm != next)
                        BUG();
                //查看 old_state 是否为  TLBSTATE_OLD, 如果是
                //则flush tlb
                if(old_state == TLBSTATE_OLD)
                        local_flush_tlb();
        }

#endif
}
```

### leave_mm
```cpp
static void inline leave_mm(unsigned long cpu)
{
#ifdef TLB_PARANOIA
        if(cpu_tlbstate[cpu].state == TLBSTATE_OK)
                BUG();
#endif
        //清楚该bit，LAZY tlb的核心部分，上面分析过
        clear_bit(cpu, &cpu_tlbstate[cpu].active_mm->cpu_vm_mask);
        //将 state 设置为 OLD, 在 switch mm 时，在 flush tlb
        cpu_tlbstate[cpu].state = TLBSTATE_OLD;
}
```

## SEND IPI optimize
之前的代码逻辑中，发送ipi是给所有的cpu发送，但是 lapic支持给某些
CPU 发送ipi 中断(在这里就不详细介绍)。这样如果LAZY tlb实现后，
接收过一次tlb flush ipi 的内核线程，发起者就不会再向其发送了。

在kernel的下一个版本:`2.3.43pre3`引入了该patch，我们看下:

```cpp
static void flush_tlb_others (unsigned long cpumask, struct mm_struct *mm,
                                                unsigned long va)
{
        /*
         * A couple of (to be removed) sanity checks:
         *
         * - we do not send IPIs to not-yet booted CPUs.
         * - current CPU must not be in mask
         * - mask must exist :)
         */
        if (!cpumask)
                BUG();
        if ((cpumask & cpu_online_map) != cpumask)
                BUG();
        if (cpumask & (1 << smp_processor_id()))
                BUG();

        /*
         * i'm not happy about this global shared spinlock in the
         * MM hot path, but we'll see how contended it is.
         */
        spin_lock(&tlbstate_lock);

        flush_mm = mm;
        flush_va = va;
        atomic_set_mask(cpumask, &flush_cpumask);
        /*
         * We have to send the IPI only to
         * CPUs affected.
         */
        send_IPI_mask(cpumask, INVALIDATE_TLB_VECTOR);

        while (flush_cpumask)
                /* nothing. lockup detection does not belong here */;

        flush_mm = NULL;
        flush_va = 0;
        spin_unlock(&tlbstate_lock);
}
```
可以看到其用 spin_lock() 替换了 关中断的spinloop, 但是作者也说到了，
他不想用spinlock在这种执行比较频繁的路径中，但是借助 spinlock可以
看一些竞争的情况。

另外，在`send_IPI_mask()` 接口中，增加了 cpumask参数。我们来看下该代码:
```cpp
static inline void send_IPI_mask(int mask, int vector)
{
        unsigned long cfg;
#if FORCE_READ_AROUND_WRITE
        unsigned long flags;

        __save_flags(flags);
        __cli();
#endif

        /*
         * prepare target chip field
         */

        cfg = __prepare_ICR2(mask);
        apic_write(APIC_ICR2, cfg);

        /*
         * program the ICR
         */
        cfg = __prepare_ICR(0, vector);

        /*
         * Send the IPI. The write to APIC_ICR fires this off.
         */
        apic_write(APIC_ICR, cfg);
#if FORCE_READ_AROUND_WRITE
        __restore_flags(flags);
#endif
}
static inline int __prepare_ICR2 (unsigned int mask)
{
        unsigned int cfg;

        cfg = __get_ICR2();
#if LOGICAL_DELIVERY
        cfg |= SET_APIC_DEST_FIELD(mask);
#else
        cfg |= SET_APIC_DEST_FIELD(mask);
#endif

        return cfg;
}
```
关于 LAPIC ICR 的部分，这里不详细介绍，可以看到其根据mask
会构造出 icr中的 destination field，这样发起者就会发送给
指定的CPU

## delay TLB invalidate side effect
`INTEL sdm 4.10.4.4 Delayed invalidation` 一节中，讲到了 `delay flush tlb`所带来的
可能的一些隐患。 其中提到:

```
However, because of speculative execution (or errant software), there may
be accesses to the freed portion of the linear-address space before the
invalidations occur. 

但是，因为预测执行(或者非法软件), 他们也可能 在 invalidate 发生之前
访问 线性地址空间的freed 的部分
```
我们来看下面的patch

```diff
commit 99ef44b79de47f23869897c11493521a1e42b2d2
Author: Linus Torvalds <torvalds@home.transmeta.com>
Date:   Mon May 20 05:58:03 2002 -0700

    Clean up %cr3 loading on x86, fix lazy TLB problem

 /*
  * We cannot call mmdrop() because we are in interrupt context,
  * instead update mm->cpu_vm_mask.
+ *
+ * We need to reload %cr3 since the page tables may be going
+ * away from under us..
  */
 static void inline leave_mm (unsigned long cpu)
 {
        if (cpu_tlbstate[cpu].state == TLBSTATE_OK)
                BUG();
        clear_bit(cpu, &cpu_tlbstate[cpu].active_mm->cpu_vm_mask);
+       load_cr3(swapper_pg_dir);
 }
```
但是这里有一个疑问, kernel 引入这行代码，真的是为了预防上面提到的
那个么?


# 总结
以上是对 LAZY TLB 的总结, 大概来说，LAZY TLB 可以使收到一次 flush tlb
ipi 的 内核线程，不再处理该ipi , 并且发起者也不再向其发送。等在
switch_mm时，再flush。
