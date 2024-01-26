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

## COUNTER READ -- hw_perf_counter_read
```cpp
void hw_perf_counter_read(struct perf_counter *counter)
{
        struct hw_perf_counter *hwc = &counter->hw;
        unsigned long addr = hwc->counter_base + hwc->idx;
        s64 offs, val = -1LL;
        s32 val32;
        int err;

        /* Careful: NMI might modify the counter offset */
        do {
                offs = hwc->prev_count;
                err = rdmsrl_safe(addr, &val);
                WARN_ON_ONCE(err);
        } while (offs != hwc->prev_count);

        val32 = (s32) val;
        val =  (s64)hwc->irq_period + (s64)val32;
        atomic64_counter_set(counter, hwc->prev_count + val);
}
```

counter read的值, 应该 = hwc->prev_count + counter的变化
= hw->prev_count + (counter - 原来counter的值)
= hw->prev_count + (counter + irq_period)

> NOTE
>
> 这里要注意的是 原来counter的值, 并不是上一次设置counter的值, 而是
> 上一次应该设置的counter的值, 也就是根据采样周期设置的值, 是以那个为基准,
> 因为在`__hw_perf_save_counter`中, 我们会看到, 会根据现有counter的值,对要设置
> counter的值, 在 -irq_period上做微调.我们会在`__hw_perf_save_counter`进一步论述

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
         */
        //==(3.1)==
        delta -= (s64)hwc->irq_period;

        //==(4)==
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

   但是如果超过的值是irq_period的倍数, 我们要减少到 < irq_period, 
   为什么呢? 假如 irq_period 是 3, 现在delta是7, 那么我们要减少到1,
   表示下次设置采样周期时, 要减少一个

   我们来看 next_count表示, 下次 要设置的 counter的值.

   应该为:
   ```
   -irq_period = -(irq_period - delta) = delta - irq_period
   ```

   所以, 在(3.1) 这个地方, 我们会将delta 调整到 < irq_period之后,
   在 delta = delta - irq_period, 调整之后的 delta 其实就是 要写入
   counter的值

   > irq_period' 表示调整之后的采样周期
4. 将调整之后的 delta 写入 perv_count

## COUNTER - INTR/NMI handler
由于特权级用户态进程可以通过指定`hw_event_type`中的 `PERF_COUNT_NMI`
来指定使用NMI作为PMI, 否则使用interrupt

我们来分别看下这两个handler

* NMI
  ```cpp
  static int __kprobes
  perf_counter_nmi_handler(struct notifier_block *self,
                           unsigned long cmd, void *__args)
  {
          struct die_args *args = __args;
          struct pt_regs *regs;
  
          if (likely(cmd != DIE_NMI_IPI))
                  return NOTIFY_DONE;
  
          regs = args->regs;
  
          apic_write(APIC_LVTPC, APIC_DM_NMI);
          __smp_perf_counter_interrupt(regs, 1);
  
          return NOTIFY_STOP;
  }
  ```

* intr
  ```cpp
  void smp_perf_counter_interrupt(struct pt_regs *regs)
  {
          irq_enter();
  #ifdef CONFIG_X86_64
          add_pda(apic_perf_irqs, 1);
  #else
          per_cpu(irq_stat, smp_processor_id()).apic_perf_irqs++;
  #endif
          apic_write(APIC_LVTPC, LOCAL_PERF_VECTOR);
          __smp_perf_counter_interrupt(regs, 0);
  
          irq_exit();
  }
  ```
都调用到了`__smp_perf_counter_interrupt`

```cpp
/*
 * This handler is triggered by the local APIC, so the APIC IRQ handling
 * rules apply:
 */
static void __smp_perf_counter_interrupt(struct pt_regs *regs, int nmi)
{
        int bit, cpu = smp_processor_id();
        struct cpu_hw_counters *cpuc;
        u64 ack, status;

        rdmsrl(MSR_CORE_PERF_GLOBAL_STATUS, status);
        if (!status) {
                ack_APIC_irq();
                return;
        }

        /* Disable counters globally */
        wrmsr(MSR_CORE_PERF_GLOBAL_CTRL, 0, 0);
        ack_APIC_irq();

        cpuc = &per_cpu(cpu_hw_counters, cpu);

again:
        ack = status;
        for_each_bit(bit, (unsigned long *) &status, nr_hw_counters) {
                struct perf_counter *counter = cpuc->counters[bit];

                clear_bit(bit, (unsigned long *) &status);
                if (!counter)
                        continue;
                //==(1)==
                perf_save_and_restart(counter);

                switch (counter->record_type) {
                case PERF_RECORD_SIMPLE:
                        continue;
                case PERF_RECORD_IRQ:
                        perf_store_irq_data(counter, instruction_pointer(regs));
                        break;
                case PERF_RECORD_GROUP:
                        perf_store_irq_data(counter, counter->hw_event_type);
                        perf_store_irq_data(counter,
                                            atomic64_counter_read(counter));
                        perf_handle_group(counter, &status, &ack);
                        break;
                }
                /*
                 * From NMI context we cannot call into the scheduler to
                 * do a task wakeup - but we mark these counters as
                 * wakeup_pending and initate a wakeup callback:
                 */
                if (nmi) {
                        counter->wakeup_pending = 1;
                        set_tsk_thread_flag(current, TIF_PERF_COUNTERS);
                } else {
                        wake_up(&counter->waitq);
                }
        }

        wrmsr(MSR_CORE_PERF_GLOBAL_OVF_CTRL, ack, 0);

        /*
         * Repeat if there is more work to be done:
         */
        rdmsrl(MSR_CORE_PERF_GLOBAL_STATUS, status);
        if (status)
                goto again;

        /*
         * Do not reenable when global enable is off:
         */
        if (cpuc->enable_all)
                __hw_perf_enable_all();
}
```
* `perf_save_and_retstart`
  ```cpp
  static void perf_save_and_restart(struct perf_counter *counter)
  {
          struct hw_perf_counter *hwc = &counter->hw;
          int idx = hwc->idx;
          //restart 这个counter
          //首先先disable, 避免save的时候, counter还在增加
          wrmsr(hwc->config_base + idx,
                hwc->config & ~ARCH_PERFMON_EVENTSEL0_ENABLE, 0);
          //先save, 在enable 
          if (hwc->config & ARCH_PERFMON_EVENTSEL0_ENABLE) {
                  __hw_perf_save_counter(counter, hwc, idx);
                  __hw_perf_counter_enable(hwc, idx);
          }
  }
  ```

> NOTE
>
> 该算法在
>
> ```
> commit ee06094f8279e1312fc0a31591320cc7b6f0ab1e
> Author: Ingo Molnar <mingo@elte.hu>
> Date:   Sat Dec 13 09:00:03 2008 +0100
> 
>     perfcounters: restructure x86 counter math
> ```
>
> 中更新.

更新后的算法:
```diff
+/*
+ * Propagate counter elapsed time into the generic counter.
+ * Can only be executed on the CPU where the counter is active.
+ * Returns the delta events processed.
+ */
+static void
+x86_perf_counter_update(struct perf_counter *counter,
+                       struct hw_perf_counter *hwc, int idx)
+{
+       u64 prev_raw_count, new_raw_count, delta;
+
+       WARN_ON_ONCE(counter->state != PERF_COUNTER_STATE_ACTIVE);
+       /*
+        * Careful: an NMI might modify the previous counter value.
+        *
+        * Our tactic to handle this is to first atomically read and
+        * exchange a new raw count - then add that new-prev delta
+        * count to the generic counter atomically:
+        */
+again:
        //==(1)==
+       prev_raw_count = atomic64_read(&hwc->prev_count);
+       rdmsrl(hwc->counter_base + idx, new_raw_count);
+
+       if (atomic64_cmpxchg(&hwc->prev_count, prev_raw_count,
+                                       new_raw_count) != prev_raw_count)
+               goto again;
+
+       /*
+        * Now we have the new raw value and have updated the prev
+        * timestamp already. We can now calculate the elapsed delta
+        * (counter-)time and add that to the generic counter.
+        *
+        * Careful, not all hw sign-extends above the physical width
+        * of the count, so we do that by clipping the delta to 32 bits:
+        */
        //==(2)==
+       delta = (u64)(u32)((s32)new_raw_count - (s32)prev_raw_count);
+       WARN_ON_ONCE((int)delta < 0);
+
        //==(3)==
+       atomic64_add(delta, &counter->count);
        //==(4)==
+       atomic64_sub(delta, &hwc->period_left);
+}
```
1. prev_count 表示上一次save的时候 count
2. delta 表示prev_count, new_count之间的差值, 也就是在这两次save中间, 触发了多少个event.
3. 将发生的事件数累加到`counter->count`上.
4. `hwc->period_left`, 也就是 上次设置的counter的负值. 那就是上次设置的实际的采样周期.
   (也就是再过多少个周期就触发overflow), 那么在这次收到PMI后, 我们做save, 去将delta减去,
   表示, 实际上再过多少个周期触发overflow

> NOTE
>
> 上面的所有计算都是无符号类型计算, 其实无符号带符号不影响等式, 而是影响不等式.

```diff
+/*
+ * Set the next IRQ period, based on the hwc->period_left value.
+ * To be called with the counter disabled in hw:
+ */
+static void
+__hw_perf_counter_set_period(struct perf_counter *counter,
+                            struct hw_perf_counter *hwc, int idx)
 {
-       per_cpu(prev_next_count[idx], smp_processor_id()) = hwc->next_count;
+       s32 left = atomic64_read(&hwc->period_left);
+       s32 period = hwc->irq_period;
+
        //==(1)==
+       WARN_ON_ONCE(period <= 0);
+
+       /*
+        * If we are way outside a reasoable range then just skip forward:
+        */
        //==(2)==      
+       if (unlikely(left <= -period)) { 
+               left = period;
+               atomic64_set(&hwc->period_left, left);
+       }
        //==(3)==
+       if (unlikely(left <= 0)) {
+               left += period;
+               atomic64_set(&hwc->period_left, left);
+       }

-       wrmsr(hwc->counter_base + idx, hwc->next_count, 0);
+       WARN_ON_ONCE(left <= 0);
+
+       per_cpu(prev_left[idx], smp_processor_id()) = left;
+
+       /*
+        * The hw counter starts counting from this counter offset,
+        * mark it to be able to extra future deltas:
+        */
+       atomic64_set(&hwc->prev_count, (u64)(s64)-left);
+
+       wrmsr(hwc->counter_base + idx, -left, 0);
 }
```
1. 在`__hw_perf_counter_init`中有说明
   ```
   /*
    * Intel PMCs cannot be accessed sanely above 32 bit width,
    * so we install an artificial 1<<31 period regardless of
    * the generic counter period:
    */
   ```
   提到, Intel PMCs 在超过32 宽度以上, 无法正常访问. 所以, 无论通用
   计数器周期如何, 我们都会install一个  artificial(人工的) `1<<31`
   的period
   代码为:
   ```cpp
   if ((s64)hwc->irq_period <= 0 || hwc->irq_period > 0x7FFFFFFF)
        hwc->irq_period = 0x7FFFFFFF;
   ```
   在无符号`[0x7fffffff, 0xffffffff]`之间都会设置成0x7fffffff

   所以这里, (s32)period不可能小于0
2. 根据1 , 可以得出,如果条件为真:
   `left < 0 <= -period`,  小于0, 说明溢出, 而`|left|`表示:
     + 如果left > 0 , 表示在恰好溢出值的基础上还差多少个event触发
     + 如果left < 0, 表示在恰好溢出值的基础上多触发了多少个event
 
   我们这里以, `left < 0` 举例

   `|left|` 表示 这次我们在设置counter时, 考虑要补偿增加多少(增加多少,
   就意味达到溢出时,少触发的event的数量). 我们记作A, 
   而 不考虑上面补偿的情况下,本次要设置的counter值, 是`-period_left`
   `period + |left| = period - left >=0` 不合理,相当于直接溢出了.
   早期x86的做法是, 循环执行 `left = |left| - period`, 一直执行到
   `left < period`
   
   例如 :left = -7, period = 2 会循环计算得到
   ```
   left = 5
   left = 4
   left = 3
   left = 1
   ```
   现在的做法是, 直接让其 `left = 2`, 这样做实际上不会影响counter值的计算,
   而是会影响采样频率.

   可以这样解释:

   之前的采样类似于这种
   假设采样周期是4.
   ```
          这里出
          现偏差
   |----|-------|-|----|----|
      4     7    1  4    4
   ```
   这里7 这个地方采样不精确了一次, 而总的采样不精确的次数是1次

   现在的做法:
   ```
   |----|-------|----|----|
     4     7       4   4 
   ```
   同样, 总的采样不精确的次数也是1次.

   两者相比, 第一种会多采样一次.(不过我更倾向与第一种, 在同样的采样时间内, 
   第一种获取到的正确的采样周期更多)
3. 这个地方跟上面的解释差不多,但是会做下面的事情(这种实际上不是overflow的场景)

   同样, 采样周期是4
   ```
   |----|---|-|----|----|
      4   3  1  4    4
   ```
   这个处理没有什么问题, 由于不是overflow的场景, 3 这个地方并没有出现采样不精确的问题,
   而随后的1,这个地方, 也会出发overflow, 整个流程没有采样不精确的情况.
