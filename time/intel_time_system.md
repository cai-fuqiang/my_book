# time

关于time子系统主要分为两个方面:
* 时钟源
* 定时器

该章节主要讨论intel 平台时钟源(主要是tsc) 和定时器(apic timer)的
实现和配置，以及虚拟化。

# TSC
关于此章节主要参考`intel sdm 17.7 Time-Stamp Counter`


## 简介
TSC 是一个高精度的时钟计数器, 该计数器时64 bits counter
该时钟计数会在系统`RESET`时初始化为0，然后在以一个频率自增，
早期的实现，TSC的频率和cpu的频率有关, cpu频率变动, 
tsc的自增频率也变动，所以该时钟源软件用起来不太好用, 
后来intel 实现了`Invariant TSC`,在CPU频率变动，以及CPU
处于不同的电源状态(ACPI P-, C-, T-states), TSC仍然以固定
的频率自增。

我们本章讲解，主要以`Invariant TSC`为主。

## introduction
TSC 机制在 Pentium processor中引入，可以用来monitor/identify
处理器事件发生的相对时间。

TSC architecture 包括如下的组成部分:
* **TSC flag** - 该位指示TSC是否可用。如果`CPUID.1.EDX.TSC[bit 4] = 1`,
 则TSC可用
* **IA32_TIME_STAMP_COUNTER MSR** (被称为TSC MSR, 在P6 family 和 
 Pentium processor中被引入) - 该MSR 用作 counter
* **RDTSC instruction** - 用于读取 time-stamp counter
* **TSD flag** - 是一个control register flags, 用来 enable/disable
 TSC (`CR4.TSD[bit 2] = 1` 时, enable tsc)
```
CR4.TSD
Time Stamp Disable (bit 2 of CR4) — Restricts the execution of the 
RDTSC instruction to procedures running at privilege level 0 when 
set; allows RDTSC instruction to be executed at any privilege level 
when clear. This bit also applies to the RDTSCP instruction if 
supported (if CPUID.80000001H:EDX[27] = 1).
```

上面说到，`Invariant TSC`可以保证 CPU在RESET后，TSC保持一个固定的
ratio, 该ratio可能被设置为处理器 core-clock to bus clock ratio 
的最大值, 也可能被设置为处理器启动时 maximum resolved frequency.
maximum resolved frequency 可能不同于processor base frequency。
在某些处理器上，TSC frequency 可能和 brand string 的 frequency 
不相同。
eg:
```
Intel(R) Core(TM) i5-10210U CPU @ 1.60GHz

[    0.000017] tsc: Detected 2112.005 MHz processor
```
`RDTSC`指令读取 `time-stamp counter` 并且保证每次执行都返回一个
`monotonically increasing unique value`(单调递增的独一无二的
值), 除非是该 64-bit counter 溢出。intel 保证`time-stamp counter`
不会在RESET后10年内溢出。

正常来说, `RDTSC`指令可以运行在任何特权级别，或者运行在`virtual 
8086 mode`。TSD flag 允许该运行在 privilege 0 的`RDTSC`指令被限
制。一个安全的操作系统可能会在系统初始化时设置TSD flags来disable
对于 `privilege level 0`的对TSC的访问。操作系统禁用用户访问tsc后，
应该通过 `user-acessible` 编程接口去模拟该指令。

`RDTSC` 指令不是 `serializing`/`ordered`。在执行读该 counter 之前
去等待所有的先前的指令执行完成。相似的，在`RDTSC`执行前，需要
执行 subsequent instruction。

`RDMSR` 和 `WRMSR` 指令会去read && write TSC, 像是读 ordinary MSR一样

## invariant TSC
新处理器中的time stamp counter 支持了一项增强功能，被称为 `invariant 
TSC`。处理器对 invariant TSC 的支持通过 CPUID.80000007H.EDX[8]。

`invariant TSC`将在所有的ACPI P-, C-, 和T-state中以不变的速率运行。
This is the architectural behavior moving forward. 在支持了
invariant TSC 的处理器上，OS可能使用TSC作为 wall clock timer service
(替代ACPI/HEPT timers)。TSC 的读取效率会更高，不会有ring translation
或者时访问 platform resource 带来的开销

## IA32_TSC_AUX register and RDTSCP support
`IA32_TSC_AUX`是一个辅助性的MSR, `IA32_TSC_AUX`被设计用于结合`IA32_TSC`
使用。`IA32_TSC_AUX`提供了一个32-bit的字段，并由特权级别软件初始化。
（例如可以初始化为 `logical processor ID`)

`IA32_TSC_AUX`早期的用法， 是结合`IA32_TSC` 允许软件通过`RDTSCP`指令atomic
读取`IA32_TSC`中的 time stamp和`IA32_TSC_AUX`中的signal value 。
并且`IA32_TSC`->`EDX:EAX`, `TSC_AUX`->`ECX`。

用户态程序可以使用`RDTSCP`指令判断，是否有CPU migration 的行为。同时也可以
使用它来判断在NUMA系统中`per-CPU TSC`是否会不一致。

## Time-Stamp Counter Adjustment
软件可以通过使用`WRMSR`指令写入`IA32_TIME_STAMP_COUNTER` MSR修改`TSC`的
值。因为每次写入只能操作当前所在的CPU，软件这边来同步这件事情是非常困难的。
（很难让所有CPU 的tsc保持在同一个值）。

`TSC adjustment`的同步机制造是使用`IA32_TSC_ADJUST`MSR。和
`IA32_TIME_STAMP_COUNTER` MSR一样，该寄存器也是每个logical processor
单独存在。逻辑处理器如下使用`IA32_TSC_ADJUST` MSR
* 在RESET时，`IA32_TSC_ADJUST` MSR为0.
* 如果执行`WRMSR`->`IA32_TIME_STAMP_COUNTER` MSR 为原来TSC的值 +/- x,
 处理器也相应的会对`IA32_TSC_ADJUST`MSR, 进行+/- x的操作。
* 如果执行`WRMSR->IA32_TSC_ADJUST` MSR为原来该寄存器值的 +/- x, 
 处理器也相应会对`IA32_TSC_ADJUST` MSR, 进行 +/- x的操作。

`IA32_TSC_ADJUST` 不像`TSC`，不会因为time elapse(时间消逝)而自增，只能通过
`WRMSR`->`IA32_TSC_ADJUST`/`IA32_TIME_STAMP_COUNTER` MSR来改变他的值。
软件可以通过在每个logical processor `WRMSR` 相同的值->`IA32_TSC_ADJUST` MSR,
来保证时间同步。

`CPUID.(EAX=07H, ECX=0H):EBX.TSC_ADJUST(bit 1)` 指示是否支持`IA32_TSC_ADJUST`
MSR。

### 17.17.4 Invariant Time-Keeping
invariant TSC 是基于 `invariant timekeeping hardware`实现，（称为
Always Running Timer or ART), 它以 core crystal clock frequency 
运行。

如果`CPUID.15H:EBX[31:0] != 0` && `CPUID.80000007H:EDX[InvariantTSC] = 1`,
`TSC`和`ART` 保持的线性关系如下：
```
TSC_Value = (ART_Value * CPUID.15H:EBX[31:0] )/ CPUID.15H:EAX[31:0] + K
```
Where 'K' is an offset that can be adjusted by a privileged agent.
> PS: 这里的 K可能指IA32_TSC_ADJUST 和 VMCS 中的 TSC-offset 的值。
When ART hardware is reset, both invariant TSC and K are also reset.

# TSC virtualization
## 简介
从上面`TSC`一章可以看到，intel 为支持`TSC`主要实现了一些MSR(
`IA32_TIME_STAMP_COUNTER`, `IA32_TSC_AUX`, `IA32_TSC_ADJUST`,
和一些指令`RDTSCP`, `RDTSC`, 以及CPUID对上述功能是否支持的
指示。

那么对于`TSC virtualization` 来说，我们不妨先来看看，
和TSC相关的`VMX non-root operation`: `RDTSCP`, `RDTSC`
是怎么个行为。
