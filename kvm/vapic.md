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
那么`virtual APIC address`也是一个HPA, 那么这两个页之间有什么联系么，实际上，
我觉得没有关系，硬件可能处理是这样，在VMX non-root operation下，访问一个
APIC page中的address, 这个address 是GVA, 此时, CPU也不知道该地址是不是APIC
page 中的地址，需要通过MMU将其转换成HPA，拿到HPA之后，再将该HPA和`APIC-access 
address`比较，如果相等，那么就认为该地址是VAPIC page的地址，在执行些emulation
的操作，例如往VAPIC page某个偏移访问，注意，这个时候CPU访问的是`virtual apic
page`, 而不是`APIC access page`。<br/>
那我们来看下，为什么`APIC-access address`不能是一个GVA/GPA
	+ GVA: 因为GVA是guest 做的内存映射, kvm侧拿不到
	+ GPA: 因为GPA的获取也是通过mmu 通过将GVA->GPA, 获得，而如果映射建立
	完整的话，GVA->HPA, 而不完整的话，则会抛一个异常，这个异常不知道是
	mmu的处理逻辑抛，还是CPU抛，如果是mmu抛的话，就必须使用HPA了，如果是
	CPU抛，可能会涉及一些多增加的CPU的处理逻辑的调整，也不合适。(my own 
	opinion)
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

