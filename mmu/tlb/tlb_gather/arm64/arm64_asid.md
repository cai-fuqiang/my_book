# ARM64 SPEC
ASID 是类似于x86的PCID, 用于在TLB中作为一个searchkey来标记
该tlb是哪个内存空间, 我们来看下arm64 ASID的相关内容:

* ASID bits

  在 `ID_AA64MMFR0_EL1.ASIDBits`中定义了ASID的bits: 

  ![ID_AA64MMFR0_EL1_ASID_BIT](pic/ID_AA64MMFR0_EL1_ASID_BIT.png) 

* switch asid

  `ttbr0_elx`很像是x86的cr3, x86的cr3可以指定pcid, 而`ttbr0_elx`也可以
  指定asid, 如下图:

  ![TTBR0_EL1_ASID](pic/TTBR0_EL1_ASID.png) 

  可以看到,一共16bits, 图片中也提到,如果asidbits为8, 高8bits是reserved


# ORG PATCH 代码分析

## asid 相关数据结构
```cpp
//FILE include/linux/mm_types.h
struct mm_struct {
    ...
    mm_context_t context;
    ...
};
//FILE arch/arm64/include/asm/mmu.h ---这个是arch 特定的
typedef struct {
        unsigned int id;
        raw_spinlock_t id_lock;
        void *vdso;
} mm_context_t;
```

其中id 表示 asid, 该字段是`unsigned int`, 32-bits, 但是asid
只有16 bits, 所以该字段有两部分:
```
31              15              0
|                |              |
  asid version         asid
```

内核中获取asid 可以通过下面的宏
```cpp
//FILE arch/arm64/include/asm/mmu.h
#define ASID(mm)        ((mm)->context.id & 0xffff)
```
那为什么有要区分两个字段呢, 我们来设想下面的场景:
> NOTE
>
> switch to (进程切换, 我们用 -> 表示

当 task1->task2时, 我们要不要flush task1 tlb ? 如下:
```
task comm           asid
a                   0
b(flush asid 0)     0
b(flush asid 1)     0
b(flush asid 2)     0
...
```

因为arm64 支持asid, 在cpu tlb 中可以共存多个地址空间的 
tlb entry. 上面这样做就体现不出asid的优点(可以共存多个地址空间tlb)
例如下面的场景:
```
task comm           asid
a                   0
b                   1
c                   2
d                   3

task switch         need flush
x->x                N
```
给进程a,b,c,d分配了自己的asid之后, 我们切换task, 就不用flush tlb,
而例如在 a->b的后, cpu中可能还存有b的tlb, 所以也会提高性能.这就是asid
的作用.

而在操作系统运行时, 我们采用什么样的asid分配策略呢,
因为8/16bits asidbits(这里我们假设为16bits), 
一时半会用不完, 我们一直往上累加asid, 这样进程每次都
是最新的, 如下:
```
task comm           asid
a                   0
b                   1
c                   2
d                   3
e                   4
...
```
但是其总会溢出16bits, 如下:
```
task comm           asid
aa                 0xffff
ab                 ???
```
当进程`aa`的asid为`0xffff`时, `ab`的asid该设置多少呢? 只能从头开
始, 设置为0, 这时, 我们相当于开启了新的一轮的tlb id allocate, 
当然, 此时我们可以只flush asid == 1 的 tlb, 但是就会有下面的
场景:
```
task comm                   asid
f                           0xfffe
aa                          0xffff
    flush asid 0
ab                          0
    flush asid 1
ac                          1
    flush asid 2
ad                          2
```
这样做有什么好处呢? 
假设, ab->f, 这时候, cpu可能还有f的tlb. 但是坏处是, 之后的每次切换都
需要flush tlb. kernel开发者们衡量之后, 是这样做的:
```
task comm                   asid
f                           0xfffe
aa                          0xffff
    flush ALL tlb
ab                          0
ac                          1
ad                          2
..
af                          0xfffe
```

在ab 分配asid之前,将所有tlb flush掉. 这样之后的asid的分配, 不再需要flush 
tlb.

在flush ALL tlb之后, cpu tlb中已经没有 进程`f`地址空间的 tlb entry了,
那么 `af->f`这时候也不需要刷tlb, 这个是怎么做到的呢, 就是上面我们提到的
version, 我们可以把 asid 在软件层面扩展成:(asid version , asid), 这样的二元结构:
```
task comm                   (asid_version, asid)
f                           (0,0xfffe)
aa                          (0,0xffff)
    flush ALL tlb
    bump version, current version is 1
ab                          (1,0)
...
af                          (1,0xfffe)
```
当`af->f`时, 发现`(1, 0xfffe) != (0,0xfffe)`, 所以不需要刷tlb. 但是切换f进程之前,可能
要重新获取下asid, `(0, 0xfffe) -> (1, 0xffff)`, 我们下面会详细分析代码

和asid 相关的一个主要流程,就是task switch, 和tlb 相关的一个重要的功能就是 lazy tlb, 
我们直接从 context_switch开始看.

## context_switch

我们直接从`context_switch`开始看:
```cpp
static inline void
context_switch(struct rq *rq, struct task_struct *prev,
               struct task_struct *next)
{
        ...
        mm = next->mm;
        ...
        //==(1)==
        if (!mm) {
                next->active_mm = oldmm;
                atomic_inc(&oldmm->mm_count);
                enter_lazy_tlb(oldmm, next);
        } else
        //==(2)==
                switch_mm(oldmm, mm, next);

        if (!prev->mm) {
                //如果是内核线程, 将 active_mm再次置为NULL
                prev->active_mm = NULL;
                rq->prev_mm = oldmm;
        }
        ...

}
```
1. 当为内核线程时, 可以进入lazy mode, 会执行 enter_lazy_tlb(),
   但是arm64并没有实现
   ```cpp
   /*
    * This is called when "tsk" is about to enter lazy TLB mode.
    *
    * mm:  describes the currently active mm context
    * tsk: task which is entering lazy tlb
    * cpu: cpu number which is entering lazy tlb
    *
    * tsk->mm will be NULL
    */
   static inline void
   enter_lazy_tlb(struct mm_struct *mm, struct task_struct *tsk)
   {
   }
   ```



下面我们详细分析 `switch_mm`

`switch_mm`:
```cpp
/*
 * This is the actual mm switch as far as the scheduler
 * is concerned.  No registers are touched.  We avoid
 * calling the CPU specific function when the mm hasn't
 * actually changed.
 */
static inline void
switch_mm(struct mm_struct *prev, struct mm_struct *next,
          struct task_struct *tsk)
{
        unsigned int cpu = smp_processor_id();

#ifdef CONFIG_SMP
        //flush icache 先不关注
        /* check for possible thread migration */
        if (!cpumask_empty(mm_cpumask(next)) &&
            !cpumask_test_cpu(cpu, mm_cpumask(next)))
                __flush_icache_all();
#endif
        //相当于判断如果当前cpu所在的地址空间不是 next, 则做切换
        //    mm_cpumask() 会统计那些cpu上运行的地址空间是该 mm
        if (!cpumask_test_and_set_cpu(cpu, mm_cpumask(next)) || prev != next)
                check_and_switch_context(next, tsk);
}

static inline void check_and_switch_context(struct mm_struct *mm,
                                            struct task_struct *tsk)
{
        /*
         * Required during context switch to avoid speculative page table
         * walking with the wrong TTBR.
         */
        cpu_set_reserved_ttbr0();
        
        /*
         * 这里会判断当前的 context.id version和 cpu_last_asid version
         * 异或的目的, 是看这两个是否相等, 异或为真, 则不相等, 所以这个if
         * 条件如果为真, 则表示 这两个 asid version 相同
         */
        //#define MAX_ASID_BITS   16
        if (!((mm->context.id ^ cpu_last_asid) >> MAX_ASID_BITS))
                /*
                 * The ASID is from the current generation, just switch to the
                 * new pgd. This condition is only true for calls from
                 * context_switch() and interrupts are already disabled.
                 *
                 * 该流程发生在 context_switch()上下文中, 并且之前获取过asid, 
                 * asid version 有是当前最新的version, 所以可以直接切换,
                 * 下面我们会详细讲 asid version 相关处理
                 */
                cpu_switch_mm(mm->pgd, mm);
        else if (irqs_disabled())
                /*
                 * Defer the new ASID allocation until after the context
                 * switch critical region since __new_context() cannot be
                 * called with interrupts disabled.
                 *
                 * 先不看这个
                 */
                set_ti_thread_flag(task_thread_info(tsk), TIF_SWITCH_MM);
        else
                /*
                 * That is a direct call to switch_mm() or activate_mm() with
                 * interrupts enabled and a new context.
                 *
                 * 这里要为进程分配新的asid, 因为要切换的task 可能使用的是old asid
                 * version, 所以
                 */
                switch_new_context(mm);
}
```

`switch_new_context`:
```cpp
static inline void switch_new_context(struct mm_struct *mm)
{
        unsigned long flags;

        __new_context(mm);

        local_irq_save(flags);
        cpu_switch_mm(mm->pgd, mm);
        local_irq_restore(flags);
}
```
大概有两件事:
* 分配新的asid -- `__new_context`
* 切换到新的 mm -- `cpu_switch_mm`

`__new_context`:
```cpp
void __new_context(struct mm_struct *mm)
{
        unsigned int asid;
        unsigned int bits = asid_bits();

        raw_spin_lock(&cpu_asid_lock);
#ifdef CONFIG_SMP
        /*
         * Check the ASID again, in case the change was broadcast from another
         * CPU before we acquired the lock.
         */
        //注释中提到可以收到其他CPU 的 braodcast(IPI), 然后,看起来会更改 mm->context.id
        //让其可能是新 version ? 跟 reset_context()流程有关,我们稍后看
        if (!unlikely((mm->context.id ^ cpu_last_asid) >> MAX_ASID_BITS)) {
                cpumask_set_cpu(smp_processor_id(), mm_cpumask(mm));
                raw_spin_unlock(&cpu_asid_lock);
                return;
        }
#endif
        /*
         * At this point, it is guaranteed that the current mm (with an old
         * ASID) isn't active on any other CPU since the ASIDs are changed
         * simultaneously via IPI.
         *
         * 什么意思呢???
         */
        asid = ++cpu_last_asid;

        /*
         * If we've used up all our ASIDs, we need to start a new version and
         * flush the TLB.
         */
        //这里说明asid 用完了, 需要 bump asid version
        if (unlikely((asid & ((1 << bits) - 1)) == 0)) {
                /* increment the ASID version */
                //这里会因为上面 ++cpu_last_asid 溢出一位,所以需要减去 
                //   - (1 << bits)
                cpu_last_asid += (1 << MAX_ASID_BITS) - (1 << bits);
                //如果整个的cpu_last_asid 都用完了, 也就是asid version 
                //也溢出了, 更新到ASID_FIRST_VERSION
                if (cpu_last_asid == 0)
                        cpu_last_asid = ASID_FIRST_VERSION;
                //==(1)==
                asid = cpu_last_asid + smp_processor_id();
                flush_context();
#ifdef CONFIG_SMP
                smp_wmb();
                //==(2)==
                smp_call_function(reset_context, NULL, 1);
#endif
                //==(3)==
                cpu_last_asid += NR_CPUS - 1;
        }
        //下面会讲
        set_mm_context(mm, asid);
        raw_spin_unlock(&cpu_asid_lock);
}
```
我们直接看, 比较关键的 `flush_context()`  和`reset_context`这两个流程:
1. `flush_context`
   ```cpp
   static void flush_context(void)
   {
           /* set the reserved TTBR0 before flushing the TLB */
           cpu_set_reserved_ttbr0();
           flush_tlb_all();
           if (icache_is_aivivt())
                   __flush_icache_all();
   }
   static inline void flush_tlb_all(void)
   {
           dsb();
           asm("tlbi       vmalle1is");
           dsb();
           isb();
   }
   ```
   这里调用的 tlbi 指令为 `vmalle1is`指令
   ```
   VMALLE1ISTLB invalidate by VMID, EL1, Inner Shareable.
   ```
   首先是无效该 VMID,这里可以认为是host, 并且是IS(broadcast)

   我们先看当前cpu的进程如何分配asid
   ```
   asid = cpu_last_asid + smp_processor_id()
   ```
   可以看到, 在 cpu_last_asid 后, 加了`smp_processor_id()` , 
   这样做是因为其他的cpu上的进程也得重新分配

   那么此时, 其他的进程应该如何做呢 ? 理论上来说,其他进程的TLB都已经被
   invalidate了, 使用老的asid已经没有意义了, 我们分两种情况:
   * 在其他cpu上运行:  立即重新分配asid
   * 没有在其他cpu上运行: 等调度到该进程时, 再重新分配asid
   
   这里立即分配,就需要发送ipi了, 我们来看 `reset_context`流程
2. `reset_context`
   ```cpp
   /*
    * Reset the ASID on the current CPU. This function call is broadcast from the
    * CPU handling the ASID rollover and holding cpu_asid_lock.
    */
   static void reset_context(void *info)
   {
           unsigned int asid;
           unsigned int cpu = smp_processor_id();
           struct mm_struct *mm = current->active_mm;
   
           smp_rmb();
           //重新获取asid
           asid = cpu_last_asid + cpu;
           //因为此时cpu还在跑, 所以可能会产生一些老的asid的tlb,
           //所以这里再flush下(那为什么还要用 IS 的tlbi指令呢)
           flush_context();
           //下面会讲这个函数, 这里作用, 主要是设置mm->context.id
           set_mm_context(mm, asid);
           //这里并不是为了切换内存空间,而是去修改asid, 我们下面
           //也会讲到这个函数
           /* set the new ASID */
           cpu_switch_mm(mm->pgd, mm);
   }
   ```
3. 前面讲到[0, NR_CPUS) 都被每个cpu上的进程申请了, 所以这里要加上

那么函数主要剩余两个:
* set_mm_context
  ```cpp
  static void set_mm_context(struct mm_struct *mm, unsigned int asid)
  {
          unsigned long flags;
  
          /*
           * Locking needed for multi-threaded applications where the same
           * mm->context.id could be set from different CPUs during the
           * broadcast. This function is also called via IPI so the
           * mm->context.id_lock has to be IRQ-safe.
           */
          raw_spin_lock_irqsave(&mm->context.id_lock, flags);
          //这里可能是reset_context流程调用, 当发起broadcast的cpu上的线程
          //和该线程属于一个进程, 那么这里条件就会为假,不用再更新asid
          if (likely((mm->context.id ^ cpu_last_asid) >> MAX_ASID_BITS)) {
                  /*
                   * Old version of ASID found. Set the new one and reset
                   * mm_cpumask(mm).
                   */
                  mm->context.id = asid;
                  cpumask_clear(mm_cpumask(mm));
          }
          raw_spin_unlock_irqrestore(&mm->context.id_lock, flags);
  
          /*
           * Set the mm_cpumask(mm) bit for the current CPU.
           */
          cpumask_set_cpu(smp_processor_id(), mm_cpumask(mm));
  }
  ```
* cpu_switch_mm
  ```cpp
  #define cpu_switch_mm(pgd,mm) cpu_do_switch_mm(virt_to_phys(pgd),mm) 
  ENTRY(cpu_do_switch_mm)
        mmid    w1, x1                          // get mm->context.id
        bfi     x0, x1, #48, #16                // set the ASID
        msr     ttbr0_el1, x0                   // set TTBR0
        isb
        ret
  ENDPROC(cpu_do_switch_mm)
  ```
  代码比较简单, 注释中都写清楚了, 不赘述. 总之 该流程为类似于x86的switch_cr3

那么, 我们这里思考下, 为什么arm64在该版本为什么没有实现lazy tlb. 原因如下:
1. x86_64 需要 tlb shootdown  flush 其他cpu的tlb, arm64 不需要
2. 目前arm64 flushtlb(tlbi) 的指令, 都是带着IS后缀的

我们知道, tlbi 指令可以不带 IS 后缀, 需要关注下后续的patch 会不会引入.


