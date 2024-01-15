The PMU can filter events by various combinations of Exception level and
Security state. This gives software the flexibility to count events across
multiple processes.

> flexibility [ˌfleksə'bɪləti]
>
> PMU 可以通过异常级别和安全状态的各种组合来过滤事件。 这使软件能够灵活地计
> 算多个进程中的事件。

## D11.7.1 Filtering by Exception level and Security state

In AArch64 state:
* For each event counter, PMEVTYPER<n>_EL0 specifies the Exception levels in
  which the counter counts events Attributable to Exception levels.
  > 对于每个事件计数器，PMEVTYPER_EL0 指定异常级别(计数器对可归因于异常级
  > 别的事件进行计数)
* PMCCFILTR_EL0 specifies the Exception levels in which the cycle counter
  counts. 
  > PMCCFILTR_EL0 指定周期计数器计数的异常级别。

For an event that is Attributable to an Exception level, in a multithreaded
implementation:
> 对于可归因于异常级别的事件，在多线程实现中：

* When the Effective value of PMEVTYPER<n>_EL0.MT is 1, the specified
  filtering is evaluated using the current Exception level and Security state
  of the thread to which the event is Attributable. See Example D11-3.
  > 当 PMEVTYPER_EL0.MT 的有效值为 1 时，将使用事件所属线程的当前异常级别和安全
  > 状态来评估指定的过滤。 请参见示例 D11-3。
* When the Effective value of PMEVTYPER<n>_EL0.MT is 0, the event is only
  counted if it is Attributable to the counting thread, and the filtering is
  evaluated using the Exception level and Security state of the counting
  thread.

> Example D11-3 Example of the effect of the PMEVTYPER<n>_EL0.MT control
>
> In a multithreaded implementation, if the Effective value of
> PMEVTYPER<n>_EL0.MT is 1 and the value of PMEVTYPER<n>_EL0.U is 1 on the
> counting thread, then event counter n does not count events Attributable to
> EL0 on another thread, even if the counting thread is not executing at EL0.
>
> > 在多线程实现中，如果计数线程上 PMEVTYPER_EL0.MT 的有效值为 1 并且 
> PMEVTYPER_EL0.U 的值为 1，则事件计数器 n 不会对另一个线程上可归因于 EL0 
> 的事件进行计数，即使计数线程是 不在 EL0 执行

For each Unattributable event, it is IMPLEMENTATION DEFINED whether the
filtering applies. In a multithreaded implementation, if the filtering applies
to an Unattributable event, then the filtering is evaluated using the Exception
level and Security state of the counting thread.

> 对于每个不可归因事件，是否应用过滤由实现定义。 在多线程实现中，如果过滤应用于
> 不可归因事件，则使用计数线程的异常级别和安全状态来评估过滤。

In AArch32 state, the filtering controls are provided by the PMEVTYPER<n> and
PMCCFILTR registers.

> 在 AArch32 状态下，过滤控制由 PMEVTYPER 和 PMCCFILTR 寄存器提供。

For more information, see the individual register descriptions and
Multithreaded implementations on page D11-5258.

> 有关详细信息，请参阅第 D11-5258 页上的各个寄存器描述和多线程实现。

## D11.7.2 Accuracy of event filtering

For most events, it is acceptable that, during a transition between states,
events generated by instructions executed in one state are counted in the other
state. The following sections describe the cases where event counts must not be
counted in the wrong state:
> 对于大多数事件，可以接受的是，在状态之间的转换期间，在一种状态中执行的指令生
> 成的事件在另一种状态中进行计数。 以下部分描述了不得在错误状态下计数事件计数的
> 情况： 

* Exception-related events
* Software increment events on page D11-5261.

### Exception-related events

The PMU must filter events related to exceptions and exception handling
according to the Exception level in which the event occurred. These events are:

> PMU必须根据事件发生的异常级别来过滤与异常相关的事件和异常处理。 这些事件是：

* EXC_TAKEN, Exception taken.
* EXC_RETURN, Instruction architecturally executed, Condition code check
  pass, exception return.
* CID_WRITE_RETIRED, Instruction architecturally executed, Condition code
  check pass, write to CONTEXTIDR.
* TTBR_WRITE_RETIRED, Instruction architecturally executed, Condition code
  check pass, write to translation table base.
* EXC_UNDEF, Exception taken, other synchronous.
* EXC_SVC, Exception taken, Supervisor Call.
* EXC_PABORT, Exception taken, Instruction Abort.
* EXC_DABORT, Exception taken, Data Abort or SError.
* EXC_IRQ, Exception taken, IRQ.
* EXC_FIQ, Exception taken, FIQ.
* EXC_SMC, Exception taken, Secure Monitor Call.
* EXC_HVC, Exception taken, Hypervisor Call.
* EXC_TRAP_PABORT, Exception taken, Instruction Abort not Taken locally.
* EXC_TRAP_DABORT, Exception taken, Data Abort or SError not Taken locally.
* EXC_TRAP_OTHER, Exception taken, other traps not Taken locally.
* EXC_TRAP_IRQ, Exception taken, IRQ not Taken locally.
* BRB_FILTRATE, Branch record captured.

The PMU must not count an exception after it has been taken because this could
systematically report a result of zero exceptions at EL0. Similarly, it is not
acceptable for the PMU to count exception returns or writes to CONTEXTIDR after
the return from the exception.

> PMU 在发生异常后不得对异常进行计数，因为这可能会系统地报告 EL0 处的零异常结果。
> 同样，PMU 也不可接受异常返回计数或异常返回后写入 CONTEXTIDR。

### Software increment events

The PMU must filter software increment events according to the Exception level
in which the software increment occurred. Software increment counting must also
be precise, meaning the PMU must count every architecturally executed software
increment event, and must not count any Speculatively executed software
increment. Software increment events must also be counted without the need for
explicit synchronization. For example, two software increments executed without
an intervening Context synchronization event must increment the event counter
twice.

For more information, see SW_INCR, Instruction architecturally executed,
Condition code check pass, software increment.

> 和 software increment 相关先不了解
>
> ```
> !!!!!!!!
> 遗留问题
> !!!!!!!!
> ```

### D11.7.3 Pseudocode description of event filtering

See AArch64.CountPMUEvents() and AArch32.CountPMUEvents() in Chapter J1 Armv8
Pseudocode for a pseudocode description of event filtering. However, this
function does not completely describe the behavior for Unattributable events.

> 有关事件过滤的伪代码描述，请参阅第 J1 章 Armv8 伪代码中的 AArch64.CountPMUEvents() 
> 和 AArch32.CountPMUEvents()。 但是，此函数并未完全描述不可归因事件的行为。