> accuracy /ˈækjərəsi/: 准确的, 精确的

The Performance Monitors:

* Are a non-invasive debug component. See Non-invasive behavior.
  > 这是一个 non-invasive debug 组建, 请参阅 Non-Invasive behavior

* Must provide broadly accurate and statistically useful count information.

However, the Performance Monitors allow for:

* A reasonable degree of inaccuracy in the counts to keep the implementation
  and validation cost low. See A reasonable degree of inaccuracy on page
  D11-5249.
  > ```
  > degree: 度;程度;
  > reasonable : 合理的,有理由的;公平的;可以接受的;合乎情理的
  > ```
  > 合理程度的计数不准确可保持较低的implementation 和验证成本。 请参阅第 D11-5249 
  > 页上的合理程度的不准确。
* IMPLEMENTATION DEFINED controls, such as those in ACTLR registers, that
  software must configure before using certain PMU events. For example, to
  configure how the PE generates PMU events for components such as external
  caches and external memory.
  > 软件必须在使用某些 PMU 事件之前配置 IMPLEMENTATION DEFINED controls(控件, 控制项)，
  > 例如 ACTLR 寄存器中的controls。该行为的例子: 配置PE如何为外部缓存和外部存储器等
  > 组件生成PMU事件。
* Other IMPLEMENTATION DEFINED controls, such as those in ACTLR registers, to
  optionally put the PE in an operating state that might do one or both of
  the following:
  > 其他 IMPLEMENTATION DEFINED controls, 例如ACTLR register中的, 可以选择将 PE 
  > 置于可能执行以如下一项或两项的操作状态：
  + Change the level of non-invasiveness of the Performance Monitors so that
    enabling an event counter can impact the performance or behavior of the PE.
    > 更改 性能监视器的 non-invasiveness 的级别, 以便 以便启用事件计数器可以影响 
    > PE 的性能或行为。
  + Allow inaccurate counts. This includes, but is not limited to, cycle counts.
    > inaccurate [ɪnˈækjərət]: adj 不准确的
    > 允许不精确的计数。这包括但不限于cycle count

# D11.2.1 Non-invasive behavior

The Performance Monitors are a non-invasive debug feature. A non-invasive debug
feature permits the observation of data and program flow. Performance Monitors,
PC Sample-based Profiling and Trace are non-invasive debug features.

> profiling [ˈproʊfaɪlɪŋ] 资料搜集 ; 扼要介绍 ; 概述 ; 写简介 
>
> 性能监视器是一种 non-invasive 调试功能。 non-invasive 调试功能允许观察数据和
> 程序流。性能监视器、PC Sample-based Profiling 和Trace 是 non-invasive 调试功能。

Non-invasive debug components do not guarantee that they do not make any
changes to the behavior or performance of the processor. Any changes that do
occur must not be severe however, as this will reduce the usefulness of event
counters for performance measurement and profiling. This does not include any
change to program behavior that results from the same program being
instrumented to use the Performance Monitors, or from some other performance
monitoring process being run concurrently with the process being profiled in a
multitasking operating system. As such, a reasonable variation in performance
is permissible.

> ```
> instrument [ˈɪnstrəmənt] n 工具;仪器 v: 给...装备测量仪器
> concurrently [kənˈkɜrəntli] n : 同时的
> ```
> severe [sɪˈvɪə\(r\)] 严格的; 严厉的;严峻的; 重的,苛刻的; 极其恶劣的;十分严重的
> non-invasive 调试组件不保证它们不会对处理器的行为或性能进行任何更改。然而，发生的
> 任何变化都不能太严重，因为这会降低事件计数器对于性能测量和分析的有用性。这不包括对
> 程序行为的任何更改，这些更改是由于使用(多个?)性能监视器来检测同一程序，或者与多任
> 务操作系统中正在分析的进程同时运行的某些其他性能监视进程而导致的。(这里应该只
> performance monitoring process 不能影响另外的正在该核上运行的task?) 因此，性能的合理
> 变化是允许的。

> NOTE
>
> Power consumption is one measure of performance. Therefore, a reasonable
> variation in power consumption is permissible.
>
> consumption  [kənˈsʌmpʃn] : 消耗
>
> 功耗是性能的衡量标准之一。 因此，功耗的合理变化是允许的。

Arm does not define a reasonable variation in performance, but recommends that
such a variation is kept within 5% of normal operating performance, when
averaged across a suite of code that is representative of the application
workload.

> suite [swiːt] : 一组,一套
>
> Arm 没有定义合理的性能变化，但建议在对代表应用程序工作负载的一组代码计算平均
> 值时, 将这种变化保持在正常操作性能的 5% 以内。

> Note
> 
> For profiles other than A-profile, there is the potential for stronger
> requirements. Ultimately, performance requirements are determined by
> end-users, and not set by the architecture.
>
>> Ultimately [ˈʌltɪmətli]: 最终的
>>
>> 对于 A-profile 以外的profiles，可能会有更严格的要求。 最终，性能要求
>> 由最终用户决定，而不是由架构设定。

For some common architectural events, this requirement to be non-invasive can
conflict with the requirement to present an accurate value of the count under
normal operating conditions. Should an implementation require more
performance-invasive techniques to accurately count an event, there are the
following options:

> present v: 提出;(以某种方式)展现，显示，表现;表达，表示;提交;
>
> 对于一些常见的架构事件，这种 non-invasive 的要求可能与在正常操作条件下呈现准确的计
> 数的要求相冲突。 如果实现需要更多 performance-invasive 技术来准确计数事件，则有以
> 下选项：

* If the event is optional, define an alternative implementation defined event
  that accurately counts the event and document the impact on performance of
  enabling the event.
  > 如果该事件是可选的，请定义一个替代实现定义的事件，该事件可以准确地对事件进
  > 行计数并记录启用该事件对性能的影响。

* Provide an implementation defined control that disables accurate counting of
  the event to restore broadly accurate performance, and document the impact on
  performance of accurate counting.
  > broadly: 基本上;大体上;不考虑细节地;
  >
  > 提供 IMPLEMENTATION  DEFINED 的控件，禁用事件的精确计数，以恢复大致准确的性能，
  > 并记录准确计数对性能的影响。

# D11.2.2 A reasonable degree of inaccuracy

The Performance Monitors provide broadly accurate and statistically useful
count information. To keep the implementation and validation cost low, a
reasonable degree of inaccuracy in the counts is acceptable. Arm does not
define a reasonable degree of inaccuracy but recommends the following
guidelines:
> statistically  /stə'tɪstɪkli/ 统计地;统计上地
>
> 性能监视器提供广泛准确且统计上有用的计数信息。 为了保持较低的implementation
> 和validation 成本，合理程度的计数不准确是可以接受的。 Arm 没有定义合理的不
> 准确程度，但建议遵循以下准则：

* Under normal operating conditions, the counters must present an accurate
  value of the count.
  > 在正常操作条件下，计数器必须提供准确的计数值。
* In exceptional circumstances, such as a change in Security state or other
  boundary condition, it is acceptable for the count to be inaccurate.
  > circumstances [ˈsɜːkəmstənsɪz]:  环境
  >
  > 在特殊情况下，例如安全状态或其他边界条件发生变化，计数不准确是可以接受的。
* Under very unusual, non-repeating pathological cases, the counts can be
  inaccurate. These cases are likely to occur as a result of asynchronous
  exceptions, such as interrupts, where the chance of a systematic error in the
  count is very unlikely.
  > ```
  > pathological /ˌpæθəˈlɒdʒɪkl/: 
  >      病理学的;病态的;与疾病有关的;
  >      与病理学相关的;不理智的;无法控制的;无道理的 
  > ```
  >
  > 在非常不寻常、非重复的pathological情况下，计数可能不准确。这些情况很可能是
  > 由于异步异常（例如中断）而发生，其中计数中出现系统错误的可能性很小。

> NOTE
>
> An implementation must not introduce inaccuracies that can be triggered
> systematically by the execution of normal pieces of software. For example, it
> is not reasonable for the count of branch behavior to be inaccurate when
> caused by a systematic error generated by the loop structure producing a
> dropping in branch count.
>
>> systematically [ˌsɪstə'mætɪklɪ] 有系统的;有组织的
>>
>> implementation 不得引入由正常软件的执行系统地触发的不准确性。 
>> 例如，当由于循环结构产生的系统误差导致分支计数下降而导致分支行为计数不准确时，
>> 这是不合理的。
>
> However, dropping a single branch count as the result of a rare interaction
> with an interrupt is acceptable.
>
>> rare: 稀有的;珍贵的;稀少的
>>
>> 然而，由于与中断的罕见交互而减少单个分支计数是可以接受的。

The permitted inaccuracy limits the possible uses of the Performance Monitors.
In particular, the architecture does not define the point in a pipeline where
the event counter is incremented, relative to the point where a read of the
event counters is made. This means that pipelining effects can cause some
imprecision, and can affect which events are counted.

> ```
> relative: 相对的
> imprecision /ˌɪmprɪˈsɪʒn/ 不精确
> ```
> 允许的不准确性限制了性能监视器的可能用途。 尤其是， 特别地，该体系结构没有定义
> pipeline中事件计数器相对于读取事件计数器的点递增的点。这意味着pipeline 影响 可能会
> 导致一些不精确，并可能影响对哪些事件进行技术
>
>> 这段没有翻译通顺

Where a direct write to a Performance Monitors control register disables a
counter, and is followed by a Context synchronization event, any subsequent
indirect read of the control register by the Performance Monitors to determine
whether the counter is enabled will return the updated value. Any subsequent
direct read of the counter or counter overflow status flags will return the
value at the point the counter was disabled.
> 如果直接写入性能监视器控制寄存器会禁用计数器，并且随后发生上下文同步事件，
> 则性能监视器对控制寄存器的任何后续间接读取以确定计数器是否启用将返回更新的值。
> 任何后续直接读取计数器或计数器溢出状态标志都将返回计数器被禁用时的值。
>
>> 这段后续在理解

> Note
>
> The imprecision means that the counter might have counted an event around the
> time the counter was disabled, but does not allow the event to be observed as
> counted after the counter was disabled.

A change of Security state can also affect the accuracy of the Performance
Monitors, see Interaction with EL3 on page D11-5245.

In addition to this, entry to and exit from Debug state can disturb the normal
running of the PE, causing further inaccuracy in the Performance Monitors.
Disabling the counters while in Debug state limits the extent of this
inaccuracy. An implementation can employ methods to limit this inaccuracy, for
example by promptly disabling the counters during the Debug state entry
sequence.

An implementation must document any particular scenarios where significant
inaccuracies are expected.

> 这些后续在理解.
