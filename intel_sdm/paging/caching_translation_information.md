# 4.10 CACHING TRANSLATION INFORMATION

The Intel-64 and IA-32 architectures may accelerate the address-translation
process by caching data from the paging structures on the processor. Because
the processor does not ensure that the data that it caches are always
consistent with the structures in memory, it is important for software
developers to understand how and when the processor may cache such data. They
should also understand what actions software can take to remove cached data
that may be inconsistent and when it should do so. This section provides
software developers information about the relevant processor operation.

Section 4.10.1 introduces process-context identifiers (PCIDs), which a logical
processor may use to distinguish information cached for different
linear-address spaces. Section 4.10.2 and Section 4.10.3 describe how the
processor may cache information in translation lookaside buffers (TLBs) and
paging-structure caches, respectively. Section 4.10.4 explains how software can
remove inconsistent cached information by invalidating portions of the TLBs and
paging-structure caches. Section 4.10.5 describes special considerations for
multiprocessor systems.


#### 4.10.2.3 Details of TLB Use
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
