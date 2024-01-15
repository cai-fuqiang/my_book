When FEAT_PMUv3_TH is implemented, threshold condition controls are accessible
through each PMEVTYPER<n>_EL0 register. This gives software the ability to
count events described by PMEVTYPER<n> only when they meet a threshold
condition.

> meet: 满足
>
> 实现 FEAT_PMUv3_TH 时，可通过每个 PMEVTYPER_EL0 寄存器访问阈值条件控制。 这使
> 得软件能够仅在满足阈值条件时对 PMEVTYPER 描述的事件进行计数。

# D11.8.1 Enabling event counting threshold
When FEAT_PMUv3_TH is implemented, threshold counting for event counter n is
disabled if both of the following are true, and enabled otherwise:
> 实现 FEAT_PMUv3_TH 时，如果以下两个条件均为 true，则事件计数器 n 的阈值计数
> 将被禁用，否则将启用：
* PMEVTYPER<n>_EL0.TC is 0b000.
* PMEVTYPER<n>_EL0.TH is zero.

# D11.8.2 Threshold conditions
The PMEVTYPER<n>_EL0.{TC, TH} fields define the threshold condition.
> PMEVTYPER_EL0.{TC, TH} 字段定义阈值条件。

If FEAT_PMUv3_TH is not implemented, or threshold counting for event counter n
is disabled, V is the amount that the event defined by PMEVTYPER<n>.{MT,
evtCount} counts by in a given processor cycle.

> 如果未实现 FEAT_PMUv3_TH，或者禁用事件计数器 n 的阈值计数，则 V 是 
> PMEVTYPER.{MT, evtCount} 定义的事件在给定处理器周期中计数的数量。

Otherwise, on each processor cycle, V is compared with the value in
PMEVTYPER<n>_EL0.TH to determine whether it meets the threshold condition.
PMEVTYPER<n>_EL0.TC determines the threshold condition, and whether the counter
increments by V or 1 when the threshold condition is met.

> 否则，在每个处理器周期，将 V 与 PMEVTYPER_EL0.TH 中的值进行比较，以确定其是否
> 满足阈值条件。 PMEVTYPER_EL0.TC 确定阈值条件，以及满足阈值条件时计数器是否递增 
> V 还是 1。

PMMIR_EL1.THWIDTH describes the maximum value that can be written to
PMEVTYPER<n>_EL0.TH. The supported threshold conditions are:
> PMMIR_EL1.THWIDTH 描述可写入 PMEVTYPER_EL0.TH 的最大值。 支持的阈值条
> 件是：

* Less-than.
* Greater-than-or-equal-to.
* Not-equals.
* Equal-to.

> Example D11-4 Incrementing event counter n by V when V meets the threshold
> condition
>
> When all of the following are true, the event counter n will increment by
> four:
> > 当以下所有条件均为真时，事件计数器 n 将增加 4：
> * PMEVTYPER<n>_EL0.TC is 0b010, equals, meaning threshold counting for event
>   counter n is enabled.
>   > PMEVTYPER_EL0.TC 为 0b010，等于，表示事件计数器 n 的阈值计数已启用。
> * PMEVTYPER<n>_EL0.TH is 4.
> * PMEVTYPER<n>.evtCount is 0x003F, STALL_SLOT.
> * There are exactly four operation Slots not occupied by an operation
>   Attributable to the PE on the cycle.
>   > ```
>   > occupied [ˈɑːkjupaɪd]: 占用
>   > exactly: 恰好
>   > ```
>   >
>   > 在该cycle中，恰好有四个operation Slot 没有被归因于PE的操作占用。

> Example D11-5 Incrementing event counter n by 1 when V meets the threshold
> condition
>
> When all of the following are true, the event counter n will increment by
> one:
> > 增长1
> * PMEVTYPER<n>_EL0.TC is 0b101, greater-than-or-equal, count, meaning
>   threshold counting for event counter n is enabled.
>   > PMEVTYPER<n>_EL0.TC 是 0b101，greater-than-or-equal，count, 意味着
>   > 启用了事件计数器 n 的阈值计数。
> * PMEVTYPER<n>_EL0.TH is 2.
> * PMEVTYPER<n>.evtCount is 0x80C1, FP_FIXED_OPS_SPEC.
>
> * At least one floating-point multiply-add instruction is issued on the
>   cycle. 
>   > 该 cycle 中至少发出一条浮点乘加指令。
>   > Note 
>   > 
>   > The event counter n also increments by 1 if, for example, two or more
>   > independent floatingtpoint add  operations are issued on the cycle.
>   >
>   > 例如，如果在该cycle中发出两个或多个独立的浮点加法运算，则事件计数器n
>   > 也会递增1。
>   >> 你这不欺负老实人么,一开始没有反应过来.

# D11.8.3 Accessing event counting threshold functionality

The PMEVTYPER<n>_EL0.{TC, TH} fields are not accessible through the AArch32
PMEVTYPER<n> System register. However, the threshold condition still applies in
AArch32 state, and PMMIR_EL1.THWIDTH is readable in the AArch32 PMMIR System
register.
> PMEVTYPER_EL0.{TC, TH} 字段无法通过 AArch32 PMEVTYPER 系统寄存器访问。 然而，
> 阈值条件在 AArch32 状态下仍然适用，并且 PMMIR_EL1.THWIDTH 在 AArch32 PMMIR 
> 系统寄存器中可读。

When FEAT_PMUv3_TH is implemented, the PMEVTYPER<n>_EL0.{TC, TH} fields are
accessible through the AArch64 PMEVTYPER<n>_EL0 System registers and the
external interface PMEVTYPER<n>_EL0 registers. See Chapter I3 Recommended
External Interface to the Performance Monitors.
> 实现 FEAT_PMUv3_TH 时，可通过 AArch64 PMEVTYPER_EL0 系统寄存器和外部接口 
> PMEVTYPER_EL0 寄存器访问 PMEVTYPER_EL0.{TC, TH} 字段。 请参阅 Chapter 13 
> Recommended External Interface to the Performance Monitors
>
> > 还有 External Interface ???

PMMIR_EL1.THWIDTH is readable in the external PMMIR register.
> PMMIR_EL1.THWIDTH 在外部 PMMIR 寄存器中可读。

# D11.8.4 Pseudocode description of event counting threshold

See PMUCountValue() in Chapter J1 Armv8 Pseudocode for a pseudocode description
of the operation of the threshold condition.
