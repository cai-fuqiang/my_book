# COMMIT MESSAGE
```
commit 241771ef016b5c0c83cd7a4372a74321c973c1e6
Author: Ingo Molnar <mingo@elte.hu>
Date:   Wed Dec 3 10:39:53 2008 +0100

    performance counters: x86 support

    Implement performance counters for x86 Intel CPUs.

    It's simplified right now: the PERFMON CPU feature is assumed,
    which is available in Core2 and later Intel CPUs.

    The design is flexible to be extended to more CPU types as well.

    Signed-off-by: Ingo Molnar <mingo@elte.hu>
```

x86 的 perf 框架比较混乱, 这里提到, 该patch可以适用于Core2, 以及更晚
的 Intel CPUs. 

# 代码分析
## COUNTER INIT -- hw_perf_counter_init
```cpp
/*
 * Setup the hardware configuration for a given hw_event_type
 */
int hw_perf_counter_init(struct perf_counter *counter, s32 hw_event_type)
{
        struct hw_perf_counter *hwc = &counter->hw;

        if (unlikely(!perf_counters_initialized))
                return -EINVAL;

        /*
         * Count user events, and generate PMC IRQs:
         * (keep 'enabled' bit clear for now)
         *
         * 默认会count USE event这里先不设置enabled bit, 
         * 会在 __hw_perf_counter_enable的时候, 使能
         */
        hwc->config = ARCH_PERFMON_EVENTSEL_USR | ARCH_PERFMON_EVENTSEL_INT;

        /*
         * If privileged enough, count OS events too, and allow
         * NMI events as well:
         *
         * 默认是不是用NMI, 使用NMI有两个条件.
         *   + 特权进程: CAP_SYS_ADMIN
         *   + hw_event_type, 标记了 PERF_COUNT_NMI
         */
        hwc->nmi = 0;
        /*
         * 另外如果是特权进程的话, 可以count OS event
         */
        if (capable(CAP_SYS_ADMIN)) {
                hwc->config |= ARCH_PERFMON_EVENTSEL_OS;
                if (hw_event_type & PERF_COUNT_NMI)
                        hwc->nmi = 1;
        }

        hwc->config_base = MSR_ARCH_PERFMON_EVENTSEL0;
        hwc->counter_base = MSR_ARCH_PERFMON_PERFCTR0;
        //中断的采样周期, 该参数是userspace 通过 sys_perf_counter_open 的
        //hw_event_period 传递下来的
        hwc->irq_period = counter->__irq_period;
        /*
         * Intel PMCs cannot be accessed sanely above 32 bit width,
         * so we install an artificial 1<<31 period regardless of
         * the generic counter period:
         *
         * 如果没有设置采样周期, 则设置为 0xFFFFFFFF / 2
         */
        if (!hwc->irq_period)
                hwc->irq_period = 0x7FFFFFFF;
        /*
         * next_count 表示下次要写入counter的值. 
         * 其为采样周期的负值, 负值的意思是相加等于
         * 0, 正好满足溢出的条件, 举个例子:
         * 
         * 如果采样周期是 100, 那么希望过100个周期达到
         * 溢出条件, 那么next_count 就设置为 0xFFFFFFFF-100
         * 其实也就是-100
         */
        hwc->next_count = -((s32) hwc->irq_period);

        /*
         * Negative event types mean raw encoded event+umask values:
         *
         * 如果 < 0, 则表示不是common counter, 需要取绝对值,
         * 另外 hw_event_type中的 PERF_COUNT_NMI位表示是否使用NMI.
         * 所以在获取eventtype值时, 需要将其屏蔽.
         */
        if (hw_event_type < 0) {
                counter->hw_event_type = -hw_event_type;
                counter->hw_event_type &= ~PERF_COUNT_NMI;
        } else {
                //这里说明是common counter
                hw_event_type &= ~PERF_COUNT_NMI;
                //不在common counter范围之内
                if (hw_event_type >= max_intel_perfmon_events)
                        return -EINVAL;
                /*
                 * The generic map:
                 */
                counter->hw_event_type = intel_perfmon_event_map[hw_event_type];
        }
        //或上 event type
        hwc->config |= counter->hw_event_type;
        counter->wakeup_pending = 0;

        return 0;
}
```
* intel_perfmon_event_map
  ```cpp
  const int intel_perfmon_event_map[] =
  {
    [PERF_COUNT_CYCLES]                   = 0x003c,
    [PERF_COUNT_INSTRUCTIONS]             = 0x00c0,
    [PERF_COUNT_CACHE_REFERENCES]         = 0x4f2e,
    [PERF_COUNT_CACHE_MISSES]             = 0x412e,
    [PERF_COUNT_BRANCH_INSTRUCTIONS]      = 0x00c4,
    [PERF_COUNT_BRANCH_MISSES]            = 0x00c5,
  };
  
  const int max_intel_perfmon_events = ARRAY_SIZE(intel_perfmon_event_map);
  ```
## COUNTER ENABLE --  hw_perf_counter_enable
```cpp
void hw_perf_counter_enable(struct perf_counter *counter)
{
        struct cpu_hw_counters *cpuc = &__get_cpu_var(cpu_hw_counters);
        struct hw_perf_counter *hwc = &counter->hw;
        int idx = hwc->idx;

        /* Try to get the previous counter again */
        //如果之前的counter被使用了, 那就再找一个空闲的
        if (test_and_set_bit(idx, cpuc->used)) {
                idx = find_first_zero_bit(cpuc->used, nr_hw_counters);
                set_bit(idx, cpuc->used);
                hwc->idx = idx;
        }
        //==(1)==
        perf_counters_lapic_init(hwc->nmi);

        wrmsr(hwc->config_base + idx,
              hwc->config & ~ARCH_PERFMON_EVENTSEL0_ENABLE, 0);
        //将该cpu counter设置上
        cpuc->counters[idx] = counter;
        //将enable bit 置位
        counter->hw.config |= ARCH_PERFMON_EVENTSEL0_ENABLE;
        //==(2)==
        __hw_perf_counter_enable(hwc, idx);
}
```
1. perf_counters_lapic_init
   ```cpp
   void __cpuinit perf_counters_lapic_init(int nmi)
   {
           u32 apic_val;
   
           if (!perf_counters_initialized)
                   return;
           /*
            * Enable the performance counter vector in the APIC LVT:
            */
           /*
            * 这里不知道为什么要处理 LVT Error Register 的 Mask bits.
            * 如果该Mask设置为1, 相当于不再接收该中断.
            * 手册中也有提到:
            *
            * When the local APIC handles a performance-monitoring counters
            * interrupt, it automatically sets the mask flag in the LVT
            * performance counter register. This flag is set to 1 on reset. It
            * can be cleared only by software.
            *
            * 暂时先不看
            */

           apic_val = apic_read(APIC_LVTERR);

           apic_write(APIC_LVTERR, apic_val | APIC_LVT_MASKED);
           //如果是 nmi的话, 将deliver mode 设置为 NMI
           if (nmi)
                   apic_write(APIC_LVTPC, APIC_DM_NMI);
           else
           //如果不是, 则设置为
                   apic_write(APIC_LVTPC, LOCAL_PERF_VECTOR);
           apic_write(APIC_LVTERR, apic_val);
   }
   ```

2.  `__hw_perf_counter_enable`
   ```cpp
   static void __hw_perf_counter_enable(struct hw_perf_counter *hwc, int idx)
   {
           per_cpu(prev_next_count[idx], smp_processor_id()) = hwc->next_count;
           //这里把 next_count, 设置到 counter_base寄存器中了
           wrmsr(hwc->counter_base + idx, hwc->next_count, 0);
           wrmsr(hwc->config_base + idx, hwc->config, 0);
   }
   ```
## COUNTER DISABLE -- hw_perf_counter_disable
```cpp
void hw_perf_counter_disable(struct perf_counter *counter)
{
        struct cpu_hw_counters *cpuc = &__get_cpu_var(cpu_hw_counters);
        struct hw_perf_counter *hwc = &counter->hw;
        unsigned int idx = hwc->idx;
        //取消enable bit
        counter->hw.config &= ~ARCH_PERFMON_EVENTSEL0_ENABLE;
        wrmsr(hwc->config_base + idx, hwc->config, 0);

        clear_bit(idx, cpuc->used);
        //将 该cpu的counter设置为 NULL
        cpuc->counters[idx] = NULL;
        //==(1)==
        __hw_perf_save_counter(counter, hwc, idx);
}
```
1.  `__hw_perf_save_counter`
```cpp
static void __hw_perf_save_counter(struct perf_counter *counter,
                                   struct hw_perf_counter *hwc, int idx)
{
        s64 raw = -1;
        s64 delta;
        int err;

        /*
         * Get the raw hw counter value:
         *
         * 从硬件里面获取counter
         */
        err = rdmsrl_safe(hwc->counter_base + idx, &raw);
        WARN_ON_ONCE(err);

        /*
         * Rebase it to zero (it started counting at -irq_period),
         * to see the delta since ->prev_count:
         */
        //==(1)==
        delta = (s64)hwc->irq_period + (s64)(s32)raw;

        //==(2)==
        atomic64_counter_set(counter, hwc->prev_count + delta);

        /*
         * Adjust the ->prev_count offset - if we went beyond
         * irq_period of units, then we got an IRQ and the counter
         * was set back to -irq_period:
         */
        //==(3)==
        while (delta >= (s64)hwc->irq_period) {
                hwc->prev_count += hwc->irq_period;
                delta -= (s64)hwc->irq_period;
        }

        /*
         * Calculate the next raw counter value we'll write into
         * the counter at the next sched-in time:
         *
         * (4)
         */
        delta -= (s64)hwc->irq_period;

        hwc->next_count = (s32)delta;
}
```
1. delta 表示, 据上次设置, counter 变化了多少
   ```
   delta = irq_period + raw = -hwc->prev_count + raw
         = 现在counter的值 - 原来counter设置的值
         = 经上次设置, counter的变化
   ```
   这里我们需要知道, 用户态传递下来的 `hw_event_period`参数是u32,
   而 hwc->irq_period, coiunter->__irq_period 都是 u64

   这里理论上可以得到counter的变化,但是需要考虑溢出

   假设, 我们将 hwc->irq_period 采样周期设置为 `0xffff fffe`, 
   理论上, prev_count 应该设置为 2, 那么如果 现在读出来的值
   为 3, 说明溢出了, 这里我们计算得到

   0x1 00000001

2. 这里将counter设置为, 原来的值 + 变化的值:

   这也是计算counter值的标准方法. 
   同样也需要考虑溢出, 我们通过(1)中的例子,得出写入counter的值
   为 0x1 00000003. 那么这里搞这些是做什么呢.
   就是为了可以读出一个总数(加上溢出位的), 可以读出counter的总数量.

3. 如果 变化的值, 超越了 irq_period, 说明counters 的变化已经
   超过了采样周期,却没有触发PMI.

   这里采用一个循环, 相当于把 delta 的值, 减少到 < irq_period, 
   然后将减出去的值, 加到prev_count. 
   
   这里为什么呢, 我们需要结合之前`hw_perf_counter_read`,
   这里之后需要将 delta 值做运算,写到next_count中, 而next_count 
   是u32 , 因为其代表enable counter 要写入counter寄存器的值, 所以
   这里我们需要写入一个不能大于 irq_period 的值.为什么? 
   因为: 

   这里需要让 变化后的 delta + irq_period 一定能刚好达到溢出条件.
   否则相当于在当前counter 基础上, 有过了 irq_period 还是没有触发PMI, 
   就不符合基本逻辑了.

   我们再来看代码:

   delta -=  hwc->irq_period
   delta < hwc->irq_period 

   delta' = delta - irq_period  此值肯定溢出
   delta < hwc->irq_period 

   那么此时 delta' + irq_period = delta - irq_period + irq_period 会不会溢出.
   其实会.

   就像 -1 + 2 = 1 溢出了 1 - 2 = -1 同样溢出.

   但是不知道是什么数学原理.

   再者, 溢出之后的值 会不会小于 irq_period, 其实会.(怎么证明呢?)
