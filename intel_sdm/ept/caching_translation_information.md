# 29.4 CACHING TRANSLATION INFORMATION

Processors supporting Intel® 64 and IA-32 architectures may accelerate the
address-translation process by caching on the processor data from the
structures in memory that control that process. Such caching is discussed in
Section 4.10, “Caching Translation Information” in the Intel® 64 and IA-32
Architectures Software Developer’s Manual, Volume 3A. The current section
describes how this caching interacts with the VMX architecture.

> interacts: 相互作用，相互影响
>
> 支持 Intel 64 和 IA-32架构的处理器可能会通过 来自内存控制该流程的structure
> cache 到处理器的数据加速 address-translation 流程。这样的caching 在 4.10 
> 章节中讨论。当前章节讨论 这些缓存如何作用于 VMX architecture.

The VPID and EPT features of the architecture for VMX operation augment this
caching architecture. EPT defines the guest-physical address space and defines
translations to that address space (from the linear-address space) and from
that address space (to the physical-address space). Both features control the
ways in which a logical processor may create and use information cached from
the paging structures.
> augment : 增加，增强
>
> 对于VMX operation 架构下的 VPID 和 EPT feature 增加了 caching architecture内容。
> EPT 定义了 guest-physical address space 并且定义了关于到该地址空间(从线性地址
> 空间) 和从该地址空间(到物理地址空间)的翻译。这两个feature都控制逻辑处理器可以
> 创建和使用从 paging structure  缓存的信息。
>
> NOTE
>
> 也就是GVA->GPA,  GPA->HPA 这两部分都可以缓存信息。

Section 29.4.1 describes the different kinds of information that may be cached.
Section 29.4.2 specifies when such information may be cached and how it may be
used. Section 29.4.3 details how software can invalidate cached information.

> Section 29.4.1描述了 cache 信息的不同种类。Section 29.4.2 指定了什么时候缓存
> 该信息和这些信息怎么使用。Section 29.4.3 细节描述了 软件如何去无效这些 缓存了的
> 信息。

## 29.4.1 Information That May Be Cached

Section 4.10, “Caching Translation Information” in Intel® 64 and IA-32
Architectures Software Developer’s Manual, Volume 3A identifies two kinds of
translation-related information that may be cached by a logical processor:
**translations**, which are mappings from linear page numbers to physical page
frames, and **paging-structure caches**, which map the upper bits of a linear
page number to information from the paging-structure entries used to translate
linear addresses matching those upper bits.

> Section 4.10 "Caching Translation Information" in INTEL SDM 指出了处理器
> 可以缓存的两种和翻译相关的信息: 
> * translation: 映射 linear page numbers ->  physical page frames
> * paging-structure caches: 映射 linear page number 的高位 -> 用于的该线性地
> 址转换的高位匹配的 paging-structure entries

The same kinds of information may be cached when VPIDs and EPT are in use. A
logical processor may cache and use such information based on its function.
Information with different functionality is identified as follows:

> 当 正在用 VPIDs 和 EPT  时，可以缓存相同种类的信息，处理器可以基于其功能缓存
> 并使用这些信息。具有不同功能的信息如下:

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

* **Guest-physical mappings**.1 There are two kinds:

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

* **Combined mappings**.2 There are two kinds:
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

>> 以上三段不再翻译, 大概如下:
>> 
>> 每种类型信息都分为 translations（TLB）和 paging-structure cache
>>
>> * Liner mappings : 用于linear page number->physical page frame 。Liner 
>>   mappings 不会包含任何和 EPT paging structure 相关的信息。
>>
>> * Guest-physical mappings: 用于 guest-physical page number-> physical page 
>> frame。该信息相当于只保存 GPA->HPA 的映射信息，所以想 access privileges 以及
>> memory type 都只来自于 EPT
>>
>> * Combined mappings: 用于 linear page number -> physical page frame。
>> 但是缓存信息包含了 guest paging structures 以及EPT paging structures

>> NOTE
>>
>> 这里我们思考一个问题:
>>
>> 在使能EPT时，我们只需要关心GVA->HPA的映射。看似只需要 Combined mappings
>> 就可以了，为什么还需要 linear mappings以及 Guest-physical mappings.
>>
>> 以下是我自己的理解: 实际上MMU在执行的时候分了两段映射 GVA->GPA, GPA->HPA
>> * GPA->HPA: 这段映射不复杂，EPT table entry中的物理地址实际上是HPA
>> * GVA->GPA: 这里面需要walk guest page tables. guest page table 中保存的
>> 地址又是 GPA，所以需要保存两部分信息，一个是guest的 paging-structure:
>> linear mappings, 另一部分是guest paging-structure 中的 GPA->HPA的信息(也就是
>> GPA of guest page table -> HPA of guest page table)。
>>
>> 页表缓存的查询和创建是相反的: 创建的顺序和page table walk一致。而查询的循序则相反。
>> 查询的tag为GVA, 顺序应该是:
>> * Combined translation
>> * EPT PDE Combined paging-structure cache
>> * EPT PDPTE Combined paging-structure cache
>> * EPT PML4 Combined paging-structure cache
>>
>> 如果在查询不到，其实缺少了GVA->GPA的映射, 本来我这边想的是，
>> CPU 会保存以线性地址为tag，映射GPA关系的cache，(例如，GUEST再找不到GPA后，首先
>> 查询Guest PDE paging-structure cache, 该cache是以GVA为tag）,但是根据intel 手册
>> 来看，貌似没有该cache, 那么这时需要从Guest CR3出发，正向进行page table walk
>> 
>> 那么, 这里我们假设guest 使用 4-level page, ept也使用4-LEVEL, 没有任何的guest-physical 
>> mappings的创建, 我们描述 cache的创建:
>>
>> * 根据线性地址的 [47:39] 和CR3 中的PML4 page frame : 得到PML4e的GPA, MMU访问
>> 该GPA, 此时需要ept table walk, 使用GPA 的page number 作为tag， 查询 
>> Guest-physical translation, 如果没有在查询 Guest-physical EPT PML4 paging-structure
>> cache（以此类推), 当EPT table work完成后，相应的 Guest-physical translation,
>> 以及Guest-physical paging-structure cache已经建立好了，得到PML4E的HPA，mmu
>> 访问得到其值，其中有page directory pointer table 的GPA。
>>
>> * 根据线性地址的[38,30] 和上述得到的PDPT 的 GPA: 得到 PDPTE的 GPA,MMU 访问
>> 其GPA，也需要 ept table walk 同上.
>>
>> * PDE 获取同上, 得到 page table的 GPA
>> * PTE 获取同上, 得到该线性地址的GPA
>>
>> 自此，cache查询创建完成，可以看到这里面查询有反向于page table walk -- 
>> combined mappings, 也有正向于 page table walk, guest-physical mappings.

>>> <font color="red">
>>> 上面流程根据intel 手册猜测，之后准备向 stackoverflow发起讨论验证。
>>> </font>

Guest-physical mappings and combined mappings may also include SPP vectors and
information about the data structures used to locate SPP vectors (see Section
29.3.4.2).

> Guest-physical mappings 和 combined mappings 可能也包括 SPP vectors 和 
> 关于 用于定位 SPP vectors 的相关数据结构的信息。

## 29.4.2 Creating and Using Cached Translation Information

The following items detail the creation of the mappings described in the
previous section:<sup>4</sup>

> 4. This section associated cached information with the current VPID and PCID. If
> PCIDs are not supported or are not being used (e.g., because CR4.PCIDE = 0),
> all the information is implicitly associated with PCID 000H; see Section
> 4.10.1, “Process-Context Identifiers (PCIDs),” in the Intel® 64 and IA-32
> Architectures Software Developer’s Manual, Volume 3A.

> 下面条目细节描述了上面章节中提到的那些映射的创建:
> 
> 该章节将缓存信息和当前VPID && PCID 相关联。如果PCIDs不支持或者没有被使用
> （CR4.PCIDE=0）,所有cache信息都隐式的于PCID OOOH相关联

* The following items describe the creation of mappings while EPT is not in use
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

> 下面章节描述了当EPT 没有被使用情况下，mappings的创建:
> * linear mappings 可能会被创建。他们是根据CR3中的值指向的(直接/间接)，并且与
> current VPID以及current PCID相关联
>
> * 不会有linear mappings在来自于下面paging-structure entries 被创建:
>   + not present (bit 0  = 0)
>   + 设置了预留位
>
>   例如, 如果PTE 没有 present, 对于使用了该PTE linear page number的 translation, 
>   不会有linear mappings被创建
>   + 没有guest-physical 或者 conbined mappings会被创建，当EPT 没有被使用

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
      information derived from EPT paging-structure entries that are not
      present (see Section 29.3.2) or that are misconfigured (see Section
      29.3.3.1).
    + No combined mappings are created with information derived from guest
      paging-structure entries that are not present or that set reserved bits.
    + No linear mappings are created while EPT is in use.

> notation: 符号，记号
>
> 当EPT 在被使用, 下面条目描述 mappings的创建:
> * Guest-physical mappings 可能会被创建。他们从当前EPTP[51:12] bits指向的 paging-
> structure 中获取。他的40个bits包含了EPT-PML4-table的地址。(该符号 EP4TA 指的
> 就是这40位)。心创建的 guest-physical mappings回合当前的EP4TA相关联。
>
> * Combined mappings 可能会被创建。他们从由当前EP4TA指向的EPT paging-structure
> 获取。如果CR0.PG=1, 他们同样从当前CR3指向的paging structure 中获取。他们
> 和current VPID, current PCID 以及 current EP4TA 相关联。当CR0.PG=0, 没有
> 相关的combined paging-structure-cache entries 被创建。

The following items detail the use of the various mappings:

> 下面条目描述了不同 mappings的用法。

* If EPT is not in use (e.g., when outside VMX non-root operation), a logical
processor may use cached mappings as follows:
    + For accesses using linear addresses, it may use linear mappings
      associated with the current VPID and the current PCID. It may also use
      global TLB entries (linear mappings) associated with the current VPID and
      any PCID.
    + No guest-physical or combined mappings are used while EPT is not in use.

> 如果 EPT 没有被使用 (e.g., 当在 VMX non-root operation 之外), 逻辑处理器可能
> 如下使用 cached mappings
> 
> * 对于使用线性地址访问, 他可能使用和当前VPID && PCID相关的linear mappings. 
> 他也可能使用 和当前 VPID 相关 的任意 PCID 的global TLB entires （linear 
> mappings)
> * 当EPT 没有被使用时，不会有 guest-physical, combined mappings被使用。

* If EPT is in use, a logical processor may use cached mappings as follows:
    + For accesses using linear addresses, it may use combined mappings
      associated with the current VPID, the current PCID, and the current
      EP4TA. It may also use global TLB entries (combined mappings) associated
      with the current VPID, the current EP4TA, and any PCID.
    + For accesses using guest-physical addresses, it may use guest-physical
      mappings associated with the current EP4TA.
    + No linear mappings are used while EPT is in use.
> 当EPT 被使用，逻辑处理器可能如下使用 cache mappings.
>   * 对于使用线性地址的访问来说，他可能使用和current VPID, current PCID,以及
>   current EP4TA 相关的combined mappings。他也可能使用 和当前VPID, 当前 EP4TA以及
>   任何 PCID 相关的global TLB entries(combined mappings)
>   * 对于使用 guest-physical address的访问，他可能使用 和当前 EP4TA 相关的
>   guest-physical mappings
>   * 当EPT 正在使用时，没有 linear mappings 被使用


## 29.4.3 Invalidating Cached Translation Information

Software modifications of paging structures (including EPT paging structures
and the data structures used to locate SPP vectors) may result in
inconsistencies between those structures and the mappings cached by a logical
processor. Certain operations invalidate information cached by a logical
processor and can be used to eliminate such inconsistencies.

> eliminate [ɪˈlɪmɪneɪt]:清除，消除
>
> 软件对 paging structure 的修改(包括 EPT paging structures以及用于定位 SPP 
> vectors的数据结构）可能造成这些结构和逻辑处理器映射缓存的不一致。某些
> 操作会无效由logical processor 缓存的信息并且可以用于清除这些不一致。

### 29.4.3.1 Operations that Invalidate Cached Mappings

The following operations invalidate cached mappings as indicated:

> as indicated : 如下所示
>
> 下面的一些操作会无效mappings, 如下所示:

* Operations that architecturally invalidate entries in the TLBs or
paging-structure caches independent of VMX operation (e.g., the INVLPG and
INVPCID instructions) invalidate linear mappings and combined
mappings.<sup>3</sup> They are required to do so only for the current VPID
(but, for combined mappings, all EP4TAs). Linear mappings for the current VPID
are invalidated even if EPT is in use.<sup>4</sup> Combined mappings for the
current VPID are invalidated even if EPT is not in use.<sup>5</sup>

> 4. See Section 4.10.4, “Invalidation of TLBs and Paging-Structure Caches,” in
>    the Intel® 64 and IA-32 Architectures Software Developer’s Manual,
>    Volume 3A, for an enumeration of operations that architecturally
>    invalidate entries in the TLBs and paging-structure caches independent of
>    VMX operation.

> 在体系结构上<font color="red">(???)</font>无效 TLBs或者 paging-structure
> caches中的条目独立于VMX operation (e.g., INVLPG, INVPCID)无效 linear mappings 
> 和 combined mappings。他们只需要为 current VPID 做这样的操作。（但是对于
> combined mappings, 会无效所有 EP4TAs相关)。对于当前 VPID Linear mapping
> 即使在 EPT 被使用的使用也可能invaliate。对于当前VPID 的 Combined mapping  在EPT
> 没有被使用的时候，也可能被 invalidate。

* An EPT violation invalidates any guest-physical mappings (associated with the
current EP4TA) that would be used to translate the guest-physical address that
caused the EPT violation. If that guest-physical address was the translation of
a linear address, the EPT violation also invalidates any combined mappings for
that linear address associated with the current PCID, the current VPID and the
current EP4TA.

> EPT violation 会 invalidate 所有 guest-physical mappings ( 和当前EP4TA
> 相关联的), 这些mapping用于翻译  造成本次 EPT violation 的GPA. 如果 
> 该GPA 是某个 linear address(GVA) 的 translation 的结果（也就是GVA翻译
> 成该GPA), EPT violation 也会无效对于该 liner address 并且和 当前PCID
> 相关的 combined mappings。

* If the "enable VPID" VM-execution control is 0, VM entries and VM exits
invalidate linear mappings and combined mappings associated with VPID 0000H
(for all PCIDs). Combined mappings for VPID 0000H are invalidated for all
EP4TAs.

> 如果 "enable VPID" VM-execution control 是0, VM entries 和 VM exits 会
> invalidate 和 VPID 000H(对于所有PCIDs) 相关的 linear mappings 和 combined 
> mappings. 对于VPID 000H 的 Combined mappings会无效全部的 EP4TAs。

* Execution of the INVVPID instruction invalidates linear mappings and combined
mappings. Invalidation is based on instruction operands, called the INVVPID
type and the INVVPID descriptor. Four INVVPID types are currently defined:
    > 执行 INVVPID 指令会无效linear mappings和 combined mappings. 该invalidation
    > 指令操作数。被称为 INVVPID type 和 INVVPID descriptor。目前定义了四种INVVPID 
    > type, 如下:
    + Individual-address. If the INVVPID type is 0, the logical processor
      invalidates linear mappings and combined mappings associated with the
      VPID specified in the INVVPID descriptor and that would be used to
      translate the linear address specified in of the INVVPID descriptor.
      Linear mappings and combined mappings for that VPID and linear address
      are invalidated for all PCIDs and, for combined mappings, all EP4TAs.
      (The instruction may also invalidate mappings associated with other VPIDs
      and for other linear addresses.)

      > 
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

The following items provide guidelines for use of the INVEPT instruction to
invalidate information cached from the EPT paging structures.


Software should use the INVEPT instruction with the “single-context” INVEPT
type after making any of the following changes to an EPT paging-structure entry
(the INVEPT descriptor should contain an EPTP value that references — directly
or indirectly — the modified EPT paging structure):

    — Changing any of the privilege bits 2:0 from 1 to 0.1
    — Changing the physical address in bits 51:12.
    — Clearing bit 8 (the accessed flag) if accessed and dirty flags for EPT
    will be enabled.
    — For an EPT PDPTE or an EPT PDE, changing bit 7 (which determines whether
    the entry maps a page).
    — For the last EPT paging-structure entry used to translate a
    guest-physical address (an EPT PDPTE with bit 7set to 1, an EPT PDE with
    bit 7 set to 1, or an EPT PTE), changing either bits 5:3 or bit 6. (These
    bits determine the effective memory type of accesses using that EPT
    paging-structure entry; see Section 29.3.7.)

    — For the last EPT paging-structure entry used to translate a
    guest-physical address (an EPT PDPTE with bit 7 set to 1, an EPT PDE with
    bit 7 set to 1, or an EPT PTE), clearing bit 9 (the dirty flag) if accessed
    and dirty flags for EPT will be enabled.

* Software should use the INVEPT instruction with the “single-context” INVEPT
type before a VM entry with an EPTP value X such that X[6] = 1 (accessed and
dirty flags for EPT are enabled) if the logical processor had earlier been in
VMX non-root operation with an EPTP value Y such that Y[6] = 0 (accessed and
dirty flags for EPT are not enabled) and Y[51:12] = X[51:12].

* Software may use the INVEPT instruction after modifying a present EPT
paging-structure entry (see Section 29.3.2) to change any of the privilege bits
2:0 from 0 to 1.2 Failure to do so may cause an EPT violation that would not
otherwise occur. Because an EPT violation invalidates any mappings that would
be used by the access that caused the EPT violation (see Section 29.4.3.1), an
EPT violation will not recur if the original access is performed again, even if
the INVEPT instruction is not executed.

* Because a logical processor does not cache any information derived from EPT
paging-structure entries that are not present (see Section 29.3.2) or
misconfigured (see Section 29.3.3.1), it is not necessary to execute INVEPT
following modification of an EPT paging-structure entry that had been not
present or misconfigured.

* As detailed in Section 30.4.5, an access to the APIC-access page might not
cause an APIC-access VM exit if software does not properly invalidate
information that may be cached from the EPT paging structures. If EPT was in
use on a logical processor at one time with EPTP X, it is recommended that
software use the INVEPT instruction with the “single-context” INVEPT type and
with EPTP X in the INVEPT descriptor before a VM entry on the same logical
processor that enables EPT with EPTP X and either (a) the “virtualize APIC
accesses” VM- execution control was changed from 0 to 1; or (b) the value of
the APIC-access address was changed.

* Software can use the INVEPT instruction with the “all-context” INVEPT type
immediately after execution of the VMXON instruction or immediately prior to
execution of the VMXOFF instruction. Either prevents potentially undesired
retention of information cached from EPT paging structures between separate
uses of VMX operation.

In a system containing more than one logical processor, software must account
for the fact that information from an EPT paging-structure entry may be cached
on logical processors other than the one that modifies that entry. The process
of propagating the changes to a paging-structure entry is commonly referred to
as “TLB shootdown.” A discussion of TLB shootdown appears in Section 4.10.5,
“Propagation of Paging-Structure Changes to Multiple Processors,” in the Intel®
64 and IA-32 Architectures Software Developer’s Manual, Volume 3A.
