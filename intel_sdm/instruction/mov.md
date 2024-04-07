# MOV

## descritpion

### MOV to SS

Loading the SS register with a MOV instruction suppresses or inhibits some
debug exceptions and inhibits interrupts on the following instruction
boundary. (The inhibition ends after delivery of an exception or the execution
of the next instruction.) This behavior allows a stack pointer to be loaded
into the ESP register with the next instruction (MOV ESP, stack-pointer
value) before an event can be delivered. See Section 6.8.3, “Masking Exceptions
and Interrupts When Switching Stacks,” in Intel® 64 and IA-32 Architectures
Software Developer’s Manual, Volume 3A. Intel recommends that software use the
LSS instruction to load the SS register and ESP together.

> 通过 MOV instruction Load SS register 会在其后的 instruction boundary suppresses 
> 或 inhibits 某些 debug exception 和 interrupt. (在delivery 一个 exepction或者执行下一条
> instruction之后结束 该inhibition). 该行为允许 在 event 被 deliver之前 在下一条指令中将
> (MOV ESP, stack-pointer value) stack pointer load 到 ESP register 请看intel sdm 6.8.3
> “Masking Exceptions and Interrupts When Switching Stacks". Intel 建议 软件使用 LSS 
> 指令来一起 load SS register 和 ESP.
