# 25.4.2 Guest Non-Register State

## Interruptibility state (32 bits). 

The IA-32 architecture includes features that permit certain events to be
blocked for a period of time. This field contains information about such
blocking. Details and the format of this field are given in Table 25-3.

> IA-32 architecture 包含了允许某些event 可以被block一些时间的 feature. 该字段
> 包含了这些 blocking的信息. 关于该字段格式和细节在 Table 25-3 中给出

----Table-25-3-----

###  Blocking by STI

See the “STI—Set Interrupt Flag” section in Chapter 4 of the Intel® 64 and
IA-32 Architectures Software Developer’s Manual, Volume 2B.

> 请查看 Intel sdm 中, Chapter 4 "STI-Set Interrupt Flag" section.

Execution of STI with RFLAGS.IF = 0 blocks maskable interrupts on the
instruction boundary following its execution.1 Setting this bit indicates that
this blocking is in effect.

> 在 RFLAGS.IF = 0 的情况下执行 STI 可能会在紧接该指令执行的instruction boundary
> blocks maskable interrupt. 设置该 bit 意味着 该blocking 正在生效.

### Blocking by MOV SS

See Section 6.8.3, “Masking Exceptions and Interrupts When Switching Stacks,”
in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume
3A.

> 请看intel sdm 中 Section 6.8.3 "Masking Exceptions and Interrupts When 
> Switching Stacks"

Execution of a MOV to SS or a POP to SS blocks or suppresses certain debug
exceptions as well as interrupts (maskable and nonmaskable) on the instruction
boundary following its execution. Setting this bit indicates that this blocking
is in effect.2 This document uses the term “blocking by MOV SS,” but it applies
equally to POP SS.

> 执行 MOV to SS 和 POP to SS 会在该指令执行后的instruct boundary block/suppresses 
> 某些 exceptions和 interrupts (maskable and nonmaskable). 设置该 bit 意味着该blocking
> 正在生效. 该doc 使用 术语 "blocking by MOV SS" 同样适用于 "POP SS"

### Blocking by SMI

See Section 32.2, “System Management Interrupt (SMI).” System-management
interrupts (SMIs) are disabled while the processor is in system-management mode
(SMM). Setting this bit indicates that blocking of SMIs is in effect.

> 先略

### Blocking by NMI

See Section 6.7.1, “Handling Multiple NMIs,” in the Intel® 64 and IA-32
Architectures Software Developer’s Manual, Volume 3A and Section 32.8, “NMI
Handling While in SMM.”

> 请查看 intel sdm Section 6.7.1 "Handling Multiple NMIs." 和 "NMI Handling
> While in SMM"章节.

Delivery of a non-maskable interrupt (NMI) or a system-management interrupt
(SMI) blocks subsequent NMIs until the next execution of IRET. See Section 26.3
for how this behavior of IRET may change in VMX non-root operation. Setting
this bit indicates that blocking of NMIs is in effect. Clearing this bit does
not imply that NMIs are not (temporarily) blocked for other reasons.

> NMI 或者 SNMI 的 delivery  会block 随后的 NMIs 直到下个IRET的执行. 请查看章节
> 26.3 了解 IRET 在 VMX non-root operation 下行为是如何改变的. 设置该bit 指示着
> blocking of NMIs 在生效. 清除该位并不意味这 NMI 不会(暂时) 因为其他原因阻塞.

If the “virtual NMIs” VM-execution control (see Section 25.6.1) is 1, this bit
does not control the blocking of NMIs. Instead, it refers to “virtual-NMI
blocking” (the fact that guest software is not ready for an NMI).

> 如果 "virtual NMIs" VM-execution control (请查看 Section 25.6.1) 是1, 该bit
> 并不 control blocking of NMIs. 而相应的, 他指的是 "virtual-NMI blocking" 
> (实际上是 guest software 并没有为 NMI 做好准备)
