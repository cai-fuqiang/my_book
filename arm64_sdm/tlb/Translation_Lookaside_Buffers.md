The Arm architecture does not specify any structure of Translation Lookaside
Buffers (TLBs), and permits any structure that complies with the requirements
described in this section.

> comply : 按要求, 命令去做
>
> Arm arch 不会去指定任何 TLBs 的数据结构, 并且允许任何 按照本章节需求描述的
> 数据结构
>
>> 满足本章需求, 芯片厂商可以随意设计TLBs的数据结构 ??

Translation table entries that generate a Translation fault, an Address size
fault, or an Access flag fault are never cached in a TLB.

> 能造成下面类型fault的 translation table entries 将不会在 TLB 中有缓存
>
> * translation fault
> * address size fault
> * access flag fault

When address translation is enabled, a translation table entry for an
in-context translation regime that does not cause a Translation fault, an
Address size fault, or an Access flag fault is permitted to be cached in a TLB
or intermediate TLB caching structure as the result of an explicit or
speculative access.

> 这里首先解释两个名词:
> * in-context translation regime:
> * intermediate TLB caching structure: 个人感觉类似于x86 的 paging-structure cache,
>   即假设一个映射关系VA->PMD->PTE->phyiscal page, paging-structure cache , 可能保存了
>   VA->PTE的映射关系. 而TLB指的是 VA->phyiscal page的映射关系.
>
> 当address translation 是enabled状态, 

When address translation is enabled, if a translation table entry meets all of
the following requirements, then that translation table entry is permitted to
be cached in a TLB or intermediate TLB caching structure at any time:

* The translation table entry itself does not generate a Translation fault, an
  Address size fault, or an Access flag fault.

* The translation table entry is not from a translation regime configured by an
  Exception level that is lower than the current Exception level.

The Arm architecture permits TLBs to cache certain information from System
control registers, including when any or all translation stages are disabled.
The individual register descriptions specify System control register fields are
permitted to be cached in a TLB.

For more information, see Chapter D17 AArch64 System Register Descriptions.

* When executing at EL3 or EL2, the TLB entries associated with the EL1&0
  translation regime are out-of-context.

* When executing at EL3, the TLB entries associated with the EL2 or EL2&0
  translation regime are out-of-context.

The VMSA provides TLB maintenance instructions for the management of TLB
contents.

When a translation stage is disabled and then re-enabled, TLB entries are not
corrupted.

# D8.12.1 TLB behavior at reset

When a reset occurs, an implementation is not required to automatically
invalidate a TLB.

When a reset occurs, a TLB is affected in all of the following ways:

All TLBs reset to an IMPLEMENTATION DEFINED state that might be UNKNOWN.

* It is IMPLEMENTATION DEFINED whether a specific TLB invalidation routine is
  required to invalidate a TLB before translation is enabled after a reset.

For the ELx reset is taken to, when a reset occurs, SCTLR_ELx.M is reset to 0.
For the translation regime controlled by that SCTLR_ELx.M bit, when SCTLR_ELx.M
is 0, TLB contents have no effect on address translation.

If an implementation requires a specific TLB invalidation routine, then all of
the following apply:


* The routine is IMPLEMENTATION DEFINED.
* The implementation documentation is required to clearly document the routine.
* Arm recommends that the routine is based on the TLB maintenance instructions.

On a Cold reset or Warm reset, an implementation might require TLBs to maintain
their contents from before the reset, including one or more of the following
reasons:

* Power management.
* Debug requirements.

For more information on the TLB maintenance instructions used in a TLB
invalidation routine, see TLB maintenance instructions on page D8-5201.

# D8.12.2 TLB lockdown

TLB lockdown support is IMPLEMENTATION DEFINED.

If an implementation supports TLB lockdown, then all of the following apply:

* The lockdown mechanism is IMPLEMENTATION DEFINED.
* The implementation documentation is required to clearly document the
  interaction of the TLB lockdown mechanism with the architecture.

* A locked TLB entry is guaranteed to remain in the TLB, unless the locked TLB
  entry is affected by a TLBI operation.

* An unlocked TLB entry is not guaranteed to remain in the TLB.

* If a translation table entry is modified, then it is not guaranteed that a
  locked TLB entry remains coherent with the modified translation table entry.

If a translation table entry is modified, then it is not guaranteed that a
locked TLB entry remains incoherent with the modified translation table entry
because the lockdown mechanism might permit a TLB maintenance instruction to
trigger an update of the locked TLB entry.

For more information, see The interaction of TLB lockdown with TLB maintenance
instructions on page D8-5200.

The implementation is permitted to use the reserved IMPLEMENTATION DEFINED
register encodings to implement TLB lockdown functions.

TLB lockdown functions might include, but are not limited to, all of the
following:

* Unlock all locked TLB entries.
* Preload a translation table entry into a specific TLB level.

If an implementation supports TLB lockdown and EL2 is enabled, then when
executing at EL1 or EL0, an exception due to TLB lockdown can be routed to one
of the following:

* EL1, as a Data Abort exception.
* EL2, as a Hyp Trap exception.
