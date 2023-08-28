# pause in  VMX non-root operation
## 9.10.2 PAUSE Instruction
The PAUSE instruction can improves the performance of processors 
supporting Intel Hyper-Threading Technology when executing “spin-wait
loops” and other routines where one thread is accessing a shared lock 
or semaphore in a tight polling loop. When executing a spin-wait loop, 
the processor can suffer a severe performance penalty when exiting the 
loop because it detects a possible memory order violation and flushes 
the core processor’s pipeline. The PAUSE instruction provides a hint 
to the processor that the code sequence is a spin-wait loop. The processor 
uses this hint to avoid the memory order violation and prevent the pipeline 
flush. In addition, the PAUSE instruction depipelines the spin-wait loop 
to prevent it from consuming execution resources excessively and consume power
needlessly. (See Section 9.10.6.1, “Use the PAUSE Instruction in Spin-Wait 
Loops,” for more information about using the PAUSE instruction with IA-32 
processors supporting Intel Hyper-Threading Technology.)

> `PAUSE`指令可以提升支持 Intel Hyper-Threading Technology技术的处理器的性能, 
> 当该处理器执行 "spin-wait loops" 或者其他的routines(例如线程在一个紧密的 polling loop中
> 访问shared lock 或者 semaphore。当执行 spin-wait loop时，处理器会遇到一个严重的性能损失
> 当退出该loop时，以为他发现有一个可能的memory order violation 并且 flush core processor's
> pipeline. `PAUSE`使用hint来避免 memory order violation 从而阻止 pipeline flush。
>
> 另外, PAUSE指令 depipelines spin-wait loop 来防止过度消耗 execution resources 和不必要的消耗
> power.

## 9.10.6.1 Use the PAUSE Instruction in Spin-Wait Loops
Intel recommends that a PAUSE instruction be placed in all spin-wait 
loops that run on Intel processors supporting Intel Hyper-Threading 
Technology and multi-core processors. Software routines that use 
spin-wait loops include multiprocessor synchronization primitives 
(spin-locks, semaphores, and mutex variables) and idle loops. Such 
routines keep the processor core busy executing a load-compare-branch 
loop while a thread waits for a resource to become available. Including
a PAUSE instruction in such a loop greatly improves efficiency (see 
Section 9.10.2, “PAUSE Instruction”). The following routine gives an 
example of a spin-wait loop that uses a PAUSE instruction: 

> Intel 建议在支持 Intel 超线程技术和 multi-core 的处理器上运行的
> 所有 spin-wait loops 都放置上 PAUSE 指令。 使用 spin-wait loops的
> 软件例子包括多处理器同步原语(spinlock, 信号量，互斥变量)和 idle loops。
> 这些routine让处理器一直忙于 执行 load-compare-brach 循环当线程正在等一个
> resources 变为可获取的状态. 在这样的循环中包含一个 PAUSE指令可以很大程度上
> 提升效率。下面的routine 给出了一个使用 PAUSE指令的 spin-wait loop 的例子

```
Spin_Lock:
    CMP lockvar, 0      ;Check if lock is free
    JE Get_Lock
    PAUSE               ;Short delay
    JMP Spin_Lock
Get_Lock:
    MOV EAX, 1
    XCHG EAX, lockvar   ;Try to get lock
    CMP EAX, 0          ;Test if successful
    JNE Spin_Lock
Critical_Section:
    <critical section code>
    MOV lockvar, 0
    ...
Continue:
```
The spin-wait loop above uses a “test, test-and-set” technique for determining the
availability of the synchronization variable. This technique is recommended when
writing spin-wait loops. In IA-32 processor generations earlier than the Pentium 4
processor, the PAUSE instruction is treated as a NOP instruction.

> 上面的spin-wait loop 使用"test,test-and-set"技术来确定同步变量的可用性。
> 在编写spin-wait loops 时，建议使用此技术。在早于奔腾4处理器的IA-32处理
> 器中，PAUSE指令被视为NOP指令。

