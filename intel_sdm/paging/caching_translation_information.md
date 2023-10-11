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
> (Section 4.10.3), 它将这些entries和 当前的PCID 联系起来。当使用TLBs和paging-
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
the upper bits of a linear address (called the page number) determine the
upper bits of the physical address (called the page frame); the lower bits of
the linear address (called the page offset) determine the lower bits of the
physical address. The boundary between the page number and the page offset is
determined by the page size. Specifically:

> Section 4.3, Section 4.4.2 和 Section 4.5 给出了不同的paging mode 是如何将
> liner address 翻译成 physical address。确切的说，线性地址的高位(被称为 page 
> number)决定了 phyiscal address的高位(被称为 page frame);线性地址的低位(被称为
> page offset)决定了物理地址的低位。page number和page offset的边界由 page size
> 决定。确切的说:

* 32-bit paging:
    + If the translation does not use a PTE (because CR4.PSE = 1 and the PS 
    flag is 1 in the PDE used), the page size is 4 MBytes and the page number
    comprises bits 31:22 of the linear address.
    > 如果使用了PDE 大页, page size = 4M,  page number : LA[31:22]

    + If the translation does use a PTE, the page size is 4 KBytes and the page
    number comprises bits 31:12 of the linear address.
    > 如果 使用 PTE, page size = 4K, page number : LA[31:12]

* PAE paging:
    + If the translation does not use a PTE (because the PS flag is 1 in the PDE
    used), the page size is 2 MBytes and the page number comprises bits 31:21
    of the linear address.
    > 使用PDE大页，page size = 2M , page number : LA[31:22]

    + If the translation does use a PTE, the page size is 4 KBytes and the page
    number comprises bits 31:12 of the linear address.
    > 如果使用PTE，page size = 4K, page number : LA[31:12]

* 4-level paging and 5-level paging:
    + If the translation does not use a PDE (because the PS flag is 1 in the
    PDPTE used), the page size is 1 GByte and the page number comprises bits
    47:30 of the linear address.
    > 如果使用PDPTE大页，page size = 1G, page number : LA[47:30]
    + If the translation does use a PDE but does not uses a PTE (because the PS
    flag is 1 in the PDE used), the page size is 2 MBytes and the page number
    comprises bits 47:21 of the linear address.
    > 如果使用PDE 大页， page size = 2M, page number : LA [47:21]
    + If the translation does use a PTE, the page size is 4 KBytes and the page
    number comprises bits 47:12 of the linear address.
    > 如果使用PTE，page size = 4K, page number : LA[47:12]
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
     > <font color="red">
     > 以上和HLAT相关，先不看
     > </font>

### 4.10.2.2 Caching Translations in TLBs

The processor may accelerate the paging process by caching individual
translations in translation lookaside buffers (TLBs). Each entry in a TLB is an
individual translation. Each translation is referenced by a page number. It
contains the following information from the paging-structure entries used to
translate linear addresses with the page number:

> 处理器可以通过在 TLBs中缓存单独的 translations加速 paging
> process。TLB中的每个 entry是一个单独的translation.每一个 translation
> 由一个page number 引用。它包含来自 paging-structure entries
> 的以下信息，这些信息用于将线性地址与页码进行转换：

* The physical address corresponding to the page number (the page frame).
> 物理地址所对应的 page number (page frame)
>
>> NOTE: 这里我觉得page number和 page frame都包含了，本身TLB就是为了实现
>> page number->page frame的翻译
* The access rights from the paging-structure entries used to translate linear
addresses with the page number (see Section 4.6):
    + The logical-AND of the R/W flags.
    + The logical-AND of the U/S flags.
    + The logical-OR of the XD flags (necessary only if IA32_EFER.NXE = 1).
    + The protection key (only with 4-level paging and 5-level paging).
> 用于该page number线性地址翻译的 paging-structure entries的 access rights
>> 这些会将各个层级的access right flags进行 logical-AND/OR操作

* Attributes from a paging-structure entry that identifies the final page frame
for the page number (either a PTE or a paging-structure entry in which the PS
flag is 1):
    + The dirty flag (see Section 4.8).
    + The memory type (see Section 4.9).
> 最后一个层级的paging-structure entry的某些属性:
>> 这些属性之后在最后一个层级中有
>>
>> 最后一个层级是指: 该页表项不再指向页表，而是指向最终的page frame

> NOTE:
>
> 这里我们思考下，为什么页表中那么多项，结果tlb
> 中就只包含这些，原因很简单，因为在address translate的过程中，只
> 用到了这些。而TLB/paging structure cache的作用，也是加速该过程。

(TLB entries may contain other information as well. A processor may implement
multiple TLBs, and some of these may be for special purposes, e.g., only for
instruction fetches. Such special-purpose TLBs may not contain some of this
information if it is not necessary. For example, a TLB used only for
instruction fetches need not contain information about the R/W and dirty
flags.)

> (TLB entries 中也可能包含其他的信息。处理器可能实现了multiple TLBs和用于某些
> 特定目的信息。例如, 只是用于指令预取。某些特定目的的TLBs可能不包含某些不必要
> 的信息，例如，仅用于指令预取的的TLB不必包含关于R/W和dirty flags的相关信息。
>
> 关于 multiple TLBs 的一些解释:
>
> [Address translation with multiple pagesize-specific TLBs](https://stackoverflow.com/questions/49842530/address-translation-with-multiple-pagesize-specific-tlbs)

As noted in Section 4.10.1, any TLB entries created by a logical processor are
associated with the current PCID. Processors need not implement any TLBs.
Processors that do implement TLBs may invalidate any TLB entry at any time.
Software should not rely on the existence of TLBs or on the retention of TLB
entries.
> retention  [rɪˈtenʃn] : 保留; 保持; 
>
> 正如Section 4.10.1中提到的, 逻辑处理器创建任何 TLB entries都要和当前的PCID
> 相关联。处理器不需要实现任何 TLBs（**这里指不必须么?**)。实现TLB的处理器可以
> 在任何时候invalidate 任意的TLB。软件不应该依赖TLB的存在或者TLB entries的保留。

### 4.10.2.3 Details of TLB Use

Because the TLBs cache entries only for linear addresses with translations,
there can be a TLB entry for a page number only if the P flag is 1 and the
reserved bits are 0 in each of the paging-structure entries used to translate
that page number. In addition, the processor does not cache a translation for a
page number unless the accessed flag is 1 in each of the paging-structure
entries used during translation; before caching a translation, the processor
sets any of these accessed flags that is not already 1.

> 因为TLBs cache entries 仅用于线性地址翻译，所以对于一个 page number 能够
> 作为TLB entry的条件是，只有当P flags = 1 并且每个用于 translate 该 page
> number 的 paging-structure entries的 reserved bit 都是0。另外，处理器
> 只有在每个用于 该translation的 paging-structure entries的accessed 
> flags是1的情况下才会cache 该 translation; 在 cache 该translation之前，
> 处理器 会设置这些accessed flags不是1的entries, 将accessed flags 设置为1.

Subject to the limitations given in the previous paragraph, the processor may
cache a translation for any linear address, even if that address is not used to
access memory. For example, the processor may cache translations required for
prefetches and for accesses that result from speculative execution that would
never actually occur in the executed code path.

> Subject to : 从属于; 使服从; 处于...中
>
> 受上之前章节中提到的限制的影响，处理器可能缓存对于 任意线性地址的 translation,
> 即使该address不再用于 access memory。例如，处理器在prefetches或者在
> speculative evecution，而该 speculative execution从未实际的发生在代码执行
> 路径中，这样的情况下，需要cache translation

If the page number of a linear address corresponds to a TLB entry associated
with the current PCID, the processor may use that TLB entry to determine the
page frame, access rights, and other attributes for accesses to that linear
address. In this case, the processor may not actually consult the paging
structures in memory. The processor may retain a TLB entry unmodified even if
software subsequently modifies the relevant paging-structure entries in memory.
See Section 4.10.4.2 for how software can ensure that the processor uses the
modified paging-structure entries.

> 如果线性地址的 page number 和 某个 关联了当前PCID的TLB entry 相匹配，处理器
> 将会使用该TLB entry 确定 page frame, access rights和其他用于访问线性地址的
> attributes。在这种情况下，处理器可能不会实际查询内存中的paging structures.
> 处理器可能保持TLB entry没有更改，即使在软件已经修改了内存中的相应的 paging-
> structure entries的情况下。查看Section 4.10.4.2 了解软件如何保证处理器使用
> 修改后的 paging-structure entries。

If the paging structures specify a translation using a page larger than 4
KBytes, some processors may cache multiple smaller-page TLB entries for that
translation. Each such TLB entry would be associated with a page number
corresponding to the smaller page size (e.g., bits 47:12 of a linear address
with 4-level paging), even though part of that page number (e.g., bits 20:12)
is part of the offset with respect to the page specified by the paging
structures. The upper bits of the physical address in such a TLB entry are
derived from the physical address in the PDE used to create the translation,
while the lower bits come from the linear address of the access for which the
translation is created. There is no way for software to be aware that multiple
translations for smaller pages have been used for a large page. For example, an
execution of INVLPG for a linear address on such a page invalidates any and
all smaller-page TLB entries for the translation of any linear address on that
page.

> 如果paging stuctures 指定了一个使用大于4Kbyte page 的 translation, 某些处理器
> 可能缓存了多个 smaller-page TLB entries。每个这样的TLB entry关联一个相对应的更小
> page size的 page number(e.g., 4-level paging 线性地址的[47:12]), 即使page number
> 的是相对于 paging structure指定的 页面偏移的一部分。这些TLB entry中的物理地址的
> 高位是从用于创建translation的 PDE 中的物理地址导出的，而低位来自于为其创建 
> tranlation 的访问的线性地址。(翻译的有点别扭，大概是PDE 提供翻译后物理地址的高位，
> 线性地址提供翻译后物理地址的低位,实际上就是大页的翻译)。软件无法意识到小页面的
> multiple translation 已用于大页面。例如，对于一个页面上的线性地址执行 INVLPG 
> 指令, 会无效任何用于该页面上线性地址翻译的任何TLBs和所有的 smaller-page的 TLB
> entries

If software modifies the paging structures so that the page size used for a
4-KByte range of linear addresses changes, the TLBs may subsequently contain
multiple translations for the address range (one for each page size). A
reference to a linear address in the address range may use any of these
translations. Which translation is used may vary from one execution to another,
and the choice may be implementation-specific.

> 如果软件修改了 paging structures 导致了用于4-KByte range 的page size的改变，
> TLBs 接下来可能会含有对于该 address range (每个 page size 一个)的多个 
> translation。哪种 translation 被使用可能因 execution 不同而不同，也可能
> 根据  implementation-specific 选择。
>
>> NOTE:
>>
>> 这里是说，之前页面大小为4Kbyte, 可能有多个连续的页面都创建了TLB entry，
>> 这时如果将其修改为大页，那么对于该大页的某些地址的访问，就会有 multiple 
>> hits。
>>
>> 举个例子:
>> 1. 虚拟地址0x1是4KByte映射，现在访问该地址，那么在4KByte
>> TLB中就会创建对应的entry
>> 2. 现在将其页修改为大页([0, 2M]为一个大页), 此时访问0x1001, 
>> 那么在2M TLB中就会创建对应的entry
>> 3. 现在继续访问0x1地址，那么就会在4KByte 和2M TLB中均会命中。
>> 
>> 在上面给出的链接中，提到了关于TLB不同的实现方式，个人感觉无论那种方式的
>> 实现都可能存在这个问题，原因就在于，当MMU拿到一个线性地址时，该线性地址
>> 所转换成的最终的页面是否是大页，在线性地址中表现不出来，只能从 final paging-
>> structure entry中获取。所以MMU拿到线性地址不会去关心其是大页还是normal
>> size page。

### 4.10.2.4 Global Pages

The Intel-64 and IA-32 architectures also allow for global pages when the PGE
flag (bit 7) is 1 in CR4. If the G flag (bit 8) is 1 in a paging-structure
entry that maps a page (either a PTE or a paging-structure entry in which the
PS flag is 1), any TLB entry cached for a linear address using that
paging-structure entry is considered to be global. Because the G flag is used
only in paging-structure entries that map a page, and because information from
such entries is not cached in the paging-structure caches, the global-page
feature does not affect the behavior of the paging-structure caches.

> Intel-64和IA-32架构允许 global poages, 当 CR4 的PGE flags(BIT 7) 为1.
> 如果映射page的 paging-stuctures entry的 G flags(bit 8) 为1 （指 PTE 
> 或者PS flags为1 的paging-structure entry), 任何对于缓存该paging-structure 
> entry的线性地址TLB entry 被认为 global。因为只有在映射页面的paging-structure
> entry使用了 G flags, 并且因为这些entries 并不缓存在 paging-structure caches,
> 所以 global-page feature 不会影响paging-structure cache的行为。

A logical processor may use a global TLB entry to translate a linear address,
even if the TLB entry is associated with a PCID different from the current
PCID.

> 逻辑处理器可能使用 global TLB entry 去翻译线性地址，即使该TLB entry相关的
> PCID 和当前的PCID 不同。

## 4.10.3 Paging-Structure Caches

In addition to the TLBs, a processor may cache other information about the
paging structures in memory.

> 除了TLBs之外，处理器可能缓存内存中关于 paging strucuture的其他信息。

#### 4.10.3.1 Caches for Paging Structures

A processor may support any or all of the following paging-structure caches:

> 处理器可能支持下面任意的或者所有的 paging-structure caches的

* PML5E cache (5-level paging only). Each PML5E-cache entry is referenced by a
 9-bit value and is used for linear addresses for which bits 56:48 have that
 value. The entry contains information from the PML5E used to translate such
 linear addresses:
    + The physical address from the PML5E (the address of the PML4 table).
    + The value of the R/W flag of the PML5E.
    + The value of the U/S flag of the PML5E.
    + The value of the XD flag of the PML5E.
    + The values of the PCD and PWT flags of the PML5E.
 
    The following items detail how a processor may use the PML5E cache:
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
 > PML5E cache: 每个 PML5E-cache entry 都由一个 9-bit 的值引用并且用于bit[56:48]
 > 具有改值的线性地址。该entry包含了来自用于翻译这些线性地址的PML5E的信息:
 >   + PML4 table physical address 
 >   + R/W, U/S, XD, PCD && PWD
 >
 > 下面的items描述了处理器将会如何使用 PML5E cache:
 > + 如果处理器有线性地址的 PML5E-cache entry, 当翻译线性地址时，他可以使用该entry(
 > 而不是使用memory中的PML5E）
 > + 处理器将只有在内存中的PML5E的 P flags = 1 并且所有的预留位都是0的情况下，才创建
 > PML5E-cache entry
 > + 只有 内存中的 PML5E 的access flag 为1的情况下，才会创建 PML5E-cache entry;
 > 在缓存 translation之前，处理器会设置不是1的accessd flags 为 1
 > + 处理器可能创建 PML5E-cache entry 即使没有任何线性地址 translation 使用它（e.g.,
 > 因为其指向的PML4 table的所有entry的 P flags都是0。
 > + 如果 processor 创建了 PML5E-cache entry, 处理器可能保持其不变，即使软件接下来修改
 > 内存中相应的 PML5E。
 >
 >> NOTE
 >> 
 >> 这里所描述的 9-bit的引用，表示其cache的tag。

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
> 该部分大部分同上，不再赘述，当时需要注意下面几点:
> * 用于引用的bits：例如在5-level page中，用于引用的bits为[56:39] 为18-bits
> * PML4E-cache entry中包含的某些flags, 例如 R/W, U/S ..., 这些flags在cache entry
> 中保存的是 PML5E && PML4E 的值的 logical-AND / logical-OR
>> 这样做是为什么呢? 下面章节 `Using the Paging-Structure Caches to Translate 
>> Linear Addresses`会介绍，和Table walk不同，paging-structure cache的查询顺序是
>> 相反的: Table walk (PML5E, PML4E, PDPTE, PDE, PTE) paging-structure cache(TLB,
>> PDE cache, PDPTE cache, PML4E cache, PML5E cache) (当然TLB也是这样缓存flag的)
>> 这样低级的页表缓存需要包含上级页表的所有信息，而这些信息线性地址 translation
>> 中仅需要关心其logical-AND/ logical-OR的结果。同样用于引用的bits也是相当于正向
>> TLB walk 所需要的虚拟地址的 bits。这个cache也可以认为，将 PML5E->PML4E的
>> table walk的结果缓存了。并不是缓存了PML4E中的某个entry。同样PDE cache 则是
>> 将 PML5E->PML4E->PDPTE->PDE table walk的结果缓存。
> * 创建PML4E-cache entry时，需要保证 内存中的 PML5E和PML4E都是1, 当然，在缓存
> 该translation 之前，处理器也会将这些accessed flags 都设置为1.

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
>> 同上不赘述
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
>> 同上不赘述

Information from a paging-structure entry can be included in entries in the
paging-structure caches for other paging-structure entries referenced by the
original entry. For example, if the R/W flag is 0 in a PML4E, then the R/W flag
will be 0 in any PDPTE-cache entry for a PDPTE from the page-directory-pointer
table referenced by that PML4E. This is because the R/W flag of each such
PDPTE-cache entry is the logical-AND of the R/W flags in the appropriate PML4E
and PDPTE.

> 来自 paging-structure entry中的信息可以被包含在其他的 paging-stucture entries
> 的 paging-structure caches中, 这些 paging-structure entries 被 original entry
> 引用( original entry 也就是最一开始提到的 entry)。例如， 如果 PML4E中的 R/W 
> flags为0, 那么被该 PML4E 指向的任何 来自pdp table 中的 PDPTE 的 PDPTE-cache 
> entry的 R/W flag都是0.这时因为每个 PDPTE-cache entry 中的 R/W flag都是 PML4E
> 和 PDPTE 的 R/W flags logical-AND的结果。

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

> <font color="red">
> 上面两段和HLAT相关。先不关心。
> </font>

The paging-structure caches contain information only from paging-structure
entries that reference other paging structures (and not those that map pages).
Because the G flag is not used in such paging-structure entries, the
global-page feature does not affect the behavior of the paging-structure
caches.

> paging-structure caches包含了某些仅指向其他paging structures
> 的paging-structure entries的信息( 这些entry并不map pages)。因为 G flags不会
> 在这些paging-structure entries使用，所以global-page feature 不会影响
> paging-structure caches的行为。

The processor may create entries in paging-structure caches for translations
required for prefetches and for accesses that are a result of speculative
execution that would never actually occur in the executed code path.

> 处理器可能在 paging-structure caches中创建了这些条目: 用于 prefetch 的
> translation需要 和 预测执行的结果， 该预测执行并没有实际发生在代码执行流里。

As noted in Section 4.10.1, any entries created in paging-structure caches by a
logical processor are associated with the current PCID.

> 正如Section 4.10.1 中提到的，逻辑处理器在 paging-structure caches中创建的任何
> entries都需要和current PCID 相关联。

A processor may or may not implement any of the paging-structure caches.
Software should rely on neither their presence nor their absence. The processor
may invalidate entries in these caches at any time. Because the processor may
create the cache entries at the time of translation and not update them
following subsequent modifications to the paging structures in memory, software
should take care to invalidate the cache entries appropriately when causing
such modifications. The invalidation of TLBs and the paging-structure caches is
described in Section 4.10.4.
 
> absence : 缺席; 离开
>
> 处理器可能或者可能没有实现任何的 paging-structure caches. 软件不应该依赖
> 他们的存在与否。处理器可能在任何时候 无效这些缓存中的 entries.因为处理器
> 可能在translation发生的时候创建 cache entries并且在修改内存中的paging
> structures后也不会更新他们，所以软件需要注意，当发生这些内存修改时，正确的
> 去无效这些 cache entries。关于TLBs和 paging-structure caches的无效操作在
> Section 4.10.4 中描述。

### 4.10.3.2 Using the Paging-Structure Caches to Translate Linear Addresses

When a linear address is accessed, the processor uses a procedure such as the
following to determine the physical address to which it translates and whether
the access should be allowed:

> 当线性地址被访问，处理器使用如下的流程来确定该翻译的物理地址和是否可以被访问。

* If the processor finds a TLB entry that is for the page number of the linear
address and that is associated with the current PCID (or which is global), it
may use the physical address, access rights, and other attributes from that
entry.

> 如果逻辑处理器发现了一个TLB entry, 该 TLB entry用于该线性地址的page number
> 并且可以和当前的 PCID相匹配( 或者是global page),他可能使用该entry的 PA, access
> rights, 和其他的属性。

* If the processor does not find a relevant TLB entry, it may use the upper bits
of the linear address to select an entry from the PDE cache that is associated
with the current PCID (Section 4.10.3.1 indicates which bits are used in each
paging mode). It can then use that entry to complete the translation process
(locating a PTE, etc.) as if it had traversed the PDE (and, for 4-level paging
and 5-level paging, the PDPTE, PML4E, and PML5E, as appropriate) corresponding
to the PDE-cache entry.

> 如果处理器没有发现相应的 TLB entry, 他可能使用 线性地址的高位去 PDE cache中
> 选择一个和当前 PCID 匹配的entry。（Section 4.10.3.1 指出了在每个paging mode中
> 使用那些bits)。然后它可以使用该entry去完成 translation process(定位
> PTE等) ,就好像他已经遍历了和PDE-cache entry相对应的 PDE (对于 4-LEVEL paging和
> 5-LEVEL paging, 可能还有 PDPTE, PML4E, PML5E, 视情况而定）

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

> 下面的 item 适用于 4-level paging / 5-level paging: 
> 
>> NOTE:
>>
>> 下面三段就不翻译了，因为每段讲的内容差不多，大概就是如果lower hierarchy 
>> paging-structure cache 没有话，就去找更higher hierarchy paging-structure cache,
>> 并且从该cache entry中找到用于遍历到 lower hierarchy paging-structure cache
>> 的信息(e.g., PA, R/W flags ...), 然后继续完成 translation process.
>>
>> 这里还需要注意一点，没有提到PAE, PAE也有PDPTE, 但是其就只有四个条目，
>> 并且PDPTE 会加载到 PDPTE register中，所以不需要paging-structure cache

(Any of the above steps would be skipped if the processor does not support the
cache in question.)

> in question : 相关的
>
> 如果处理器不支持上述相关的 cache，那么该步骤就会跳过。

If the processor does not find a TLB or paging-structure-cache entry for the
linear address, it uses the linear address to traverse the entire
paging-structure hierarchy, as described in Section 4.3, Section 4.4.2, and
Section 4.5.

> 对于该线性地址，处理器没有发现 TLB/ paging-structure-cache entry, 他将遍历
> 整个的 paging-structure hierarchy， 正如 Section 4.3, 4.4.2, 4.5 描述的那样

### 4.10.3.3 Multiple Cached Entries for a Single Paging-Structure Entry

The paging-structure caches and TLBs may contain multiple entries associated
with a single PCID and with information derived from a single paging-structure
entry. The following items give some examples for 4-level paging:

> paging-structure caches 和 TLBs 中可能包含了多个这样的entry:
>  * 相同的 PCID
>  * 信息都来自同一个 paging-structure entry
>
> 下面给出了一些 4-level paging 的例子

* Suppose that two PML4Es contain the same physical address and thus reference
    the same page-directory-pointer table. Any PDPTE in that table may result
    in two PDPTE-cache entries, each associated with a different set of linear
    addresses. Specifically, suppose that the n<sub>1</sub><sup>th</sup> and
    n<sub>2</sub><sup>th</sup> entries in the PML4 table contain the same
    physical address. This implies that the physical address in the
    m<sup>th</sup> PDPTE in the page-directory-pointer table would appear in
    the PDPTE-cache entries associated with both p<sub>1</sub> and
    p<sub>2</sub>, where (p1 » 9) = n1, (p2 » 9) = n2, and (p1 & 1FFH) = (p2 &
    1FFH) = m. This is because both PDPTE-cache entries use the same PDPTE, one
    resulting from a reference from the n1th PML4E and one from the n2th PML4E.

> 假设两个 PML4Es中包含了相同的 phyiscal address，因此他们指向了相同的 PDPT。
> 在该PDPT中的任何PDPTE 都可能会有两个 PDPTE-cache entries, 每一个都会相关联
> 一组不同的线性地址。确切的说，假设PML4 Table中有两个entry n1th, n2th 包含了
> 相同的物理地址。这也就意味着 PDPT table 中的mth位置的 PDPTE 可能会在 PDPTE-cache
> 有有两个entry分别关联 p1, p2, 其中 (p1 >> 9) = n1, (p2 >> 9) = n2, 并且 p1 & 1FFH
> = p2 & 1FFH = m。这是因为两个 PDPTE-cache entries 都是用了相同的 PDPTE, 一个
> 是由 n1th位置的PML4E引用，另一个是有n2th位置的 PML4E 引用
>
>> NOTE
>>
>> 这里 p1 >> 9 = n1, 实际上表示的是PML4E的位置，9 bits正好是用于PDPTE 索引的index, 
>> 而p1 第9位正好是这9个bits, 所以 p1 & 1FFH = p2 & 1FFH = m, 也就表示该index相同。
>> 都指向了同一个位置m
>>
>> 这个例子简单来说，就是上级页表中有两个表项都指向了同一个 paging-structure entry,
>> 这样在 该 paging-structure entry cache中就可能有信息完全相同的表项，但是
>> 用于索引的 LA 不同。

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

> * 假设 第一个PML4E(i.e., 在PML4 table的第一个位置) 包含了物理地址CR3中的物理地址X
> (PML4 table的物理地址), 这也意味着如下:
>   + 任何和[bit 47:39] 为0 的线性地址相关的PML4-cache entry 都包含地址 X.
>   + 任何和[bit 47:30] 为0 的线性地址相关的PDPTE-cache entry 都包含地址 X。这是因为
>   对于翻译[bit 47:30] 为0 的线性地址使用 [bit 47:39]\(0\)定位到的 page-directory table
>   位于地址X(PML4 table的地址).使用线性地址的 bit 38:30 （仍然是0) ,再一次定位到
>   地址X。并且将改地址store 在 PDPTE-cache entry
>
>> NOTE
>> 
>> 但是这里要注意，这样的配置可以正常 complete translation, page-table  entry
>> 中的PS位只存在于 not final page table entry中。所以address X 位于的page table
>> entry, 可以作为PML4E, PDPTE, PDE, PTE使用。
>
> 同一个PML4E 为这些所有的 cache entries贡献了他的物理地址X ,因为该entry的自
> 引用的性质，导致该条目可以用于 PML4E，PDPTE，PDE，PTE

> NOTE
>
> 上面给出了两个例子，描述了 page-cache entry中可能出现的有相同信息的page-cache entry 
> cache。总结了两种情况:
>
> * 同一级 page table cache , 有多个相同信息的 page table entry cache
> * 不同级 page table cache , 有多个相同信息的 page table entry cache


## 4.10.4 Invalidation of TLBs and Paging-Structure Caches

As noted in Section 4.10.2 and Section 4.10.3, the processor may create entries
in the TLBs and the paging-structure caches when linear addresses are
translated , and it may retain these entries even after the paging structures
used to create them have been modified. To ensure that linear-address
translation uses the modified paging structures, software should take action to
invalidate any cached entries that may contain information that has since been
modified.

> 正如 Section 4.10.2 和 Section 4.10.3 中提到的，处理器可能当执行线性地址翻译
> 时，在 TLBs和 paging-structure cache中创建了 entries， 并且处理器可能在 创建
> 他们(cache)的 paging structure 被修改后，仍然持有这些entries。为了保证线性地
> 址翻译使用修改后的 paging structures, 软件应该去无效那些已经己经被修改的cached
> entries

### 4.10.4.1 Operations that Invalidate TLBs and Paging-Structure Caches

The following instructions invalidate entries in the TLBs and the
paging-structure caches:

> 下面的指令用于无效TLB，paging-structure caches:

* INVLPG. This instruction takes a single operand, which is a linear address. The
instruction invalidates any TLB entries that are for a page number
corresponding to the linear address and that are associated with the current
PCID. It also invalidates any global TLB entries with that page number,
regardless of PCID (see Section 4.10.2.4).<sup>1</sup> INVLPG also invalidates
all entries in all paging-structure caches associated with the current PCID,
regardless of the linear addresses to which they correspond.

> correspond /ˌkɒrəˈspɒnd/ :  相当于;通信;符合;相一致;类似于
>
> INVLPG. 该指令持有一个操作数，该操作数是一个线性地址。该指令会无效下面特征
> 的所有TLB:
>  * 和该线性地址对应的 page number 匹配
>  * 和 current PCID 匹配
>
> 它也能无效任何和该 page number 匹配的 global TLB entries，不管PCID(Section
> 4.10.2.4)。另外，INVLPG 能够无效 所有 paging-structure caches中的所有 和
> 当前PCID 相关的 entries，不管线性地址是否能够匹配。

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
    mappings—except global translations—associated with all PCIDs. (The
    instruction may also invalidate global translations.)

    See Chapter 3 of the Intel 64 and IA-32 Architecture Software Developer’s
    Manual, Volume 2A for details of the INVPCID instruction.

> INVPCID. 该指令的操作会基于指令操作数，被称为 INVPCID type和 INVPCID descriptor。
> 当前定义的四种 INVPCID type 如下:
> * Individual-address. 如果 INVPCID type = 0, 逻辑处理器会无效下面的映射
>   + 除了 global translation
>   + INVPCID descriptor 中指定的PCID 
>   + INVPCID descriptor 指定的 线性地址
> 
>    该指令也可能会无效global translation, 以及其他 PCID , 其他的线性地址
>    相关的mapping
>
> * Single-context. 如果 INVPCID type = 1, logical processor 无效如下映射:
>   + 除了 global translation
>   + INVPCID descriptor 中指定的PCID 
>
>   同上，也可能通杀
>
> * All-context. 如果 INVPCID type = 2:
>   + 包括 global translation
>   + 所有 PCIDs
>
> * ALL-context. 如果INVPCID type = 3 
>   + 除了 global translation
>   + 所有PCIDs
>
>  同上，也可能通杀global translation
>
>> NOTE
>>
>> 通杀的真随意, 不知有何用意
>
> 查看Intel sdm Chapter 3 Volume 2A 了解更多关于INVPCID指令的细节

* MOV to CR0. The instruction invalidates all TLB entries (including global
entries) and all entries in all paging-structure caches (for all PCIDs) if it
changes the value of CR0.PG from 1 to 0.

> MOV to CRO. 如果该指令将它的该由1->0, 指令会无效所有的TLB entries (包括global
> entries) 以及所有paging-structure caches 的所有entries (也是对于所有PCIDs)

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

> MOV to CR3. 该行为依赖 CR4.PCIDE的值:
>   * 如果CR4.PCIDE = 0, 该指令会无效: 
>     + 除了 global pages
>     + PCID 000H 相关的所有 TLBs 和 paging-structure caches
>   * 如果CR4.PCIDE = 1 并且 该指令源操作数bit 63 是0,  该指令会无效
>     + 除了global pages
>     + 由指令源操作数 BIT 11：0 指定的PCID相关的所有TLBs 和 paging-structure
>       caches
>   * 如果CR4.PCIDE=1, 并且源操作数的63 bit是1, 该指令不需要无效人和的TLBs和
>   paging-structure caches中的entries

* MOV to CR4. The behavior of the instruction depends on the bits being modified:
    + The instruction invalidates all TLB entries (including global entries) and
    all entries in all paging-structure caches (for all PCIDs) if (1) it
    changes the value of CR4.PGE;1 or (2) it changes the value of the CR4.PCIDE
    from 1 to 0.
    + The instruction invalidates all TLB entries and all entries in all
    paging-structure caches for the current PCID if (1) it changes the value of
    CR4.PAE; or (2) it changes the value of CR4.SMEP from 0 to 1.

> MOV to CR4. 该指令的行为依赖某些bits是否被更改
>  * 该指令会无效所有TLB entries(包括global entries) 以及所有paging-structure
>  caches中的 所有entries (对于所有的PCIDs): 
>    + 改变了CR4.PGE 的值
>    + 将CR4.PCIDE 1->0
>  * 该指令会无效当前PCID的所有TLB entries和所有paging-structure caches的所有
>  entries:
>    + 改变了 CR4.PAE的值
>    + 将CR4.SMEP 0->1

* Task switch. If a task switch changes the value of CR3, it invalidates all TLB
entries associated with PCID 000H except those for global pages. It also
invalidates all entries in all paging-structure caches associated with PCID
000H.<sup>2</sup>

> 2. Task switches do not occur in IA-32e mode and thus cannot occur with 4-level
> paging. Since CR4.PCIDE can be set only with 4-level paging, task switches
> occur only with CR4.PCIDE = 0.

> Task switch. 如果task switch 更改了CR3的值，他将无效所有除了global pages, 和 
> PCID 000H 相关的的所有TLB，同时也会无效和PCID 000H相关的所有的paging-structure 
> caches
>
> 2. task switch 不会发生在IA-32e mode中因此不会发生在 4-LEVEL paging中。因为
> CR4.PCIDE 只能在 4-level paging 中被设置，所以task switches 只能发生在 CR4.PCIDE
> = 0 的情况下

* VMX transitions. See Section 4.11.1.

The processor is always free to invalidate additional entries in the TLBs and
paging-structure caches. The following are some examples:

> 处理器 总会自由的无效 额外的 TLBs  entries和 paging-structure caches.下面
> 是一些例子:

* INVLPG may invalidate TLB entries for pages other than the one corresponding to
its linear-address operand. It may invalidate TLB entries and
paging-structure-cache entries associated with PCIDs other than the current
PCID.

> INVLPG 可能会无效除了他线性地址操作数指定的那个page的其他pages的TLB entries。
> 他也可能无效除了和current PCID 其他PCIDs相关的 TLB entries以及paging-structure-
> cache entries。

* INVPCID may invalidate TLB entries for pages other than the one corresponding
to the specified linear address. It may invalidate TLB entries and
paging-structure-cache entries associated with PCIDs other than the specified
PCID.

> INVPCID 同上

* MOV to CR0 may invalidate TLB entries even if CR0.PG is not changing. For
example, this may occur if either CR0.CD or CR0.NW is modified.

> MOV to CR0 可能在即使CR0.PG 没有被更改的情况下 无效TLB entries。例如，他可能
> 发生在 CR0.CD 或者CR0.NW 被修改的情况下

* MOV to CR3 may invalidate TLB entries for global pages. If CR4.PCIDE = 1 and
bit 63 of the instruction’s source operand is 0, it may invalidate TLB entries
and entries in the paging-structure caches associated with PCIDs other than the
PCID it is establishing. It may invalidate entries if CR4.PCIDE = 1 and bit 63
of the instruction’s source operand is 1.

> MOV to CR3 可能会无效 global pages 的 TLB entries. 如果CR4.PCIDE =1,并且
> 该指令源操作数的63 bit 是0, 它可能会无效不是他所建立的PCID相关的TLB entries
> 和 paging-structure entries。他可能在CR4.PCIDE=1 和 指令源操作数的63 bit
> 为1的情况下也会无效 entries.

* MOV to CR4 may invalidate TLB entries when changing CR4.PSE or when changing
CR4.SMEP from 1 to 0.

> MOV to CR4 可能在改变CR4.PSE或者将CR4.SMEP 1 -> 0 的情况下，无效TLB entries

* On a processor supporting Hyper-Threading Technology, invalidations performed
on one logical processor may invalidate entries in the TLBs and
paging-structure caches used by other logical processors.

> 在支持超线程技术的处理器上，某个逻辑处理器无效了另一个逻辑处理器使用的
> TLB和paging- structure caches

(Other instructions and operations may invalidate entries in the TLBs and the
paging-structure caches, but the instructions identified above are
recommended.)

> 其他的指令和操作数可能也会无效TLBs中的某些entries和 paging-structure caches,
> 但是建议使用上面已经证实的指令(也就是上面明确说明的)。

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

> 除了上面提到的这些指令，page faults 也会 invalidate TLBs 和 paging-structure
> caches。尤其是，尝试使用某个线性地址访问造成PF, 将会无效该线性地址对应的 page
> number和当前PCID相关的所有的TLBs。他也会无效该线性地址对应的 page number以及
> 和当前PCID相关的 paging-structure cache。如果该PF不是由内存中的 paging
> structure 的内容引起的(因此，它是由修改了内存中的paging structure后，没有
> invaildate cache entries导致)，该无效操作可以确保 page-fault exception
> 将不会再次发生。(如果造成 PF的指令再次执行)

As noted in Section 4.10.2, some processors may choose to cache multiple
smaller-page TLB entries for a translation specified by the paging structures
to use a page larger than 4 KBytes. There is no way for software to be aware
that multiple translations for smaller pages have been used for a large page.
The INVLPG instruction and page faults provide the same assurances that they
provide when a single TLB entry is used: they invalidate all TLB entries
corresponding to the translation specified by the paging structures.

> 正如 Section 4.10.2中提到的，某些处理器可能对于使用超过4KByte page的
> paging-structure 去缓存多个smaller-page TLB entries。INVLPG指令和 page
> faults 提供了和single TLB entry 相同的保证: 他将会无效 该paging structure
> 指定的所有translation 相关的TLB entries

### 4.10.4.2 Recommended Invalidation

> recommend /ˌrekəˈmend/ : 推荐

The following items provide some recommendations regarding when software should
perform invalidations:

> 以下items 提供了一些关于软件应在何时执行invalidation的建议：

* If software modifies a paging-structure entry that maps a page (rather than
referencing another paging structure), it should execute INVLPG for any linear
address with a page number whose translation uses that paging-structure entry.1

(If the paging-structure entry may be used in the translation of different page
numbers — see Section 4.10.3.3 — software should execute INVLPG for linear
addresses with each of those page numbers; alternatively, it could use MOV to
CR3 or MOV to CR4.)

> 如果软件修改了 map page 的paging-structure entry(而不是指向另一个 paging 
> structurea), 他应该执行 INVPG , 参数是使用该 paging-structure entry 进行
> 翻译的page number对应的任意线性地址
>
> （如果该paging-structure entry 可能被不同的page numbers 用于translation --
> 如Section 4.10.3.3 -- 如那间应该为每个page numbers 对应的线性地址执行 INVLPG
> 指令; 或者是执行 MOV to CR3, MOV to CR4

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

> 如果软件修改了指向另一个paging structure 的paging-structure entry, 根据
> 被修改entry控制的 translation的类型和数量，它可以使用以下方法之一:
>   + 为每一个使用该entry的translation对应page number的线性地址执行 INVLPG指令。
>   但是，如果没有page numbers 使用该entry进行translate (e.g., 因为modified entry
>   指向的paging structure 中的所有条目 P flags都是0），仍然有必要执行一次 INVLPG
>   + 如果modify entry 没有控制global pages，执行MOV to CR3
>   + 执行 MOV to CR4 去修改 CR4.PGE

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

> 如果 CR4.PCIDE = 1, 并且软件修改了没有映射page的 paging-structure entry 或者
> 他的G flag(bit 8) 是0, 如果该entry可能使用了 PCIDs 不是当前的，还需要额外的步
> 骤。下面任意一个可以满足:
>   + 执行 MOV to CR4 修改 CR4.PGE，立即执行和或者在使用 affected PCIDs之前。例如，
>   软件可以为使用了affected PCIDs的进程使用不同的(以前未使用的)PCIDs

* If software using PAE paging modifies a PDPTE, it should reload CR3 with the
register’s current value to ensure that the modified PDPTE is loaded into the
corresponding PDPTE register (see Section 4.4.1).

> 如果软件使用 PAE paging 并修改了 PDPTE, 应该 使用寄存器当前的 value 重新 load
> CR3, 来保证 修改后的PDPTE 已经load到 对应的 PDPTE 寄存器中。

* If the nature of the paging structures is such that a single entry may be used
for multiple purposes (see Section 4.10.3.3), software should perform
invalidations for all of these purposes. For example, if a single entry might
serve as both a PDE and PTE, it may be necessary to execute INVLPG with two (or
more) linear addresses, one that uses the entry as a PDE and one that uses it
as a PTE. (Alternatively, software could use MOV to CR3 or MOV to CR4.)

> 如果paging structures的性质是单个entry可能用于多个目标(Section 4.10.3.3), 
> software 应该为所有目标执行 invalidate。例如，如果单个entry 可能同时用于
> PDE和PTE, 他可能有必要执行 INVLPG，操作数分别有两个（或者更多）线性地址。
> 一个是作为PDE使用的entry，一个是作为PTE（作为替代的，软件可以执行MOV to CR3
> 或者MOV to CR4
>
>> 这个地方比较抽象, 我们来举个例子:
>>
>> 假设有一个 page directory table, page frame 为 PF_pd, 里面前两个entry
>> E_a, E_b, 分指向page frame pf_a, pf_b, 其中 pf_a == PF_pd, 
>>
>> E_b其实可以作为PDE，也可以作为PTE使用，我们假设pf_b 中的第一个entry
>> 为E_ba, 指向页面pf_ba
>>
>> 另外我们假设，线性地址LA 恰好是该 page directory table 映射的最低的地址,
>> (LA % 1G = 0), 我们来看两个地址的映射。
>>
>> |线性地址|PDE|page frame of page table|PTE|page frame|
>> |----|----|---|----|---|
>> |LA|E_a|pf_a (实际上是PF_pd)|E_a|PF_pd|
>> |LA+4K|E_a|pf_a(实际上是PF_pd)|E_b|pf_b|
>> |LA+2M|E_b|pf_b|E_ba|pf_ba|
>>
>> 可以看到这里 E_b 既可以作为PDE使用也可以作为PTE使用。
>> 所以如果修改了该entry，需要用INVLPG指令对线性地址LA+4K, 
>> LA + 2M分别执行无效操作

* As noted in Section 4.10.2, the TLBs may subsequently contain multiple
  translations for the address range if software modifies the paging structures
  so that the page size used for a 4-KByte range of linear addresses changes. A
  reference to a linear address in the address range may use any of these
  translations.

  Software wishing to prevent this uncertainty should not write to a
  paging-structure entry in a way that would change, for any linear address, both
  the page size and either the page frame, access rights, or other attributes. It
  can instead use the following algorithm: first clear the P flag in the relevant
  paging-structure entry (e.g., PDE); then invalidate any translations for the
  affected linear addresses (see above); and then modify the relevant
  paging-structure entry to set the P flag and establish modified translation(s)
  for the new page size.
> uncertainty : 不确定性
>
> 正如Section 4.10.2 中提到的, 如果软件修改了 paging structure 导致用于线性地址
> 范围的4-Kbyte page size发生了改变，TLBs接下来可能包含multiple translations。
> 该地址空间中的线性地址可能使用这些任意的translation。
>
> 希望防止这种不确定性的的软件不应该对任何线性地址的paging-structure entry做
> 写入操作，包括page size ,page frame, access right 或者其他的属性。应该使用
> 下面的算法:
>  1. 清空相应paging-structure entry的P flag (e.g., PDE); 
>  2. 然后无效受影响线性地址任何translation;
>  3. 修改相应的paging-structure entry 来设置 P flag, 并且为新的page size建立
>  修改后的translation

Software should clear bit 63 of the source operand to a MOV to CR3 instruction
that establishes a PCID that had been used earlier for a different
linear-address space (e.g., with a different value in bits 51:12 of CR3). This
ensures invalidation of any information that may have been cached for the
previous linear-address space.

> 软件应该清空MOV to CR3 指令的源操作数的63 bit来建立不同于先前线性地址空间
> 的PCID（例如CR3的52:12中具有不同值)。他保证了为之前线性地址空间缓存的任何信息
> 都会被无效。

This assumes that both linear-address spaces use the same global pages and that
it is thus not necessary to invalidate any global TLB entries. If that is not
the case, software should invalidate those entries by executing MOV to CR4 to
modify CR4.PGE.

> 这假设两个线性地址空间使用相同的global pages，因此没有必要是全局的 TLB entires
> 无效。如果不是这样情况的话，软件应该通过修改CR4.PGE来使这些条目无效。

### 4.10.4.3 Optional Invalidation

The following items describe cases in which software may choose not to
invalidate and the potential consequences of that choice:

> potential [pəˈtenʃl]: 潜在的;可能的 <br/>
> consequences [ˈkɒnsɪkwənsɪz]: 后果，结果
>
> 下面的条目描述了软件可能选择不去invalidate 的情况，以及该选择后的潜在后果:

* If a paging-structure entry is modified to change the P flag from 0 to 1, no
invalidation is necessary. This is because no TLB entry or paging-structure
cache entry is created with information from a paging-structure entry in which
the P flag is 0.<sup>1</sup>

> 1. If it is also the case that no invalidation was performed the last time the
>    P flag was changed from 1 to 0, the processor may use a TLB entry or
>    paging-structure cache entry that was created when the P flag had earlier
>    been 1.

> 如果paging-structure entry 被修改将Pflag 0 -> 1, invlidation是没有必要的。
> 这是因为没有TLB entry或者paging-structure cache entry 会在 该paging-structure
> entry 的 P flags为0 的情况下创建。
>
> 1. 如果在上次执行Pflag 0 -> 1后，处理器可能会使用之前P flag 为1时创建的 TLB 
> entry 或者 paging-structure cache entry。
>
>> NOTE
>>
>> 那为什么手册中还是说这种情况是 nonecessary的呢，因为感觉使用该TLB entry
>> 的行为是软件发起的，硬件不会主动发起，所以软件只有在出问题的情况下，才会
>> 在 LA 对应的paging-structure entry P = 0的情况下访问该 LA

* If a paging-structure entry is modified to change the accessed flag from 0 to
1, no invalidation is necessary (assuming that an invalidation was performed
the last time the accessed flag was changed from 1 to 0). This is because no
TLB entry or paging-structure cache entry is created with information from a
paging-structure entry in which the accessed flag is 0.

> 如果paging-structure entry 修改 accessed flag 0 -> 1, invalidation 是没有
> 必要的(假设上次accessed flag 1 -> 0的时候，已经执行了 invalidate )。
> 这是因为没有TLB entry或者paging-structure cache entry 会在 
> paging-structure entry 的 accessed flag = 0 的情况下创建

* If a paging-structure entry is modified to change the R/W flag from 0 to 1,
failure to perform an invalidation may result in a “spurious” page-fault
exception (e.g., in response to an attempted write access) but no other adverse
behavior. Such an exception will occur at most once for each affected linear
address (see Section 4.10.4.1).

>
> failure: 这里的 failure 不是失败的意思，而是 未能/忽略/忘记<br/>
> adverse：不利的，相反的
>
> 如果 将 paging-structure entry  中R/W flag 0->1, 但是没有执行 invalidation
> 可能会造成 "spurious" page-fault exception(e.g., 尝试相应 wirte access),
> 但是不会造成其他不利的影响。像这样的异常对于每个某影响的线性地址只会发生一次
> (Section 4.10.4.1)
>
>> 这里只会发生一次的原因是, page fault 会 invalidate。

* If CR4.SMEP = 0 and a paging-structure entry is modified to change the U/S
flag from 0 to 1, failure to perform an invalidation may result in a “spurious”
page-fault exception (e.g., in response to an attempted user-mode access) but
no other adverse behavior. Such an exception will occur at most once for each
affected linear address (see Section 4.10.4.1).

> <font color="red">
> CR4.SMEP 未了解
> </font>

* If a paging-structure entry is modified to change the XD flag from 1 to 0,
failure to perform an invalidation may result in a “spurious” page-fault
exception (e.g., in response to an attempted instruction fetch) but no other
adverse behavior. Such an exception will occur at most once for each affected
linear address (see Section 4.10.4.1).

> <font color="red">XD 未了解</font>

* If a paging-structure entry is modified to change the accessed flag from 1 to
0, failure to perform an invalidation may result in the processor not setting
that bit in response to a subsequent access to a linear address whose
translation uses the entry. Software cannot interpret the bit being clear as an
indication that such an access has not occurred.

> interpret : 解释;说明;
> 
> 如果paging-structure entry 修改 accessed flag 1->0, 没有执行invalidation的话，
> 将会导致，处理器在接下来的 translation中使用该entry则不会设置该bit。软件
> 层面不能将清除该位解释为写入操作没有发生。

* If software modifies a paging-structure entry that identifies the final
physical address for a linear address (either a PTE or a paging-structure entry
in which the PS flag is 1) to change the dirty flag from 1 to 0, failure to
perform an invalidation may result in the processor not setting that bit in
response to a subsequent write to a linear address whose translation uses the
entry. Software cannot interpret the bit being clear as an indication that such
a write has not occurred.

>> 这个是dirty flag，也是同上，如果将dirty flag 1 -> 0 之后，没有invalidate, 软件
>> 层面接下来就不好判断如果dirty flag是clear状态下，这段时间有没有发生写入操作

* The read of a paging-structure entry in translating an address being used to
fetch an instruction may appear to execute before an earlier write to that
paging-structure entry if there is no serializing instruction between the write
and the instruction fetch. Note that the invalidating instructions identified
in Section 4.10.4.1 are all serializing instructions.

> 在 translating 地址过程中读取 paging-structure entry 发生在 fetch a instruction,
> 而这个过程可能在更早的对于该 paging-structure entry写入操作之前执行, 如果这里
> 在写入操作和instruction fetch 之间没有 serializing instruction。注意 Section 
> 4.10.4.1中提到的 invalidation instructions 都是 serializing instruction

* Section 4.10.3.3 describes situations in which a single paging-structure entry
may contain information cached in multiple entries in the paging-structure
caches. Because all entries in these caches are invalidated by any execution of
INVLPG, it is not necessary to follow the modification of such a
paging-structure entry by executing INVLPG multiple times solely for the
purpose of invalidating these multiple cached entries. (It may be necessary to
do so to invalidate multiple TLB entries.)

> 4.10.3.3 提到的 单个paging-structure entry 可能在多个paging-structure caches中都
> 有保存了信息。因为这些cache中的所有的entries 都可以被任意执行的INVLPG invalidate
> 掉，所以没有必要在修改这样的paging-structure entry 后，仅仅为了无效这些 multiple 
> cache entries, 去单独执行多次 INVLPG 指令.（但是可能有必要为 mulitple TLB 
> entries 做这样的事情)

### 4.10.4.4 Delayed Invalidation 

Required invalidations may be delayed under some circumstances. Software
developers should understand that, between the modification of a
paging-structure entry and execution of the invalidation instruction
recommended in Section 4.10.4.2, the processor may use translations based on
either the old value or the new value of the paging-structure entry. The
following items describe some of the potential consequences of delayed
invalidation:

> circumstances [ˈsɜːkəmstənsɪz]: 环境;条件;情况
>
> 在某些情况下需要 invalidation delay 执行。软件工程师应该理解 在修改
> paging-structure entry后和执行 Section 4.10.4.2中提到的invalidation
> instruction 之间，处理器可能基于 paging-structure entry中的old value
> 还是 new value。 下面的一些 items 描述了 delayed invalidation 的潜在
> 后果。

* If a paging-structure entry is modified to change the P flag from 1 to 0, an
access to a linear address whose translation is controlled by this entry may or
may not cause a page-fault exception.

> 如果paging-structure entry 将 P 1->0, 访问该entry控制的translation的线性地址
> 可能会也可能不会造成 page-fault exception

* If a paging-structure entry is modified to change the R/W flag from 0 to 1,
write accesses to linear addresses whose translation is controlled by this
entry may or may not cause a page-fault exception.

>> R/W flag 0->1 ,也是上述情况

* If a paging-structure entry is modified to change the U/S flag from 0 to 1,
user-mode accesses to linear addresses whose translation is controlled by this
entry may or may not cause a page-fault exception.

>> U/S flag 0->1, user-mode 访问也是上述情况

* If a paging-structure entry is modified to change the XD flag from 1 to 0,
instruction fetches from linear addresses whose translation is controlled by
this entry may or may not cause a page-fault exception.

>> XD flag 1->0, instruction fetches也是这种情况。

As noted in Section 9.1.1, an x87 instruction or an SSE instruction that
accesses data larger than a quadword may be implemented using multiple memory
accesses. If such an instruction stores to memory and invalidation has been
delayed, some of the accesses may complete (writing to memory) while another
causes a page-fault exception.1 In this case, the effects of the completed
accesses may be visible to software even though the overall instruc- tion
caused a fault.

> <font color="red">
> x87 / SSE 相关, 先不看。
> </font>

In some cases, the consequences of delayed invalidation may not affect software
adversely. For example, when freeing a portion of the linear-address space (by
marking paging-structure entries “not present”), invalidation using INVLPG may
be delayed if software does not re-allocate that portion of the linear-address
space or the memory that had been associated with it. However, because of
speculative execution (or errant software), there may be accesses to the freed
portion of the linear-address space before the invalidations occur. In this
case, the following can happen:

> errant [ˈerənt]: 犯错的，行为不当的
>
> 在某些情况下，delayed invalidation 可能不会对软件不利。例如，当释放一段线性
> 地址空间是(通过让paging-structure entry 标记为 "not present"), 如果软件
> 没有对该线性地址区域重新分配或者与之相关的memory, 使用 INVLPG 指令 
> invalidation 可以被 delayed。但是，因为投机执行(或者犯错的软件), 他们也可能
> 在 invldation 发挥僧之前会访问 线性地址空间的freed 的部分, 在这种情况下，
> 会发生:

* Reads can occur to the freed portion of the linear-address space. Therefore,
invalidation should not be delayed for an address range that has read side
effects.

> 对线性地址空间的释放的部分读取操作可以发生。因此，对于具有读取副作用的地址
> 范围的 invalidation 不应该 delay 

* The processor may retain entries in the TLBs and paging-structure caches for an
extended period of time. Software should not assume that the processor will not
use entries associated with a linear address simply because time has passed.

> 处理器可能将TLBs和paging-structure cache的 entries保留一段延长的时间。软件
> 不应该简单因为已经过去一段时间而假设处理器不会使用该 线性地址相关的entries

* As noted in Section 4.10.3.1, the processor may create an entry in a
paging-structure cache even if there are no translations for any linear address
that might use that entry. Thus, if software has marked “not present” all
entries in a page table, the processor may subsequently create a PDE-cache
entry for the PDE that references that page table (assuming that the PDE itself
is marked “present”).

> 如Section 4.10.3.1中提到的，处理器即使使用该entry的任何线性地址不会有
> translation 的情况下也可能在paging-structure cache 中为其创建entry。因此，
> 如果软件 将一个page table中的所有entries都标记成了"not present", 处理器
> 也可能为该指向 那个page table 的PDE创建PDE-cache entry(假设PDE本身被标记
> 成"present")

* If software attempts to write to the freed portion of the linear-address space,
the processor might not generate a page fault. (Such an attempt would likely be
the result of a software error.) For that reason, the page frames previously
associated with the freed portion of the linear-address space should not be
reallocated for another purpose until the appropriate invalidations have been
performed.

> 如果软件尝试去写线性地址空间已经释放的部分，处理器可能不会造成page fault.
> (这样尝试更像是造成了软件上的错误）。基于该原因，和已经释放的线性地址空间
> 的之前关联的page frame 在正确的invalidation执行之前，不应该重新分配给
> 另一个目标

## 4.10.5 Propagation of Paging-Structure Changes to Multiple Processors 

As noted in Section 4.10.4, software that modifies a paging-structure entry may
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

> 正如Section 4.10.4中提到的，软件修改paging-structure entry 可能需要无效从该
> 修改的entry, 在其修改之前获取的TLBs和paging-structure caches中的 entires。
> (真TM严谨)。在一个包含了多个逻辑处理器的系统上, 软件

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


# 其他链接
[TLBs, Paging-Structure Caches, and Their Invalidation](http://kib.kiev.ua/x86docs/Intel/WhitePapers/317080-002.pdf)

[KAISER: hiding the kernel from user space](https://lwn.net/Articles/738975/)

[PCID is now a critical performance/security feature on x86](https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&ved=2ahUKEwi3os-44uqBAxVYBTQIHRYmD0MQFnoECC8QAQ&url=https%3A%2F%2Fgroups.google.com%2Fg%2Fmechanical-sympathy%2Fc%2FL9mHTbeQLNU&usg=AOvVaw2WBKn4zECDNZWvC6lb8jrX&opi=89978449)

[\[PATCH 23/30\] x86, kaiser: use PCID feature to make user and kernel switches faster](https://www.mail-archive.com/linux-kernel@vger.kernel.org/msg1534623.html)

<font size="4" color="red">
</font> 
