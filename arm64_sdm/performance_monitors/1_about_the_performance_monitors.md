The Performance Monitors Extension is an OPTIONAL feature of an implementation,
but Arm strongly recommends that implementations include version 3 of the
Performance Monitors Extension, FEAT_PMUv3.

> Performance Monitors Extension 是 一个 implementation中 OPTIONAL feature, 但Arm强烈
> 建议实现包括第3版的性能监视器扩展FEAT_PMUv3。


> NOTE
>
> No previous versions of the Performance Monitors Extension can be implemented
> in architectures from Armv8.0.
>
> 以前版本的性能监视器扩展无法在Armv8.0的体系结构中实现。

The basic form of the Performance Monitors is:
> 性能监视器的基本形式是：
* A 64-bit cycle counter, see Time as measured by the Performance Monitors
  cycle counter on page D11-5246.
  > 一个 64-bit 周期计数器(cycle conuter), 请参阅第 D11-5246 页上的性能监视
  > 器周期计数器测量的时间。
* A number of 64-bit or 32-bit event counters. If FEAT_PMUv3p5 is implemented
  and the highest Exception level is using AArch64, the event counters are
  64-bit. If FEAT_PMUv3p5 is not implemented, the event counters are 32-bit.
  > a number of: 多个
  >
  > 多个64位或32位事件计数器。如果实现了FEAT_PMUv3p5，并且最高异常级别使用AArch64，
  > 则事件计数器为64位。如果未实现FEAT_PMUv3p5，则事件计数器为32位。
* The event counted by each event counter is programmable. The architecture
  provides space for up to 31 event counters. The actual number of event
  counters is IMPLEMENTATION DEFINED, and the specification includes an
  identification mechanism.
  > 每个事件计数器计数的事件是可编程的。 该架构提供了多达 31 个事件计数器.事件计数器
  > 的实际数量是 IMPLEMENTATION DEFINED ，而该规范只包含 identification 的机制。

> NOTE
>
> The Performance Monitors Extension permits an implementation with no event
> counters (PMCR_EL0.N==0). However, Arm recommends that at least two event
> counters are implemented, and that hypervisors provide at least this many
> event counters to guest operating systems.
>
> 性能监视器扩展允许没有事件计数器的实现 (PMCR_EL0.N==0)。 但是，Arm 建议至少
> 实现两个事件计数器，并且VMM至少向guest OS 提供这么多(至少两个)事件计数器。

When EL2 is implemented, the required controls to partition the implemented
event counters into the following ranges:

> 当 实现了 EL2，需要控制将实现的的事件计数器划分为以下范围：

* A first range which is available for use by the guest operating system
  accessible at all Exception levels.
  > 第一个范围可供 所有异常级别访问的 Guest OS使用。

* A second range which is available for use by the hypervisor accessible at EL3
  and EL2, and, if FEAT_SEL2 is not implemented or if Secure EL2 is disabled,
  in Secure state.
  > 第二个范围可供在 运行在 EL3和EL2上的hypervisor 使用，并且如果未实现 FEAT_SEL2 
  > 或如果禁用安全 EL2，则处于安全状态。

Controls for:
> 提供了如下的控制:
* Enabling and resetting counters.
* Flagging overflows.
* Enabling interrupts on overflow.
* Disabling or freezing counters.
* Threshold counting.

The PMU architecture uses event numbers to identify an event. It:

> PMU architecture 使用 event number 来标识一个 event. 它:

* Defines event numbers for common events, for use across many architectures and
  microarchitectures.
  > 定义常见事件的事件编号，以便在许多体系结构和微体系结构中使用。

  > Note
  >
  > Implementations that include FEAT_PMUv3 must, as a minimum requirement,
  > implement a subset of the common events. See Common event numbers on page
  > D11-5306.
  >
  > 作为最低要求，包含 FEAT_PMUv3 的实现必须实现公共事件的子集。 请参阅第 
  > D11-5306 页上的常见事件编号。

* Reserves a large event number space for IMPLEMENTATION DEFINED events.
  > 为IMPLEMENTATION DEFINED事件保留大量 event number space。


The full set of events for an implementation is IMPLEMENTATION DEFINED. Arm
recommends that implementations include all of the events that are appropriate
to the architecture profile and microarchitecture of the implementation.

> 实现的完整事件集是 IMPLEMENTATION DEFINED。Arm 建议implementation包括适合
> 于 architecture profile 和 微架构的所有事件

When an implementation includes the Performance Monitors Extension, the
architecture defines the following possible interfaces to the Performance
Monitors Extension registers:

> 当实现包括性能监视器扩展时，体系结构会定义以下可能的性能监视器扩展寄存器
> 接口：

* A System register interface. This interface is mandatory.
  > mandatory [ˈmændətəri] adj. 强制性的; 强制的; 法定的; 义务的
  >
  > 系统寄存器接口。 该接口是必需的

> Note
>
> In AArch32 state, the interface is in the (coproc == 0b1111) encoding space.

* An external debug interface which optionally supports memory-mapped accesses.
  Implementation of this interface is OPTIONAL. See Chapter I3 Recommended
  External Interface to the Performance Monitors.
  > 外部调试接口，可选择支持内存映射访问。 该接口的实现是可选的。 请参阅第 I3 章
  > 推荐的性能监视器外部接口。

An operating system can use the System registers to access the counters.
> 操作系统可以使用系统寄存器来访问计数器。

Also, if required, the operating system can enable application software to
access the counters. This enables an application to monitor its own performance
with fine-grain control without requiring operating system support. For
example, an application might implement per-function performance monitoring.

> ```
> fine : 小颗粒构成
> grain: 颗粒,细粒
> ```
>
> 此外，如果需要，操作系统可以使应用软件能够访问计数器。这使得应用程序能够
> 通过细粒度控制来监控其自身的性能，而无需操作系统支持。 例如，应用程序
> 可能会实现每个功能的性能监控。

To enable interaction with external monitoring, an implementation might
consider additional enhancements, such as providing:

> 为了实现与外部监控的交互，implementation 可能会考虑其他增强功能，例如提供：

* A set of events, from which a selection can be exported onto a bus for use as
  external events.
  > from which: 其中
  >
  > 一组事件，其中的选定部分可以导出到总线上作为外部事件使用。
* The ability to count external events. This enhancement requires the
  implementation to include a set of external event input signals.
  > 计数外部事件的能力。 此增强功能要求实现包括一组外部事件输入信号。

The Performance Monitors Extension is common to AArch64 operation and AArch32
operation. This means the architecture defines both AArch64 and AArch32 System
registers to access the Performance Monitors. For example, the Performance
Monitors Cycle Count Register is accessible as:
> 性能监视器扩展对于 AArch64 操作和 AArch32 操作是通用的。 这意味着该架构定义了
> AArch64 和 AArch32 系统寄存器来访问性能监视器。 例如，性能监视器Cycle Count寄存器
> 可通过以下方式访问：
* When executing in AArch64 state, PMCCNTR_EL0.
* When executing in AArch32 state, PMCCNTR.

When executing in AArch32 state, if FEAT_PMUv3p5 is implemented, bits [63:32]
of the event counters are not accessible. If the implementation does not
support AArch64 at any Exception level, 64-bit event counters are not required
to be implemented.
> 在 AArch32 状态下执行时，如果实现了 FEAT_PMUv3p5，则事件计数器的位 [63:32] 不可
> 访问。 如果implementation 在任何异常级别都不支持 AArch64，则不需要实现 64 位事件计
> 数器。

# D11.1.1 Interaction with EL3

Software executing at EL3 can trap attempts by lower Exception levels to access
the PMU. This means that the Secure monitor can identify any software which is
using the PMU and switch contexts, if required. 
> 在 EL3 上执行的软件可以捕获较低异常级别访问 PMU 的尝试。 这意味着安全监视器可
> 以识别正在使用 PMU 的任何软件，并根据需要切换上下文。 

Software executing at EL3 can:
* Prohibit counting of events Attributable to Secure state.
  > prohibit : 禁止
  >
  > 禁止计数归因于安全状态的事件。

* If FEAT_PMUv3p5 is implemented, prohibit the cycle counter from counting
  cycles in Secure state, see Controlling the PMU counters on page D11-5254.
  > 如果实现了 FEAT_PMUv3p5，则禁止周期计数器在 Secure state(安全状态) 对周期进行
  > 计数, 请参阅第 D11-5254 页上的控制 PMU 计数器。
* If FEAT_PMUv3p7 is implemented:
  + Prohibit event counters from counting events at EL3 without affecting the
    rest of Secure state.
    > 禁止事件计数器对 EL3 上的**event**(事件)进行计数，而不影响安全状态的其余部分。
  + Prohibit the cycle counter from counting cycles at EL3 without affecting
    the rest of Secure state.
    > 禁止周期计数器在 EL3 处对**cycle**(周期)进行计数，而不影响安全状态的其余部分。
 
  For more information, see Controlling the PMU counters on page D11-5254 and
  Freezing event counters on page D11-5255.
  > 有关详细信息，请参阅第 D11-5254 页上的控制 PMU 计数器和第 D11-5255 页上的
  > 冻结事件计数器。

In AArch32 state, the Performance Monitors registers are Common registers, see
Classification of System registers on page G5-9281.

> 在 AArch32 状态下，性能监视器寄存器是通用寄存器，请参阅第 G5-9281 页上的系统
> 寄存器分类

If FEAT_MTPMU is implemented and EL3 is implemented, MDCR_EL3.MTPME and
SDCR.MTPME enable and disable the PMEVTYPER<n>.MT bit.

> 如果实现了 FEAT_MTPMU 并且实现了 EL3，则 MDCR_EL3.MTPME 和 SDCR.MTPME 
> 使能和禁用 PMEVTYPER<n>.MT 位。

# D11.1.2 Interaction with EL2

Software executing at EL3 or EL2 can program HDCR.HPMN to partition the event
counters into two ranges:
> 在 EL3 或 EL2 上执行的软件可以对 HDCR.HPMN 进行编程，将事件计数器分为两个范
> 围：

* If HDCR.HPMN is not 0 and is less-than PMCR.N, HDCR.HPMN divides the event
  counters into a first range [0..(HDCR.HPMN-1)], and a second range
  [HDCR.HPMN..(PMCR.N-1)].
  > 如果HDCR.HPMN不为0并且小于PMCR.N，则HDCR.HPMN将事件计数器分为first 
  > range[0…(HDCR.HPMN-1)]和second range[HDCR.HPMN…(PMCR .N-1)]。

* If FEAT_HPMN0 is implemented and HDCR.HPMN is 0, all event counters are in
  the second range and none are in the first range. 
  > 如果实现 FEAT_HPMN0 并且 HDCR.HPMN 为 0，则所有事件计数器都在second range
  > 内，并且没有一个事件计数器在first range内。

* If HDCR.HPMN is equal to PMCR.N, all event counters are in the first range
  and none are in the second range. This does not depend on whether EL2 is
  enabled in the current Security state. Each range of event counters has its
  own global controls.
  > 如果HDCR.HPMN等于PMCR.N，则所有事件计数器都在first range内，并且没有事件计数器
  > 在second range内。 这不依赖于当前安全状态下EL2是否启用。 每个事件计数器范围都有
  > 自己的global controls.

If FEAT_HPMN0 is not implemented and HDCR.HPMN is 0, the behavior is CONSTRAINED 
UNPREDICTABLE. See:
> 如果未实现 FEAT_HPMN0 并且 HDCR.HPMN 为 0，则行为为“CONSTRAINED UNPREDICTABLE”。 
> 请见：

* The Performance Monitors Extension on page K1-11569.
* The Performance Monitors Extension on page K1-11586.

Software executing at EL3 or EL2 can:
* Trap an access at EL0 or EL1 to the PMU. This means the hypervisor can
  identify which Guest OSs are using the PMU and intelligently employ switching
  of the PMU state. There is a separate trap for the PMCR register, and if
  FEAT_FGT is implemented and enabled, fine-grained traps are provided.
  > ```
  > intelligently: 智能的
  > employ: 这里应该是服务的意思
  > ```
  >
  > 捕获 EL0 或 EL1 处对 PMU 的访问。 这意味着虚拟机管理程序可以识别哪些Guest OS
  > 正在使用 PMU，并智能地切换 PMU 状态。 PMCR 寄存器有一个单独的trap，如果
  > 实现并启用 FEAT_FGT，则会提供fine-grained(细粒度)trap。

* If FEAT_PMUv3p1 is implemented, prohibit counting of events Attributable to
  EL2 by the event counters in the first range.
  > attribute : 认为某事物属于某人[某事物]; 认为某事物由某人[某事物]引起或产生:归属于
  >     ;归因于
  >
  > 如果实现了 FEAT_PMUv3p1，则禁止first range 内的事件计数器对属于 EL2 的事
  > 件进行计数。

* If FEAT_PMUv3p5 is implemented, prohibit the cycle counter from counting
  cycles at EL2.
  > 如果 实现了FEAT_PMUv3p5, 禁止cycle counter 对 EL2 的 cycle 进行计数。

When EL2 is implemented and enabled in the current Security state, software
executing at EL1 and, if enabled by PMUSERENR, EL0:
> 当 EL2 在当前安全状态下实现并启用时，软件在 EL1 上执行，如果由 PMUSERENR 启用，
> 则在 EL0 上执行：

* Will read the value of HDCR.HPMN for PMCR.N.
  > 将读取 PMCR.N 的 HDCR.HPMN 值。
  >
  >> 这个PMCR.N 是只读字段, 如果 EL1/EL0, 要访问该寄存器, 要么trap EL2, 由
  >> 由软件去 emulate, 要么在其他的寄存器里有备份, arm采用的是第二种.
* Cannot access the event counters in the second range, or the controls
  associated with them.
  > 无法访问second range中的事件计数器或与其关联的controlssd。

If FEAT_MTPMU is implemented, EL3 is not implemented, and EL2 is implemented,
MDCR_EL2.MTPME and HDCR.MTPME enable and disable the PMEVTYPER<n>.MT bit.
> (先略)

For more information, see:

* Enabling event counters on page D11-5254.
* Counter access on page D11-5265.
* Controlling the PMU counters on page D11-5254.
* Multithreaded implementations on page D11-5258.

# D11.1.3 Time as measured by the Performance Monitors cycle counter

The Performance Monitors cycle counter, accessed through PMCCNTR_EL0 or
PMCCNTR, increments from the hardware processor clock, not PE clock cycles.
> 通过 PMCCNTR_EL0 或 PMCCNTR 访问的性能监视器周期计数器从硬件处理器时钟而
> 不是 PE 时钟周期递增。

The relationship between the count recorded by the Performance Monitors cycle
counter and the passage of real time is IMPLEMENTATION DEFINED.
> passage: 过,经过;时间的推移
>
> 性能监视器周期计数器记录的计数与实时流逝之间的关系是 IMPLEMENTATION DEFINED.

See Controlling the PMU counters on page D11-5254 for information about when
the cycle counter does not increment.
> 有关周期计数器何时不递增的信息，请参阅第 D11-5254 页上的控制 PMU 计数器。

> Note
>
> * This means that, in an implementation where PEs are multithreaded, when
>   enabled, the cycle counter continues to increment across all PEs, rather
>   than only counting cycles for which the current PE is active.
>   > 这意味着，在 PE 是多线程的实现中，当启用时，周期计数器会在所有 PE 上继
>   > 续递增，而不是仅对当前 PE 处于活动状态的周期进行计数。
>
> * Although the architecture requires that direct reads of PMCCNTR_EL0 or
>   PMCCNTR occur in program order, there is no requirement that the count
>   increments between two such reads. Even when the counter is incrementing on
>   every clock cycle, software might need check that the difference between
>   two reads of the counter is nonzero.
>   > 尽管该架构要求按程序顺序直接读取 PMCCNTR_EL0 或 PMCCNTR，但不要求计数在两
>   > 次此类读取之间递增。 即使计数器在每个时钟周期递增，软件也可能需要检查计数
>   > 器的两次读取之间的差异是否非零。
>
> The architecture requires that an indirect write to the PMCCNTR_EL0 or
> PMCCNTR is observable to direct reads of the register in finite time. The
> counter increments from the hardware processor clock are indirect writes to
> these registers.
>> finite: 有限的
>> 
>> 该架构要求对 PMCCNTR_EL0 或 PMCCNTR 的间接写入，可以被在有限时间内直接
>> 读取寄存器观察到。 来自硬件处理器时钟的计数器增量是对这些寄存器的间接写入。
>>
>>> 这里有点迷, 一方面说程序两次读取 PMCCNTR_EL0 不一定能获取到 increment, 
>>> 另一方面说 hardware processor clock 对该寄存器的间接写入能被观测到.
>>> 那也就是说, 这两次操作可以在一个时钟周期内? 不可能吧.

# D11.1.4 Interaction with trace

It is IMPLEMENTATION DEFINED whether the implementation exports counter events
to a trace unit, or other external monitoring agent, to provide triggering
information. The form of any exporting is also IMPLEMENTATION DEFINED.
> implementation 是否将计数器事件导出到trace unit 或其他 external monitor agemtn, 
> 以提供triggering information 是 IMPLEMENTATION DEFINED。任何exporting 的形式也
> 是IMPLEMENTATION DEFINED。

If implemented, this exporting might be enabled as part of the performance
monitoring control functionality.
> 如果实现了，这种exporting 可以作为性能监控控制功能的一部分来启用。

Arm recommends system designers include a mechanism for importing a set of
external events to be counted, but such a feature is IMPLEMENTATION DEFINED.
When implemented, this feature enables the trace unit to pass in events to be
counted.

> mechanism  [ˈmekənɪzəm]
> 
> Arm 建议系统设计人员采用一种机制，用于导入一组要计数的外部事件，但此类功能
> 是IMPLEMENTATION DEFINED。 实现后，此功能使trace unit 能够传入要计数的事件。

Exporting PMU events to the ETM is prohibited for some Exception levels when
SelfHostedTraceEnabled() == TRUE. For more information, see Controls to
prohibit trace at Exception levels on page D3-4759.
> (略)
