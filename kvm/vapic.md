# vapic
## intruduction
在没有引入virtual apic之前，如果想将一个中断注入到guest，
只能通过`Event injection`(事件注入) 的方式注入中断(详见
intel sdm 26.6)

该方式有一些缺点:
* 一次只能注入一个中断
* 并且注入的时间点，只发生在vm entry, 所以受interrupt window
的影响，可能会导致软件注入中断不成功，需要软件特殊处理。

那么我们来看, 上面的两个缺点，kvm(software)这边是如何处理的: 
* 一次只能注入一个中断:<br/>
当如果本次vm entry 发现有多个中断需要注入时，设置VMCS中的`primary 
processor-based VM-execution controls`中的`interrupt-window exit`
字段。因为在注入中断过程中会将`interrupt-windows`关闭(实际上
也就是将IF=0)，所以等guest software 将interrupt-windows开启时，
就使其产生vm-exit, 然后在下次的vm entry中在将下一个中断注入。

* 受interrupt-window 影响<br/>
如果本次vm entry发现`interrupt-windows`关闭(主要有guest的
IF=0，或者VMCS中`Guest-state Aare`中`Interruptibility 
state`中的某些位为1(详见intel  sdm 24.4.2 Guest 
Non-Register state), 那么在本次vm-entry 就不注入中断，
然后把`interrupt-window exit`字段置1，让guest在interrupt
window开启的时候产生vm exit, 然后在下次vm entry 时注入
中断。

所以我们来看上面的影响，处理上面两种情况时，会产生多次的vm 
exit。另外还有guest software 对于apic register的访问，这里面
有些寄存器可能访问的比较频繁，例如TPR，所以为了减少vm exit,
intel 引入了 `APIC Virtualization 和 virtual interrupt`。

引入上述功能后，可以在一次vm-entry中注入多个中断，并且
无需关心interrupt window, 并且，还可以使用posted-interrupt
在 VMX non-root operation 下，通过修改PID(posted-interrupt 
descriptor)和向其发送一个特殊的中断NV(notification vector),
注入中断。

我们来看下上述功能的实现


## vapic实现
apic 虚拟化，最底层的是要虚拟化apic 的这些寄存器，而intel 这边的实现
是在将这些寄存器虚拟化在内存中，读写某些寄存器硬件方面会有一些虚拟化
的动作, 如果是读的话，会从内存中某个偏移处获取到寄存器的值，如果是读的话，
可能还会有额外的emulation 的操作。

上面提到的这个page，被称为`virtual-APIC page`, 该page 是一个4-KByte的内存区域，
该page的物理地址，需要配置在VMCS中`virtual-APIC address`字段中。

对于guest software 可能会有以下的场景访问 APIC register:
* 直接访问
  * 如果是xapic，内存读写指令访问到APIC mapped page 的某些偏移地址
  * 如果是x2apic, 通过RDMSR, WRMSR 访问到和APIC相关的某些MSR的 encoding
* 非直接访问
  * 可能有一些其他的情况访问到了APIC mapped page , 例如page table walks. 
  详见(intel sdm 29.4.6 APIC Accesses Not Directly Resulting From Linear 
  Addresses)
  * 某些 access vapic regsiter 的emulate行为，或者是virtual interrupt process
  过程中会发生对该资源的访问
  * mov to CR8

> NOTE:
>
> 这里的访问有读写操作，读操作其实没有什么，主要是写操作，因为
> 写操作不仅要将欲写入的值同步到`virtual-APIC page`, 而且还可能会有一些
> virtualization的操作，请看后面的章节。

而上面也提到，VAPIC目前只对部分寄存器有virtualization的行为，寄存器列表如下:
* virtual task-priority register:VTPR
* virtual processor-priority rresigter:VPPR
* virtual end-of-interrupt register:VEOI
* virtual interrupt-serive register:VISR
* virtual interrupt-request register:VIRR
* virtual interrupt-command register:VICR_LO
* virtual interrupt-command register:VICR_HI

为支持vapic, 在VMCS中提供了一些控制字段，来控制一些virtualization的行为:
* Virtual-interrupt delivery: 使能该功能，使得VMX non-root operation下
 可以去delivery pending virtual interrupt, 并且还可以控制TPR virtualization
 的行为，我们下面会看到
* Use TPR shadow: CR8 virtualization中会提到
* Virtualize APIC access: 使能该功能，可以虚拟化`memory-mapped access`的行为，
这个地址是GUEST APIC MAP PAGE 通过EPT转换后的 phyiscal address, 是一个HPA, 
那么`virtual APIC address`也是一个HPA, 那么这两个页之间有什么联系么，在
下面的章节讲述下自己的看法。
* Virtualize x2APIC mode: 以MSR的方式访问vapic, 这个功能要好用些，一方面没有
	那么多的异常情况需要考虑，另一方面效率也高，因为不需要mmu介入。
* APIC-register virtualization: 
* Process posted interrupts

本章主要是将`memory-mapped APIC Access` 的虚拟化行为(MSR-based 和其差不多)。
在介绍`memory-mapped APIC access`之前, 我们先看非直接访问的`mov to CR8`操作，
这个操作比较特殊，它并没有去访问apic 的资源，而在64-bit mode下，对于该寄存
器的access, 实际上就是访问的APIC的TPR register, 对于host是这样，而对于
guest，它实际上需要访问vapic的VTPR, 我们来看下guest 是怎么控制的。
## CR8 virtualization
在VMCS的`primary processor-based vm-execution controls`提供了3个字段，用于
CR8 virtualization:
* **CR8-load exiting**: Mov to CR8 cause VM exits
* **CR8-store exiting**: Mov from CR8 cause VM exits
* **use TPR shadow**: 开启该选项使得 CR8-load/store 行为 实际上是去
access VTPR

我们来看，当使能了`use TPR shadow` 后，VMX non-root  operation下访问CR8, 
实际上是访问的 VTPR, 据说早期的vapic的实现很有限, 
[仅仅是控制eCR8的访问](https://zhuanlan.zhihu.com/p/267815728)。

接下来我们来看下`Virtualization memory-mapped APIC Access`

## Virtualization memory-mapped APIC Access
在xapic 模式中，软件对于local APIC寄存器，可以使用内存映射的方式进行访问。
详细来说，可以通过使用翻译为IA32_APIC_BASE MSR指示的物理地址的线性地址进行访问。
在没有引入vapic之前，对于该内存区域的访问通常会造成vm-exit。这个VM-EXIT的行为是由
VMM去控制的，在vm exit后，可以对该访问进行 emulate，可以使用paging或者EPT达到这
个目的。当intel 支持了vapic后，可以通过设置`virtual APIC access` vm-execution
control 改变这一行为。

当`virtual APIC access`控制字段为1 后，处理器相会对翻译地址落在4-KByte
`APIC-access page`的线性地址的访问特殊对待。(关于`APIC-access page`, 是一个
VMCS中的字段，详见24.6.8)。

通常来说，访问`APIC-access page` 会导致`APIC-access VM exit`。这个vm exit
提供给VMM一些VM exit的原因。而当设置了某些`VM-execution controls`时，
处理器会虚拟化某些对于APIC-access page 的访问，并且不产生VM exit。
这些virtualization 将会对`virtual-APIC page`进行访问而代替对`APIC-access page`
的访问。

> NOTE
>
> 上面提到过，`APIC-access address`和`virtual-APIC address`都对应的是HPA，
> 为什么要设置两个地址呢，他们之间有没有什么关系呢?
>
> 我觉得没有关系，硬件可能处理是这样，在VMX non-root operation下，访问一个
> APIC page中的address, 这个address 是GVA, 此时, CPU也不知道该地址是不是APIC
> page 中的地址，需要通过MMU将其转换成HPA，拿到HPA之后，再将该HPA和`APIC-access 
> address`比较，如果相等，那么就认为该地址是VAPIC page的地址，在执行些emulation
> 的操作，例如往VAPIC page某个偏移访问，注意，这个时候CPU访问的是`virtual apic
> page`, 而不是`APIC access page`。<br/>
> 那我们来看下，为什么`APIC-access address`不能是一个GVA/GPA
> 	+ GVA: 因为GVA是guest 做的内存映射, kvm侧拿不到
> 	+ GPA: 因为GPA的获取也是通过mmu 通过将GVA->GPA, 获得，而如果映射建立
> 	完整的话，GVA->HPA, 而不完整的话，则会抛一个异常，这个异常不知道是
> 	mmu的处理逻辑抛，还是CPU抛，如果是mmu抛的话，就必须使用HPA了，如果是
> 	CPU抛，可能会涉及一些多增加的CPU的处理逻辑的调整，也不合适。
> 	因为手册29.4.1 讲述了`priority of APIC-Access VM Exits`, 里面讲述到
> 	由于内存访问导致的`APIC-access VM exit`比page fault 或者EPT violation
> 	要低，从这点是不是可以猜测, 该异常可能是mmu抛呢?(自己的猜想)

对于`APIC-access page`的访问主要有read/write两种访问。

我们先来看下读访问的虚拟化行为。

### Virtualizing Read from the APIC-Access Page
对于写操作来说呢，读操作还是比较简单，因为没有复杂的virtualizing操作，当对`APIC-access`
进行读操作时，只需要判断是否满足`virtualize`的条件，如果满足的话，则从`virtual
APIC page`的某个偏移处读取内存值即可。

本章节主要来看下，哪些`virtual APIC register`在什么条件下可以被`virtualize`。

如果下面的任意条件为true的情况下，访问`APIC-access page`将会产生`APIC-access VM exit`
* `use TPR shadow` VM execution control 为0
* 该访问通过预取指令访问
* 该访问访问的地址宽度大于32 bits
* The access is part of an operation for which the processor has already 
virtualized a write to the APIC-access page.(没看懂)
* The access is not entirely contained within the low 4 bytes of a naturally
aligned 16-byte region. That is, bits 3:2 of the access’s address are 0, and 
the same is true of the address of the highest byte accessed.
<br/>
因为apic page中的寄存器是按照16-byte 对齐，但是这些寄存器都是32bits的。
所以在VMX root operation 下,  访问这些寄存器的4byte~15byte 将会导致undefine 
behavior, 而这里就是在解释这种情况。在VMX non-root operation 下，则会导致
`APIC-access VM exit`。

上面这几条比较关键的是`use TPR shadow`，该功能是可以将对VMX non-root operation
下对CR8的访问，virtualize为对 virtual apic page 中VTPR的访问，该功能是intel 对
vapic最早的功能支持，该功能不需要其他的 VM execution control 的开启，就可以
支持该功能。请看下面：

如果上面的选项是真，一个读操作是否被虚拟化，依赖于`APIC-register virtualization`
VM-execition control 的设置:
* 如果`APIC-register virtualization`和`virtual-interrupt delivery` VM-execution
  control均为0，除了对page offset 080H(VTPR) 的读访问可以被virtualized; 其他
  情况均造成一个 `APIC-access VM exit`
* 如果`APIC-register virtualization`VM-execution control 为0,而`virtual-interrupt 
  delivery` VM-execution control 为1, 对下面的page offset 的读访问可以被
  virtualized, 否则将会产生`APIC-acceess VM exit`
	+ 080H(VTPR)
	+ 0B0H(VEOI)
	+ 300H(VICR_LO)
* 如果`APIC-register virtualization`为1, 对于下面范围的读访问将会被virtualized:
	+ 020H–023H (local APIC ID);
	+ 030H–033H (local APIC version);
	+ 080H–083H (task priority);
	+ 0B0H–0B3H (end of interrupt);
	+ 0D0H–0D3H (logical destination);
	+ 0E0H–0E3H (destination format);
	+ 0F0H–0F3H (spurious-interrupt vector);
	+ 100H–103H, 110H–113H, 120H–123H, 130H–133H, 140H–143H, 150H–153H, 160H–163H, or 170H–
		173H (in-service);
	+ 180H–183H, 190H–193H, 1A0H–1A3H, 1B0H–1B3H, 1C0H–1C3H, 1D0H–1D3H, 1E0H–1E3H, or 1F0H–
		1F3H (trigger mode);
	+ 200H–203H, 210H–213H, 220H–223H, 230H–233H, 240H–243H, 250H–253H, 260H–263H, or 270H–
		273H (interrupt request);
	+ 280H–283H (error status);
	+ 300H–303H or 310H–313H (interrupt command);
	+ 320H–323H, 330H–333H, 340H–343H, 350H–353H, 360H–363H, or 370H–373H (LVT entries);
	+ 380H–383H (initial count); or
	+ 3E0H–3E3H (divide configuration).
	除了上面的情况，其他的访问都会造成`APIC-access VM exit`

而对于上面描述的virtualize行为，实际上就是从`virtual-APIC page`相应的偏移处，读取其相应的值。

上面说完了对`APIC-access page` 读操作的虚拟化，下面说下写操作

### Virtualizing Write to the APIC-Access Page
不同于读操作，写操作实际上会造成一些影响，例如，在VMX root operation下，写ICR寄存器，
可能会导致发送IPI中断，所以写操作的虚拟化行为要复杂一些，不仅要在`virtual
APIC page`相应的偏移处写入值，而且还有一些针对性的emulation
操作。而在某些情况下，则会出现，在`virtual APIC page`相应的位置写入值后，还是要
产生VM exit。

并不是对`APIC-access page` 的所有位置的写操作都需要被virtualized, 而且还受 
VM-execution  control 某些字段的限制，我们先来看下哪些情况会被virtualized。

#### Determining Whether a Write Access is Virtualized
下面任意情况为true将导致 `APIC-access VM exit`:
* `use TPR shadow` VM-execution control 为0
* 该访问地址宽度超过32 bits
* The access is part of an operation for which the processor 
  has already virtualized a write (with a different page offset
  or a different size) to the APIC-access page.(这个不懂)
* The access is not entirely contained within the low 4 bytes
  of a naturally aligned 16-byte region. That is, bits 3:2 of the
  access’s address are 0, and the same is true of the address of
  the highest byte accessed.(同读操作)

如果上述情况都不满足，写操作是否被virtualized依赖于`APIC-register
virtualization`和`virtual-interrupt delivery`VM-execution control
的设置:
* 如果`APIC-register virtualization` 和`virtual-interrupt delivery`都是
  0, 除了对080H偏移处(VTPR)的访问可以被virtualized, 其他的情况，都会
  造成`APIC-access VM exit`。
* 如果`APIC-register virtualization`为0, `virtual-interrupt delivery`
  VM-execution control为1, 对下面页内偏移的访问会被virtualized, 其他的
  情况，都会造成`APIC-access VM exit`
    + 080H(VTPR)
	+ 0B0H(VEOI)
	+ 300H(VICR_LO)
* 如果`APIC-register virtualization` VM-execution control为1，对于下面页内
  偏移的写访问均被virtualized.
	+ 020H–023H (local APIC ID);
	+ 080H–083H (task priority);
	+ 0B0H–0B3H (end of interrupt);
	+ 0D0H–0D3H (logical destination);
	+ 0E0H–0E3H (destination format);
	+ 0F0H–0F3H (spurious-interrupt vector);
	+ 280H–283H (error status);
	+ 300H–303H or 310H–313H (interrupt command);
	+ 320H–323H, 330H–333H, 340H–343H, 350H–353H, 
		360H–363H, or 370H–373H (LVT entries);
	+ 380H–383H (initial count); or
	+ 3E0H–3E3H (divide configuration).<br/>
	除上面的其他情况, 都会导致`APIC-access VM exit`

处理器在virtualize上面的写操作后，接下来可能会执行`APIC-write emulation`,
我们来看下。

#### APIC-Write Emulation
上面提到，如果是对某些page offset的写操作，在写入`virtual APIC page`后，
可能会有额外的emulate行为，细节如下:
* 080H (VTPR) : 处理器会清空VTPR的3:1 bytes, 并且执行`TPR virtualization`
* 0B0H (VEOI) : 如果`virtual-interrupt delivery` VM-execution control
 为1，处理器清空VEOI 然后执行`EOI virtualization`
* 300H(VICR_LO): 如果`virtual-interrupt delivery` VM-execution control
字段为1, 处理器检查`VICR_LO`的值，判断其值是否符合下面的条件:
	+ Reserved bits (31:20, 17:16, 13) and bit 12 (delivery status) are all 0.
	+ Bits 19:18 (destination shorthand) are 01B (self).
	+ Bit 15 (trigger mode) is 0 (edge).
	+ Bits 10:8 (delivery mode) are 000B (fixed).
	+ Bits 7:4 (the upper half of the vector) are not 0000B.
如果上述条件为真, 处理器则会使用`VICR_LO`中8-bits vector执行一个`self-IPI 
virtualization`。<br/>
如果`virtual interrupt delivery` VM-execution control 为0, 或者上述任意
条件不满足，处理器将会制造成`APIC-write VM exit`
* 如果其他的page offset. 处理器则会造成`APIC-write VM exit`。

> NOTE:
> 
> 关于这些处理和异常之前，这里有一个优先级的关系:
>
> 如果在 write access to the APIC-access page 后，在APIC-write 
> emulation 之前，出现了一个fault, 并且这个fault不会导致VM
> exit, APIC-write emulation 则在fault delivery 之后，在fault 
> handler 执行之前完成。如果上述fault 造成了VM exit, 则APIC-write
> emualation 不会执行。(这块不是很懂为什么要这么做)

刚才提到了`TPR virtualization`和`EOI virtualization`和`self-IPI virtualization`,
其实还有对其他的VAPIC register 的virtualization操作, `PPR virtualization`
只不过可能是由上面的操作引起的，我们来看下

## VAPIC register virtualization
### TPR virtualization
在下面几种情况下，可能会执行`TPR virtualization`:
* mov to CR8
* write APIC-access page 080H offset
* WRMSR ECX=808H

执行`TPR virtualization`的伪代码如下:
```
IF “virtual-interrupt delivery” is 0
	THEN
		IF VTPR[7:4] < TPR threshold (see Section 24.6.8)
		THEN cause VM exit due to TPR below threshold;
	FI;
ELSE
	perform PPR virtualization (see Section 29.1.3);
	evaluate pending virtual interrupts (see Section 29.2.1);
FI;
```

在`virtual-interrupt delivery` VM-execution control为0时, 会比对
`VTPR`和`TPR threshold`的值，如果`VTPR` 小于 `TPR threshold`的话，
则会造成VM exit。

关于`TPR threshold`的作用就如上所述，这个在软件层看来有什么
用呢, 这个可以协助减少中断延时。在没有支持`virtual-interrupt 
delivery` 之前，中断只能通过`event injection`的方式注入, 
假如说，当前的`TPR > MAX_IRR`的话，则表示该中断被TPR阻塞了，
本次的vm-entry不注入该中断, 但是guest os 可能会修改TPR导致上面
的条件满足，如果没有`TPR threshold`的话，可能得等某个事件
导致`VM exit`，中断延时比较高，如果软件层面把`TPR threshold`设置
为`MAX_IRR`的话，则避免了这个问题，在guest os 修改
`TPR < TPR threshold(MAX_IRR)`时, 则直接产生VM-exit。该字段和
`interrupt-window exit`产生的作用相似。

而在支持了`virtual-interrupt delivery`之后, 则没必要处理`TPR
threshold`逻辑了, 则会执行`PPR virtualization`, 并且去`evaluate
pending virtual interrupts`, 实际上是去pending virtual interrupt,
VMX non-root operation下的cpu会在合适的时机处理该pending的
vintr, 之后会讲到这个行为。

### PPR Virtualization
下面的行为可能会导致`PPR virtualization`:
* VM entry
* TPR virtualization
* EOI virtualization

伪代码如下:
```
IF VTPR[7:4] ≥ SVI[7:4]
	THEN VPPR := VTPR & FFH;
	ELSE VPPR := SVI & F0H;
FI
```

这里面涉及到了`SVI`, 该字段解释在intel sdm 24.4.2, 该字段实际上代表的是
当前vm 正在处理的中断。

我们会在下面章节讲到`SVI`

`PPR virtualization` 是由`TPR virtualization`, `EOI virtualization`和
`VM entry` 造成。

### 
