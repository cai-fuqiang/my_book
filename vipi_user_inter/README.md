# CHAPTER 9 USER INTERRUPTS
## 9.1 INTRODUCTION
This chapter details an architectural feature called user interrupts.
> 该章节描述了一个称为 `user interrupts` architecture feature

This feature defines user interrupts as new events in the architecture. They are delivered to software operating in
64-bit mode with CPL = 3 without any change to segmentation state. Different user interrupts are distinguished by
a 6-bit user-interrupt vector, which is pushed on the stack as part of user-interrupt delivery. A new instruction,
UIRET (user-interrupt return) reverses user-interrupt delivery.
> 该feature 定义 user interrupts 为架构中的新的events。他们将递送到运行在 64-bit mode &&
> CPU = 3 的software，并且没有任何segmentation state 的改变。不同的user interrupts 通过
> 一个6-bit user-interrupt vector 区分，它在user-interrupts delivery中会压在 stack上。
> 一个新的指令 `UIRET` （user-interrupt return) 返回? user-interrupt delivery

The user-interrupt architecture is configured by new supervisor-managed state. This state includes new MSRs. In
expected usages, an operating system (OS) will update the content of these MSRs when switch between OS-
managed threads.
> user-interrupt architecture 可以通过 一个新的 supervisor-managed state配置。该state 包括一些新的MSR。
> 在预期的用法中，当进行OS-manager threads切换时，操作系统(OS)将会更新这些MSR的内容。

One of the MSRs references a data structure called the user posted-interrupt descriptor (UPID). User inter-
rupts for an OS-managed thread can be posted in the UPID associated with that thread. Such user interrupts will
be delivered after receipt of an ordinary interrupt (also identified in the UPID) called a user-interrupt notifica-
tion.<sup>1</sup>
> 这些MSRs其中之一指向了一个数据结构称为 user posted-interrupt descriptor (UPID)。 对于那些 OS-managed thread的 
> User interrupt可以通过其关联的UPID posted。这些user interrupt 将会在收到一个被称为user-interrupt notification 
> 的ordinary interrupt (在UPID 也会被定义) 后被deliverd 

System software can define operations to post user interrupts and to send user-interrupt notifications. In addition,
the user-interrupt architecture defines a new instruction, SENDUIPI, by which application software can send interprocessor 
user interrupts (user IPIs). An execution of SENDUIPI posts a user interrupt in a UPID and sends a user-
interrupt notification.
> 系统软件可以定义 post user interrupt 和 send user-interrupt notification的行为。另外，user-interrupt
> architecture 定义了一个新的指令, SENDUIPI, 借此，用户态程序可以发送 user IPI。执行SENDUPIP将会递送一个
> UPID中的一个user interrupt，并且发送一个 user interrupt notification。
>
> **by which** : 借此，由于，凭借

(Platforms may include mechanisms to process external interrupts as either ordinary interrupts or user interrupts.
Those processed as user interrupts would be posted in UPIDs may result in user-interrupt notifications. Specifics of
such mechanisms are outside of the scope of this document.)
> 平台可能包括将外部中断作为 ordinary interrupt 或者 user interrupts 的机制。当 user interrupt 在 UPIDs被posted时，
> 可能会造成 user interrupts notification。这些基质的spec 将不在该doc的范围之内

Section 9.2 explains how a processor enumerates support for user interrupts and how they are enabled by system
software. Section 9.3 identifies the new processor state defined for user interrupts. Section 9.4 explains how a
processor identifies and delivers user interrupts. Section 9.5 describes how a processor identifies and processes
user-interrupt notifications. Section 9.7 defines new support for user inter-processor interrupts (user IPIs). Section
9.8 details how existing instructions support the new processor state and presents instructions to be introduced for
user interrupts. Section 9.8.2 and Section 9.9 describe how user interrupts are supported by the XSAVE feature set
and the VMX extensions, respectively.
> Section 9.2 讲解了 处理器将如何枚举对 user interrupt 的支持并且怎么被系统软件enable。
>
> Section 9.3 规定了用于定义 user interrupt 新的 processor state。
>
> Section 9.4 讲解了处理其如何识别并delivery user interrupt
>
> Section 9.5 描述了 处理器如何识别并且 processes user-interrupt notifications
>
> Section 9.7 定义了对于 user IPI 的新支持。
>
> Section 9.8 描述了现有的指令如何支持 new processor state 并且展示了为user interrupt 引入的指令
>
> Section 9.8.2 Secion 9.9 描述了 user interrupt 如何分别的通过 XSAVE feature set支持以及被 VMX extensions 支持


## 9.2 ENUMERATION AND ENABLING
Software enables user interrupts by setting bit 25 (UINTR) in control register CR4. Setting CR4.UINTR enables
user-interrupt delivery (Section 9.4.2), user-interrupt notification identification (Section 9.5.1), and the user-
interrupt instructions (Section 9.6). It does not affect the accessibility of the user-interrupt MSRs (Section 9.3) by
RDMSR, WRMSR or the XSAVE feature set.
> 软件通过设置 CR4 bit 25(UINTR) 来enable user interrupt。设置CR4.UINTR将enables user-interrupt delivery(Section 9.4.2)
> user-interrupt notification identification(Section 9.5.1)和 user-interrupt instructions(Section 9.6)。它不会
> 影响通过RDMSR,WRMSR,以及XSAVE feature set 等指令 对user-interrupt MSRs（Section 9.3)访问(设不设置CR4.UINTR不会影响这些
> MSR的访问?)
>
Processor support for user interrupts is enumerated by CPUID.(EAX=7,ECX=0):EDX[5]. If this bit is set, software
can set CR4.UINTR to 1 and can access the user-interrupt MSRs using RDMSR and WRMSR (see Section 9.3 and
Section 9.8.1).
> 处理器支持 通过CPUID.(EAX=7,ECX=0):EDX[5] 枚举对user interrupts的支持。如果该位设置了, 润见可以设置
> CR4.UINTR为1, 并且可以使用RDMSR，WRMSR 访问 user-interrupt MSR（可见Section 9.3 和Section 9.8.1)

The user-interrupt feature is XSAVE-managed (see Section 9.8.2). This implies that aspects of the feature are
enumerated as part of enumeration of the XSAVE feature set. See Section 9.8.2.2 for details.
> user-interrupt feature  是 XSAVE-managed(见 Section 9.8.2)。它意味着该功能一些（各个）方面作为
> XSAVE feature set 的枚举一部分被枚举

## 9.3 USER-INTERRUPT STATE AND USER-INTERRUPT MSRS
The user-interrupt architecture defines the following new state. Some of this state can be accessed via the RDMSR
> user interrupt architecture 定义了下面的new state。这些state中的一部分可以通过RDMSR访问

### 9.3.1 User-Interrupt State
The following are the elements of the new state (enumerated here independent of how they are accessed):
> 下面是new state的 元素(此处列举的内容与访问方式无关)

* UIRR: user-interrupt request register.<br/>
This value includes one bit for each of the 64 user-interrupt vectors. If UIRR[i] = 1, a user interrupt with
vector i is requesting service. The notation UIRRV is used to refer to the position of the most significant bit
set in UIRR; if UIRR = 0, UIRRV = 0.
> 该值包含了每一个64 user-interrupt vector的one bit。如果UIRR[i] = 1, 带有vector i 的 user interrupt
> 是正在请求的service。符号`UIRRV`用于表明 UIRR中的最高位的位置; 如果`UIRR` = 0,`UIRRV`=0
* UIF: user-interrupt flag.<br/>
If UIF = 0, user-interrupt delivery is blocked; if UIF = 1, user interrupts may be delivered. User-interrupt
delivery clears UIF, and the new UIRET instruction sets it. Section 9.6 defines other new instructions for
accessing UIF.
> 如果UIF = 0, user-interrupt delivery 将被 blocked; 如果UIF=1, user interrupt 可能会被 delivered。User-interrupt
> delivery 会清空 UIF, 并且new UIRET 指令会设置该位。Section 9.6 定义了新的指令用于访问UIF

* UIHANDLER: user-interrupt handler.<br/>
This is the linear address of the user-interrupt handler. User-interrupt delivery loads this address into RIP.
> 这时一个 user interrupt handler 的线性地址。 user-interrupt delivery会将该地值 load到 RIP
* UISTACKADJUST: user-interrupt stack adjustment.<br/>
This value controls adjustment to the stack pointer (RSP) prior to user-interrupt delivery. It can account for
an OS ABI’s “red zone” or be configured to load RSP with an alternate stack pointer.<br/>
The value UISTACKADJUST must be canonical. If bit 0 is 1, user-interrupt delivery loads RSP with UISTACK-
ADJUST; otherwise, it subtracts UISTACKADJUST from RSP. Either way, user-interrupt delivery then aligns
RSP to a 16-byte boundary. See Section 9.4.2 for details.
> 
* UINV: user-interrupt notification vector.<br/>
This is the vector of those ordinary interrupts that are treated as user-interrupt notifications (Section 9.5.1).
When the logical processor receives user-interrupt notification, it processes the user interrupts in the user
posted-interrupt descriptor (UPID) referenced by UPIDADDR (see below and Section 9.5.2).
* UPIDADDR: user posted-interrupt descriptor address.<br/>
This is the linear address of the UPID that the logical processor consults upon receiving an ordinary interrupt
with vector UINV.
* UITTADDR: user-interrupt target table address.<br/>
This is the linear address of user-interrupt target table (UITT), which the logical processor consults when
software invokes the SENDUIPI instruction (see Section 9.7).
* UITTSZ: user-interrupt target table size.<br/>
This value is the highest index of a valid entry in the UITT (see Section 9.7).
