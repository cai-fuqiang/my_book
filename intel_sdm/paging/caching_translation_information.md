# 4.10 CACHING TRANSLATION INFORMATION
The Intel-64 and IA-32 architectures may accelerate the address-translation
process by caching data from the paging structures on the processor. Because
the processor does not ensure that the data that it caches are always
consistent with the structures in memory, it is important for software
developers to understand how and when the processor may cache such data. They
should also understand what actions software can take to remove cached data
that may be inconsistent and when it should do so. This section provides
software developers information about the relevant processor operation.

> relevant /ˈreləvənt/ : 相关的;有关的
>
> Intel-64 和 IA-32 architectures 可以通过 处理器中的来自paging structures的
> caching data 来加速 address-translation.因为处理器不保证 cache 中的数据总是
> 和内存中的structures保持一致, 所以对于软件工程师来说理解处理器 如何/何时 
> 去 cache 这些数据。这些工程师也应该理解 软件执行什么操作可以移除已经不一致
> 的 cached data和什么时候应该做这样的事情。该章节提供给软件工程师相关的 
> processor operation 的信息。

Section 4.10.1 introduces process-context identifiers (PCIDs), which a logical
processor may use to distinguish information cached for different
linear-address spaces. Section 4.10.2 and Section 4.10.3 describe how the
processor may cache information in translation lookaside buffers (TLBs) and
paging-structure caches, respectively. Section 4.10.4 explains how software can
remove inconsistent cached information by invalidating portions of the TLBs and
paging-structure caches. Section 4.10.5 describes special considerations for
multiprocessor systems.

> Section 4.10.1 介绍了 process-context identifiers (PCIDs), logical processor
> 可以用其区分不同 liner-address space 的缓存信息。Section 4.10.2和 Section 
> 4.10.3 描述了 处理器如何将information分别缓存在 TLBs 和 paging-structure 
> cache中。Section 4.10.4 解释了 software 如何通过无效 TLBs && paging-structure
> caches的一部分来移除不一致的 cached information

## 4.10.1 Process-Context Identifiers (PCIDs)

Process-context identifiers (PCIDs) are a facility by which a logical processor
may cache information for multiple linear-address spaces. The processor may
retain cached information when software switches to a different linear-address
space with a different PCID (e.g., by loading CR3; see Section 4.10.4.1 for
details).

> PCIDs 是逻辑处理器可以缓存多个线性地址空间的信息的工具。当软件切换到具有不同
> PCID的不同线性地址空间时，处理器可以保留高速缓存的信息。(e.g, 通过 loading CR3;
> Section 4.10.4.1 有更多细节)

A PCID is a 12-bit identifier. Non-zero PCIDs are enabled by setting the PCIDE
flag (bit 17) of CR4. If CR4.PCIDE = 0, the current PCID is always 000H;
otherwise, the current PCID is the value of bits 11:0 of CR3.<sup>1</sup> Not
all processors allow CR4.PCIDE to be set to 1; see Section 4.1.4 for how to
determine whether this is allowed. The processor ensures that CR4.PCIDE can be
1 only in IA-32e mode (thus, 32-bit paging and PAE paging use only PCID 000H).
In addition, software can change CR4.PCIDE from 0 to 1 only if CR3[11:0] =
000H. These requirements are enforced by the following limitations on the MOV
CR instruction:

> PCID 是一个 12-bit 的标识符。Non-zero PCIDs 通过设置CR4.PCIDE[bit 17] 
> 标志位 enable。 如果 CR4.PCIDE = 0, 当前的PCID总是 000H;否则，当前的PCID是
> CR3.[11:0]。不是所有的处理器都允许 CR4.PCIDE设置为1; 请查看4.1.4 了解如何
> 确定该设置是否允许。处理器需要保证只有在 IA-32e mode中将 CR4.PCIDE设置为1
>（因此，32-bit paging 和PAE paging 只允许PCID 000H)。另外，软件只有在 
> CR3[11:0] = 000H的时候将CR4.PCIDE 0 -> 1。上面的这些需求会强制 MOV CR指令
> 有如下的限制:

* MOV to CR4 causes a general-protection exception (#GP) if it would change
 CR4.PCIDE from 0 to 1 and either IA32_EFER.LMA = 0 or CR3[11:0] ≠ 000H.
* MOV to CR0 causes a general-protection exception if it would clear CR0.PG to 0
 while CR4.PCIDE = 1.

> * 如果 将 CR4.PCIDE 0->1 && (IA32_EFER.LMA == 0 || CR3[11:0] != 000H),
> MOV to CR4 将导致 #GP (这里大家需要思考下为什么，个人感觉可能跟流水线
> 相关, 流水线中的load是使用的 PCID = 000H, 那么在执行MOV CR4.PCIDE[1] 
> to CR4后，而CR3中指示了其他的PCID，这时候，流水线需要重排。索性，intel
> 禁用了该行为。
>
> * 如果当CR4.PCIDE=1时，清除CR.PG, 将导致 #GP

When a logical processor creates entries in the TLBs (Section 4.10.2) and
paging-structure caches (Section 4.10.3), it associates those entries with the
current PCID. When using entries in the TLBs and paging-structure caches to
translate a linear address, a logical processor uses only those entries
associated with the current PCID (see Section 4.10.2.4 for an exception).

> 当逻辑处理器在TLBs中创建了 entries(Section 4.10.2)和paging-structure caches
> (Section 4.10.3), 它将这些entires和 当前的PCID 联系起来。当使用TLBs和paging-
> structure中的 entries来 翻译 线性地址时，逻辑处理器只能使用和当前PCID 匹配
> 的PCID(Section 4.10.2.4是例外)

If CR4.PCIDE = 0, a logical processor does not cache information for any PCID
other than 000H. This is because (1) if CR4.PCIDE = 0, the logical processor
will associate any newly cached information with the current PCID, 000H; and
(2) if MOV to CR4 clears CR4.PCIDE, all cached information is invalidated (see
Section 4.10.4.1).

> 如果CR4.PCIDE = 0, 逻辑处理器不会缓存除了PCID=000H以外的任何信息。这是因为
>
> 1. 如果CR4.PCIDE=0, 逻辑处理器将任何新产生的cached information 和 PCID 000H
> 相关联
> 2. 如果执行MOV to CR4 清空CR4.PCIDE,所有 cached information 将会被无效化(请
> 查看Section 4.10.4.1)
>> PS: 这里实际上阐述了为什么在PCIDE = 0时，逻辑处理器中没有缓存除了PCID==000H
>> 以外的缓存信息。(1)表明了产生新的cached information的时候，关联的是PCID 000H
>> (2) 表明在CR4.PCIDE刚被置为0的时候，所有缓存都被无效。所以也不会存在
>> PCID != 000H的entry

> NOTE
>
> In revisions of this manual that were produced when no processors allowed
> CR4.PCIDE to be set to 1, the Section “Caching Translation Information”
> discussed the caching of translation information without any reference to
> PCIDs. While the section now refers to PCIDs in its specification of this
> caching, this documentation change is not intended to imply any change to the
> behavior of processors that do not allow CR4.PCIDE to be set to 1.


## 4.10.2 Translation Lookaside Buffers (TLBs)

A processor may cache information about the translation of linear addresses in
translation lookaside buffers (TLBs). In general, TLBs contain entries that map
page numbers to page frames; these terms are defined in Section 4.10.2.1.
Section 4.10.2.2 describes how information may be cached in TLBs, and Section
4.10.2.3 gives details of TLB usage. Section 4.10.2.4 explains the global-page
feature, which allows software to indicate that certain translations should
receive special treatment when cached in the TLBs.

> 处理器可以在TLBs中缓存关于线性地址翻译的信息。通常的，TLBs包含 page number->
> page frame的entries; 这些术语在 Section 4.10.2.1中定义。Section 4.10.2.2描述
> 了这些信息如何在TLBs中缓存。(这句没有翻译通顺)，Section 4.10.2.3给出了关于TLB
> 用法的更多细节。Section 4.10.2.4 讲解了 global-page 特性，该特性允许software
> 指示某些translations当缓存到TLBs时候，应该受到特殊对待。

### 4.10.2.1 Page Numbers, Page Frames, and Page Offsets

Section 4.3, Section 4.4.2, and Section 4.5 give details of how the different
paging modes translate linear addresses to physical addresses. Specifically,
the upper bits of a linear address (called the page number) deter- mine the
upper bits of the physical address (called the page frame); the lower bits of
the linear address (called the page offset) determine the lower bits of the
physical address. The boundary between the page number and the page offset is
determined by the page size. Specifically:

* 32-bit paging:
    + If the translation does not use a PTE (because CR4.PSE = 1 and the PS 
    flag is 1 in the PDE used), the page size is 4 MBytes and the page number
    comprises bits 31:22 of the linear address.

    + If the translation does use a PTE, the page size is 4 KBytes and the page
    number comprises bits 31:12 of the linear address.

* PAE paging:
    If the translation does not use a PTE (because the PS flag is 1 in the PDE
    used), the page size is 2 MBytes and the page number comprises bits 31:21
    of the linear address.

     If the translation does use a PTE, the page size is 4 KBytes and the page
     number comprises bits 31:12 of the linear address.

* 4-level paging and 5-level paging:
    + If the translation does not use a PDE (because the PS flag is 1 in the
    PDPTE used), the page size is 1 GByte and the page number comprises bits
    47:30 of the linear address.
    + If the translation does use a PDE but does not uses a PTE (because the PS
    flag is 1 in the PDE used), the page size is 2 MBytes and the page number
    comprises bits 47:21 of the linear address.
    + If the translation does use a PTE, the page size is 4 KBytes and the page
    number comprises bits 47:12 of the linear address.
    + The page size identified by the preceding items may be reduced if there
     has been a restart of HLAT paging (see Section 4.5.5). Restart of HLAT
     paging always specifies a maximum page size; this page size is determined
     by the level of the paging-structure entry that caused the restart. The
     page size used by the translation is the minimum of the maximum page size
     specified by the restart and the page size determined by the restarted
     translation (as specified by the previous items).<br/> <br/>
     For example, suppose that HLAT paging encounters a PDE that sets bit 11,
     indicating a restart. As a result, the restart uses a maximum page size of
     2 MBytes. Suppose that the restarted translation encounters a PDPTE that
     sets bit 7, indicating a 1-GByte page. In this case, the translation
     produced will have a page size of 2 MBytes (the smaller of the two sizes).

### 4.10.2.2 Caching Translations in TLBs

The processor may accelerate the paging process by caching individual
translations in translation lookaside buffers (TLBs). Each entry in a TLB is an
individual translation. Each translation is referenced by a page number. It
contains the following information from the paging-structure entries used to
translate linear addresses with the page number:

* The physical address corresponding to the page number (the page frame).
 
* The access rights from the paging-structure entries used to translate linear
addresses with the page number (see Section 4.6):
    + The logical-AND of the R/W flags.
    + The logical-AND of the U/S flags.
    + The logical-OR of the XD flags (necessary only if IA32_EFER.NXE = 1).
    + The protection key (only with 4-level paging and 5-level paging).
* Attributes from a paging-structure entry that identifies the final page frame
for the page number (either a PTE or a paging-structure entry in which the PS
flag is 1):
    + The dirty flag (see Section 4.8).
    + The memory type (see Section 4.9).

(TLB entries may contain other information as well. A processor may implement
multiple TLBs, and some of these may be for special purposes, e.g., only for
instruction fetches. Such special-purpose TLBs may not contain some of this
information if it is not necessary. For example, a TLB used only for
instruction fetches need not contain infor- mation about the R/W and dirty
flags.)

As noted in Section 4.10.1, any TLB entries created by a logical processor are
associated with the current PCID. Processors need not implement any TLBs.
Processors that do implement TLBs may invalidate any TLB entry at any time.
Software should not rely on the existence of TLBs or on the retention of TLB
entries.

### 4.10.2.3 Details of TLB Use

Because the TLBs cache entries only for linear addresses with translations,
there can be a TLB entry for a page number only if the P flag is 1 and the
reserved bits are 0 in each of the paging-structure entries used to translate
that page number. In addition, the processor does not cache a translation for a
page number unless the accessed flag is 1 in each of the paging-structure
entries used during translation; before caching a translation, the processor
sets any of these accessed flags that is not already 1.

Subject to the limitations given in the previous paragraph, the processor may
cache a translation for any linear address, even if that address is not used to
access memory. For example, the processor may cache translations required for
prefetches and for accesses that result from speculative execution that would
never actually occur in the executed code path.

If the page number of a linear address corresponds to a TLB entry associated
with the current PCID, the processor may use that TLB entry to determine the
page frame, access rights, and other attributes for accesses to that linear
address. In this case, the processor may not actually consult the paging
structures in memory. The processor may retain a TLB entry unmodified even if
software subsequently modifies the relevant paging-structure entries in memory.
See Section 4.10.4.2 for how software can ensure that the processor uses the
modified paging-structure entries.


### 4.10.2.4 Global Pages

The Intel-64 and IA-32 architectures also allow for global pages when the PGE
flag (bit 7) is 1 in CR4. If the G flag (bit 8) is 1 in a paging-structure
entry that maps a page (either a PTE or a paging-structure entry in which the
PS flag is 1), any TLB entry cached for a linear address using that
paging-structure entry is considered to be global. Because the G flag is used
only in paging-structure entries that map a page, and because information from
such entries is not cached in the paging-structure caches, the global-page
feature does not affect the behavior of the paging-structure caches.

A logical processor may use a global TLB entry to translate a linear address,
even if the TLB entry is associated with a PCID different from the current
PCID.

## 4.10.3 Paging-Structure Caches

In addition to the TLBs, a processor may cache other information about the
paging structures in memory.

#### 4.10.3.1 Caches for Paging Structures

A processor may support any or all of the following paging-structure caches:

* PML5E cache (5-level paging only). Each PML5E-cache entry is referenced by a
 9-bit value and is used for linear addresses for which bits 56:48 have that
 value. The entry contains information from the PML5E used to translate such
 linear addresses:
    + The physical address from the PML5E (the address of the PML4 table).
    + The value of the R/W flag of the PML5E.
    + The value of the U/S flag of the PML5E.
    + The value of the XD flag of the PML5E.
    + The values of the PCD and PWT flags of the PML5E.
* The following items detail how a processor may use the PML5E cache:
    + If the processor has a PML5E-cache entry for a linear address, it may use
    that entry when translating the linear address (instead of the PML5E in
    memory).
    + The processor does not create a PML5E-cache entry unless the P flag is 1
    and all reserved bits are 0 in the PML5E in memory.
    + The processor does not create a PML5E-cache entry unless the accessed flag
    is 1 in the PML5E in memory; before caching a translation, the processor
    sets the accessed flag if it is not already 1.
    + The processor may create a PML5E-cache entry even if there are no
    translations for any linear address that might use that entry (e.g.,
    because the P flags are 0 in all entries in the referenced PML4 table).
    + If the processor creates a PML5E-cache entry, the processor may retain it
    unmodified even if software subsequently modifies the corresponding PML5E
    in memory.

* PML4E cache (4-level paging and 5-level paging only). The use of the PML4E
cache depends on the paging mode:<br/>
    + For 4-level paging, each PML4E-cache entry is referenced by a 9-bit value
    and is used for linear addresses for which bits 47:39 have that value.
    + For 5-level paging, each PML4E-cache entry is referenced by an 18-bit value
    and is used for linear addresses for which bits 56:39 have that value.

    A PML4E-cache entry contains information from the PML5E and PML4E used to
    translate the relevant linear addresses (for 4-level paging, the PML5E does
    not apply):
    + The physical address from the PML4E (the address of the
    page-directory-pointer table).
    + The logical-AND of the R/W flags in the PML5E and the PML4E.
    + The logical-AND of the U/S flags in the PML5E and the PML4E.
    + The logical-OR of the XD flags in the PML5E and the PML4E.
    + The values of the PCD and PWT flags of the PML4E.

    The following items detail how a processor may use the PML4E cache:
    + If the processor has a PML4E-cache entry for a linear address, it may use
    that entry when translating the linear address (instead of the PML5E and
    PML4E in memory).
    + The processor does not create a PML4E-cache entry unless the P flags are 1
    and all reserved bits are 0 in the PML5E and the PML4E in memory.
    + The processor does not create a PML4E-cache entry unless the accessed flags
    are 1 in the PML5E and the PML4E in memory; before caching a translation,
    the processor sets any accessed flags that are not already 1.
    + The processor may create a PML4E-cache entry even if there are no
    translations for any linear address that might use that entry (e.g.,
    because the P flags are 0 in all entries in the referenced
    page-directory-pointer table).
    + If the processor creates a PML4E-cache entry, the processor may retain it
    unmodified even if software subsequently modifies the corresponding PML4E
    in memory.

* PDPTE cache (4-level paging and 5-level paging only).1 The use of the PML4E
cache depends on the paging mode:
    + For 4-level paging, each PDPTE-cache entry is referenced by an 18-bit value
    and is used for linear addresses for which bits 47:30 have that value.
    + For 5-level paging, each PDPTE-cache entry is referenced by a 27-bit value
    and is used for linear addresses for which bits 56:30 have that value.

    A PDPTE-cache entry contains information from the PML5E, PML4E, PDPTE used
    to translate the relevant linear addresses (for 4-level paging, the PML5E
    does not apply):
    + The physical address from the PDPTE (the address of the page directory).
    (No PDPTE-cache entry is created for a PDPTE that maps a 1-GByte page.)
    
    + The logical-AND of the R/W flags in the PML5E, PML4E, and PDPTE.
    + The logical-AND of the U/S flags in the PML5E, PML4E, and PDPTE.
    + The logical-OR of the XD flags in the PML5E, PML4E, and PDPTE.
    + The values of the PCD and PWT flags of the PDPTE.

    The following items detail how a processor may use the PDPTE cache:
    + If the processor has a PDPTE-cache entry for a linear address, it may use
    that entry when translating the linear address (instead of the PML5E,
    PML4E, and PDPTE in memory).
    + The processor does not create a PDPTE-cache entry unless the P flags are 1,
    the PS flags are 0, and the reserved bits are 0 in the PML5E, PML4E, and
    PDPTE in memory.
    + The processor does not create a PDPTE-cache entry unless the accessed flags
    are 1 in the PML5E, PML4E, and PDPTE in memory; before caching a
    translation, the processor sets any accessed flags that are not already 1.
    + The processor may create a PDPTE-cache entry even if there are no
    translations for any linear address that might use that entry.
    + If the processor creates a PDPTE-cache entry, the processor may retain it
    unmodified even if software subsequently modifies the corresponding PML5E,
    PML4E, or PDPTE in memory.

* PDE cache. The use of the PDE cache depends on the paging mode:
    + For 32-bit paging, each PDE-cache entry is referenced by a 10-bit value and
    is used for linear addresses for which bits 31:22 have that value.
    + For PAE paging, each PDE-cache entry is referenced by an 11-bit value and
    is used for linear addresses for which bits 31:21 have that value.
    + For 4-level paging, each PDE-cache entry is referenced by a 27-bit value
    and is used for linear addresses for which bits 47:21 have that value.
    + For 5-level paging, each PDE-cache entry is referenced by a 36-bit value
    and is used for linear addresses for which bits 56:21 have that value.
    
    A PDE-cache entry contains information from the PML5E, PML4E, PDPTE, and
    PDE used to translate the relevant linear addresses (for 32-bit paging and
    PAE paging, only the PDE applies; for 4-level paging, the PML5E does not
    apply):
    + The physical address from the PDE (the address of the page table). (No
    PDE-cache entry is created for a PDE that maps a page.)
    + The logical-AND of the R/W flags in the PML5E, PML4E, PDPTE, and PDE.
    + The logical-AND of the U/S flags in the PML5E, PML4E, PDPTE, and PDE.
    + The logical-OR of the XD flags in the PML5E, PML4E, PDPTE, and PDE.
    + The values of the PCD and PWT flags of the PDE.

    The following items detail how a processor may use the PDE cache
    (references below to PML5Es, PML4Es, and PDPTEs apply only to 4-level
    paging and to 5-level paging, as appropriate):
    + If the processor has a PDE-cache entry for a linear address, it may use
    that entry when translating the linear address (instead of the PML5E,
    PML4E, PDPTE, and PDE in memory).
    + The processor does not create a PDE-cache entry unless the P flags are 1,
    the PS flags are 0, and the reserved bits are 0 in the PML5E, PML4E, PDPTE,
    and PDE in memory.
    + The processor does not create a PDE-cache entry unless the accessed flag is
    1 in the PML5E, PML4E, PDPTE, and PDE in memory; before caching a
    translation, the processor sets any accessed flags that are not already 1.
    + The processor may create a PDE-cache entry even if there are no
    translations for any linear address that might use that entry.
    + If the processor creates a PDE-cache entry, the processor may retain it
    unmodified even if software subse- quently modifies the corresponding
    PML5E, PML4E, PDPTE, or PDE in memory.

Information from a paging-structure entry can be included in entries in the
paging-structure caches for other paging-structure entries referenced by the
original entry. For example, if the R/W flag is 0 in a PML4E, then the R/W flag
will be 0 in any PDPTE-cache entry for a PDPTE from the page-directory-pointer
table referenced by that PML4E. This is because the R/W flag of each such
PDPTE-cache entry is the logical-AND of the R/W flags in the appropriate PML4E
and PDPTE.

On processors that support HLAT paging (see Section 4.5.1), each entry in a
paging-structure cache indicates whether the entry was cached during ordinary
paging or HLAT paging. When the processor commences linear- address translation
using ordinary paging (respectively, HLAT paging), it will use only entries
that indicate that they were cached during ordinary paging (respectively, HLAT
paging).

Entries that were cached during HLAT paging also include the restart flag (bit
11) of the original paging-structure entry. When the processor commences HLAT
paging using such an entry, it immediately restarts (using ordinary paging) if
this cached restart flag is 1.

The paging-structure caches contain information only from paging-structure
entries that reference other paging structures (and not those that map pages).
Because the G flag is not used in such paging-structure entries, the
global-page feature does not affect the behavior of the paging-structure
caches.

The processor may create entries in paging-structure caches for translations
required for prefetches and for accesses that are a result of speculative
execution that would never actually occur in the executed code path.

As noted in Section 4.10.1, any entries created in paging-structure caches by a
logical processor are associated with the current PCID.

A processor may or may not implement any of the paging-structure caches.
Software should rely on neither their presence nor their absence. The processor
may invalidate entries in these caches at any time. Because the processor may
create the cache entries at the time of translation and not update them
following subsequent modi- fications to the paging structures in memory,
software should take care to invalidate the cache entries appropri- ately when
causing such modifications. The invalidation of TLBs and the paging-structure
caches is described in Section 4.10.4.

### 4.10.3.2 Using the Paging-Structure Caches to Translate Linear Addresses

* When a linear address is accessed, the processor uses a procedure such as the
following to determine the physical address to which it translates and whether
the access should be allowed:
* If the processor finds a TLB entry that is for the page number of the linear
address and that is associated with the current PCID (or which is global), it
may use the physical address, access rights, and other attributes from that
entry.
* If the processor does not find a relevant TLB entry, it may use the upper bits
of the linear address to select an entry from the PDE cache that is associated
with the current PCID (Section 4.10.3.1 indicates which bits are used in each
paging mode). It can then use that entry to complete the translation process
(locating a PTE, etc.) as if it had traversed the PDE (and, for 4-level paging
and 5-level paging, the PDPTE, PML4E, and PML5E, as appropriate) corresponding
to the PDE-cache entry.

* The following items apply when 4-level paging or 5-level paging is used:

    + If the processor does not find a relevant TLB entry or PDE-cache entry, it
    may use the upper bits of the linear address (for 4-level paging, bits
    47:30; for 5-level paging, bits 56:30) to select an entry from the PDPTE
    cache that is associated with the current PCID. It can then use that entry
    to complete the translation process (locating a PDE, etc.) as if it had
    traversed the PDPTE, the PML4E, and (for 5-level paging) the PML5E
    corresponding to the PDPTE-cache entry.
    
    + If the processor does not find a relevant TLB entry, PDE-cache entry, or
    PDPTE-cache entry, it may use the upper bits of the linear address (for
    4-level paging, bits 47:39; for 5-level paging, bits 56:39) to select an
    entry from the PML4E cache that is associated with the current PCID. It can
    then use that entry to complete the translation process (locating a PDPTE,
    etc.) as if it had traversed the corresponding PML4E.
    
    + With 5-level paging, if the processor does not find a relevant TLB entry,
    PDE-cache entry, PDPTE-cache entry, or PML4E-cache entry, it may use bits
    56:48 of the linear address to select an entry from the PML5E cache that is
    associated with the current PCID. It can then use that entry to complete
    the translation process (locating a PML4E, etc.) as if it had traversed the
    corresponding PML5E.

(Any of the above steps would be skipped if the processor does not support the
cache in question.)

If the processor does not find a TLB or paging-structure-cache entry for the
linear address, it uses the linear address to traverse the entire
paging-structure hierarchy, as described in Section 4.3, Section 4.4.2, and
Section 4.5.

### 4.10.3.3 Multiple Cached Entries for a Single Paging-Structure Entry

The paging-structure caches and TLBs may contain multiple entries associated
with a single PCID and with infor- mation derived from a single
paging-structure entry. The following items give some examples for 4-level
paging:

* Suppose that two PML4Es contain the same physical address and thus reference
the same page-directory- pointer table. Any PDPTE in that table may result in
two PDPTE-cache entries, each associated with a different set of linear
addresses. Specifically, suppose that the n1th and n2th entries in the PML4
table contain the same physical address. This implies that the physical address
in the mth PDPTE in the page-directory-pointer table would appear in the
PDPTE-cache entries associated with both p1 and p2, where (p1 » 9) = n1, (p2 »
9) = n2, and (p1 & 1FFH) = (p2 & 1FFH) = m. This is because both PDPTE-cache
entries use the same PDPTE, one resulting from a reference from the n1th PML4E
and one from the n2th PML4E.

* Suppose that the first PML4E (i.e., the one in position 0) contains the
physical address X in CR3 (the physical address of the PML4 table). This
implies the following:

    + Any PML4-cache entry associated with linear addresses with 0 in bits 47:39
    contains address X.
    + Any PDPTE-cache entry associated with linear addresses with 0 in bits 47:30
    contains address X. This is because the translation for a linear address
    for which the value of bits 47:30 is 0 uses the value of bits 47:39 (0) to
    locate a page-directory-pointer table at address X (the address of the PML4
    table). It then uses the value of bits 38:30 (also 0) to find address X
    again and to store that address in the PDPTE-cache entry.
    + Any PDE-cache entry associated with linear addresses with 0 in bits 47:21
    contains address X for similar reasons.
    + Any TLB entry for page number 0 (associated with linear addresses with 0 in
    bits 47:12) translates to page frame X » 12 for similar reasons.

The same PML4E contributes its address X to all these cache entries because the
self-referencing nature of the entry causes it to be used as a PML4E, a PDPTE,
a PDE, and a PTE.

## 4.10.4 Invalidation of TLBs and Paging-Structure Caches

As noted in Section 4.10.2 and Section 4.10.3, the processor may create entries
in the TLBs and the paging-struc- ture caches when linear addresses are
translated, and it may retain these entries even after the paging structures
used to create them have been modified. To ensure that linear-address
translation uses the modified paging struc- tures, software should take action
to invalidate any cached entries that may contain information that has since
been modified.

### 4.10.4.1 Operations that Invalidate TLBs and Paging-Structure Caches

The following instructions invalidate entries in the TLBs and the
paging-structure caches:

* INVLPG. This instruction takes a single operand, which is a linear address. The
instruction invalidates any TLB entries that are for a page number
corresponding to the linear address and that are associated with the current
PCID. It also invalidates any global TLB entries with that page number,
regardless of PCID (see Section 4.10.2.4).1 INVLPG also invalidates all entries
in all paging-structure caches associated with the current PCID, regardless of
the linear addresses to which they correspond.

* INVPCID. The operation of this instruction is based on instruction operands,
called the INVPCID type and the INVPCID descriptor. Four INVPCID types are
currently defined:
    + Individual-address. If the INVPCID type is 0, the logical processor
    invalidates mappings—except global translations—associated with the PCID
    specified in the INVPCID descriptor and that would be used to translate the
    linear address specified in the INVPCID descriptor.2 (The instruction may
    also invalidate global translations, as well as mappings associated with
    other PCIDs and for other linear addresses.)
    + Single-context. If the INVPCID type is 1, the logical processor invalidates
    all mappings—except global translations—associated with the PCID specified
    in the INVPCID descriptor. (The instruction may also invalidate global
    translations, as well as mappings associated with other PCIDs.)
    + All-context, including globals. If the INVPCID type is 2, the logical
    processor invalidates mappings—including global translations—associated
    with all PCIDs.
    + All-context. If the INVPCID type is 3, the logical processor invalidates
    mappings—except global transla- tions—associated with all PCIDs. (The
    instruction may also invalidate global translations.)

    See Chapter 3 of the Intel 64 and IA-32 Architecture Software Developer’s
    Manual, Volume 2A for details of the INVPCID instruction.

* MOV to CR0. The instruction invalidates all TLB entries (including global
entries) and all entries in all paging- structure caches (for all PCIDs) if it
changes the value of CR0.PG from 1 to 0.
* MOV to CR3. The behavior of the instruction depends on the value of CR4.PCIDE:
    + If CR4.PCIDE = 0, the instruction invalidates all TLB entries associated
    with PCID 000H except those for global pages. It also invalidates all
    entries in all paging-structure caches associated with PCID 000H.
    + If CR4.PCIDE = 1 and bit 63 of the instruction’s source operand is 0, the
    instruction invalidates all TLB entries associated with the PCID specified
    in bits 11:0 of the instruction’s source operand except those for global
    pages. It also invalidates all entries in all paging-structure caches
    associated with that PCID. It is not required to invalidate entries in the
    TLBs and paging-structure caches that are associated with other PCIDs.
    + If CR4.PCIDE = 1 and bit 63 of the instruction’s source operand is 1, the
    instruction is not required to invalidate any TLB entries or entries in
    paging-structure caches.
* MOV to CR4. The behavior of the instruction depends on the bits being modified:
    + The instruction invalidates all TLB entries (including global entries) and
    all entries in all paging-structure caches (for all PCIDs) if (1) it
    changes the value of CR4.PGE;1 or (2) it changes the value of the CR4.PCIDE
    from 1 to 0.
    + The instruction invalidates all TLB entries and all entries in all
    paging-structure caches for the current PCID if (1) it changes the value of
    CR4.PAE; or (2) it changes the value of CR4.SMEP from 0 to 1.

* Task switch. If a task switch changes the value of CR3, it invalidates all TLB
entries associated with PCID 000H except those for global pages. It also
invalidates all entries in all paging-structure caches associated with PCID
000H.2
* VMX transitions. See Section 4.11.1.

The processor is always free to invalidate additional entries in the TLBs and
paging-structure caches. The following are some examples:

* INVLPG may invalidate TLB entries for pages other than the one corresponding to
its linear-address operand. It may invalidate TLB entries and
paging-structure-cache entries associated with PCIDs other than the current
PCID.
* INVPCID may invalidate TLB entries for pages other than the one corresponding
to the specified linear address. It may invalidate TLB entries and
paging-structure-cache entries associated with PCIDs other than the specified
PCID.
* MOV to CR0 may invalidate TLB entries even if CR0.PG is not changing. For
example, this may occur if either CR0.CD or CR0.NW is modified.
* MOV to CR3 may invalidate TLB entries for global pages. If CR4.PCIDE = 1 and
bit 63 of the instruction’s source operand is 0, it may invalidate TLB entries
and entries in the paging-structure caches associated with PCIDs other than the
PCID it is establishing. It may invalidate entries if CR4.PCIDE = 1 and bit 63
of the instruction’s source operand is 1.
* MOV to CR4 may invalidate TLB entries when changing CR4.PSE or when changing
CR4.SMEP from 1 to 0.
* On a processor supporting Hyper-Threading Technology, invalidations performed
on one logical processor may invalidate entries in the TLBs and
paging-structure caches used by other logical processors.

(Other instructions and operations may invalidate entries in the TLBs and the
paging-structure caches, but the instructions identified above are
recommended.)

In addition to the instructions identified above, page faults invalidate
entries in the TLBs and paging-structure caches. In particular, a page-fault
exception resulting from an attempt to use a linear address will invalidate any
TLB entries that are for a page number corresponding to that linear address and
that are associated with the current PCID. It also invalidates all entries in
the paging-structure caches that would be used for that linear address and that
are associated with the current PCID.3 These invalidations ensure that the
page-fault exception will not recur (if the faulting instruction is
re-executed) if it would not be caused by the contents of the paging structures
in memory (and if, therefore, it resulted from cached entries that were not
invalidated after the paging structures were modified in memory).

As noted in Section 4.10.2, some processors may choose to cache multiple
smaller-page TLB entries for a transla- tion specified by the paging structures
to use a page larger than 4 KBytes. There is no way for software to be aware
that multiple translations for smaller pages have been used for a large page.
The INVLPG instruction and page faults provide the same assurances that they
provide when a single TLB entry is used: they invalidate all TLB entries
corresponding to the translation specified by the paging structures.

### 4.10.4.2 Recommended Invalidation

The following items provide some recommendations regarding when software should
perform invalidations:

* If software modifies a paging-structure entry that maps a page (rather than
referencing another paging structure), it should execute INVLPG for any linear
address with a page number whose translation uses that paging-structure entry.1
* (If the paging-structure entry may be used in the translation of different page
numbers — see Section 4.10.3.3 — software should execute INVLPG for linear
addresses with each of those page numbers; alternatively, it could use MOV to
CR3 or MOV to CR4.)

* If software modifies a paging-structure entry that references another paging
structure, it may use one of the following approaches depending upon the types
and number of translations controlled by the modified entry:
    + Execute INVLPG for linear addresses with each of the page numbers with
    translations that would use the entry. However, if no page numbers that
    would use the entry have translations (e.g., because the P flags are 0 in
    all entries in the paging structure referenced by the modified entry), it
    remains necessary to execute INVLPG at least once.
    + Execute MOV to CR3 if the modified entry controls no global pages.
    + Execute MOV to CR4 to modify CR4.PGE.
* If CR4.PCIDE = 1 and software modifies a paging-structure entry that does not
map a page or in which the G flag (bit 8) is 0, additional steps are required
if the entry may be used for PCIDs other than the current one. Any one of the
following suffices:
    + Execute MOV to CR4 to modify CR4.PGE, either immediately or before again
    using any of the affected PCIDs. For example, software could use different
    (previously unused) PCIDs for the processes that used the affected PCIDs.
    + For each affected PCID, execute MOV to CR3 to make that PCID current (and
    to load the address of the appropriate PML4 table). If the modified entry
    controls no global pages and bit 63 of the source operand to MOV to CR3 was
    0, no further steps are required. Otherwise, execute INVLPG for linear
    addresses with each of the page numbers with translations that would use
    the entry; if no page numbers that would use the entry have translations,
    execute INVLPG at least once.

* If software using PAE paging modifies a PDPTE, it should reload CR3 with the
register’s current value to ensure that the modified PDPTE is loaded into the
corresponding PDPTE register (see Section 4.4.1).

* If the nature of the paging structures is such that a single entry may be used
for multiple purposes (see Section 4.10.3.3), software should perform
invalidations for all of these purposes. For example, if a single entry might
serve as both a PDE and PTE, it may be necessary to execute INVLPG with two (or
more) linear addresses, one that uses the entry as a PDE and one that uses it
as a PTE. (Alternatively, software could use MOV to CR3 or MOV to CR4.)

* As noted in Section 4.10.2, the TLBs may subsequently contain multiple
translations for the address range if software modifies the paging structures
so that the page size used for a 4-KByte range of linear addresses changes. A
reference to a linear address in the address range may use any of these
translations.<br/>
Software wishing to prevent this uncertainty should not write to a
paging-structure entry in a way that would change, for any linear address, both
the page size and either the page frame, access rights, or other attributes. It
can instead use the following algorithm: first clear the P flag in the relevant
paging-structure entry (e.g., PDE); then invalidate any translations for the
affected linear addresses (see above); and then modify the relevant
paging-structure entry to set the P flag and establish modified translation(s)
for the new page size.

Software should clear bit 63 of the source operand to a MOV to CR3 instruction
that establishes a PCID that had been used earlier for a different
linear-address space (e.g., with a different value in bits 51:12 of CR3). This
ensures invalidation of any information that may have been cached for the
previous linear-address space.

This assumes that both linear-address spaces use the same global pages and that
it is thus not necessary to invalidate any global TLB entries. If that is not
the case, software should invalidate those entries by executing MOV to CR4 to
modify CR4.PGE.

### 4.10.4.3 Optional Invalidation

The following items describe cases in which software may choose not to
invalidate and the potential consequences of that choice:

* If a paging-structure entry is modified to change the P flag from 0 to 1, no
invalidation is necessary. This is because no TLB entry or paging-structure
cache entry is created with information from a paging-structure entry in which
the P flag is 0.1
* If a paging-structure entry is modified to change the accessed flag from 0 to
1, no invalidation is necessary (assuming that an invalidation was performed
the last time the accessed flag was changed from 1 to 0). This is because no
TLB entry or paging-structure cache entry is created with information from a
paging-structure entry in which the accessed flag is 0.
* If a paging-structure entry is modified to change the R/W flag from 0 to 1,
failure to perform an invalidation may result in a “spurious” page-fault
exception (e.g., in response to an attempted write access) but no other adverse
behavior. Such an exception will occur at most once for each affected linear
address (see Section 4.10.4.1).
* If CR4.SMEP = 0 and a paging-structure entry is modified to change the U/S
flag from 0 to 1, failure to perform an invalidation may result in a “spurious”
page-fault exception (e.g., in response to an attempted user-mode access) but
no other adverse behavior. Such an exception will occur at most once for each
affected linear address (see Section 4.10.4.1).
* If a paging-structure entry is modified to change the XD flag from 1 to 0,
failure to perform an invalidation may result in a “spurious” page-fault
exception (e.g., in response to an attempted instruction fetch) but no other
adverse behavior. Such an exception will occur at most once for each affected
linear address (see Section 4.10.4.1).
* If a paging-structure entry is modified to change the accessed flag from 1 to
0, failure to perform an invali- dation may result in the processor not setting
that bit in response to a subsequent access to a linear address whose
translation uses the entry. Software cannot interpret the bit being clear as an
indication that such an access has not occurred.
* If software modifies a paging-structure entry that identifies the final
physical address for a linear address (either a PTE or a paging-structure entry
in which the PS flag is 1) to change the dirty flag from 1 to 0, failure to
perform an invalidation may result in the processor not setting that bit in
response to a subsequent write to a linear address whose translation uses the
entry. Software cannot interpret the bit being clear as an indication that such
a write has not occurred.
* The read of a paging-structure entry in translating an address being used to
fetch an instruction may appear to execute before an earlier write to that
paging-structure entry if there is no serializing instruction between the write
and the instruction fetch. Note that the invalidating instructions identified
in Section 4.10.4.1 are all serializing instructions.
* Section 4.10.3.3 describes situations in which a single paging-structure entry
may contain information cached in multiple entries in the paging-structure
caches. Because all entries in these caches are invalidated by any execution of
INVLPG, it is not necessary to follow the modification of such a
paging-structure entry by executing INVLPG multiple times solely for the
purpose of invalidating these multiple cached entries. (It may be necessary to
do so to invalidate multiple TLB entries.)

### 4.10.4.4 Delayed Invalidation Required invalidations may be delayed under
some circumstances. Software developers should understand that, between the
modification of a paging-structure entry and execution of the invalidation
instruction recommended in Section 4.10.4.2, the processor may use translations
based on either the old value or the new value of the paging- structure entry.
The following items describe some of the potential consequences of delayed
invalidation:

* If a paging-structure entry is modified to change the P flag from 1 to 0, an
access to a linear address whose translation is controlled by this entry may or
may not cause a page-fault exception.

* If a paging-structure entry is modified to change the R/W flag from 0 to 1,
write accesses to linear addresses whose translation is controlled by this
entry may or may not cause a page-fault exception.

* If a paging-structure entry is modified to change the U/S flag from 0 to 1,
user-mode accesses to linear addresses whose translation is controlled by this
entry may or may not cause a page-fault exception.

* If a paging-structure entry is modified to change the XD flag from 1 to 0,
instruction fetches from linear addresses whose translation is controlled by
this entry may or may not cause a page-fault exception.

As noted in Section 9.1.1, an x87 instruction or an SSE instruction that
accesses data larger than a quadword may be implemented using multiple memory
accesses. If such an instruction stores to memory and invalidation has been
delayed, some of the accesses may complete (writing to memory) while another
causes a page-fault excep- tion.1 In this case, the effects of the completed
accesses may be visible to software even though the overall instruc- tion
caused a fault.

In some cases, the consequences of delayed invalidation may not affect software
adversely. For example, when freeing a portion of the linear-address space (by
marking paging-structure entries “not present”), invalidation using INVLPG may
be delayed if software does not re-allocate that portion of the linear-address
space or the memory that had been associated with it. However, because of
speculative execution (or errant software), there may be accesses to the freed
portion of the linear-address space before the invalidations occur. In this
case, the following can happen:

* Reads can occur to the freed portion of the linear-address space. Therefore,
invalidation should not be delayed for an address range that has read side
effects.

* The processor may retain entries in the TLBs and paging-structure caches for an
extended period of time. Software should not assume that the processor will not
use entries associated with a linear address simply because time has passed.

* As noted in Section 4.10.3.1, the processor may create an entry in a
paging-structure cache even if there are no translations for any linear address
that might use that entry. Thus, if software has marked “not present” all
entries in a page table, the processor may subsequently create a PDE-cache
entry for the PDE that references that page table (assuming that the PDE itself
is marked “present”).

* If software attempts to write to the freed portion of the linear-address space,
the processor might not generate a page fault. (Such an attempt would likely be
the result of a software error.) For that reason, the page frames previously
associated with the freed portion of the linear-address space should not be
reallocated for another purpose until the appropriate invalidations have been
performed.

## 4.10.5 Propagation of Paging-Structure Changes to Multiple Processors As
noted in Section 4.10.4, software that modifies a paging-structure entry may
need to invalidate entries in the TLBs and paging-structure caches that were
derived from the modified entry before it was modified. In a system containing
more than one logical processor, software must account for the fact that there
may be entries in the TLBs and paging-structure caches of logical processors
other than the one used to modify the paging-structure entry. The process of
propagating the changes to a paging-structure entry is commonly referred to as
“TLB shoot- down.” TLB shootdown can be done using memory-based semaphores
and/or interprocessor interrupts (IPI). The following items describe a simple
but inefficient example of a TLB shootdown algorithm for processors supporting
the Intel-64 and IA-32 architectures:

1. Begin barrier: Stop all but one logical processor; that is, cause all but
   one to execute the HLT instruction or to enter a spin loop.
2. Allow the active logical processor to change the necessary paging-structure
   entries.
3. Allow all logical processors to perform invalidations appropriate to the
   modifications to the paging-structure entries.
4. Allow all logical processors to resume normal operation.



Alternative, performance-optimized, TLB shootdown algorithms may be developed;
however, software developers must take care to ensure that the following
conditions are met:

* All logical processors that are using the paging structures that are being
modified must participate and perform appropriate invalidations after the
modifications are made.
* If the modifications to the paging-structure entries are made before the
barrier or if there is no barrier, the operating system must ensure one of the
following: (1) that the affected linear-address range is not used between the
time of modification and the time of invalidation; or (2) that it is prepared
to deal with the conse- quences of the affected linear-address range being used
during that period. For example, if the operating system does not allow pages
being freed to be reallocated for another purpose until after the required
invalida- tions, writes to those pages by errant software will not unexpectedly
modify memory that is in use.
* Software must be prepared to deal with reads, instruction fetches, and prefetch
requests to the affected linear- address range that are a result of speculative
execution that would never actually occur in the executed code path.

When multiple logical processors are using the same linear-address space at the
same time, they must coordinate before any request to modify the
paging-structure entries that control that linear-address space. In these
cases, the barrier in the TLB shootdown routine may not be required. For
example, when freeing a range of linear addresses, some other mechanism can
assure no logical processor is using that range before the request to free it
is made. In this case, a logical processor freeing the range can clear the P
flags in the PTEs associated with the range, free the physical page frames
associated with the range, and then signal the other logical processors using
that linear-address space to perform the necessary invalidations. All the
affected logical processors must complete their invalidations before the
linear-address range and the physical page frames previously associated with
that range can be reallocated.
