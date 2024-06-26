# 8.1 TASK MANAGEMENT OVERVIEW

A task is a unit of work that a processor can dispatch, execute, and suspend.
It can be used to execute a program, a task or process, an operating-system
service utility, an interrupt or exception handler, or a kernel or executive
utility.

> ```
> utility: /juːˈtɪləti/ : 有用,有效, 实用
> executive /ɛgˈzɛkjutɪv/ : 经营管理的; 有执行权的; 行政的;实施的;高级的;
> ```
>
> task 是一个 processor 可以 dispatch/execute/suspend work的单元. 它可以用于
> 执行一个 program, task, process, operating-system service utility, intr/exception
> handler, 或者 kernel/executive utility.

The IA-32 architecture provides a mechanism for saving the state of a task, for
dispatching tasks for execution, and for switching from one task to another.
When operating in protected mode, all processor execution takes place from
within a task. Even simple systems must define at least one task. More complex
systems can use the processor’s task management facilities to support
multitasking applications.

> take place:  发生，产生; 进行，举行
>
> IA-32 arch 为调度要执行的任务和 切换一个任务到另一个任务, 提供了一个用于 保存
> task 状态的机制. 当运行在保护模式下, 所有的 processor的都运行在task中. 即使
> 简单的系统必须定义至少一个task. 更复杂的系统 可能使用 processor的 task management
> 功能来支持多任务.

## 8.1.1 Task Structure

A task is made up of two parts: a task execution space and a task-state segment
(TSS). The task execution space consists of a code segment, a stack segment,
and one or more data segments (see Figure 8-1). If an operating system or
executive uses the processor’s privilege-level protection mechanism, the task
execution space also provides a separate stack for each privilege level.

> task 有两部分 组成: task execution space 和 task-state segment(TSS)
>
> task execution space:
>   * code segment
>   * task segment
>   * 1/more data segment
>
> 如果操作系统或者 executive 使用了处理器的 privilege-level protection 机制,
> task execution space 也应该提供给每个 privilege level 一个单独的stack.

The TSS specifies the segments that make up the task execution space and
provides a storage place for task state information. In multitasking systems,
the TSS also provides a mechanism for linking tasks. A task is identified by
the segment selector for its TSS. When a task is loaded into the processor for
execution, the segment selector, base address, limit, and segment descriptor
attributes for the TSS are loaded into the task register (see Section 2.4.4,
“Task Register (TR)”).

> make up : 构成
>
> TSS 指定了构成 task execution space 的segments并且提供了保存task state information
> 的地方. 在多任务系统中, TSS 也提供了对 linking tasks的支持. task由他的TSS的
> 段选择子指定. 当任务被加载到 processor 来运行时, 该TSS的 segment selector, base 
> address, limit 和 segment descriptor attr 都被加载到 task register (Section 2.4.4)

If paging is implemented for the task, the base address of the page directory
used by the task is loaded into control register CR3.

> 如果该task实现了分页, 该用于该task的 page directory 的 base address 被加载到 控制寄存器
> CR3.

![structure_of_a_task](pic/structure_of_a_task.png)

## 8.1.2 Task State

The following items define the state of the currently executing task:

* The task’s current execution space, defined by the segment selectors in the
  segment registers (CS, DS, SS, ES, FS, and GS).
* The state of the general-purpose registers.
* The state of the EFLAGS register.
* The state of the EIP register.
* The state of control register CR3.
* The state of the task register.
* The state of the LDTR register.
* The I/O map base address and I/O map (contained in the TSS).
* Stack pointers to the privilege 0, 1, and 2 stacks (contained in the TSS).
* Link to previously executed task (contained in the TSS).
* The state of the shadow stack pointer (SSP).

> NOTE
>
> 该段落中描述的 "contained in the TSS" 表示这些信息本身就保存在 TSS,
> 而其他的信息只是在task switch 时 store/load.

Prior to dispatching a task, all of these items are contained in the task’s
TSS, except the state of the task register. Also, the complete contents of the
LDTR register are not contained in the TSS, only the segment selector for the
LDT.

> 在调度一个任务之前, 所有的item 都会被包含在 task的 TSS中, 除了task register 
> 的状态. 同时, LDTR register 完整的内容也不会包含进 TSS, 只包含了该LDT的 segment
> selector.

## 8.1.3 Executing a Task

Software or the processor can dispatch a task for execution in one of the
following ways:

> software 或者processor 可以通过执行下面的任意一种方式来调度任务

* A explicit call to a task with the CALL instruction.
* A explicit jump to a task with the JMP instruction.
* An implicit call (by the processor) to an interrupt-handler task.
* An implicit call to an exception-handler task.
* A return (initiated with an IRET instruction) when the NT flag in the EFLAGS
  register is set.

> * CALL task
> * JMP task
> * interrupt-handler task
> * exception-handler task
> * IRET (当 EFLAGS 中的 NT flag 被设置时)

All of these methods for dispatching a task identify the task to be dispatched
with a segment selector that points to a task gate or the TSS for the task.
When dispatching a task with a CALL or JMP instruction, the selector in the
instruction may select the TSS directly or a task gate that holds the selector
for the TSS. When dispatching a task to handle an interrupt or exception, the
IDT entry for the interrupt or exception must contain a task gate that holds
the selector for the interrupt- or exception-handler TSS.

> 所有这些调度任务的方法都通过 指向 该任务的 task gate 或者 TSS的段选择子来
> 标识要调度的任务. 当通过 CALL 或者 JMP 指令调度一个任务时, 指令中的选择子
> 可以直接选择TSS 或者一个持有该TSS的 task gate. 当调度一个任务来处理 interrupt
> 或者 exception时, 对于该interrupt或者 exception 的 IDT entry必须包含持有
> interrupt- 或者 exception-handler TSS 的selector的 task gate
>
> > NOTE
> >
> > IOW:
> > ```
> > +---------+
> > |GDT/LDT  |
> > +---------+
> > |  ...    |
> > +---------+
> > |TSS DESC | <---call /jmp
> > +---------+
> > |TASKGATE |
> > |(TSS     | <----call /jmp
> > |segent   |
> > |selector)|
> > +---------+
> >
> > +---------+
> > | IDT     |
> > +---------+
> > |TASKGATE |
> > |(TSS     | <----call /jmp, TSS segment is interrupt/exception-handler TSS
> > |segent   |
> > |selector)|
> > +---------+
> > ```

When a task is dispatched for execution, a task switch occurs between the
currently running task and the dispatched task. During a task switch, the
execution environment of the currently executing task (called the task’s state
or context) is saved in its TSS and execution of the task is suspended. The
context for the dispatched task is then loaded into the processor and execution
of that task begins with the instruction pointed to by the newly loaded EIP
register. If the task has not been run since the system was last initialized,
the EIP will point to the first instruction of the task’s code; otherwise, it
will point to the next instruction after the last instruction that the task
executed when it was last active.

> 当一个任务调度来执行时, 在当前running task 和要 被dispatch的 task之前
> 发生 task switch. 在task switch 中, 当前正在执行的的task的 execution
> environment(被称作 task的 state/context) 被保存在他的 TSS 中, 并且该task
> 的执行被suspend.  要被调度道德task 的context 将会 load到 processor 并且在
> 由新加载的EIP register的指令开始执行该task. 如果task 在系统上一次初始化
> 后还没有运行过, EIP 则只想该task的code第一条指令;否则, 它将会只想上一次task
> active时的最后一条指令的下一条指令.

If the currently executing task (the calling task) called the task being
dispatched (the called task), the TSS segment selector for the calling task is
stored in the TSS of the called task to provide a link back to the calling
task. For all IA-32 processors, tasks are not recursive. A task cannot call or
jump to itself.

> recursive  [rɪˈkɜːrsɪv] : 递归的
>
> 如果 当前执行的 task (calling task) 调度到 即将被调度的task( called task), 
> calling task 的TSS segment selector 被保存在 called tasks 的TSS中, 以提供
> 一个回到 calling task 的 link. 对于所有的 IA-32 processor, tasks 不能是
> 递归的. tasks不能 call/jump 它自己.

Interrupts and exceptions can be handled with a task switch to a handler task.
Here, the processor performs a task switch to handle the interrupt or exception
and automatically switches back to the interrupted task upon returning from the
interrupt-handler task or exception-handler task. This mechanism can also
handle interrupts that occur during interrupt tasks.

> 通过将 tasks 切换到 handler tasks 来处理 interrupts 和 exceptions. 这里, 处理器
> 执行了一个 task switch 来处理 interrupt 或者 exception 并从 interrupt-handler
> task 或者 exception-handler task 返回时 自动切换到 interrupted tasks(被中断的task).
> 该机制也可以处理发生在 interrupt tasks中的interrupt.

As part of a task switch, the processor can also switch to another LDT,
allowing each task to have a different logical-to-physical address mapping for
LDT-based segments. The page-directory base register (CR3) also is reloaded on
a task switch, allowing each task to have its own set of page tables. These
protection facilities help isolate tasks and prevent them from interfering with
one another.

> 作为 task switch 的一部分, processor 也可以switch 到另一个LDT, 允许每一个tasks
> 有一个不同的 基于 LDT segment 的 logical-to-physical address mapping . CR3 也
> 会在 task switch 中 reload, 允许每一个task 有自己的 page tables 集合.

If protection mechanisms are not used, the processor provides no protection
between tasks. This is true even with operating systems that use multiple
privilege levels for protection. A task running at privilege level 3 that uses
the same LDT and page tables as other privilege-level-3 tasks can access code
and corrupt data and the stack of other tasks.

> 如果 protection 机制没有被使用, 处理器在 tasks 之间没有提供 protection.
> 即使操作系统为 protection 使用 multiple privilege level  也是正确的.
> 运行在 特权级 3的tasks 使用相同的 LDT 和 page tables, 可以访问代码, 损坏
> 数据和其他任务的堆栈.

Use of task management facilities for handling multitasking applications is
optional. Multitasking can be handled in software, with each software defined
task executed in the context of a single IA-32 architecture task.

> 使用 task management 功能来处理 multitasking application 是可选的. Multitasking
> 可以被软件处理, 每个软件定义的人物在单个 IA-32 Architectures 上下文中执行. 

If shadow stack is enabled, then the SSP of the task is located at the 4 bytes
at offset 104 in the 32-bit TSS and is used by the processor to establish the
SSP when a task switch occurs from a task associated with this TSS. Note that
the processor does not write the SSP of the task initiating the task switch to
the TSS of that task, and instead the SSP of the previous task is pushed onto
the shadow stack of the new task.

> 如果 shadow stack 被使能, 然后 task 的 SSP 在 32-bit TSS 的 offset 104 位置(4 
> Byte) 并且当 task switch 发生在 和 该 TSS 相关的 tasks时, 处理器用它来建立 SSP.
> 注意, processor 没有将发起 task switch 的 SSP 写到该task的 TSS 中, 反而将previous
> tasks 的 SSP 会被push到新tasks的 shadow stack上.
