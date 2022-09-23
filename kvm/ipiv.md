# 目前处理 ipi 存在的一些问题
在当前架构下，当guest 需要向其他的vcpu发送ipi时，会
发生vm-exit(当发送self-IPI(guest write `VICR_LO`的`destination 
shorthand`为01B(self)))在合理配置下不会触发vm-exit,
而是会触发`self-IPI virtualization`(详见intel sdm 29.4.3.2
`APIC-Write Emulation`和29.1.5`self-IPI Virtualization`)。

而接收ipi的这一端可以通过posted-interrupt 的方式注入virtual 
interrupt (详见 intel sdm 29.6 posted-interrupt processing)。

所以我们设想一下，如果是在虚拟化write ICR_LO的行为中，能够去获取到
dest vcpu 的`PID` (posted interrupt descriptor), 然后去做一些对`PID`
的update，发送`NV` interrupt(notification vector)。这样就可以利用
现有的posted-interrupt processing 框架完成对vipi的发送和接收。

综上所述，这个过程只需要在发送ipi的这一端的write APIC ICR_LO 
emulation 的行为中做些改动，需要做哪些准备呢?
实际上就一个:

* **能够找到dest virtual APIC ID 和当前vcpu 的`PID`的对应关系**

那么我们接下来看一些实现细节。

# 实现细节
## VMCS 改动
### new VM-Execution Control
* **IPI virtualization**: tertiary porocessor-based VM-execution bit 4

### PID-Pointer Table
当`IPI virtualization`字段为1时， 处理器会使用该数据结构。PID-pointer table中的
每个entry 包含了一个PID的 64-bits的物理地址, 这些地址必须64-byte对齐,
其中:
* bit 0 : 表示valid bit
* bit 5:1: reserved，并且必须为0

一个`PID-Pointer table` 最多可以包含 `2 ^ 16 -1`个entry。处理器会利用`virtual
APIC ID`作为 index 去找到响应的 entry。

为支持该table 在VMCS中新增了 `VM-execution`控制字段，如下:
* **PID-pointer table address**: 逻辑处理器可能使用使用该table 去 virtualization
  IPIs。该字段 encoding 为 `2042H`(在64-bit mode为64 bits,在legacy mode中为low
  32 bit), `2043H`(high 32 bits)
* **Last PID-pointer index**: 该字段是16-bit 并且encoding 为 `8H`。该字段表示
  `PID-pointer table`中的last index。

上面的两个字段在不支持 1-setting `IPI virtualization`的情况下不存在

> NOTE:
>
> 所以我们来看，VMCS 中主要增加的信息字段，就是PID-Pointer Table,
> 该table就是一个map，用于将virtual APIC ID和 该vcpu 的`PID`关联起来

## VM ENTRIES
在`VM entry`过程中，会做一些字段的检查，此处略过。

## VMX NON-ROOT OPERATION
IPIV的实现依赖`APIC virtualization`的功能，也可以说是对`APIC virtualization`功能
的补充。为支持ipiv, cpu对于emulation APIC register LCR的某些写操作，会更改原
有的处理逻辑。而guest software 导致上述过程可能如下:

* write VLCR
	* write APIC-access page : offset 300H
	* WRMSR : ECX = 830
* SENDUIPI指令: 该指令的某些流程会导致发送ipi, 而这个动作也可以被virtualization
	后面结合`user interrupt` new feature, 我们再看下


