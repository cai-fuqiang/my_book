# 1
```
Those results are probably realistic. But your inline asm is very unsafe, 
e.g. modifying a register you declared as a "r" read-only input, not a 
"+r" output/input operand. And your asm modifies memory you haven't told 
the compiler about (*global_lock, when you've only told it the pointer 
value is an input operand: How can I indicate that the memory *pointed*
to by an inline ASM argument may be used?). 


这些结果可能是现实的。但是你的内联 asm是非常不安全的，
例如，modify 描述为 "r" 的 只读输入的寄存器，而不是
"+r"的输出/输入操作数。你的asm对memory 的修改不会告诉 compiler(关于
*global_lock,当您只告诉它指针的值是输入操作数： 
[How can I indicate that the memory *pointed* to by an inline ASM argument may be used?]
(https://stackoverflow.com/q/56432259) )
```

# 2
```
Either use "+m"(*global_lock) to let the compiler pick an addressing mode,
or add a "memory" clobber and make your asm volatile (which needs to be 
explicit when you have at least one output operand). Also, int locked_val 
doesn't need to be an input; it looks like it could just be a dummy output 
operand to let the compiler pick a spare register. 

You already mov $1, %[locked_val] instead of reading the int locked_val = 1; 
initialized value you asked the compiler for.

要么使用"+m"（*global_lock）让编译器选择寻址模式，
或者添加一个"memory" clobber，使你的asm volatile（当您至少有一个输出操作数时，
它需要显式）。此外，int locked_val 不需要作为输入；看起来可能只是一个伪输出
操作数，让编译器选择一个备用寄存器。

您已经移动了$1，%[locked_val]，而不是读取int locked_val=1；
您向编译器请求的初始化值。
```

# 3
```
Anyway, I'm not surprised there are still memory-ordering machine clears; 
your get_lock starts out with a read-only access to the lock and branches 
on it, instead of starting with an xchg attempt. So there's a non-locked 
access before any pause. That might perhaps be good in some cases like very 
high contention (something real use-cases would want to avoid), but has other 
downsides, too, like first making a MESI share request, and then having to 
do a MESI RFO (Read For Ownership) before it can write the line. If the first
access was xchg, the uncontended case would only do an RFO.

不管怎样，我一点也不惊讶还有memory-ordering machine clears；
getlock从对锁的只读访问锁开始 并且 branches on it (???)，而不是从xchg尝试开始。
因此，在任何pause之前都有一个non-locked access。

在某些情况下，这可能是好的，比如非常高的争用（这是真实用例想要避免的），
但也有其他缺点，比如首先发出MESI共享请求，然后必须执行MESI RFO（Read For Ownership）
才能写入行。如果第一次访问是xchg，那么 uncontended case 将只执行RFO。
```

# 4
```
See my example code in Locks around memory manipulation via inline assembly (NASM syntax, 
despite the question asking for inline asm. You might want to make your asm code into 
functions that take a pointer arg, to avoid the challenges of inline asm.) (Does Intel 
really recommend this code, starting with a read-only access and unlocking with xchg? 
Unlock only needs to be mov to get memory_order_release; it doesn't need to be an atomic 
RMW because this thread owns the lock; we know the current value is 1 and that we're setting 
it to 0.) 

请参阅我在`Locks around memory manipulation via inline assembly`的示例代码，尽管 the question asking for asm ???。
您可能希望将asm代码转换为使用指针arg的函数，以避免内联asm的挑战。)（英特尔真的建议使用这段代码吗，
从只读访问开始，用xchg解锁？解锁只需要是mov就可以获得memory_order_release；它不需要是原子RMW，
因为这个线程拥有锁；我们知道当前值是1，我们将其设置为0。）
```

# 5
```
Also re: explaining your data: it's expected that the number of machine clears per instruction 
will be different with vs. without pause, since many spin iterations can happen without a pause 
before the load finally arrives and a memory-ordering violation is detected. (And yes, that 
perf event counts pipeline nukes due to memory-ordering mis-speculation.) The remaining machine-clears 
in the version with pause might be mostly from the initial read on the first attempt to take 
the lock; I'd be curious to see how it goes starting with an xchg attempt, with pure-load 
only after pause.

另外：解释您的数据：预计每个指令的机器清除次数在有暂停和没有暂停的情况下会有所不同，
因为在负载最终到达并检测到内存顺序违规之前，许多spin iterations 可能会在没有pause的条件下发生。
（是的，由于内存排序错误推测，该perf事件 计数由 memory-ordering mis-speculation 带来的 
pipeline nukes）版本中剩余的机器在暂停的情况
下清除可能主要来自第一次尝试获取锁时的初始读取；我很想看看它是如何从xchg尝试开始的，
只有在 pause 后才有pure-load
```

# 6
```
On the other hand, the total execution time of programs using the pause instruction is NOT LESS 
than that of programs using the nop instruction. - your program doesn't do anything except spin-wait 
and contend for locks. Part of the idea of Skylake's change to pause (making it block 100 cycles 
instead of 5) is to let the other hyperthread get more useful work done while we're waiting for a 
lock, even if that slightly delays us from noticing the lock is available. But here there is no useful 
work; all threads spend most of their time spin-waiting. This is not the case Intel optimized for. 

另一方面，使用pause指令的程序的总执行时间不少于使用nop指令的程序。
- 您的程序除了旋转等待和争锁之外什么都不做。Skylake对 pause的改动（使其阻塞100个周期而不是5个周期）
的部分想法是让其他超线程在我们等待锁定时完成更有用的工作，即使这会稍微延迟我们注意到锁定可用。
但这里没有有用的工作；所有线程的大部分时间都在等待旋转。英特尔针对以下情况进行了优化。
```
