# 6.8 ENABLING AND DISABLING INTERRUPTS
## 6.8.3 Masking Exceptions and Interrupts When Switching Stacks

To switch to a different stack segment, software often uses a pair of
instructions, for example:

> 为了 switch 到 不同的stack segment, software 通常使用 一对 instructions,
> 例如:

```
MOV SS, AX
MOV ESP, StackTop
```

(Software might also use the POP instruction to load SS and ESP.)

> (软件可能也使用 POP instruction 来 load SS 和 ESP.)

If an interrupt or exception occurs after the new SS segment descriptor has
been loaded but before the ESP register has been loaded, these two parts of the
logical address into the stack space are inconsistent for the duration of the
interrupt or exception handler (assuming that delivery of the interrupt or
exception does not itself load a new stack pointer).

> duration: 持续时间;期间
>
> 如果 interrupt 或者 exception 在 新的 SS segment descriptor 已经被loaded 之后,
> 在 ESP 被 loaded之前发生, 该逻辑地址的这两部分将在interrupt/exception 执行期间
> inconsistent. (假设 interrupt/exception delivery 不会load一个新的 stack pointer)

To account for this situation, the processor prevents certain events from being
delivered after execution of a MOV to SS instruction or a POP to SS
instruction. The following items provide details:

> 考虑到这种情况, 处理器在 MOV to SS 指令或者 POP to SS 指令执行后, 组织某些事件
> 的delivery. 下面的条目提供详细信息:

* Any instruction breakpoint on the next instruction is suppressed (as if
  EFLAGS.RF were 1).
  > 在下一条指令上的任何instruction上的breakpoint 将会被 suppressed(就好像 EFLAGS.RF
  > 是1的情况)
* Any single-step trap that would be delivered following the MOV to SS
  instruction or POP to SS instruction (because EFLAGS.TF is 1) is suppressed.
  > 在 MOV to SS 或者 POP to SS 指令后的 delivery 任何 single-step trap 都被 
  > supressed.
* The suppression and inhibition ends after delivery of an exception or the
  execution of the next instruction.
  > 在 exception delivery 或者下一个指令执行之后, 结束suppression 和 inhibition
* Any data breakpoint on the MOV to SS instruction or POP to SS instruction is
  inhibited until the instruction boundary following the next instruction.
  > 直到下一个指令的 instruction boundary, MOV to SS 或者 POP to SS 上的 data 
  > breakpoint 才不会被 inhibited.
* If a sequence of consecutive instructions each loads the SS register (using
  MOV or POP), only the first is guaranteed to inhibit or suppress events in
  this way.
  > 如果一系列连续指令中的每一个都 load SS register (使用 MOV 或者 POP), 只有第一个
  > 指令能保证以这种方式 inhibit 或者 suppress event.

Intel recommends that software use the LSS instruction to load the SS register
and ESP together. The problem identified earlier does not apply to LSS, and the
LSS instruction does not inhibit events as detailed above.

> Intel 建议软件使用 LSS 指令来 一起 load SS  和 ESP. 前面提到的问题不适用于LSS,
> 而且LSS指令也不 inhibit 如上所述的event.
