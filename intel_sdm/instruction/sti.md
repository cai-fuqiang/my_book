# STI
## description

In most cases, STI sets the interrupt flag (IF) in the EFLAGS register. This
allows the processor to respond to maskable hardware interrupts.

> 在大多数情况下, STI 会设置 EFLAGS register 中的 interrupt flag (IF). 其允许
> 处理器可以回应 maskable hardware interrupt.

If IF = 0, maskable hardware interrupts remain inhibited on the instruction
boundary following an execution of STI. (The delayed effect of this instruction
is provided to allow interrupts to be enabled just before returning from a
procedure or subroutine. For instance, if an STI instruction is followed by an
RET instruction, the RET instruction is allowed to execute before external
interrupts are recognized. No interrupts can be recognized if an execution of
CLI immediately follow such an execution of STI.) The inhibition ends after
delivery of another event (e.g., exception) or the execution of the next
instruction.

> 如果 IF = 0, maskable hardware interrupt 仍然会 inhibited STI 执行后的 instruction
> boundary. 提供该指令的延迟效果是为了允许从 procedure 和 subroutine 返回之前启用中断.
> 举个例子, 如果 STI 后面跟着 RET 指令, 则允许 RET 指令在识别外部中断之前执行.
> 如果CLI指令紧跟着STI的执行, 则无法识别中断). 该 inhibition 在 delivery 另一个event
> (e.g., exception) 或者执行下一条指令后结束.

The IF flag and the STI and CLI instructions do not prohibit the generation of
exceptions and nonmaskable interrupts (NMIs). However, NMIs (and
system-management interrupts) may be inhibited on the instruction boundary
following an execution of STI that begins with IF = 0.

> IF flag 和 STI 和 CLI 指令不会 prohibit excpetion 和 NMI的产生. 但是 NMI(SMI)
> 可能会在IF = 0 情况下执行STI后的 instruction boundary 被 inhibited
