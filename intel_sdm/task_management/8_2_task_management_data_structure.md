# 8.2 TASK MANAGEMENT DATA STRUCTURES

The processor defines five data structures for handling task-related
activities:

* Task-state segment (TSS).
* Task-gate descriptor.
* TSS descriptor.
* Task register.
* NT flag in the EFLAGS register.

When operating in protected mode, a TSS and TSS descriptor must be created for
at least one task, and the segment selector for the TSS must be loaded into the
task register (using the LTR instruction).

## 8.2.1 Task-State Segment (TSS)

The processor state information needed to restore a task is saved in a system
segment called the task-state segment (TSS). Figure 8-2 shows the format of a
TSS for tasks designed for 32-bit CPUs. The fields of a TSS are divided into
two main categories: dynamic fields and static fields.

For information about 16-bit Intel 286 processor task structures, see Section
8.6, “16-Bit Task-State Segment (TSS).” For information about 64-bit mode task
structures, see Section 8.7, “Task Management in 64-bit Mode.”

![32-bit-task-state-segment](pic/32-bit-task-state-segment.png)

The processor updates dynamic fields when a task is suspended during a task switch. The following are dynamic
fields:

* General-purpose register fields — State of the EAX, ECX, EDX, EBX, ESP, EBP,
  ESI, and EDI registers prior to the task switch.
* Segment selector fields — Segment selectors stored in the ES, CS, SS, DS, FS,
  and GS registers prior to the task switch.
* EFLAGS register field — State of the EFLAGS register prior to the task switch.
* EIP (instruction pointer) field — State of the EIP register prior to the task switch.
* Previous task link field — Contains the segment selector for the TSS of the
  previous task (updated on a task switch that was initiated by a call,
  interrupt, or exception). This field (which is sometimes called the back link
  field) permits a task switch back to the previous task by using the IRET
  instruction.

The processor reads the static fields, but does not normally change them. These
fields are set up when a task is created. The following are static fields:

* LDT segment selector field — Contains the segment selector for the task's
  LDT.
* CR3 control register field — Contains the base physical address of the page
  directory to be used by the task. Control register CR3 is also known as the
  page-directory base register (PDBR).
* Privilege level-0, -1, and -2 stack pointer fields — These stack pointers
  consist of a logical address made up of the segment selector for the stack
  segment (SS0, SS1, and SS2) and an offset into the stack (ESP0, ESP1, and
  ESP2). Note that the values in these fields are static for a particular task;
  whereas, the SS and ESP values will change if stack switching occurs within
  the task.
* T (debug trap) flag (byte 100, bit 0) — When set, the T flag causes the
  processor to raise a debug exception when a task switch to this task occurs
  (see Section 18.3.1.5, “Task-Switch Exception Condition”).
* I/O map base address field — Contains a 16-bit offset from the base of the
  TSS to the I/O permission bit map and interrupt redirection bitmap. When
  present, these maps are stored in the TSS at higher addresses. The I/O map
  base address points to the beginning of the I/O permission bit map and the
  end of the interrupt redirection bit map. See Chapter 19, “Input/Output,” in
  the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1,
  for more information about the I/O permission bit map. See Section 21.3,
  “Interrupt and Exception Handling in Virtual-8086 Mode,” for a detailed
  description of the interrupt redirection bit map.
* Shadow Stack Pointer (SSP) — Contains task's shadow stack pointer. The shadow
  stack of the task should have a supervisor shadow stack token at the address
  pointed to by the task SSP (offset 104). This token will be verified and made
  busy when switching to that shadow stack using a CALL/JMP instruction, and
  made free when switching out of that task using an IRET instruction.

If paging is used:

* Pages corresponding to the previous task’s TSS, the current task’s TSS, and
  the descriptor table entries for each all should be marked as read/write.
* Task switches are carried out faster if the pages containing these structures
  are present in memory before the task switch is initiated.

## 8.2.2 TSS Descriptor

The TSS, like all other segments, is defined by a segment descriptor. Figure
8-3 shows the format of a TSS descriptor. TSS descriptors may only be placed in
the GDT; they cannot be placed in an LDT or the IDT.

An attempt to access a TSS using a segment selector with its TI flag set (which
indicates the current LDT) causes a general-protection exception (#GP) to be
generated during CALLs and JMPs; it causes an invalid TSS exception (#TS)
during IRETs. A general-protection exception is also generated if an attempt is
made to load a segment selector for a TSS into a segment register.

The busy flag (B) in the type field indicates whether the task is busy. A busy
task is currently running or suspended. A type field with a value of 1001B
indicates an inactive task; a value of 1011B indicates a busy task. Tasks are
not recursive. The processor uses the busy flag to detect an attempt to call a
task whose execution has been inter- rupted. To ensure that there is only one
busy flag is associated with a task, each TSS should have only one TSS
descriptor that points to it.

![TSS_DESC](pic/TSS_DESC.png)

The base, limit, and DPL fields and the granularity and present flags have
functions similar to their use in data- segment descriptors (see Section 3.4.5,
“Segment Descriptors”). When the G flag is 0 in a TSS descriptor for a 32- bit
TSS, the limit field must have a value equal to or greater than 67H, one byte
less than the minimum size of a TSS. Attempting to switch to a task whose TSS
descriptor has a limit less than 67H generates an invalid-TSS excep- tion
(#TS). A larger limit is required if an I/O permission bit map is included or
if the operating system stores addi- tional data. The processor does not check
for a limit greater than 67H on a task switch; however, it does check when
accessing the I/O permission bit map or interrupt redirection bit map.

Any program or procedure with access to a TSS descriptor (that is, whose CPL is
numerically equal to or less than the DPL of the TSS descriptor) can dispatch
the task with a call or a jump.

In most systems, the DPLs of TSS descriptors are set to values less than 3, so
that only privileged software can perform task switching. However, in
multitasking applications, DPLs for some TSS descriptors may be set to 3 to
allow task switching at the application (or user) privilege level.

## 8.2.3 TSS Descriptor in 64-bit mode

In 64-bit mode, task switching is not supported, but TSS descriptors still
exist. The format of a 64-bit TSS is described in Section 8.7.

In 64-bit mode, the TSS descriptor is expanded to 16 bytes (see Figure 8-4).
This expansion also applies to an LDT descriptor in 64-bit mode. Table 3-2
provides the encoding information for the segment type field.

![TSS_LDT_DESC](pic/64_TSS_LDT_DESC.png)

## 8.2.4 Task Register

The task register holds the 16-bit segment selector and the entire segment
descriptor (32-bit base address (64 bits in IA-32e mode), 16-bit segment limit,
and descriptor attributes) for the TSS of the current task (see Figure 2-6).
This information is copied from the TSS descriptor in the GDT for the current
task. Figure 8-5 shows the path the processor uses to access the TSS (using the
information in the task register).

The task register has a visible part (that can be read and changed by software)
and an invisible part (maintained by the processor and is inaccessible by
software). The segment selector in the visible portion points to a TSS
descriptor in the GDT. The processor uses the invisible portion of the task
register to cache the segment descriptor for the TSS. Caching these values in a
register makes execution of the task more efficient. The LTR (load task
register) and STR (store task register) instructions load and read the visible
portion of the task register:

The LTR instruction loads a segment selector (source operand) into the task
register that points to a TSS descriptor in the GDT. It then loads the
invisible portion of the task register with information from the TSS
descriptor. LTR is a privileged instruction that may be executed only when the
CPL is 0. It’s used during system initialization to put an initial value in the
task register. Afterwards, the contents of the task register are changed
implicitly when a task switch occurs.

The STR (store task register) instruction stores the visible portion of the
task register in a general-purpose register or memory. This instruction can be
executed by code running at any privilege level in order to identify the
currently running task. However, it is normally used only by operating system
software. (If CR4.UMIP = 1, STR can be executed only when CPL = 0.)

On power up or reset of the processor, segment selector and base address are
set to the default value of 0; the limit is set to FFFFH.

![Task_register](pic/Task_register.png)

## 8.2.5 Task-Gate Descriptor

A task-gate descriptor provides an indirect, protected reference to a task (see
Figure 8-6). It can be placed in the GDT, an LDT, or the IDT. The TSS segment
selector field in a task-gate descriptor points to a TSS descriptor in the GDT.
The RPL in this segment selector is not used.

The DPL of a task-gate descriptor controls access to the TSS descriptor during
a task switch. When a program or procedure makes a call or jump to a task
through a task gate, the CPL and the RPL field of the gate selector pointing to
the task gate must be less than or equal to the DPL of the task-gate
descriptor. Note that when a task gate is used, the DPL of the destination TSS
descriptor is not used.

![task_gate_desc](pic/task_gate_desc.png)

A task can be accessed either through a task-gate descriptor or a TSS
descriptor. Both of these structures satisfy the following needs:

* Need for a task to have only one busy flag — Because the busy flag for a task
  is stored in the TSS descriptor, each task should have only one TSS
  descriptor. There may, however, be several task gates that reference the same
  TSS descriptor.

* Need to provide selective access to tasks — Task gates fill this need,
  because they can reside in an LDT and can have a DPL that is different from
  the TSS descriptor's DPL. A program or procedure that does not have
  sufficient privilege to access the TSS descriptor for a task in the GDT
  (which usually has a DPL of 0) may be allowed access to the task through a
  task gate with a higher DPL. Task gates give the operating system greater
  latitude for limiting access to specific tasks.

* Need for an interrupt or exception to be handled by an independent task —
  Task gates may also reside in the IDT, which allows interrupts and exceptions
  to be handled by handler tasks. When an interrupt or exception vector points
  to a task gate, the processor switches to the specified task. Figure 8-7
  illustrates how a task gate in an LDT, a task gate in the GDT, and a task
  gate in the IDT can all point to the same task.

![task_gate_ref_same_task](pic/task_gate_ref_same_task.png)