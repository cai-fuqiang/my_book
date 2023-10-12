# 29.4 CACHING TRANSLATION INFORMATION

Processors supporting Intel® 64 and IA-32 architectures may accelerate the
address-translation process by caching on the processor data from the
structures in memory that control that process. Such caching is discussed in
Section 4.10, “Caching Translation Information” in the Intel® 64 and IA-32
Architectures Software Developer’s Manual, Volume 3A. The current section
describes how this caching interacts with the VMX architecture.

The VPID and EPT features of the architecture for VMX operation augment this
caching architecture. EPT defines the guest-physical address space and defines
translations to that address space (from the linear-address space) and from
that address space (to the physical-address space). Both features control the
ways in which a logical processor may create and use information cached from
the paging structures.

Section 29.4.1 describes the different kinds of information that may be cached.
Section 29.4.2 specifies when such information may be cached and how it may be
used. Section 29.4.3 details how software can invalidate cached information.

## 29.4.1 Information That May Be Cached

Section 4.10, “Caching Translation Information” in Intel® 64 and IA-32
Architectures Software Developer’s Manual, Volume 3A identifies two kinds of
translation-related information that may be cached by a logical processor:
translations, which are mappings from linear page numbers to physical page
frames, and paging- structure caches, which map the upper bits of a linear page
number to information from the paging-structure entries used to translate
linear addresses matching those upper bits.

The same kinds of information may be cached when VPIDs and EPT are in use. A
logical processor may cache and use such information based on its function.
Information with different functionality is identified as follows:

* **Linear mappings.**<sup>2</sup> There are two kinds:

    + Linear translations. Each of these is a mapping from a linear page number
      to the physical page frame to which it translates, along with information
      about access privileges and memory typing.

    + Linear paging-structure-cache entries. Each of these is a mapping from the
      upper portion of a linear address to the physical address of the paging
      structure used to translate the corresponding region of the linear-address
      space, along with information about access privileges. For example, bits
      47:39 of a linear address would map to the address of the relevant
      page-directory-pointer table. Linear mappings do not contain information
      from any EPT paging structure.

* Guest-physical mappings.1 There are two kinds:

    + Guest-physical translations. Each of these is a mapping from a
    guest-physical page number to the physical page frame to which it
    translates, along with information about access privileges and memory
    typing.

    + Guest-physical paging-structure-cache entries. Each of these is a mapping
    from the upper portion of a guest-physical address to the physical address
    of the EPT paging structure used to translate the corre- sponding region of
    the guest-physical address space, along with information about access
    privileges. The information in guest-physical mappings about access
    privileges and memory typing is derived from EPT paging structures.

* Combined mappings.2 There are two kinds:
    + Combined translations. Each of these is a mapping from a linear page
    number to the physical page frame to which it translates, along with
    information about access privileges and memory typing.
    + Combined paging-structure-cache entries. Each of these is a mapping from
    the upper portion of a linear address to the physical address of the paging
    structure used to translate the corresponding region of the linear-address
    space, along with information about access privileges.

    The information in combined mappings about access privileges and memory
    typing is derived from both guest paging structures and EPT paging
    structures.

Guest-physical mappings and combined mappings may also include SPP vectors and
information about the data structures used to locate SPP vectors (see Section
29.3.4.2).

## 29.4.2 Creating and Using Cached Translation Information

The following items detail the creation of the mappings described in the
previous section:<sup>3</sup>

The following items describe the creation of mappings while EPT is not in use
(including execution outside VMX non-root operation):
    + Linear mappings may be created. They are derived from the paging
      structures referenced (directly or indirectly) by the current value of
      CR3 and are associated with the current VPID and the current PCID.
    + No linear mappings are created with information derived from
      paging-structure entries that are not present (bit 0 is 0) or that set
      reserved bits. For example, if a PTE is not present, no linear mapping
      are created for any linear page number whose translation would use that
      PTE.
    + No guest-physical or combined mappings are created while EPT is not in
      use.

* The following items describe the creation of mappings while EPT is in use:

    + Guest-physical mappings may be created. They are derived from the EPT
      paging structures referenced (directly or indirectly) by bits 51:12 of
      the current EPTP. These 40 bits contain the address of the EPT-PML4-
      table. (the notation EP4TA refers to those 40 bits). Newly created
      guest-physical mappings are associated with the current EP4TA.

    + Combined mappings may be created. They are derived from the EPT paging
      structures referenced (directly or indirectly) by the current EP4TA. If
      CR0.PG = 1, they are also derived from the paging structures referenced
      (directly or indirectly) by the current value of CR3. They are associated
      with the current VPID, the current PCID, and the current EP4TA.1 No
      combined paging-structure-cache entries are created if CR0.PG = 0.2

    + No guest-physical mappings or combined mappings are created with
      information derived from EPT paging- structure entries that are not
      present (see Section 29.3.2) or that are misconfigured (see Section
      29.3.3.1).

    + No combined mappings are created with information derived from guest
      paging-structure entries that are not present or that set reserved bits.

    + No linear mappings are created while EPT is in use.

The following items detail the use of the various mappings:

If EPT is not in use (e.g., when outside VMX non-root operation), a logical
processor may use cached mappings as follows:

    + For accesses using linear addresses, it may use linear mappings
      associated with the current VPID and the current PCID. It may also use
      global TLB entries (linear mappings) associated with the current VPID and
      any PCID.

    + No guest-physical or combined mappings are used while EPT is not in use.

    + If EPT is in use, a logical processor may use cached mappings as follows:

    + For accesses using linear addresses, it may use combined mappings
      associated with the current VPID, the current PCID, and the current
      EP4TA. It may also use global TLB entries (combined mappings) associated
      with the current VPID, the current EP4TA, and any PCID.

    + For accesses using guest-physical addresses, it may use guest-physical
      mappings associated with the current EP4TA.

    + No linear mappings are used while EPT is in use.

## 29.4.3 Invalidating Cached Translation Information

Software modifications of paging structures (including EPT paging structures
and the data structures used to locate SPP vectors) may result in
inconsistencies between those structures and the mappings cached by a logical
processor. Certain operations invalidate information cached by a logical
processor and can be used to eliminate such inconsistencies.

### 29.4.3.1 Operations that Invalidate Cached Mappings

The following operations invalidate cached mappings as indicated:

* Operations that architecturally invalidate entries in the TLBs or
paging-structure caches independent of VMX operation (e.g., the INVLPG and
INVPCID instructions) invalidate linear mappings and combined mappings.3 They
are required to do so only for the current VPID (but, for combined mappings,
all EP4TAs). Linear mappings for the current VPID are invalidated even if EPT
is in use.4 Combined mappings for the current VPID are invalidated even if EPT
is not in use.5

* An EPT violation invalidates any guest-physical mappings (associated with the
current EP4TA) that would be used to translate the guest-physical address that
caused the EPT violation. If that guest-physical address was the translation of
a linear address, the EPT violation also invalidates any combined mappings for
that linear address associated with the current PCID, the current VPID and the
current EP4TA.

* If the “enable VPID” VM-execution control is 0, VM entries and VM exits
invalidate linear mappings and combined mappings associated with VPID 0000H
(for all PCIDs). Combined mappings for VPID 0000H are invalidated for all
EP4TAs.

* Execution of the INVVPID instruction invalidates linear mappings and combined
mappings. Invalidation is based on instruction operands, called the INVVPID
type and the INVVPID descriptor. Four INVVPID types are currently defined:

    + Individual-address. If the INVVPID type is 0, the logical processor
      invalidates linear mappings and combined mappings associated with the
      VPID specified in the INVVPID descriptor and that would be used to
      translate the linear address specified in of the INVVPID descriptor.
      Linear mappings and combined mappings for that VPID and linear address
      are invalidated for all PCIDs and, for combined mappings, all EP4TAs.
      (The instruction may also invalidate mappings associated with other VPIDs
      and for other linear addresses.)

    + Single-context. If the INVVPID type is 1, the logical processor
      invalidates all linear mappings and combined mappings associated with the
      VPID specified in the INVVPID descriptor. Linear mappings and combined
      mappings for that VPID are invalidated for all PCIDs and, for combined
      mappings, all EP4TAs. (The instruction may also invalidate mappings
      associated with other VPIDs.)

    + All-context. If the INVVPID type is 2, the logical processor invalidates
      linear mappings and combined mappings associated with all VPIDs except
      VPID 0000H and with all PCIDs. (The instruction may also invalidate
      linear mappings with VPID 0000H.) Combined mappings are invalidated for
      all EP4TAs.

    + Single-context-retaining-globals. If the INVVPID type is 3, the logical
      processor invalidates linear mappings and combined mappings associated
      with the VPID specified in the INVVPID descriptor. Linear mappings and
      combined mappings for that VPID are invalidated for all PCIDs and, for
      combined mappings, all EP4TAs. The logical processor is not required to
      invalidate information that was used for global transla- tions (although
      it may do so). See Section 4.10, “Caching Translation Information” for
      details regarding global translations. (The instruction may also
      invalidate mappings associated with other VPIDs.) See Chapter 31 for
      details of the INVVPID instruction. See Section 29.4.3.3 for guidelines
      regarding use of this instruction.

* Execution of the INVEPT instruction invalidates guest-physical mappings and
combined mappings. Invalidation is based on instruction operands, called the
INVEPT type and the INVEPT descriptor. Two INVEPT types are currently defined:

    + Single-context. If the INVEPT type is 1, the logical processor
      invalidates all guest-physical mappings and combined mappings associated
      with the EP4TA specified in the INVEPT descriptor. Combined mappings for
      that EP4TA are invalidated for all VPIDs and all PCIDs. (The instruction
      may invalidate mappings associated with other EP4TAs.)

    + All-context. If the INVEPT type is 2, the logical processor invalidates
      guest-physical mappings and combined mappings associated with all EP4TAs
      (and, for combined mappings, for all VPIDs and PCIDs). See Chapter 31 for
      details of the INVEPT instruction. See Section 29.4.3.4 for guidelines
      regarding use of this instruction.


* A power-up or a reset invalidates all linear mappings, guest-physical mappings,
and combined mappings.

### 29.4.3.2 Operations that Need Not Invalidate Cached Mapping

The following items detail cases of operations that are not required to
invalidate certain cached mappings:

* Operations that architecturally invalidate entries in the TLBs or
paging-structure caches independent of VMX operation are not required to
invalidate any guest-physical mappings.

* The INVVPID instruction is not required to invalidate any guest-physical
mappings. The INVEPT instruction is not required to invalidate any linear
mappings.

* VMX transitions are not required to invalidate any guest-physical mappings. If
the “enable VPID” VM-execution control is 1, VMX transitions are not required
to invalidate any linear mappings or combined mappings.

* The VMXOFF and VMXON instructions are not required to invalidate any linear
mappings, guest-physical mappings, or combined mappings.

A logical processor may invalidate any cached mappings at any time. For this
reason, the operations identified above may invalidate the indicated mappings
despite the fact that doing so is not required.

### 29.4.3.3 Guidelines for Use of the INVVPID Instruction

The need for VMM software to use the INVVPID instruction depends on how that
software is virtualizing memory. If EPT is not in use, it is likely that the
VMM is virtualizing the guest paging structures. Such a VMM may configure the
VMCS so that all or some of the operations that invalidate entries the TLBs and
the paging-structure caches (e.g., the INVLPG instruction) cause VM exits. If
VMM software is emulating these operations, it may be necessary to use the
INVVPID instruction to ensure that the logical processor’s TLBs and the
paging-structure caches are appropriately invalidated.

Requirements of when software should use the INVVPID instruction depend on the
specific algorithm being used for page-table virtualization. The following
items provide guidelines for software developers:

* Emulation of the INVLPG instruction may require execution of the INVVPID
instruction as follows:

    + The INVVPID type is individual-address (0).

    + The VPID in the INVVPID descriptor is the one assigned to the virtual
      processor whose execution is being emulated.

    + The linear address in the INVVPID descriptor is that of the operand of
      the INVLPG instruction being emulated.

* Some instructions invalidate all entries in the TLBs and paging-structure
caches—except for global translations. An example is the MOV to CR3
instruction. (See Section 4.10, “Caching Translation Information” in the Intel®
64 and IA-32 Architectures Software Developer’s Manual, Volume 3A for details
regarding global translations.) Emulation of such an instruction may require
execution of the INVVPID instruction as follows:

    + The INVVPID type is single-context-retaining-globals (3).

    + The VPID in the INVVPID descriptor is the one assigned to the virtual
      processor whose execution is being emulated.

* Some instructions invalidate all entries in the TLBs and paging-structure
caches—including for global transla- tions. An example is the MOV to CR4
instruction if the value of value of bit 4 (page global enable—PGE) is
changing. Emulation of such an instruction may require execution of the INVVPID
instruction as follows:

    + The INVVPID type is single-context (1).

    + The VPID in the INVVPID descriptor is the one assigned to the virtual
      processor whose execution is being emulated.

If EPT is not in use, the logical processor associates all mappings it creates
with the current VPID, and it will use such mappings to translate linear
addresses. For that reason, a VMM should not use the same VPID for different
non-EPT guests that use different page tables. Doing so may result in one guest
using translations that pertain to the other.

If EPT is in use, the instructions enumerated above might not be configured to
cause VM exits and the VMM might not be emulating them. In that case,
executions of the instructions by guest software properly invalidate the
required entries in the TLBs and paging-structure caches (see Section
29.4.3.1); execution of the INVVPID instruc- tion is not required.

If EPT is in use, the logical processor associates all mappings it creates with
the value of bits 51:12 of current EPTP. If a VMM uses different EPTP values
for different guests, it may use the same VPID for those guests. Doing so
cannot result in one guest using translations that pertain to the other.

The following guidelines apply more generally and are appropriate even if EPT
is in use:

* As detailed in Section 30.4.5, an access to the APIC-access page might not
cause an APIC-access VM exit if software does not properly invalidate
information that may be cached from the paging structures. If, at one time, the
current VPID on a logical processor was a non-zero value X, it is recommended
that software use the INVVPID instruction with the “single-context” INVVPID
type and with VPID X in the INVVPID descriptor before a VM entry on the same
logical processor that establishes VPID X and either (a) the “virtualize APIC
accesses” VM-execution control was changed from 0 to 1; or (b) the value of the
APIC-access address was changed.

* Software can use the INVVPID instruction with the “all-context” INVVPID type
immediately after execution of the VMXON instruction or immediately prior to
execution of the VMXOFF instruction. Either prevents potentially undesired
retention of information cached from paging structures between separate uses of
VMX operation.

### 29.4.3.4 Guidelines for Use of the INVEPT Instruction
The following items provide guidelines for use of the INVEPT instruction to invalidate information cached from the
EPT paging structures.


Software should use the INVEPT instruction with the “single-context” INVEPT type after making any of the
following changes to an EPT paging-structure entry (the INVEPT descriptor should contain an EPTP value that
references — directly or indirectly — the modified EPT paging structure):
— Changing any of the privilege bits 2:0 from 1 to 0.1
— Changing the physical address in bits 51:12.
— Clearing bit 8 (the accessed flag) if accessed and dirty flags for EPT will be enabled.
— For an EPT PDPTE or an EPT PDE, changing bit 7 (which determines whether the entry maps a page).
— For the last EPT paging-structure entry used to translate a guest-physical address (an EPT PDPTE with bit 7
set to 1, an EPT PDE with bit 7 set to 1, or an EPT PTE), changing either bits 5:3 or bit 6. (These bits
determine the effective memory type of accesses using that EPT paging-structure entry; see Section
29.3.7.)
— For the last EPT paging-structure entry used to translate a guest-physical address (an EPT PDPTE with bit 7
set to 1, an EPT PDE with bit 7 set to 1, or an EPT PTE), clearing bit 9 (the dirty flag) if accessed and dirty
flags for EPT will be enabled.
•Software should use the INVEPT instruction with the “single-context” INVEPT type before a VM entry with an
EPTP value X such that X[6] = 1 (accessed and dirty flags for EPT are enabled) if the logical processor had
earlier been in VMX non-root operation with an EPTP value Y such that Y[6] = 0 (accessed and dirty flags for
EPT are not enabled) and Y[51:12] = X[51:12].
•Software may use the INVEPT instruction after modifying a present EPT paging-structure entry (see Section
29.3.2) to change any of the privilege bits 2:0 from 0 to 1.2 Failure to do so may cause an EPT violation that
would not otherwise occur. Because an EPT violation invalidates any mappings that would be used by the access
that caused the EPT violation (see Section 29.4.3.1), an EPT violation will not recur if the original access is
performed again, even if the INVEPT instruction is not executed.
•Because a logical processor does not cache any information derived from EPT paging-structure entries that are
not present (see Section 29.3.2) or misconfigured (see Section 29.3.3.1), it is not necessary to execute INVEPT
following modification of an EPT paging-structure entry that had been not present or misconfigured.
•As detailed in Section 30.4.5, an access to the APIC-access page might not cause an APIC-access VM exit if
software does not properly invalidate information that may be cached from the EPT paging structures. If EPT
was in use on a logical processor at one time with EPTP X, it is recommended that software use the INVEPT
instruction with the “single-context” INVEPT type and with EPTP X in the INVEPT descriptor before a VM entry
on the same logical processor that enables EPT with EPTP X and either (a) the “virtualize APIC accesses” VM-
execution control was changed from 0 to 1; or (b) the value of the APIC-access address was changed.
•Software can use the INVEPT instruction with the “all-context” INVEPT type immediately after execution of the
VMXON instruction or immediately prior to execution of the VMXOFF instruction. Either prevents potentially
undesired retention of information cached from EPT paging structures between separate uses of VMX
operation.

In a system containing more than one logical processor, software must account for the fact that information from
an EPT paging-structure entry may be cached on logical processors other than the one that modifies that entry. The
process of propagating the changes to a paging-structure entry is commonly referred to as “TLB shootdown.” A
discussion of TLB shootdown appears in Section 4.10.5, “Propagation of Paging-Structure Changes to Multiple
Processors,” in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A.
