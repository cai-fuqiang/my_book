# clock source
## `clocksource` structure
```cpp
struct clocksource {
    u64         (*read)(struct clocksource *cs);
    u64         mask;
    u32         mult;
    u32         shift;
    u64         max_idle_ns;
    u32         maxadj;
    u32         uncertainty_margin;
#ifdef CONFIG_ARCH_CLOCKSOURCE_DATA
    struct arch_clocksource_data archdata;
#endif
    u64         max_cycles;
    const char      *name;
    struct list_head    list;
    int         rating;
    enum clocksource_ids    id;
    enum vdso_clock_mode    vdso_clock_mode;
    unsigned long       flags;

    int         (*enable)(struct clocksource *cs);
    void            (*disable)(struct clocksource *cs);
    void            (*suspend)(struct clocksource *cs);
    void            (*resume)(struct clocksource *cs);
    void            (*mark_unstable)(struct clocksource *cs); void            (*tick_stable)(struct clocksource *cs);

    /* private: */
#ifdef CONFIG_CLOCKSOURCE_WATCHDOG
    /* Watchdog related data, used by the framework */
    struct list_head    wd_list;
    u64         cs_last;
    u64         wd_last;
#endif
    struct module       *owner;
};
```

* `read`: 是一个函数指针，通过调用可以获取该时钟源的时间值
* `mask`: Bitmask for two's complement subtraction of non 64 bit counters.
	简单翻译是: 非64位计数器的二进制补码减法的位掩码。
	不知道有什么作用
> NOTE:
>
> clocksource_tsc : CLOCKSOURCE_MASK(64)<br/>
> clocksource_hpet, clocksource_jiffies: CLOCKSOURCE_MASK(32)<br/>
> clocksource_acpi_pm: CLOCKSOURCE_MASK(24)<br/>

* `mult`: Cycle to nanosecond multiplier。
	用于将Cycle --> ns，作为乘数使用
* `shift`: Cycle to nanosecond divisor
	用于将Cycle --> ns，作为除数使用，但是这里需要注意的是, 变量名为shift
	除数的值相当于(power of two: 2 ^ shift)

> NOTE:
>
> 这里简单介绍下cycle, cycle相当于是时钟源计数器的值，
> 但是这个值对于使用者而言
> 没有什么作用，最好以时间刻度为单位，例如ns。一个cycle对应多少
> ns是和输入频率有关, 所以这个cycle和ns之间有一定的转换关系, 
> 关系如下:
>
> ```
> 转换后的纳表数 = (A / F) * NSEC_PER_SEC
> ```
> 这里A表示cycle， F 表示频率,  NSEC_PER_SEC表示1s对应的ns数量
> 那么mult变量对应的NSEC_PER_SEC, 而shift代表的F, 但是kernel为了
> 照顾那些没有除法指令的处理器，并且也为了顾及效率，降低了些精度，
> 采用右移的方式代替除法
>
> 代码如下:
> ```cpp
> static inline s64 clocksource_cyc2ns(u64 cycles, u32 mult, u32 shift)
> {
>    return ((u64) cycles * mult) >> shift;
> }
> ```

* `max_idle_ns`: Maximum idle time permitted by the clocksource (nsecs)
	简单翻译为: clocksource允许的最大的 idle time, 以ns为单位
	在`CONFIG_NO_HZ`编译条件下使用（默认是启用的), 允许Linux kernel
	在没有定期的timer tick。这样就允许kernel睡眠时间超过一个 tick, 
	并且睡眠时间也可能是无限的。`max_idle_ns`字段表示这个睡眠时间
	的期限
* `maxadj`: Maximum adjustment value to mult (~11%) (这个和校准有关，还得再看下)
* `max_cycles`: Maximum safe cycle value which won't overflow on
	multiplication<br/>
	T: 在作乘法时，不会造成溢出的最大的 cycle 值。
* `name`: Pointer to clocksource name
* `rating`: Rating value for selection (higher is better)
```
To avoid rating inflation the following list should 
give you a guide as to how to assign your clocksource 
a rating
1-99: Unfit for real use
    Only available for bootup and testing purposes.
100-199: Base level usability.
    Functional for real use, but not desired.
200-299: Good.
    A correct and usable clocksource.
300-399: Desired.
    A reasonably fast and accurate clocksource.
400-499: Perfect
    The ideal clocksource. A must-use where
    available.
```
> NOTE:
>
> 这里rating 代表频率，频率越高，精度越高， 我们来看下各个
> clocksource的精度
>
> clocksource_tsc		: 300<br/> 
> clocksource_hpet		: 250<br/>
> clocksource_acpi_pm	: 200<br/>
> clocksource_jiffies	: 1
>
> 可见tsc的精度最高

* some function pointer:
	+ `enable` - optional function to enable clocksource;
	+ `disable` - optional function to disable clocksource;
	+ `suspend` - suspend function for the clocksource;
	+ `resume` - resume function for the clocksource;
* `wd_list,cs_last, wd_last` 和 `CONFIG_CLOCKSOURCE_WATCHDOG`相关。
__关于CONFIG_CLOCKSOURCE_WATCHDOG后面再看__

* `owner`: 指向 clocksource 的 kernel module
# PS
## 用户态操作
可以通过参看
```
/sys/devices/system/clocksource/clocksource0/available_clocksource
```
可获得的clocksource,通过
```
/sys/devices/system/clocksource/clocksource0/current_clocksources
```
查看当前的clocksource

> NOTE
>
> 当前在物理机中 ，查看上面两个文件输出如下:<br/>
> available_clocksource :`tsc hpet acpi_pm`<br/>
> current_clocksources  : `tsc`
>
> 而在虚拟机中 :<br/>
> available_clocksource: `kvm-clock tsc hpet acpi_pm` <br/>
> current_clocksources  : `kvm-clock`
>
> tsc: Time Stamp Counter
> hpet: High Precision Event Timer
> acpi_pm : ACPI Power Management Timer

# 参考代码
linux code tag v6.0-rc1
