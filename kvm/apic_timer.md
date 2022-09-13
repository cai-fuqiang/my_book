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
	//////////////(3)
    if (apic_lvtt_period(apic) || apic_lvtt_oneshot(apic)) {
        if (unlikely(count_reg != APIC_TMICT)) {
            deadline = tmict_to_ns(apic,
                   kvm_lapic_get_reg(apic, count_reg));
            if (unlikely(deadline <= 0))
                deadline = apic->lapic_timer.period;
            else if (unlikely(deadline > apic->lapic_timer.period)) {
                pr_info_ratelimited(
                   "kvm: vcpu %i: requested lapic timer restore with "
                   "starting count register %#x=%u (%lld ns) > initial count (%lld ns). "
                   "Using initial count to start timer.\n",
                   apic->vcpu->vcpu_id,
                   count_reg,
                   kvm_lapic_get_reg(apic, count_reg),
                   deadline, apic->lapic_timer.period);
                kvm_lapic_set_reg(apic, count_reg, 0);
                deadline = apic->lapic_timer.period;
            }
        }
    }
	//////////////(4)
    apic->lapic_timer.tscdeadline = kvm_read_l1_tsc(apic->vcpu, tscl) +
        nsec_to_cycles(apic->vcpu, deadline);
	//////////////(5)
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
另外也需要把`tscdeadline`清空。这个还得看下为什么

3. 这个里面会有一个unlikely, 但是能调用到该接口的，`count_reg`
都为`APIC_TMICT`寄存器所以该分支走不进来

4. 计算guest 的 tscdeadline, 该值会给`vmx-preemption`使用。
但是tsc的计算比较复杂:
* tsc时钟是开机时，开始计时，所以guest 开机时刻要比host要晚，
他们之间有一个offset的关系。并且热迁移的虚机，tsc还可能比
host要早(这里有个疑问，`tsc_offset`在kernel中的值均为unsigned,
所以看起来只有 > 0的offset，还需对照下手册再看下.
* 另外呢，guest 的tsc的频率有可能和host的tsc频率不同，例如，
热迁移过来的虚机。

基于上面的说的两点, 我们来看下代码实现:
首先看下`kvm_read_l1_tsc`, 该函数用来获取
guest此刻的tsc的值

```cpp
u64 kvm_read_l1_tsc(struct kvm_vcpu *vcpu, u64 host_tsc)
{
        return vcpu->arch.l1_tsc_offset +
                kvm_scale_tsc(host_tsc, vcpu->arch.l1_tsc_scaling_ratio);
}

u64 kvm_scale_tsc(u64 tsc, u64 ratio)
{
        u64 _tsc = tsc;

        if (ratio != kvm_caps.default_tsc_scaling_ratio)
                _tsc = __scale_tsc(ratio, tsc);

        return _tsc;
}

static inline u64 __scale_tsc(u64 ratio, u64 tsc)
{
        return mul_u64_u64_shr(tsc, ratio, kvm_caps.tsc_scaling_ratio_frac_bits);
}
```
`l1_tsc_offset`, 是指`l1 guest`和`host`之前的tsc差值，在intel sdm `24.6.5
Time-stamp counter offset and mutiplier` 章节中有讲。

> NOTE
>
> 在`struct kvm_vcpu_arch`中有`tsc_offset`和`l1_tsc_offset`两个成员，
> 在没有嵌套虚拟化的场景下，两个值相等，详见`kvm_vcpu_write_tsc_offset()`
> 函数

除了`offset`之外, `kvm_scale_tsc()`还根据host 和 guest之间，tsc的频率
比例, 得到guest 频率的tsc值，当然，最终这个值，还需要加上`tsc_offset`

我们来仔细看下这块:

在`struct kvm_vcpu_arch`中，也有和`tsc offset`类似的成员
```cpp
struct kvm_vcpu_arch {
	...
	u64 l1_tsc_scaling_ratio;
	u64 tsc_scaling_ratio; /* current scaling ratio */
	...
};
```
在没有嵌套虚拟化的场景下，`l1_tsc_scaling_ratio == tsc_scaling_ratio`, 
这个值表示 `guest_tsc_hz` 和 `host_tsc_hz`, 的一个比例关系，该值, 该值是一个整数，所以
只能允许`guest tsc` 比`host tsc` 大。

另外 `struct kvm_caps`中有两个成员会涉及到:
```cpp
struct kvm_caps {
	...
	u64 default_tsc_scaling_ratio;
	u8 tsc_scaling_ratio_frac_bits;
	...
};
```
这里先解释下`tsc_scaling_ratio_frac_bits`, 在intel sdm `25.3 changes to 
instruction behavior in VMX Non-Root Operation`章节中，关于`RDMSR`的
一些解释:

在使能了`use TSC offseting`和`use TSC scaling`后，
```
RDMSR first computes the product of the value of the
IA32_TIME_STAMP_COUNTER MSR and the value of the TSC 
multiplier. It then shifts the value of the product right 48 
bits and loads EAX:EDX with the sum of that shifted value and
the value of the TSC offset.
```
这里会现将 `IA32_TIME_STAMP_COUNTER` msr value 和 `TSC multiplier`
做乘法，然后在`左移48 bits`, 之后再将这个结果和 `TSC offset`
相加。

猜测，这里这样做的目的是为了提高下精度，如果只是做乘积，那么
得到的值只能是整数倍。

首先在`hardware_setup()`代码中，赋值`kvm_caps.tsc_scaling_ratio_frac_bits`
```cpp
static __init int hardware_setup(void)
{
	...
	kvm_caps.tsc_scaling_ratio_frac_bits = 48;
	...
}
```
在`kvm_arch_hardware_setup()`中赋值`kvm_caps.default_tsc_scaling_ratio`
```cpp
int kvm_arch_hardware_setup(void *opaque)
{
	...
	kvm_caps.default_tsc_scaling_ratio = 1ULL << kvm_caps.tsc_scaling_ratio_frac_bits;
	...
}
```

# PS
## 相关资料
* intel sdm `17.17 time-stamp counter`: 里面讲到了`contant tsc`, 和tsc频率相关
