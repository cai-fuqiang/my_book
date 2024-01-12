The event counters, PMEVCNTR<n> are either 32-bit or 64-bit unsigned counters
that overflow in the following situations:
> situation: 状况
>
> 事件计数器PMEVCNTR是在以下情况下溢出的32位或64位无符号计数器:
>
>> NOTE
>>
>> unsigned overflow 是指最高位向更高位进位

* If FEAT_PMUv3p5 is not implemented, 32-bit event counters are implemented,
  and if incrementing PMEVCNTR<n> causes an unsigned overflow of an event
  counter, the PE sets PMOVSCLR[n] to 1.
  > 如果未实现 FEAT_PMUv3p5，则实现 32 位事件计数器，并且如果递增 PMEVCNTR 
  > 导致事件计数器无符号溢出，则 PE 将 PMOVSCLR[n] 设置为 1。
* If FEAT_PMUv3p5 is implemented, 64-bit event counters are implemented,
  HDCR.HPMN is not 0, and either n is in the range [0 .. (HDCR.HPMN-1)] or EL2
  is not implemented, then event counter overflow is configured by PMCR.LP:
  > 如果实现了 FEAT_PMUv3p5，则实现了 64 位事件计数器，HDCR.HPMN 不为 0，并且 n 
  > 在 [0 … (HDCR.HPMN-1)] 范围内或未实现 EL2，则配置事件计数器溢出 由 PMCR.LP 
  > 提供：
  >> 未实现 EL2, 那么所有的寄存器都在 first range
  + When PMCR.LP is set to 0, if incrementing PMEVCNTR<n> causes an unsigned
    overflow of bits [31:0] of the event counter, the PE sets PMOVSCLR[n] to 1.
    > 当 PMCR.LP 设置为 0 时，如果递增 PMEVCNTR 导致事件计数器的位 [31:0] 无符
    > 号溢出，则 PE 将 PMOVSCLR[n] 设置为 1。
  + When PMCR.LP is set to 1, if incrementing PMEVCNTR<n> causes an unsigned
    overflow of bits [63:0] of the event counter, the PE sets PMOVSCLR[n] to 1.
    > 当 PMCR.LP 设置为 1 时，如果递增 PMEVCNTR 导致事件计数器的位 [63:0] 无符号
    > 溢出，则 PE 将 PMOVSCLR[n] 设置为 1。

* If FEAT_PMUv3p5 is implemented, 64-bit event counters are implemented, EL2 is
  implemented, and HDCR.HPMN is less-than PMCR.N, when n is in the range
  [HDCR.HPMN .. (PMCR.N-1)], event counter overflow is configured by HDCR.HLP:
  > 如果实现 FEAT_PMUv3p5，则实现 64 位事件计数器，实现 EL2，并且 HDCR.HPMN 小于
  > PMCR.N，当 n 在 [HDCR.HPMN … (PMCR.N-1)] 范围内时，事件 计数器溢出由 HDCR.HLP 
  > 配置：
  + When HDCR.HLP is set to 0, if incrementing PMEVCNTR<n> causes an unsigned
    overflow of bits [31:0] of the event counter, the PE sets PMOVSCLR[n] to 1.
    > 当 HDCR.HLP 设置为 0 时，如果递增 PMEVCNTR 导致事件计数器的位 [31:0] 无符
    > 号溢出，则 PE 将 PMOVSCLR[n] 设置为 1。
  + When HDCR.HLP is set to 1, if incrementing PMEVCNTR<n> causes an unsigned
    overflow of bits [63:0] of the event counter, the PE sets PMOVSCLR[n] to 1.
    > 当 HDCR.HLP 设置为 1 时，如果递增 PMEVCNTR 导致事件计数器的位 [63:0] 无符
    > 号溢出，则 PE 将 PMOVSCLR[n] 设置为 1。

The cycle counter, PMCCNTR, is a 64-bit unsigned counter, that is configured by
PMCR.LC:
> 周期计数器 PMCCNTR 是一个 64 位无符号计数器，由 PMCR.LC 配置：

* If PMCR.LC is set to 0, if incrementing PMCCNTR causes an unsigned overflow
  of bits [31:0] of the cycle counter, the PE sets PMOVSCLR[31] to 1.
  > 如果 PMCR.LC 设置为 0，并且递增 PMCCNTR 导致周期计数器的位 [31:0] 无符号溢出，
  > 则 PE 将 PMOVSCLR[31] 设置为 1。

* If PMCR.LC is set to 1, if incrementing PMCCNTR causes an unsigned overflow
  of bits [63:0] of the cycle counter, the PE sets PMOVSCLR[31] to 1.
  > 如果 PMCR.LC 设置为 1，并且递增 PMCCNTR 导致周期计数器的位 [63:0] 无符号溢出，
  > 则 PE 将 PMOVSCLR[31] 设置为 1。

The update of PMOVSCLR occurs synchronously with the update of the counter.
> PMOVSCLR 的更新与计数器的更新同步发生。
>
>> 这里指的是update PMOVSCLR overflow bit 和更新 couter的值同时发生

For all 64-bit counters, incrementing the counter is the same whether an
unsigned overflow occurs at [31:0] or [63:0]. If the counter increments for an
event, bits [63:0] are always incremented,

> 对于所有 64 位计数器，无论无符号溢出发生在 [31:0] 还是 [63:0]，计数器递增都
> 是相同的。如果计数器因事件而递增，则位 [63:0] 始终递增，

When any overflow occurs, an interrupt request is generated if the PE is
configured to generate counter overflow interrupts. For more information, see
Generating overflow interrupt requests.

> 当任何溢出发生时，如果PE配置为产生计数器溢出中断，则产生中断请求。 有关更多
> 信息，请参阅Generating overflow interrupt request.


If FEAT_PMUv3p7 is implemented, event counting can be frozen after an unsigned
overflow is detected, see Freezing event counters on page D11-5255.

> 如果实现 FEAT_PMUv3p7，则在检测到无符号溢出后可以冻结事件计数，请参阅第 D11-5255 
> 页上的冻结事件计数器。

> Note
>
> Software executing at EL1 or higher must take care that setting PMCR.LP or
> HDCR.HLP does not cause software executing at lower Exception levels to
> malfunction. If legacy software accesses the PMU at lower Exception levels,
> software at the higher Exception levels should not set the PMCR.LP or
> HDCR.HLP fields to 1. However, if the legacy software does not use the
> counter overflow, it is not affected by setting the PMCR.LP or HDCR.HLP to 1.
>
>> 在 EL1 或更高级别执行的软件必须注意设置 PMCR.LP 或 HDCR.HLP 不会导致在
>> 较低异常级别执行的软件出现故障。 如果旧版软件访问较低异常级别的 PMU，
>> 则较高异常级别的软件不应将 PMCR.LP 或 HDCR.HLP 字段设置为 1

# D11.3.1 Generating overflow interrupt requests

Software can program the Performance Monitors so that an overflow interrupt
request is generated when a counter overflows. See PMINTENSET and PMINTENCLR.

> 软件可以对性能监视器进行编程，以便在计数器溢出时生成溢出中断请求。 请参阅 
> PMINTENSET 和 PMINTENCLR。

> Note
>
> * The mechanism by which an interrupt request from the Performance Monitors
>   generates an FIQ or IRQ exception is IMPLEMENTATION DEFINED.
>   > 来自性能监视器的中断请求生成 FIQ 或 IRQ 异常的机制是由实现定义的。
>
> * Arm recommends that the overflow interrupt requests:
>   + Translate into a PMUIRQ signal, so that they are observable to external
>     devices.
>     > 转换为 PMUIRQ 信号，以便外部设备可以观察到它们。
>   + Connect to inputs on an IMPLEMENTATION DEFINED Generic Interrupt
>     Controller as a Private Peripheral Interrupt (PPI) for the originating
>     processor. See the ARM Generic Interrupt Controller Architecture
>     Specification for information about PPIs. 
>     > Peripheral  [pəˈrɪfərəl] : adj 外围的, 周边的, 次要的 n 外围设备
>     >
>     > 连接到 IMPLEMENTATION DEFINED 通用中断控制器上的输入，作为原始处理器的 Private
>     > Peripheral Interrupt (PPI)。 有关 PPI 的信息，请参阅 ARM 通用中断控制器架构规范。
>   + Connect to a Cross Trigger Interface (CTI), see `Chapter H5 The Embedded
>     Cross-Trigger Interface`.
> 
> * Arm strongly discourages implementations from connecting overflow interrupt
>   requests from multiple PEs to the same System Peripheral Interrupt (SPI)
>   identifier. 
>   > Arm 强烈建议不要将来自多个 PE 的overflow interrupt request 连接到同一个 System 
>   > Peripheral  Interrupt (SPI) 标识符。
> * From GICv3, the ARM® Generic Interrupt Controller Architecture
>   Specification recommends that the Private Peripheral Interrupt (PPI) with
>   ID 23 is used for overflow interrupt requests.
>   > 从 GICv3 开始，ARM® 通用中断控制器架构规范建议将 ID 为 23 的PPI用于溢出
>   > 中断请求。

Software can write to the counters to control the frequency at which interrupt
requests occur. For example, software might set a 32-bit counter to 0xFFFF0000,
to generate another counter overflow after 65536 increments, and reset it to
this value every time an overflow interrupt occurs.

> 软件可以写入计数器来控制中断请求发生的频率。 例如，软件可能将 32 位计数器设置
> 为 0xFFFF0000，以在 65536 增量后生成另一个计数器溢出，并在每次发生溢出中断时将
> 其重置为该值。
>
>> WDF?? 
>> 
>> 原来是这么控制频率的, 原始高效.
>>
>> 这么设计更高效, 不用在update count 时, 和另一个值进行比对,而只需要检测其是否
>> overflow 就行了

> Note
>
> If an event can occur multiple times in a single clock cycle, then counter
> overflow can occur without the counter registering a value of zero.
> 
> > 如果一个事件可以在单个时钟周期内多次发生，则可能会发生计数器溢出，而计数
> > 器不会记录零值。

The overflow interrupt request is a level-sensitive request. The PE signals a
request for:

> sensitive : 易受伤害的;易损坏的; 很受影响的; 敏感的;
>
> 溢出中断请求是 level-sensitive 的请求。 PE 会为下面的情况发出请求:

* Any given PMEVCNTR<n> counter, when the value of PMOVSSET[n] is 1, the value
  of PMINTENSET[n] is 1, and one of the following is true:
  > 任何给定的 PMEVCNTR 计数器，当 PMOVSSET[n] 的值为 1 时，PMINTENSET[n] 的值为 
  > 1，且以下条件之一为 true：

  + EL2 is not implemented and the value of PMCR.E is 1.
    > EL2 没有实现, 并且 PMCR.E == 1

  + EL2 is implemented, n is less than the value of HDCR.HPMN, and the value of
    PMCR.E is 1.
    > 实现了EL2, 且 n < HDCR.HPMN, 并且 PMCR.E == 1
 
  + EL2 is implemented, n is greater than or equal to the value of HDCR.HPMN, and
    the value of HDCR.HPME is 1.
    >  实现了 EL2, n >= HDCR.HPMN, 并且 HDCR.HPME == 1

> NOTE
>
> 这里仍然是考虑虚拟化的情况, 除了 HDCR 其他寄存器都是 guest host 共享的, 所以怎么
> 只 控制 在 non-EL2 时, second range 的PMI呢 :
>
> 通过 HDCR.HPME, 当然这里只控制是否关闭, 因为开启的话, 还需要看 PMCNTENSET_EL0,
> 这个不会在 non-EL2 中有 second range 的 register

* The cycle counter, when the values of PMOVSSET[31], PMINTENSET[31], and PMCR.E
  are all 1.
  > 周期计数器，当 PMOVSSET[31]、PMINTENSET[31] 和 PMCR.E 的值都为 1 时。

The overflow interrupt request is active in both Secure and Non-secure states.
In particular, if EL3 and EL2 are both implemented, overflow events from
PMEVCNTR<n> where n is greater than or equal to the value of HDCR.HPMN can be
signaled from all modes and states but only if the value of HDCR.HPME is 1.

> 溢出中断请求在安全和非安全状态下均有效。 特别是，如果 EL3 和 EL2 均已实现，
> 则可以从所有模式和状态发出来自 PMEVCNTR 的溢出事件（其中 n 大于或等于 
> HDCR.HPMN 的值），但仅当 HDCR.HPME 的值为 1 时。

The interrupt handler for the counter overflow request must cancel the
interrupt request, by writing 1 to PMOVSCLR[n] to clear the overflow bit to 0.

> 计数器溢出请求的中断处理程序必须取消中断请求，方法是向 PMOVSCLR[n] 写入 1，
> 将溢出位清除为 0。

**Pseudocode description of overflow interrupt requests**

See Chapter J1 Armv8 Pseudocode for a pseudocode description of overflow
interrupt requests. The AArch64.CheckForPMUOverflow() and
AArch32.CheckForPMUOverflow() pseudocode functions signal PMU overflow
interrupt requests to an interrupt controller and PMU overflow trigger events
to the cross-trigger interface.

> 有关溢出中断请求的伪代码描述，请参阅章节 J1 Armv8 伪代码。 
> AArch64.CheckForPMUOverflow() 和 AArch32.CheckForPMUOverflow() 伪代码函数
> 向中断控制器发出 PMU 溢出中断请求信号，并向 cross-trigger interface发出 PMU 
> 溢出触发事件信号。
