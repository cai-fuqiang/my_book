# struct kvm timer
```cpp
struct kvm_timer {
    struct hrtimer timer;
    s64 period;                 /* unit: ns */
    ktime_t target_expiration;
    u32 timer_mode;
    u32 timer_mode_mask;
    u64 tscdeadline;
    u64 expired_tscdeadline;
    u32 timer_advance_ns;
    atomic_t pending;           /* accumulated triggered timers */
    bool hv_timer_in_use;
};

struct kvm_lapic {
	...
	struct kvm_timer lapic_timer;
	...

};
```
* **struct hrtimer timer**<br/>
每个`kvm_lapic`有一个`kvm_timer`, 而每个`kvm_timer`中有
一个`hrtimer`来描述软件层面的timer
> NOTE:
> kvm对于guest lapic timer模拟使用的有两种，
> 一种是基于软件实现(hrtimer) , 另外一种
> 是基于硬件实现`VMX-preemption timer`实现

* **period**<br/>
表示当前initial count register 转换为ns的值。
* **target_expiration**<br/>
表示该timer过期的时间，注意类型为`ktime_t`,
主要用来使能`hrtimer`
> NOTE
>
> hrtimer 相关时间单位的类型都为`ktime_t`
>
> eg: 
> ```
> void hrtimer_start(struct hrtimer *timer, ktime_t tim,
>			const enum hrtimer_mode mode)
> ```
* **timer_mode**
```
#define     APIC_LVT_TIMER_ONESHOT      (0 << 17) 
#define     APIC_LVT_TIMER_PERIODIC     (1 << 17) 
#define     APIC_LVT_TIMER_TSCDEADLINE  (2 << 17) 
```
* **timer_mode_mask**
* **tscdeadline**<br/>
时钟过期的 tsc, 该值是 guest 的 tscdeadline
* **expired_tscdeadline**
```
commit : d0659d946be05e098883b6955d2764595997f6a4
KVM: x86: add option to advance tscdeadline hrtimer expiration
```
* **pending**<br/>
表示有一个timer pending

# apic register write
```cpp
static int (*kvm_vmx_exit_handlers[])(struct kvm_vcpu *vcpu) = {
	...
	[EXIT_REASON_APIC_WRITE]              = handle_apic_write,
	...
};
```

stack
```
handle_apic_write
	kvm_apic_write_nodecode
		kvm_lapic_reg_write
			case APIC_TMICT
			start_apic_timer
				__start_apic_timer
```

# __start_apic_timer
```cpp
static void __start_apic_timer(struct kvm_lapic *apic, u32 count_reg)
{
    atomic_set(&apic->lapic_timer.pending, 0);

    if ((apic_lvtt_period(apic) || apic_lvtt_oneshot(apic))
        && !set_target_expiration(apic, count_reg))
        return;

    restart_apic_timer(apic);
}
```

## set_target_expiration
```cpp
static bool set_target_expiration(struct kvm_lapic *apic, u32 count_reg)
{
    ktime_t now;
    u64 tscl = rdtsc();
    s64 deadline;

    now = ktime_get();
	//////////////(1)
    apic->lapic_timer.period =
            tmict_to_ns(apic, kvm_lapic_get_reg(apic, APIC_TMICT));

	//////////////(2)
    if (!apic->lapic_timer.period) {
        apic->lapic_timer.tscdeadline = 0;
        return false;
    }

    limit_periodic_timer_frequency(apic);
    deadline = apic->lapic_timer.period;

    if (apic_lvtt_period(apic) || apic_lvtt_oneshot(apic)) {
        if (unlikely(count_reg != APIC_TMICT)) {
            deadline = tmict_to_ns(apic,
                ¦   ¦kvm_lapic_get_reg(apic, count_reg));
            if (unlikely(deadline <= 0))
                deadline = apic->lapic_timer.period;
            else if (unlikely(deadline > apic->lapic_timer.period)) {
                pr_info_ratelimited(
                ¦   "kvm: vcpu %i: requested lapic timer restore with "
                ¦   "starting count register %#x=%u (%lld ns) > initial count (%lld ns). "
                ¦   "Using initial count to start timer.\n",
                ¦   apic->vcpu->vcpu_id,
                ¦   count_reg,
                ¦   kvm_lapic_get_reg(apic, count_reg),
                ¦   deadline, apic->lapic_timer.period);
                kvm_lapic_set_reg(apic, count_reg, 0);
                deadline = apic->lapic_timer.period;
            }
        }
    }

    apic->lapic_timer.tscdeadline = kvm_read_l1_tsc(apic->vcpu, tscl) +
        nsec_to_cycles(apic->vcpu, deadline);
    apic->lapic_timer.target_expiration = ktime_add_ns(now, deadline);

    return true;
}
```
1. 计算`period`，实际上是获取`initial count`的值，会去做一个`tmict_to_ns`
的运算:
```cpp
static inline u64 tmict_to_ns(struct kvm_lapic *apic, u32 tmict)
{
    return (u64)tmict * APIC_BUS_CYCLE_NS * (u64)apic->divide_count;
}
```
实际上使用的`initial count * 1 * apic->divide_count`
> NOTE:
>
> initial count 寄存器比较好配置，它的频率是通过
> `Divide Configuration Register`决定，和频率无关。
> 跟tsc还不一样。

2. 如果写入值为0 的话，则`tscdeadline = 0`, 并且返回false，
在`__start_apic_timer`中, 直接return，而不去设置timer.<br/>
原因见 `intel sdm 10.5.4 APIC timer`, 中讲到
```
A write of 0 to the initial-count register effectively stops 
the local APIC timer, in both one-shot and periodic mode.
```
另外也需要把`tscdeadline`清空。这个还得看下
