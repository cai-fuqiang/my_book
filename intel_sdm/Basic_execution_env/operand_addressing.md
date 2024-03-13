# 3.7 OPERAND ADDRESSING
## 3.7.3 Memory Operands

Source and destination operands in memory are referenced by means of a segment
selector and an offset (see Figure 3-9). Segment selectors specify the segment
containing the operand. Offsets specify the linear or effective address of the
operand. Offsets can be 32 bits (represented by the notation m16:32) or 16 bits
(represented by the notation m16:16).

> ```
> means of: ...手段;...方式
> notation: 符号;记号; 谱号
> ```
>
> 内存中的源和目的操作数以[segment selector, offset]的方式被引用.(请看 Figure 3-9).
> Segment select 指定了包含操作数的段. offset指定了操作数的 线性/有效地址. offset
> 可以为32 bits(以 m16:32 这样的符号展示) 或者 16 bits (m16:16)

![memory_operand_address](pic/3-9_memory_operand_address.png)

