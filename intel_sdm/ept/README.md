## 29.3.5 Accessed and Dirty Flags for EPT The Intel 64 architecture supports
accessed and dirty flags in ordinary paging-structure entries (see Section 4.8).
Some processors also support corresponding flags in EPT paging-structure
entries. Software should read the VMX capability MSR IA32_VMX_EPT_VPID_CAP (see
Appendix A.10) to determine whether the processor supports this feature.

Software can enable accessed and dirty flags for EPT using bit 6 of the
extended-page-table pointer (EPTP), a VM- execution control field (see Table
25-9 in Section 25.6.11). If this bit is 1, the processor will set the accessed
and dirty flags for EPT as described below. In addition, setting this flag
causes processor accesses to guest paging- structure entries to be treated as
writes (see below and Section 29.3.3.2).

For any EPT paging-structure entry that is used during guest-physical-address
translation, bit 8 is the accessed flag. For a EPT paging-structure entry that
maps a page (as opposed to referencing another EPT paging structure), bit 9 is
the dirty flag.

Whenever the processor uses an EPT paging-structure entry as part of
guest-physical-address translation, it sets the accessed flag in that entry (if
it is not already set).

Whenever there is a write to a guest-physical address, the processor sets the
dirty flag (if it is not already set) in the EPT paging-structure entry that
identifies the final physical address for the guest-physical address (either an
EPT PTE or an EPT paging-structure entry in which bit 7 is 1).

When accessed and dirty flags for EPT are enabled, processor accesses to guest
paging-structure entries are treated as writes (see Section 29.3.3.2). Thus,
such an access will cause the processor to set the dirty flag in the EPT
paging-structure entry that identifies the final physical address of the guest
paging-structure entry. (This does not apply to loads of the PDPTE registers for
PAE paging by the MOV to CR instruction; see Section 4.4.1. Those loads of guest
PDPTEs are treated as reads and do not cause the processor to set the dirty flag
in any EPT paging-structure entry.)

These flags are "sticky," meaning that, once set, the processor does not clear
them; only software can clear them. A processor may cache information from the
EPT paging-structure entries in TLBs and paging-structure caches (see Section
29.4). This fact implies that, if software changes an accessed flag or a dirty
flag from 1 to 0, the processor might not set the corresponding bit in memory on
a subsequent access using an affected guest-physical address.
