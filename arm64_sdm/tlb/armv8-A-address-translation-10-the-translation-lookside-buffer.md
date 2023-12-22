The Translation Lookaside Buffer (TLB) is a cache of recently accessed page
translations in the MMU. For each memory access performed by the processor, the
MMU checks whether the translation is cached in the TLB. If the requested
address translation causes a hit within the TLB, the translation of the address
is immediately available.

> TLB 是 在 MMU 中 用于 recently accessed page translation 的cache. 对于由处理器
> 执行的每个内存访问, MMU 会检查 TLB 中是否有该 translation 在 TLB 中有缓存.
> 如果请求地址的 translation 在 TLB 中 hit了, 该地址的translation 将会立即获得.
> (从tlb中)

Each TLB entry typically contains not only physical and virtual addresses, but
also attributes such as memory type, cache policies, access permissions, the
Address Space ID (ASID), and the Virtual Machine ID (VMID). If the TLB does not
contain a valid translation for the virtual address that is issued by the
processor, which is known as a TLB miss, an external translation table walk or
lookup is performed. Dedicated hardware within the MMU enables it to read the
translation tables in memory. The newly loaded translation can then be cached
in the TLB for possible reuse if the translation table walk does not result in
a page fault. The exact structure of the TLB differs between implementations of
the Arm processors.

> typically: 典型的, 通常
> 
> 每一个 TLB entry 通常不会只包含PA和VA, 同时也包涵某些 attr, e.g., memory type, 
> cachet policies(不知道是啥), access permissions, ASID, VMID. 如果TLB没有包含
> 对于当前处理器提交的虚拟地址的 valid translation, 这个被称为 TLB miss, 将会有
> 一个额外的 translation table walk 或者 lookup 将被执行.


If the OS modifies translation entries that have been cached in the TLB, it is
the responsibility of the OS to invalidate these stale TLB entries.

When executing A64 code, there is a TLBI, which is a TLB invalidate
instruction. It has the form:
```
TLBI <type><level>{IS} {, <Xt>}
```
The following list gives some of the more common selections for the type field.

```
ALL         All TLB entries.
VMALL       All TLB entries. This is stage 1 for current guest OS.
VMALLS12    All TLB entries. This is stage 1 and 2 for current guest OS.
ASID        Entries that match ASID in Xt.
VA          Entry for virtual address and ASID specified in Xt.
VAA         Entries for virtual address that is specified in Xt, with any ASID.
```
Each Exception level, that is EL3, EL2, or EL1, has its own virtual address space that the operation
applies to. The IS field specifies that this is only for Inner Shareable entries.

The <level> field simply specifies the Exception level virtual address space (can be 3, 2 or 1) that
the operation must apply to.

The IS field specifies that this is only for Inner Shareable entries.

The following table lists TLB configuration instructions:

![TLBI_1](pic/TLBI_1.png)

![TLBI_2](pic/TLBI_2.png)

The following code example shows a sequence for writes to translation tables
backed by Inner Shareable memory:
```
<< Writes to translation tables >>
DSB ISHST           // ensure write has completed
TLBI ALLE1          // invalidate all TLB entries
DSB ISH             // ensure completion of TLB invalidation
ISB                 // synchronize context and ensure that no
                    // instructions are fetched using the old
                    // translation
```
For a change to a single entry, for example, use the instruction:
```
TLBI VAE1, X0
```

Which invalidates an entry that is associated with the address that is
specified in the register X0.

The TLB can hold a fixed number of entries. You can achieve best performance by
minimizing the number of external memory accesses caused by translation table
traversal and obtaining a high TLB hit rate. The Armv8-A architecture provides
a feature known as contiguous block entries to efficiently use TLB space.
Translation table block entries each contain a contiguous bit. When set, this
bit signals to the TLB that it can cache a single entry covering translations
for multiple blocks. A lookup can index anywhere into an address range covered
by a contiguous block. The TLB can therefore cache one entry for a defined
range of addresses, making it possible to store a larger range of virtual
addresses within the TLB than is otherwise possible.

To use a contiguous bit, the contiguous blocks must be adjacent, that is they
must correspond to a contiguous range of virtual addresses. They must start on
an aligned boundary, have consistent attributes, and point to a contiguous
output address range at the same level of translation. The required alignment
is that VA[20:16] for a 4KB granule or VA[28:21] for a 64KB granule, are the
same for all addresses. The following numbers of contiguous blocks are
required:

* 16 × 4KB adjacent blocks giving a 64KB entry with 4KB granule.
* 32 ×32MB adjacent blocks giving a 1GB entry for L2 descriptors.
* 128 ×16KB giving a 2MB entry for L3 descriptors when using a 16KB granule.
* 32 ×64Kb adjacent blocks giving a 2MB entry with a 64KB granule.

If these conditions are not met, a programming error occurs, which can cause
TLB aborts or corrupted lookups. Possible examples of such an error include:

* One or more of the table entries do not have the contiguous bit set.
* The output of one of the entries points outside the aligned range.

With the Armv8-A architecture, incorrect use does not allow permissions checks
outside of EL0 and EL1 valid address space to be escaped, or to erroneously
provide access to EL3 space.
