* UISTACKADJUST: user-interrupt stack adjustment.<br/>
This value controls adjustment to the stack pointer (RSP) prior to user-interrupt delivery. It can account for
an OS ABI’s “red zone” or be configured to load RSP with an alternate stack pointer.<br/>
The value UISTACKADJUST must be canonical. If bit 0 is 1, user-interrupt delivery loads RSP with UISTACKADJUST; 
otherwise, it subtracts UISTACKADJUST from RSP. Either way, user-interrupt delivery then aligns
RSP to a 16-byte boundary. See Section 9.4.2 for details.
> 该值控制在 user-interrupt delivery 之前 调整stack pointer(RSP)。他可以解释OS ABI's "red zone" 或者被配置来load 
> RSP 通过一个备用的stack pointer 

* UINV: user-interrupt notification vector.<br/>
This is the vector of those ordinary interrupts that are treated as user-interrupt notifications (Section 9.5.1).
When the logical processor receives user-interrupt notification, it processes the user interrupts in the user
posted-interrupt descriptor (UPID) referenced by UPIDADDR (see below and Section 9.5.2).
> 这是一个ordinary interrupt 的vector，这个interrupt 被当作 user-interrupt notification对待(Section 9.5.1)
> 当逻辑处理器收到user-interrupt notification, 它将使用被 `UPIDADDR`指向的 user posted-interrupt descriptor(UPID)
> 处理user  interrupt

* UPIDADDR: user posted-interrupt descriptor address.<br/>
This is the linear address of the UPID that the logical processor consults upon receiving an ordinary interrupt
with vector UINV.
> 这是一个UPID的线性地址，逻辑处理器在收到一个带有vector UINV的ordinary interrupt 后，会查阅他。

* UITTADDR: user-interrupt target table address.<br/>
This is the linear address of user-interrupt target table (UITT), which the logical processor consults when
software invokes the SENDUIPI instruction (see Section 9.7).
> user-interrupt target table(UITT) 线性地址, 当软件执行SENDUIPI 指令时，逻辑处理器会查阅它。(见Section 9.7)

• UITTSZ: user-interrupt target table size.<br/>
This value is the highest index of a valid entry in the UITT (see Section 9.7).
> 该值是UITT中合法entry中的最高的index

### 9.3.2 User-Interrupt MSRs
Some of the state elements identified in Section 9.3.1 can be accessed as user-interrupt MSRs using the RDMSR 
and WRMSR instructions:
> 在Section 9.3.1 列出的一些state 可以当作user-interrupt MSRs，并使用RDMSR/WRMSR指令访问

* IA32_UINTR_RR MSR (MSR address 985H). This MSR is an interface to UIRR (64 bits).

* IA32_UINTR_HANDLER MSR (MSR address 986H). This MSR is an interface to the UIHANDLER address (see 
Section 9.8.1 for canonicality checking).
> canonicality: 规范性

* IA32_UINTR_STACKADJUST MSR (MSR address 987H). This MSR is an interface to the UISTACKADJUST value 
(see Section 9.8.1 for canonicality checking).
* IA32_UINTR_MISC MSR (MSR address 988H). This MSR is an interface to the UITTSZ and UINV values. The 
MSR has the following format:
	+ bits 31:0 are UITTSZ;
	+ bits 39:32 are UINV; and
	+ bits 63:40 are reserved (see Section 9.8.1 for reserved-bit checking).<br/>
	Because this MSR will share an 8-byte portion of the XSAVE area with UIF (see Section 9.8.2), bit 63 of the
	MSR will never be used and will always be reserved.
* IA32_UINTR_PD MSR (MSR address 989H). This MSR is an interface to the UPIDADDR address (see Section 
9.8.1 for canonicality and reserved-bit checking).
* IA32_UINTR_TT MSR (MSR address 98AH). This MSR is an interface to the UITTADDR address (in addition, bit 
0 enables SENDUIPI; see Section 9.8.1 for canonicality and reserved-bit checking).
