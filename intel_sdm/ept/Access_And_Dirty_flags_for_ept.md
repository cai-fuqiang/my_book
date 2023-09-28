## 29.3.5 Accessed and Dirty Flags for EPT The Intel 64 architecture supports
The Intel 64 architecture supports accessed and dirty flags in ordinary
paging-structure entries (see Section 4.8). Some processors also support
corresponding flags in EPT paging-structure entries. Software should read the
VMX capability MSR IA32_VMX_EPT_VPID_CAP (see Appendix A.10) to determine
whether the processor supports this feature.

> Intel 64 arch 支持 accessed 和 dirty flags 在 ordinary paging-structure entries.
> (请看 Section 4.8). 某些处理器也支持在 EPT paging-structure entries 中的相应字段。
> 软件应该读取 VMX capability MSR IA32_VMX_EPT_VPID_CAP( Appendix A.10) 来确定
> 处理器是否支持该feature

Software can enable accessed and dirty flags for EPT using bit 6 of the
extended-page-table pointer (EPTP), a VM- execution control field (see Table
25-9 in Section 25.6.11). If this bit is 1, the processor will set the accessed
and dirty flags for EPT as described below. In addition, setting this flag
causes processor accesses to guest paging- structure entries to be treated as
writes (see below and Section 29.3.3.2).

> 软件可以使用 EPTP中的 BIT 6 使能 EPT 中的 accessed 和 dirty flags，（该位位于
> VM-execution control filed. 如果该位是1, 处理器将会在如下的场景中设置 EPT的
> accessed 和 dirty flags。 另外，设置改位(EPTP BIT 6) 将会导致处理器访问 guest
> paging-structure entries 当作 write 行为对待。(请查看 Section 29.3.3.2)

For any EPT paging-structure entry that is used during guest-physical-address
translation, bit 8 is the accessed flag. For a EPT paging-structure entry that
maps a page (as opposed to referencing another EPT paging structure), bit 9 is
the dirty flag.

> 对于任何 用于 guest-physical-address translation 的 EPT paging-structure
> 而言， bit 8 都是 accessed flag. 对于map a page 的 EPT paging-structure
> entry(而不是指向 另一个 EPT paging structure), bit 9 都是 dirty flag

Whenever the processor uses an EPT paging-structure entry as part of
guest-physical-address translation, it sets the accessed flag in that entry (if
it is not already set).

> 无论何时，只要处理器在 guest-physical-address translation 时候使用EPT
> paging-structure, 他都会设置该entry的 accessed flag(如果该位还没有被设置)

Whenever there is a write to a guest-physical address, the processor sets the
dirty flag (if it is not already set) in the EPT paging-structure entry that
identifies the final physical address for the guest-physical address (either an
EPT PTE or an EPT paging-structure entry in which bit 7 is 1).

> 无论何时，只要对一个 guest-phyiscal address 进行写操作，处理器都会设置 该 EPT
> paging-structure entry中的 dirty flag, 该 EPT paging-structure 会标记 GPA的
> 最终的物理地址(HPA) (也就是最后一级页表) (也就是 EPT PTE 或者该 EPT
> paging-structure entry的 BIT 7 是 1)

When accessed and dirty flags for EPT are enabled, processor accesses to guest
paging-structure entries are treated as writes (see Section 29.3.3.2). Thus,
such an access will cause the processor to set the dirty flag in the EPT
paging-structure entry that identifies the final physical address of the guest
paging-structure entry. (This does not apply to loads of the PDPTE registers for
PAE paging by the MOV to CR instruction; see Section 4.4.1. Those loads of guest
PDPTEs are treated as reads and do not cause the processor to set the dirty flag
in any EPT paging-structure entry.)

> 当 EPT accessed 和 dirty flags 被使能时，处理器访问 guest paging-structure entries
> 被当作 writes操作(请查看 29.3.3.2). 因此，这样的一个访问会导致处理器设置 最后
> 一级页表的paging-structure entry的 dirty flag。（这不适用 对于 PAE paging 通过
> MOV to CR 指令 loads PDPTE registers; 请查看 4.4.1。这些 guest PDPTEs的 load
> 动作被当作 reads操作并且不会设置任何 EPT paging structure entry的 dirty flag)

These flags are "sticky," meaning that, once set, the processor does not clear
them; only software can clear them. A processor may cache information from the
EPT paging-structure entries in TLBs and paging-structure caches (see Section
29.4). This fact implies that, if software changes an accessed flag or a dirty
flag from 1 to 0, the processor might not set the corresponding bit in memory on
a subsequent access using an affected guest-physical address.

> 这些flags是 "sticky", 意味着，一旦设置，处理器将不会clear;
> 只有软件可以clear。 处理器可能从 从 EPT paging-structure entries 中 cache
> information 到 TLBs和 paging-structure caches(请查看 Section
> 29.4)。这也就意味着，如果软件改动 access flags 或者 dirty flags 1 -> 0,
> 在一次 使用了 affected GPA 的  subsequent access<sub>1</sub>,
> 处理器可能不会设置内存中的相应的位，
>
>> 1. 这一块需要看下, 4.10.2 以及 4.10.3: 我这边的暂时的理解是, processor page
>> table walk 可能会访问 TLBs 和paging-structure caches, 但是如果 processor修改
>> 了 page table entry 中的 A D flags 1->0，修改后可能会在 cache / memory 中 visible，
>> 但是 TLBs 和 paging-structure caches中还没有更改。所以processor在 table walk, 
>> 还是认为 A/D flag 是1, 所以不会在去修改该flag。这时需要软件去invalidate TLBs/paging-
>> structure cache
