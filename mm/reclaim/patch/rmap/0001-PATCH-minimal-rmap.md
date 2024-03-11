
```diff
From c48c43e6ed41a3bcec0155e8e4b8440a9a769a0a Mon Sep 17 00:00:00 2001
From: Andrew Morton <akpm@zip.com.au>
Date: Thu, 18 Jul 2002 21:08:35 -0700
Subject: [PATCH] [PATCH] minimal rmap

This is the "minimal rmap" patch, writen by Rik, ported to 2.5 by Craig
Kulsea.

Basically,

before: When the page reclaim code decides that is has scanned too many
unreclaimable pages on the LRU it does a scan of process virtual
address spaces for pages to add to swapcache.  ptes pointing at the
page are unmapped as the scan proceeds.  When all ptes referring to a
page have been unmapped and it has been written to swap the page is
reclaimable.

> proceeds: /proʊˈsiːdz/ 行进;前往;继续做
>
> before : 
> 当 page reclaim 代码发现已经扫描了太多 LRU 上的unreclaimable 
> page, 他将扫描 process virtual address space 中的pages 来加到swapcache,
> 随着扫描的进行,指向该page的pte也逐步unmap. 当所有引用的页面的pte都unmap
> 并且已经写入swap, 该page是可回收的.

after: When an anonymous page is encountered on the tail of the LRU we
use the rmap to see if it hasn't been referenced lately.  If so then
add it to swapcache.  When the page is again encountered on the LRU, if
it is still unreferenced then try to unmap all ptes which refer to it
in one hit, and if it is clean (ie: on swap) then free it.

> after:
> 当 在LRU的尾部遇到一个anonymous page ,我们使用rmap来看, 他是否最近已不再被
> referenced. 如果是这样, 将他加到swapcache. 当在 LRU 上再次遇到该page时, 
> 如果他仍然是 unreferenced, 然后尝试在一次hit中unmap 所有的它所引用的所有的
> ptes, 如果他是clean的(即: 在swap) , 释放它.

The rest of the VM - list management, the classzone concept, etc
remains unchanged.

> VM 中的剩余部分 : list management , classzone concept 等都保持不变.

There are a number of things which the per-page pte chain could be
used for.  Bill Irwin has identified the following.

> per-page pte chain可以用于很多事情. Bill Irwin 确认了如下部分:


(1)  page replacement no longer goes around randomly unmapping things
> 页面替换不再随意取消映射

(2)  referenced bits are more accurate because there aren't several ms
        or even seconds between find the multiple pte's mapping a page
> accurate /ˈækjərət/: 精确的;准确的
> referenced bits 将更加准确, 因为在寻找map到一个page 的多个pte之前没有
> 几ms 甚至几秒钟的时间.

(3)  reduces page replacement from O(total virtually mapped) to O(physical)
> 减少页面替换从 0(total virtually mapped) 到 0 (physical)
> ????

(4)  enables defragmentation of physical memory
> defragmentation: [defræɡmen'teɪʃn]  碎片整理;磁盘碎片整理;重组
>
> 启用物理内存的碎片整理.

(5)  enables cooperative offlining of memory for friendly guest instance
        behavior in UML and/or LPAR settings

> cooperative [koʊˈɑːpərətɪv] : 合作的;配合的
>
> 在 UML and/or LPAR settings 的设置中, 为友好的 guest instance 实现内存的
> 协作 offline

(6)  demonstrable benefit in performance of swapping which is common in
        end-user interactive workstation workloads (I don't like the word
        "desktop"). c.f. Craig Kulesa's post wrt. swapping performance
> demonstrable [dɪˈmɑːnstrəbl] : 可证明的, 明显的
> interactive: 互动的,交互的
> c.f. : 请比较,请参照
>
> swap性能方面有明显的优势. 这最终体现在用户交互式工作站的workload
> 中很常见. (我并不喜欢这个词 "desktop"). c.f. Craig Kulesa's post wrt.(???)
> swapping performance

(7)  evidence from 2.4-based rmap trees indicates approximate parity
        with mainline in kernel compiles with appropriate locking bits
> parity: 平等的
>
> 基于 2.4-based rmap tree 测试表明 大概和主线中带有适当的locking bit编译的
> kernel 类似.(性能)

(8)  partitioning of physical memory can reduce the complexity of page
        replacement searches by scanning only the "interesting" zones
        implemented and merged in 2.4-based rmap
> 物理内存分区可以通过只扫描“感兴趣”区域来 降低页面替换搜索的复杂性
>
> 在 2.4-based rmap 中实现并merge.

(9)  partitioning of physical memory can increase the parallelism of page
        replacement searches by independently processing different zones
        implemented, but not merged in 2.4-based rmap
> parallelism: 平行的.
> 
> 物理内存的分区可以通过通过独立的处理不同的zone 来提高页面替换的并行性.
> 没有merge到2.4-based rmap


(10) the reverse mappings may be used for efficiently keeping pte cache
        attributes coherent
> rmap 可能会用作高效的保持 pte cache attr coherent

(11) they may be used for virtual cache invalidation (with changes)

(12) the reverse mappings enable proper RSS limit enforcement
        implemented and merged in 2.4-based rmap

The code adds a pointer to struct page, consumes additional storage for
the pte chains and adds computational expense to the page reclaim code
(I measured it at 3% additional load during streaming I/O).  The
benefits which we get back for all this are, I must say, theoretical
and unproven.  If it has real advantages (or, indeed, disadvantages)
then why has nobody demonstrated them?

> theoretical: [ˌθiːəˈretɪkl]: 理论上的
> unproven: 未验证的
> indeed [ɪnˈdiːd] : 的确, 其实
> demonstrated [ˈdemənstreɪtɪd]: 证明, 演示
>
> 该code 增加了一个pointer到 struct page中, 消耗一个额外的存储位置为pte chain
> 并且在 page reclaim 代码中增加了额外的计算消耗. ( 我测量他在streaming I/O 期间
> 有额外的 3% load). 我必须说, 我们从这一切得到的好处是理论上的和未经证实的.
> 如果他真有这些有点(or, 甚至是缺点) . 为什么没有人证明他们呢?

There are a number of things remaining to be done:

1: Demonstrate the above advantages.
> 证明上面的优点

2: Make it work with pte-highmem  (Bill Irwin is signed up for this)
> 让他能够在 pte-highmem 上工作.(Bill Irwin 在做这个)

3: Don't add pte_chains to non-shared pages optimisation (Dave McCracken's
   patch does this)
> 不将 pte_chains 添加到 non-shared pages 优化

4: Move the pte_chains into highmem too (Bill, I guess)
> 将pte_chains move到highmem 

5: per-cpu pte_chain freelists (Rik?)

6: maybe GC the pte_chain backing pages. (Seems unavoidable.  Rik?)

7: multithread the page reclaim code.  (I have patches).
> 多线程的page reclaim code

8: clustered add-to-swap.  Not sure if I buy this.  anon pages are
   often well-ordered-by-virtual-address on the LRU, so it "just
   works" for benchmarky loads.  But there may be some other loads...
> 集中 add-to-swap. 

9: Fix bad IO latency in page reclaim (I have lame patches)

10: Develop tuning tools, use them.

11: The nightly updatedb run is still evicting everything.
---
 fs/exec.c                        |   2 +
 include/asm-alpha/rmap.h         |   7 +
 include/asm-arm/proc-armv/rmap.h |  49 ++++
 include/asm-arm/rmap.h           |   6 +
 include/asm-cris/rmap.h          |   7 +
 include/asm-generic/rmap.h       |  52 ++++
 include/asm-i386/rmap.h          |   7 +
 include/asm-ia64/rmap.h          |   7 +
 include/asm-m68k/rmap.h          |   7 +
 include/asm-mips/rmap.h          |   7 +
 include/asm-mips64/rmap.h        |   7 +
 include/asm-parisc/rmap.h        |   7 +
 include/asm-ppc/rmap.h           |   9 +
 include/asm-s390/rmap.h          |   7 +
 include/asm-s390x/rmap.h         |   7 +
 include/asm-sh/rmap.h            |   7 +
 include/asm-sparc/rmap.h         |   7 +
 include/asm-sparc64/rmap.h       |   7 +
 include/linux/mm.h               |   5 +
 include/linux/page-flags.h       |  28 +-
 include/linux/swap.h             |  14 +
 kernel/fork.c                    |   4 -
 mm/Makefile                      |   2 +-
 mm/filemap.c                     |   9 +-
 mm/memory.c                      |  27 +-
 mm/mremap.c                      |   8 +
 mm/page_alloc.c                  |   1 +
 mm/rmap.c                        | 394 +++++++++++++++++++++++++++
 mm/swap_state.c                  |  63 +++++
 mm/swapfile.c                    |   1 +
 mm/vmscan.c                      | 447 ++++++-------------------------
 31 files changed, 832 insertions(+), 380 deletions(-)
 create mode 100644 include/asm-alpha/rmap.h
 create mode 100644 include/asm-arm/proc-armv/rmap.h
 create mode 100644 include/asm-arm/rmap.h
 create mode 100644 include/asm-cris/rmap.h
 create mode 100644 include/asm-generic/rmap.h
 create mode 100644 include/asm-i386/rmap.h
 create mode 100644 include/asm-ia64/rmap.h
 create mode 100644 include/asm-m68k/rmap.h
 create mode 100644 include/asm-mips/rmap.h
 create mode 100644 include/asm-mips64/rmap.h
 create mode 100644 include/asm-parisc/rmap.h
 create mode 100644 include/asm-ppc/rmap.h
 create mode 100644 include/asm-s390/rmap.h
 create mode 100644 include/asm-s390x/rmap.h
 create mode 100644 include/asm-sh/rmap.h
 create mode 100644 include/asm-sparc/rmap.h
 create mode 100644 include/asm-sparc64/rmap.h
 create mode 100644 mm/rmap.c

diff --git a/fs/exec.c b/fs/exec.c
index a46cd7942db..354735b146c 100644
--- a/fs/exec.c
+++ b/fs/exec.c
@@ -36,6 +36,7 @@
 #include <linux/spinlock.h>
 #include <linux/personality.h>
 #include <linux/binfmts.h>
+#include <linux/swap.h>
 #define __NO_VERSION__
 #include <linux/module.h>
 #include <linux/namei.h>
@@ -283,6 +284,7 @@ void put_dirty_page(struct task_struct * tsk, struct page *page, unsigned long a
 	flush_dcache_page(page);
 	flush_page_to_ram(page);
 	set_pte(pte, pte_mkdirty(pte_mkwrite(mk_pte(page, PAGE_COPY))));
+	page_add_rmap(page, pte);
 	pte_unmap(pte);
 	tsk->mm->rss++;
 	spin_unlock(&tsk->mm->page_table_lock);
diff --git a/include/asm-alpha/rmap.h b/include/asm-alpha/rmap.h
new file mode 100644
index 00000000000..08b2236efd3
--- /dev/null
+++ b/include/asm-alpha/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _ALPHA_RMAP_H
+#define _ALPHA_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-arm/proc-armv/rmap.h b/include/asm-arm/proc-armv/rmap.h
new file mode 100644
index 00000000000..0a9a9a55fb6
--- /dev/null
+++ b/include/asm-arm/proc-armv/rmap.h
@@ -0,0 +1,49 @@
+#ifndef _ARMV_RMAP_H
+#define _ARMV_RMAP_H
+/*
+ * linux/include/asm-arm/proc-armv/rmap.h
+ *
+ * Architecture dependant parts of the reverse mapping code,
+ *
+ * ARM is different since hardware page tables are smaller than
+ * the page size and Linux uses a "duplicate" one with extra info.
+ * For rmap this means that the first 2 kB of a page are the hardware
+ * page tables and the last 2 kB are the software page tables.
+ */
+
+static inline void pgtable_add_rmap(pte_t * ptep, struct mm_struct * mm, unsigned long address)
+{
+	struct page * page = virt_to_page(ptep);
+
+	page->mm = mm;
+	page->index = address & ~((PTRS_PER_PTE * PAGE_SIZE) - 1);
+}
+
+static inline void pgtable_remove_rmap(pte_t * ptep)
+{
+	struct page * page = virt_to_page(ptep);
+
+	page->mm = NULL;
+	page->index = 0;
+}
+
+static inline struct mm_struct * ptep_to_mm(pte_t * ptep)
+{
+	struct page * page = virt_to_page(ptep);
+
+	return page->mm;
+}
+
+/* The page table takes half of the page */
+#define PTE_MASK  ((PAGE_SIZE / 2) - 1)
+
+static inline unsigned long ptep_to_address(pte_t * ptep)
+{
+	struct page * page = virt_to_page(ptep);
+	unsigned long low_bits;
+
+	low_bits = ((unsigned long)ptep & PTE_MASK) * PTRS_PER_PTE;
+	return page->index + low_bits;
+}
+
+#endif /* _ARMV_RMAP_H */
diff --git a/include/asm-arm/rmap.h b/include/asm-arm/rmap.h
new file mode 100644
index 00000000000..d79cb373829
--- /dev/null
+++ b/include/asm-arm/rmap.h
@@ -0,0 +1,6 @@
+#ifndef _ARM_RMAP_H
+#define _ARM_RMAP_H
+
+#include <asm/proc/rmap.h>
+
+#endif /* _ARM_RMAP_H */
diff --git a/include/asm-cris/rmap.h b/include/asm-cris/rmap.h
new file mode 100644
index 00000000000..c5bf2a81165
--- /dev/null
+++ b/include/asm-cris/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _CRIS_RMAP_H
+#define _CRIS_RMAP_H
+
+/* nothing to see, move along :) */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-generic/rmap.h b/include/asm-generic/rmap.h
new file mode 100644
index 00000000000..09ddf42f863
--- /dev/null
+++ b/include/asm-generic/rmap.h
@@ -0,0 +1,52 @@
+#ifndef _GENERIC_RMAP_H
+#define _GENERIC_RMAP_H
+/*
+ * linux/include/asm-generic/rmap.h
+ *
+ * Architecture dependant parts of the reverse mapping code,
+ * this version should work for most architectures with a
+ * 'normal' page table layout.
+ *
+ * We use the struct page of the page table page to find out
+ * the process and full address of a page table entry:
+ * - page->mapping points to the process' mm_struct
+ * - page->index has the high bits of the address
+ * - the lower bits of the address are calculated from the
+ *   offset of the page table entry within the page table page
+ */
+#include <linux/mm.h>
+
+static inline void pgtable_add_rmap(struct page * page, struct mm_struct * mm, unsigned long address)
+{
+#ifdef BROKEN_PPC_PTE_ALLOC_ONE
+	/* OK, so PPC calls pte_alloc() before mem_map[] is setup ... ;( */
+	extern int mem_init_done;
+
+	if (!mem_init_done)
+		return;
+#endif
+	page->mapping = (void *)mm;
+	page->index = address & ~((PTRS_PER_PTE * PAGE_SIZE) - 1);
+}
+
+static inline void pgtable_remove_rmap(struct page * page)
+{
+	page->mapping = NULL;
+	page->index = 0;
+}
+
+static inline struct mm_struct * ptep_to_mm(pte_t * ptep)
+{
+	struct page * page = virt_to_page(ptep);
+	return (struct mm_struct *) page->mapping;
+}
+
+static inline unsigned long ptep_to_address(pte_t * ptep)
+{
+	struct page * page = virt_to_page(ptep);
+	unsigned long low_bits;
+	low_bits = ((unsigned long)ptep & ~PAGE_MASK) * PTRS_PER_PTE;
+	return page->index + low_bits;
+}
+
+#endif /* _GENERIC_RMAP_H */
diff --git a/include/asm-i386/rmap.h b/include/asm-i386/rmap.h
new file mode 100644
index 00000000000..5989b2938b5
--- /dev/null
+++ b/include/asm-i386/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _I386_RMAP_H
+#define _I386_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-ia64/rmap.h b/include/asm-ia64/rmap.h
new file mode 100644
index 00000000000..6738fe9e228
--- /dev/null
+++ b/include/asm-ia64/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _IA64_RMAP_H
+#define _IA64_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-m68k/rmap.h b/include/asm-m68k/rmap.h
new file mode 100644
index 00000000000..85119e4145b
--- /dev/null
+++ b/include/asm-m68k/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _M68K_RMAP_H
+#define _M68K_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-mips/rmap.h b/include/asm-mips/rmap.h
new file mode 100644
index 00000000000..2dc334a3b5f
--- /dev/null
+++ b/include/asm-mips/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _MIPS_RMAP_H
+#define _MIPS_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-mips64/rmap.h b/include/asm-mips64/rmap.h
new file mode 100644
index 00000000000..07df131559c
--- /dev/null
+++ b/include/asm-mips64/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _MIPS64_RMAP_H
+#define _MIPS64_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-parisc/rmap.h b/include/asm-parisc/rmap.h
new file mode 100644
index 00000000000..4ea8eb45475
--- /dev/null
+++ b/include/asm-parisc/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _PARISC_RMAP_H
+#define _PARISC_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-ppc/rmap.h b/include/asm-ppc/rmap.h
new file mode 100644
index 00000000000..50556b5ff25
--- /dev/null
+++ b/include/asm-ppc/rmap.h
@@ -0,0 +1,9 @@
+#ifndef _PPC_RMAP_H
+#define _PPC_RMAP_H
+
+/* PPC calls pte_alloc() before mem_map[] is setup ... */
+#define BROKEN_PPC_PTE_ALLOC_ONE
+
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-s390/rmap.h b/include/asm-s390/rmap.h
new file mode 100644
index 00000000000..43d6a87b6e8
--- /dev/null
+++ b/include/asm-s390/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _S390_RMAP_H
+#define _S390_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-s390x/rmap.h b/include/asm-s390x/rmap.h
new file mode 100644
index 00000000000..c41a23a18e4
--- /dev/null
+++ b/include/asm-s390x/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _S390X_RMAP_H
+#define _S390X_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-sh/rmap.h b/include/asm-sh/rmap.h
new file mode 100644
index 00000000000..31db8cc0773
--- /dev/null
+++ b/include/asm-sh/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _SH_RMAP_H
+#define _SH_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-sparc/rmap.h b/include/asm-sparc/rmap.h
new file mode 100644
index 00000000000..06063cffe7d
--- /dev/null
+++ b/include/asm-sparc/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _SPARC_RMAP_H
+#define _SPARC_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/asm-sparc64/rmap.h b/include/asm-sparc64/rmap.h
new file mode 100644
index 00000000000..681849b2dce
--- /dev/null
+++ b/include/asm-sparc64/rmap.h
@@ -0,0 +1,7 @@
+#ifndef _SPARC64_RMAP_H
+#define _SPARC64_RMAP_H
+
+/* nothing to see, move along */
+#include <asm-generic/rmap.h>
+
+#endif
diff --git a/include/linux/mm.h b/include/linux/mm.h
index 163e19fd7b3..0c0b6d41dbb 100644
--- a/include/linux/mm.h
+++ b/include/linux/mm.h
@@ -130,6 +130,9 @@ struct vm_operations_struct {
 	struct page * (*nopage)(struct vm_area_struct * area, unsigned long address, int unused);
 };
 
+/* forward declaration; pte_chain is meant to be internal to rmap.c */
+struct pte_chain;
+
 /*
  * Each physical page in the system has a struct page associated with
  * it to keep track of whatever it is we are using the page for at the
@@ -154,6 +157,8 @@ struct page {
 					   updated asynchronously */
 	struct list_head lru;		/* Pageout list, eg. active_list;
 					   protected by pagemap_lru_lock !! */
+	struct pte_chain * pte_chain;	/* Reverse pte mapping pointer.
+					 * protected by PG_chainlock */
 	unsigned long private;		/* mapping-private opaque data */
 
 	/*
diff --git a/include/linux/page-flags.h b/include/linux/page-flags.h
index 93a6f27cb45..7cdd56c8cc3 100644
--- a/include/linux/page-flags.h
+++ b/include/linux/page-flags.h
@@ -47,7 +47,7 @@
  * locked- and dirty-page accounting.  The top eight bits of page->flags are
  * used for page->zone, so putting flag bits there doesn't work.
  */
-#define PG_locked	 0	/* Page is locked. Don't touch. */
+#define PG_locked	 	 0	/* Page is locked. Don't touch. */
 #define PG_error		 1
 #define PG_referenced		 2
 #define PG_uptodate		 3
@@ -65,6 +65,7 @@
 #define PG_private		12	/* Has something at ->private */
 #define PG_writeback		13	/* Page is under writeback */
 #define PG_nosave		15	/* Used for system suspend/resume */
+#define PG_chainlock		16	/* lock bit for ->pte_chain */
 
 /*
  * Global page accounting.  One instance per CPU.
@@ -216,6 +217,31 @@ extern void get_page_state(struct page_state *ret);
 #define ClearPageNosave(page)		clear_bit(PG_nosave, &(page)->flags)
 #define TestClearPageNosave(page)	test_and_clear_bit(PG_nosave, &(page)->flags)
 
+/*
+ * inlines for acquisition and release of PG_chainlock
+ */
+static inline void pte_chain_lock(struct page *page)
+{
+	/*
+	 * Assuming the lock is uncontended, this never enters
+	 * the body of the outer loop. If it is contended, then
+	 * within the inner loop a non-atomic test is used to
+	 * busywait with less bus contention for a good time to
+	 * attempt to acquire the lock bit.
+	 */
+	preempt_disable();
+	while (test_and_set_bit(PG_chainlock, &page->flags)) {
+		while (test_bit(PG_chainlock, &page->flags))
+			cpu_relax();
+	}
+}
+
+static inline void pte_chain_unlock(struct page *page)
+{
+	clear_bit(PG_chainlock, &page->flags);
+	preempt_enable();
+}
+
 /*
  * The PageSwapCache predicate doesn't use a PG_flag at this time,
  * but it may again do so one day.
diff --git a/include/linux/swap.h b/include/linux/swap.h
index 0b448a811a3..8ba0854d69a 100644
--- a/include/linux/swap.h
+++ b/include/linux/swap.h
@@ -142,6 +142,19 @@ struct sysinfo;
 struct address_space;
 struct zone_t;
 
+/* linux/mm/rmap.c */
+extern int FASTCALL(page_referenced(struct page *));
+extern void FASTCALL(page_add_rmap(struct page *, pte_t *));
+extern void FASTCALL(page_remove_rmap(struct page *, pte_t *));
+extern int FASTCALL(try_to_unmap(struct page *));
+extern int FASTCALL(page_over_rsslimit(struct page *));
+
+/* return values of try_to_unmap */
+#define	SWAP_SUCCESS	0
+#define	SWAP_AGAIN	1
+#define	SWAP_FAIL	2
+#define	SWAP_ERROR	3
+
 /* linux/mm/swap.c */
 extern void FASTCALL(lru_cache_add(struct page *));
 extern void FASTCALL(__lru_cache_del(struct page *));
@@ -168,6 +181,7 @@ int rw_swap_page_sync(int rw, swp_entry_t entry, struct page *page);
 extern void show_swap_cache_info(void);
 #endif
 extern int add_to_swap_cache(struct page *, swp_entry_t);
+extern int add_to_swap(struct page *);
 extern void __delete_from_swap_cache(struct page *page);
 extern void delete_from_swap_cache(struct page *page);
 extern int move_to_swap_cache(struct page *page, swp_entry_t entry);
diff --git a/kernel/fork.c b/kernel/fork.c
index 1221b31e9c9..c0fb979902f 100644
--- a/kernel/fork.c
+++ b/kernel/fork.c
@@ -189,7 +189,6 @@ static inline int dup_mmap(struct mm_struct * mm)
 	mm->map_count = 0;
 	mm->rss = 0;
 	mm->cpu_vm_mask = 0;
-	mm->swap_address = 0;
 	pprev = &mm->mmap;
 
 	/*
@@ -308,9 +307,6 @@ inline void __mmdrop(struct mm_struct *mm)
 void mmput(struct mm_struct *mm)
 {
 	if (atomic_dec_and_lock(&mm->mm_users, &mmlist_lock)) {
-		extern struct mm_struct *swap_mm;
-		if (swap_mm == mm)
-			swap_mm = list_entry(mm->mmlist.next, struct mm_struct, mmlist);
 		list_del(&mm->mmlist);
 		mmlist_nr--;
 		spin_unlock(&mmlist_lock);
diff --git a/mm/Makefile b/mm/Makefile
index bcc0c36c23a..6bb872cf202 100644
--- a/mm/Makefile
+++ b/mm/Makefile
@@ -16,6 +16,6 @@ obj-y	 := memory.o mmap.o filemap.o mprotect.o mlock.o mremap.o \
 	    vmalloc.o slab.o bootmem.o swap.o vmscan.o page_io.o \
 	    page_alloc.o swap_state.o swapfile.o numa.o oom_kill.o \
 	    shmem.o highmem.o mempool.o msync.o mincore.o readahead.o \
-	    pdflush.o page-writeback.o
+	    pdflush.o page-writeback.o rmap.o
 
 include $(TOPDIR)/Rules.make
diff --git a/mm/filemap.c b/mm/filemap.c
index e755d89071e..d7a4970c68a 100644
--- a/mm/filemap.c
+++ b/mm/filemap.c
@@ -176,14 +176,13 @@ static inline void truncate_partial_page(struct page *page, unsigned partial)
  */
 static void truncate_complete_page(struct page *page)
 {
-	/* Leave it on the LRU if it gets converted into anonymous buffers */
-	if (!PagePrivate(page) || do_invalidatepage(page, 0)) {
-		lru_cache_del(page);
-	} else {
+	/* Drop fs-specific data so the page might become freeable. */
+	if (PagePrivate(page) && !do_invalidatepage(page, 0)) {
 		if (current->flags & PF_INVALIDATE)
 			printk("%s: buffer heads were leaked\n",
 				current->comm);
 	}
+
 	ClearPageDirty(page);
 	ClearPageUptodate(page);
 	remove_inode_page(page);
@@ -660,7 +659,7 @@ EXPORT_SYMBOL(wait_on_page_bit);
  * But that's OK - sleepers in wait_on_page_writeback() just go back to sleep.
  *
  * The first mb is necessary to safely close the critical section opened by the
- * TryLockPage(), the second mb is necessary to enforce ordering between
+ * TestSetPageLocked(), the second mb is necessary to enforce ordering between
  * the clear_bit and the read of the waitqueue (to avoid SMP races with a
  * parallel wait_on_page_locked()).
  */
diff --git a/mm/memory.c b/mm/memory.c
index a9691d59728..c2455084c4d 100644
--- a/mm/memory.c
+++ b/mm/memory.c
@@ -46,6 +46,7 @@
 #include <linux/pagemap.h>
 
 #include <asm/pgalloc.h>
+#include <asm/rmap.h>
 #include <asm/uaccess.h>
 #include <asm/tlb.h>
 #include <asm/tlbflush.h>
@@ -79,7 +80,7 @@ struct page *mem_map;
  */
 static inline void free_one_pmd(mmu_gather_t *tlb, pmd_t * dir)
 {
-	struct page *pte;
+	struct page *page;
 
 	if (pmd_none(*dir))
 		return;
@@ -88,9 +89,10 @@ static inline void free_one_pmd(mmu_gather_t *tlb, pmd_t * dir)
 		pmd_clear(dir);
 		return;
 	}
-	pte = pmd_page(*dir);
+	page = pmd_page(*dir);
 	pmd_clear(dir);
-	pte_free_tlb(tlb, pte);
+	pgtable_remove_rmap(page);
+	pte_free_tlb(tlb, page);
 }
 
 static inline void free_one_pgd(mmu_gather_t *tlb, pgd_t * dir)
@@ -150,6 +152,7 @@ pte_t * pte_alloc_map(struct mm_struct *mm, pmd_t *pmd, unsigned long address)
 			pte_free(new);
 			goto out;
 		}
+		pgtable_add_rmap(new, mm, address);
 		pmd_populate(mm, pmd, new);
 	}
 out:
@@ -177,6 +180,7 @@ pte_t * pte_alloc_kernel(struct mm_struct *mm, pmd_t *pmd, unsigned long address
 			pte_free_kernel(new);
 			goto out;
 		}
+		pgtable_add_rmap(virt_to_page(new), mm, address);
 		pmd_populate_kernel(mm, pmd, new);
 	}
 out:
@@ -260,10 +264,13 @@ skip_copy_pte_range:		address = (address + PMD_SIZE) & PMD_MASK;
 
 				if (pte_none(pte))
 					goto cont_copy_pte_range_noset;
+				/* pte contains position in swap, so copy. */
 				if (!pte_present(pte)) {
 					swap_duplicate(pte_to_swp_entry(pte));
-					goto cont_copy_pte_range;
+					set_pte(dst_pte, pte);
+					goto cont_copy_pte_range_noset;
 				}
+				ptepage = pte_page(pte);
 				pfn = pte_pfn(pte);
 				if (!pfn_valid(pfn))
 					goto cont_copy_pte_range;
@@ -272,7 +279,7 @@ skip_copy_pte_range:		address = (address + PMD_SIZE) & PMD_MASK;
 					goto cont_copy_pte_range;
 
 				/* If it's a COW mapping, write protect it both in the parent and the child */
-				if (cow && pte_write(pte)) {
+				if (cow) {
 					ptep_set_wrprotect(src_pte);
 					pte = *src_pte;
 				}
@@ -285,6 +292,7 @@ skip_copy_pte_range:		address = (address + PMD_SIZE) & PMD_MASK;
 				dst->rss++;
 
 cont_copy_pte_range:		set_pte(dst_pte, pte);
+				page_add_rmap(ptepage, dst_pte);
 cont_copy_pte_range_noset:	address += PAGE_SIZE;
 				if (address >= end) {
 					pte_unmap_nested(src_pte);
@@ -342,6 +350,7 @@ static void zap_pte_range(mmu_gather_t *tlb, pmd_t * pmd, unsigned long address,
 					if (pte_dirty(pte))
 						set_page_dirty(page);
 					tlb->freed++;
+					page_remove_rmap(page, ptep);
 					tlb_remove_page(tlb, page);
 				}
 			}
@@ -992,7 +1001,9 @@ static int do_wp_page(struct mm_struct *mm, struct vm_area_struct * vma,
 	if (pte_same(*page_table, pte)) {
 		if (PageReserved(old_page))
 			++mm->rss;
+		page_remove_rmap(old_page, page_table);
 		break_cow(vma, new_page, address, page_table);
+		page_add_rmap(new_page, page_table);
 		lru_cache_add(new_page);
 
 		/* Free the old page.. */
@@ -1199,6 +1210,7 @@ static int do_swap_page(struct mm_struct * mm,
 	flush_page_to_ram(page);
 	flush_icache_page(vma, page);
 	set_pte(page_table, pte);
+	page_add_rmap(page, page_table);
 
 	/* No need to invalidate - it was non-present before */
 	update_mmu_cache(vma, address, pte);
@@ -1215,14 +1227,13 @@ static int do_swap_page(struct mm_struct * mm,
 static int do_anonymous_page(struct mm_struct * mm, struct vm_area_struct * vma, pte_t *page_table, pmd_t *pmd, int write_access, unsigned long addr)
 {
 	pte_t entry;
+	struct page * page = ZERO_PAGE(addr);
 
 	/* Read-only mapping of ZERO_PAGE. */
 	entry = pte_wrprotect(mk_pte(ZERO_PAGE(addr), vma->vm_page_prot));
 
 	/* ..except if it's a write access */
 	if (write_access) {
-		struct page *page;
-
 		/* Allocate our own private page. */
 		pte_unmap(page_table);
 		spin_unlock(&mm->page_table_lock);
@@ -1248,6 +1259,7 @@ static int do_anonymous_page(struct mm_struct * mm, struct vm_area_struct * vma,
 	}
 
 	set_pte(page_table, entry);
+	page_add_rmap(page, page_table); /* ignores ZERO_PAGE */
 	pte_unmap(page_table);
 
 	/* No need to invalidate - it was non-present before */
@@ -1327,6 +1339,7 @@ static int do_no_page(struct mm_struct * mm, struct vm_area_struct * vma,
 		if (write_access)
 			entry = pte_mkwrite(pte_mkdirty(entry));
 		set_pte(page_table, entry);
+		page_add_rmap(new_page, page_table);
 		pte_unmap(page_table);
 	} else {
 		/* One of our sibling threads was faster, back out. */
diff --git a/mm/mremap.c b/mm/mremap.c
index 8056fcfebf0..91b16a6e053 100644
--- a/mm/mremap.c
+++ b/mm/mremap.c
@@ -68,8 +68,14 @@ static inline int copy_one_pte(struct mm_struct *mm, pte_t * src, pte_t * dst)
 {
 	int error = 0;
 	pte_t pte;
+	struct page * page = NULL;
+
+	if (pte_present(*src))
+		page = pte_page(*src);
 
 	if (!pte_none(*src)) {
+		if (page)
+			page_remove_rmap(page, src);
 		pte = ptep_get_and_clear(src);
 		if (!dst) {
 			/* No dest?  We must put it back. */
@@ -77,6 +83,8 @@ static inline int copy_one_pte(struct mm_struct *mm, pte_t * src, pte_t * dst)
 			error++;
 		}
 		set_pte(dst, pte);
+		if (page)
+			page_add_rmap(page, dst);
 	}
 	return error;
 }
diff --git a/mm/page_alloc.c b/mm/page_alloc.c
index ce2cfafca09..e34b71e2db7 100644
--- a/mm/page_alloc.c
+++ b/mm/page_alloc.c
@@ -92,6 +92,7 @@ static void __free_pages_ok (struct page *page, unsigned int order)
 	BUG_ON(PageLRU(page));
 	BUG_ON(PageActive(page));
 	BUG_ON(PageWriteback(page));
+	BUG_ON(page->pte_chain != NULL);
 	if (PageDirty(page))
 		ClearPageDirty(page);
 	BUG_ON(page_count(page) != 0);
diff --git a/mm/rmap.c b/mm/rmap.c
new file mode 100644
index 00000000000..e41198daee5
--- /dev/null
+++ b/mm/rmap.c
@@ -0,0 +1,394 @@
+/*
+ * mm/rmap.c - physical to virtual reverse mappings
+ *
+ * Copyright 2001, Rik van Riel <riel@conectiva.com.br>
+ * Released under the General Public License (GPL).
+ *
+ *
+ * Simple, low overhead pte-based reverse mapping scheme.
+ * This is kept modular because we may want to experiment
+ * with object-based reverse mapping schemes. Please try
+ * to keep this thing as modular as possible.
+ */
+
+/*
+ * Locking:
+ * - the page->pte_chain is protected by the PG_chainlock bit,
+ *   which nests within the pagemap_lru_lock, then the
+ *   mm->page_table_lock, and then the page lock.
+ * - because swapout locking is opposite to the locking order
+ *   in the page fault path, the swapout path uses trylocks
+ *   on the mm->page_table_lock
+ */
+#include <linux/mm.h>
+#include <linux/pagemap.h>
+#include <linux/swapops.h>
+
+#include <asm/pgalloc.h>
+#include <asm/rmap.h>
+#include <asm/smplock.h>
+#include <asm/tlb.h>
+#include <asm/tlbflush.h>
+
+/* #define DEBUG_RMAP */
+
+/*
+ * Shared pages have a chain of pte_chain structures, used to locate
+ * all the mappings to this page. We only need a pointer to the pte
+ * here, the page struct for the page table page contains the process
+ * it belongs to and the offset within that process.
+ *
+ * A singly linked list should be fine for most, if not all, workloads.
+ * On fork-after-exec the mapping we'll be removing will still be near
+ * the start of the list, on mixed application systems the short-lived
+ * processes will have their mappings near the start of the list and
+ * in systems with long-lived applications the relative overhead of
+ * exit() will be lower since the applications are long-lived.
+ */
+struct pte_chain {
+	struct pte_chain * next;
+	pte_t * ptep;
+};
+
+static inline struct pte_chain * pte_chain_alloc(void);
+static inline void pte_chain_free(struct pte_chain *, struct pte_chain *,
+		struct page *);
+static void alloc_new_pte_chains(void);
+
+/**
+ * page_referenced - test if the page was referenced
+ * @page: the page to test
+ *
+ * Quick test_and_clear_referenced for all mappings to a page,
+ * returns the number of processes which referenced the page.
+ * Caller needs to hold the pte_chain_lock.
+ */
+int page_referenced(struct page * page)
+{
+	struct pte_chain * pc;
+	int referenced = 0;
+
+	if (TestClearPageReferenced(page))
+		referenced++;
+
+	/* Check all the page tables mapping this page. */
+	for (pc = page->pte_chain; pc; pc = pc->next) {
+		if (ptep_test_and_clear_young(pc->ptep))
+			referenced++;
+	}
+	return referenced;
+}
+
+/**
+ * page_add_rmap - add reverse mapping entry to a page
+ * @page: the page to add the mapping to
+ * @ptep: the page table entry mapping this page
+ *
+ * Add a new pte reverse mapping to a page.
+ * The caller needs to hold the mm->page_table_lock.
+ */
+void page_add_rmap(struct page * page, pte_t * ptep)
+{
+	struct pte_chain * pte_chain;
+	unsigned long pfn = pte_pfn(*ptep);
+
+#ifdef DEBUG_RMAP
+	if (!page || !ptep)
+		BUG();
+	if (!pte_present(*ptep))
+		BUG();
+	if (!ptep_to_mm(ptep))
+		BUG();
+#endif
+
+	if (!pfn_valid(pfn) || PageReserved(page))
+		return;
+
+#ifdef DEBUG_RMAP
+	pte_chain_lock(page);
+	{
+		struct pte_chain * pc;
+		for (pc = page->pte_chain; pc; pc = pc->next) {
+			if (pc->ptep == ptep)
+				BUG();
+		}
+	}
+	pte_chain_unlock(page);
+#endif
+
+	pte_chain = pte_chain_alloc();
+
+	pte_chain_lock(page);
+
+	/* Hook up the pte_chain to the page. */
+	pte_chain->ptep = ptep;
+	pte_chain->next = page->pte_chain;
+	page->pte_chain = pte_chain;
+
+	pte_chain_unlock(page);
+}
+
+/**
+ * page_remove_rmap - take down reverse mapping to a page
+ * @page: page to remove mapping from
+ * @ptep: page table entry to remove
+ *
+ * Removes the reverse mapping from the pte_chain of the page,
+ * after that the caller can clear the page table entry and free
+ * the page.
+ * Caller needs to hold the mm->page_table_lock.
+ */
+void page_remove_rmap(struct page * page, pte_t * ptep)
+{
+	struct pte_chain * pc, * prev_pc = NULL;
+	unsigned long pfn = pte_pfn(*ptep);
+
+	if (!page || !ptep)
+		BUG();
+	if (!pfn_valid(pfn) || PageReserved(page))
+		return;
+
+	pte_chain_lock(page);
+	for (pc = page->pte_chain; pc; prev_pc = pc, pc = pc->next) {
+		if (pc->ptep == ptep) {
+			pte_chain_free(pc, prev_pc, page);
+			goto out;
+		}
+	}
+#ifdef DEBUG_RMAP
+	/* Not found. This should NEVER happen! */
+	printk(KERN_ERR "page_remove_rmap: pte_chain %p not present.\n", ptep);
+	printk(KERN_ERR "page_remove_rmap: only found: ");
+	for (pc = page->pte_chain; pc; pc = pc->next)
+		printk("%p ", pc->ptep);
+	printk("\n");
+	printk(KERN_ERR "page_remove_rmap: driver cleared PG_reserved ?\n");
+#endif
+
+out:
+	pte_chain_unlock(page);
+	return;
+			
+}
+
+/**
+ * try_to_unmap_one - worker function for try_to_unmap
+ * @page: page to unmap
+ * @ptep: page table entry to unmap from page
+ *
+ * Internal helper function for try_to_unmap, called for each page
+ * table entry mapping a page. Because locking order here is opposite
+ * to the locking order used by the page fault path, we use trylocks.
+ * Locking:
+ *	pagemap_lru_lock		page_launder()
+ *	    page lock			page_launder(), trylock
+ *		pte_chain_lock		page_launder()
+ *		    mm->page_table_lock	try_to_unmap_one(), trylock
+ */
+static int FASTCALL(try_to_unmap_one(struct page *, pte_t *));
+static int try_to_unmap_one(struct page * page, pte_t * ptep)
+{
+	unsigned long address = ptep_to_address(ptep);
+	struct mm_struct * mm = ptep_to_mm(ptep);
+	struct vm_area_struct * vma;
+	pte_t pte;
+	int ret;
+
+	if (!mm)
+		BUG();
+
+	/*
+	 * We need the page_table_lock to protect us from page faults,
+	 * munmap, fork, etc...
+	 */
+	if (!spin_trylock(&mm->page_table_lock))
+		return SWAP_AGAIN;
+
+	/* During mremap, it's possible pages are not in a VMA. */
+	vma = find_vma(mm, address);
+	if (!vma) {
+		ret = SWAP_FAIL;
+		goto out_unlock;
+	}
+
+	/* The page is mlock()d, we cannot swap it out. */
+	if (vma->vm_flags & VM_LOCKED) {
+		ret = SWAP_FAIL;
+		goto out_unlock;
+	}
+
+	/* Nuke the page table entry. */
+	pte = ptep_get_and_clear(ptep);
+	flush_tlb_page(vma, address);
+	flush_cache_page(vma, address);
+
+	/* Store the swap location in the pte. See handle_pte_fault() ... */
+	if (PageSwapCache(page)) {
+		swp_entry_t entry;
+		entry.val = page->index;
+		swap_duplicate(entry);
+		set_pte(ptep, swp_entry_to_pte(entry));
+	}
+
+	/* Move the dirty bit to the physical page now the pte is gone. */
+	if (pte_dirty(pte))
+		set_page_dirty(page);
+
+	mm->rss--;
+	page_cache_release(page);
+	ret = SWAP_SUCCESS;
+
+out_unlock:
+	spin_unlock(&mm->page_table_lock);
+	return ret;
+}
+
+/**
+ * try_to_unmap - try to remove all page table mappings to a page
+ * @page: the page to get unmapped
+ *
+ * Tries to remove all the page table entries which are mapping this
+ * page, used in the pageout path.  Caller must hold pagemap_lru_lock
+ * and the page lock.  Return values are:
+ *
+ * SWAP_SUCCESS	- we succeeded in removing all mappings
+ * SWAP_AGAIN	- we missed a trylock, try again later
+ * SWAP_FAIL	- the page is unswappable
+ * SWAP_ERROR	- an error occurred
+ */
+int try_to_unmap(struct page * page)
+{
+	struct pte_chain * pc, * next_pc, * prev_pc = NULL;
+	int ret = SWAP_SUCCESS;
+
+	/* This page should not be on the pageout lists. */
+	if (PageReserved(page))
+		BUG();
+	if (!PageLocked(page))
+		BUG();
+	/* We need backing store to swap out a page. */
+	if (!page->mapping)
+		BUG();
+
+	for (pc = page->pte_chain; pc; pc = next_pc) {
+		next_pc = pc->next;
+		switch (try_to_unmap_one(page, pc->ptep)) {
+			case SWAP_SUCCESS:
+				/* Free the pte_chain struct. */
+				pte_chain_free(pc, prev_pc, page);
+				break;
+			case SWAP_AGAIN:
+				/* Skip this pte, remembering status. */
+				prev_pc = pc;
+				ret = SWAP_AGAIN;
+				continue;
+			case SWAP_FAIL:
+				return SWAP_FAIL;
+			case SWAP_ERROR:
+				return SWAP_ERROR;
+		}
+	}
+
+	return ret;
+}
+
+/**
+ ** No more VM stuff below this comment, only pte_chain helper
+ ** functions.
+ **/
+
+struct pte_chain * pte_chain_freelist;
+spinlock_t pte_chain_freelist_lock = SPIN_LOCK_UNLOCKED;
+
+/* Maybe we should have standard ops for singly linked lists ... - Rik */
+static inline void pte_chain_push(struct pte_chain * pte_chain)
+{
+	pte_chain->ptep = NULL;
+	pte_chain->next = pte_chain_freelist;
+	pte_chain_freelist = pte_chain;
+}
+
+static inline struct pte_chain * pte_chain_pop(void)
+{
+	struct pte_chain *pte_chain;
+
+	pte_chain = pte_chain_freelist;
+	pte_chain_freelist = pte_chain->next;
+	pte_chain->next = NULL;
+
+	return pte_chain;
+}
+
+/**
+ * pte_chain_free - free pte_chain structure
+ * @pte_chain: pte_chain struct to free
+ * @prev_pte_chain: previous pte_chain on the list (may be NULL)
+ * @page: page this pte_chain hangs off (may be NULL)
+ *
+ * This function unlinks pte_chain from the singly linked list it
+ * may be on and adds the pte_chain to the free list. May also be
+ * called for new pte_chain structures which aren't on any list yet.
+ * Caller needs to hold the pte_chain_lock if the page is non-NULL.
+ */
+static inline void pte_chain_free(struct pte_chain * pte_chain,
+		struct pte_chain * prev_pte_chain, struct page * page)
+{
+	if (prev_pte_chain)
+		prev_pte_chain->next = pte_chain->next;
+	else if (page)
+		page->pte_chain = pte_chain->next;
+
+	spin_lock(&pte_chain_freelist_lock);
+	pte_chain_push(pte_chain);
+	spin_unlock(&pte_chain_freelist_lock);
+}
+
+/**
+ * pte_chain_alloc - allocate a pte_chain struct
+ *
+ * Returns a pointer to a fresh pte_chain structure. Allocates new
+ * pte_chain structures as required.
+ * Caller needs to hold the page's pte_chain_lock.
+ */
+static inline struct pte_chain * pte_chain_alloc()
+{
+	struct pte_chain * pte_chain;
+
+	spin_lock(&pte_chain_freelist_lock);
+
+	/* Allocate new pte_chain structs as needed. */
+	if (!pte_chain_freelist)
+		alloc_new_pte_chains();
+
+	/* Grab the first pte_chain from the freelist. */
+	pte_chain = pte_chain_pop();
+
+	spin_unlock(&pte_chain_freelist_lock);
+
+	return pte_chain;
+}
+
+/**
+ * alloc_new_pte_chains - convert a free page to pte_chain structures
+ *
+ * Grabs a free page and converts it to pte_chain structures. We really
+ * should pre-allocate these earlier in the pagefault path or come up
+ * with some other trick.
+ *
+ * Note that we cannot use the slab cache because the pte_chain structure
+ * is way smaller than the minimum size of a slab cache allocation.
+ * Caller needs to hold the pte_chain_freelist_lock
+ */
+static void alloc_new_pte_chains()
+{
+	struct pte_chain * pte_chain = (void *) get_zeroed_page(GFP_ATOMIC);
+	int i = PAGE_SIZE / sizeof(struct pte_chain);
+
+	if (pte_chain) {
+		for (; i-- > 0; pte_chain++)
+			pte_chain_push(pte_chain);
+	} else {
+		/* Yeah yeah, I'll fix the pte_chain allocation ... */
+		panic("Fix pte_chain allocation, you lazy bastard!\n");
+	}
+}
diff --git a/mm/swap_state.c b/mm/swap_state.c
index 7386e49ccf3..044f71d6bda 100644
--- a/mm/swap_state.c
+++ b/mm/swap_state.c
@@ -105,6 +105,69 @@ void __delete_from_swap_cache(struct page *page)
 	INC_CACHE_INFO(del_total);
 }
 
+/**
+ * add_to_swap - allocate swap space for a page
+ * @page: page we want to move to swap
+ *
+ * Allocate swap space for the page and add the page to the
+ * swap cache.  Caller needs to hold the page lock. 
+ */
+int add_to_swap(struct page * page)
+{
+	swp_entry_t entry;
+	int flags;
+
+	if (!PageLocked(page))
+		BUG();
+
+	for (;;) {
+		entry = get_swap_page();
+		if (!entry.val)
+			return 0;
+
+		/* Radix-tree node allocations are performing
+		 * GFP_ATOMIC allocations under PF_MEMALLOC.  
+		 * They can completely exhaust the page allocator.  
+		 *
+		 * So PF_MEMALLOC is dropped here.  This causes the slab 
+		 * allocations to fail earlier, so radix-tree nodes will 
+		 * then be allocated from the mempool reserves.
+		 *
+		 * We're still using __GFP_HIGH for radix-tree node
+		 * allocations, so some of the emergency pools are available,
+		 * just not all of them.
+		 */
+
+		flags = current->flags;
+		current->flags &= ~PF_MEMALLOC;
+		current->flags |= PF_NOWARN;
+		ClearPageUptodate(page);		/* why? */
+
+		/*
+		 * Add it to the swap cache and mark it dirty
+		 * (adding to the page cache will clear the dirty
+		 * and uptodate bits, so we need to do it again)
+		 */
+		switch (add_to_swap_cache(page, entry)) {
+		case 0:				/* Success */
+			current->flags = flags;
+			SetPageUptodate(page);
+			set_page_dirty(page);
+			swap_free(entry);
+			return 1;
+		case -ENOMEM:			/* radix-tree allocation */
+			current->flags = flags;
+			swap_free(entry);
+			return 0;
+		default:			/* ENOENT: raced */
+			break;
+		}
+		/* Raced with "speculative" read_swap_cache_async */
+		current->flags = flags;
+		swap_free(entry);
+	}
+}
+
 /*
  * This must be called only on pages that have
  * been verified to be in the swap cache and locked.
diff --git a/mm/swapfile.c b/mm/swapfile.c
index 54d19a9a431..2479dfcc59f 100644
--- a/mm/swapfile.c
+++ b/mm/swapfile.c
@@ -383,6 +383,7 @@ static inline void unuse_pte(struct vm_area_struct * vma, unsigned long address,
 		return;
 	get_page(page);
 	set_pte(dir, pte_mkold(mk_pte(page, vma->vm_page_prot)));
+	page_add_rmap(page, dir);
 	swap_free(entry);
 	++vma->vm_mm->rss;
 }
diff --git a/mm/vmscan.c b/mm/vmscan.c
index 759fb8f7c43..eb1a51034a3 100644
--- a/mm/vmscan.c
+++ b/mm/vmscan.c
@@ -42,347 +42,23 @@ static inline int is_page_cache_freeable(struct page * page)
 	return page_count(page) - !!PagePrivate(page) == 1;
 }
 
-/*
- * On the swap_out path, the radix-tree node allocations are performing
- * GFP_ATOMIC allocations under PF_MEMALLOC.  They can completely
- * exhaust the page allocator.  This is bad; some pages should be left
- * available for the I/O system to start sending the swapcache contents
- * to disk.
- *
- * So PF_MEMALLOC is dropped here.  This causes the slab allocations to fail
- * earlier, so radix-tree nodes will then be allocated from the mempool
- * reserves.
- *
- * We're still using __GFP_HIGH for radix-tree node allocations, so some of
- * the emergency pools are available - just not all of them.
- */
-static inline int
-swap_out_add_to_swap_cache(struct page *page, swp_entry_t entry)
-{
-	int flags = current->flags;
-	int ret;
-
-	current->flags &= ~PF_MEMALLOC;
-	current->flags |= PF_NOWARN;
-	ClearPageUptodate(page);		/* why? */
-	ClearPageReferenced(page);		/* why? */
-	ret = add_to_swap_cache(page, entry);
-	current->flags = flags;
-	return ret;
-}
-
-/*
- * The swap-out function returns 1 if it successfully
- * scanned all the pages it was asked to (`count').
- * It returns zero if it couldn't do anything,
- *
- * rss may decrease because pages are shared, but this
- * doesn't count as having freed a page.
- */
-
-/* mm->page_table_lock is held. mmap_sem is not held */
-static inline int try_to_swap_out(struct mm_struct * mm, struct vm_area_struct* vma, unsigned long address, pte_t * page_table, struct page *page, zone_t * classzone)
+/* Must be called with page's pte_chain_lock held. */
+static inline int page_mapping_inuse(struct page * page)
 {
-	pte_t pte;
-	swp_entry_t entry;
+	struct address_space *mapping = page->mapping;
 
-	/* Don't look at this pte if it's been accessed recently. */
-	if ((vma->vm_flags & VM_LOCKED) || ptep_test_and_clear_young(page_table)) {
-		mark_page_accessed(page);
-		return 0;
-	}
+	/* Page is in somebody's page tables. */
+	if (page->pte_chain)
+		return 1;
 
-	/* Don't bother unmapping pages that are active */
-	if (PageActive(page))
+	/* XXX: does this happen ? */
+	if (!mapping)
 		return 0;
 
-	/* Don't bother replenishing zones not under pressure.. */
-	if (!memclass(page_zone(page), classzone))
-		return 0;
-
-	if (TestSetPageLocked(page))
-		return 0;
-
-	if (PageWriteback(page))
-		goto out_unlock;
-
-	/* From this point on, the odds are that we're going to
-	 * nuke this pte, so read and clear the pte.  This hook
-	 * is needed on CPUs which update the accessed and dirty
-	 * bits in hardware.
-	 */
-	flush_cache_page(vma, address);
-	pte = ptep_get_and_clear(page_table);
-	flush_tlb_page(vma, address);
-
-	if (pte_dirty(pte))
-		set_page_dirty(page);
-
-	/*
-	 * Is the page already in the swap cache? If so, then
-	 * we can just drop our reference to it without doing
-	 * any IO - it's already up-to-date on disk.
-	 */
-	if (PageSwapCache(page)) {
-		entry.val = page->index;
-		swap_duplicate(entry);
-set_swap_pte:
-		set_pte(page_table, swp_entry_to_pte(entry));
-drop_pte:
-		mm->rss--;
-		unlock_page(page);
-		{
-			int freeable = page_count(page) -
-				!!PagePrivate(page) <= 2;
-			page_cache_release(page);
-			return freeable;
-		}
-	}
+	/* File is mmap'd by somebody. */
+	if (!list_empty(&mapping->i_mmap) || !list_empty(&mapping->i_mmap_shared))
+		return 1;
 
-	/*
-	 * Is it a clean page? Then it must be recoverable
-	 * by just paging it in again, and we can just drop
-	 * it..  or if it's dirty but has backing store,
-	 * just mark the page dirty and drop it.
-	 *
-	 * However, this won't actually free any real
-	 * memory, as the page will just be in the page cache
-	 * somewhere, and as such we should just continue
-	 * our scan.
-	 *
-	 * Basically, this just makes it possible for us to do
-	 * some real work in the future in "refill_inactive()".
-	 */
-	if (page->mapping)
-		goto drop_pte;
-	if (!PageDirty(page))
-		goto drop_pte;
-
-	/*
-	 * Anonymous buffercache pages can be left behind by
-	 * concurrent truncate and pagefault.
-	 */
-	if (PagePrivate(page))
-		goto preserve;
-
-	/*
-	 * This is a dirty, swappable page.  First of all,
-	 * get a suitable swap entry for it, and make sure
-	 * we have the swap cache set up to associate the
-	 * page with that swap entry.
-	 */
-	for (;;) {
-		entry = get_swap_page();
-		if (!entry.val)
-			break;
-		/* Add it to the swap cache and mark it dirty
-		 * (adding to the page cache will clear the dirty
-		 * and uptodate bits, so we need to do it again)
-		 */
-		switch (swap_out_add_to_swap_cache(page, entry)) {
-		case 0:				/* Success */
-			SetPageUptodate(page);
-			set_page_dirty(page);
-			goto set_swap_pte;
-		case -ENOMEM:			/* radix-tree allocation */
-			swap_free(entry);
-			goto preserve;
-		default:			/* ENOENT: raced */
-			break;
-		}
-		/* Raced with "speculative" read_swap_cache_async */
-		swap_free(entry);
-	}
-
-	/* No swap space left */
-preserve:
-	set_pte(page_table, pte);
-out_unlock:
-	unlock_page(page);
-	return 0;
-}
-
-/* mm->page_table_lock is held. mmap_sem is not held */
-static inline int swap_out_pmd(struct mm_struct * mm, struct vm_area_struct * vma, pmd_t *dir, unsigned long address, unsigned long end, int count, zone_t * classzone)
-{
-	pte_t * pte;
-	unsigned long pmd_end;
-
-	if (pmd_none(*dir))
-		return count;
-	if (pmd_bad(*dir)) {
-		pmd_ERROR(*dir);
-		pmd_clear(dir);
-		return count;
-	}
-	
-	pte = pte_offset_map(dir, address);
-	
-	pmd_end = (address + PMD_SIZE) & PMD_MASK;
-	if (end > pmd_end)
-		end = pmd_end;
-
-	do {
-		if (pte_present(*pte)) {
-			unsigned long pfn = pte_pfn(*pte);
-			struct page *page = pfn_to_page(pfn);
-
-			if (pfn_valid(pfn) && !PageReserved(page)) {
-				count -= try_to_swap_out(mm, vma, address, pte, page, classzone);
-				if (!count) {
-					address += PAGE_SIZE;
-					pte++;
-					break;
-				}
-			}
-		}
-		address += PAGE_SIZE;
-		pte++;
-	} while (address && (address < end));
-	pte_unmap(pte - 1);
-	mm->swap_address = address;
-	return count;
-}
-
-/* mm->page_table_lock is held. mmap_sem is not held */
-static inline int swap_out_pgd(struct mm_struct * mm, struct vm_area_struct * vma, pgd_t *dir, unsigned long address, unsigned long end, int count, zone_t * classzone)
-{
-	pmd_t * pmd;
-	unsigned long pgd_end;
-
-	if (pgd_none(*dir))
-		return count;
-	if (pgd_bad(*dir)) {
-		pgd_ERROR(*dir);
-		pgd_clear(dir);
-		return count;
-	}
-
-	pmd = pmd_offset(dir, address);
-
-	pgd_end = (address + PGDIR_SIZE) & PGDIR_MASK;	
-	if (pgd_end && (end > pgd_end))
-		end = pgd_end;
-	
-	do {
-		count = swap_out_pmd(mm, vma, pmd, address, end, count, classzone);
-		if (!count)
-			break;
-		address = (address + PMD_SIZE) & PMD_MASK;
-		pmd++;
-	} while (address && (address < end));
-	return count;
-}
-
-/* mm->page_table_lock is held. mmap_sem is not held */
-static inline int swap_out_vma(struct mm_struct * mm, struct vm_area_struct * vma, unsigned long address, int count, zone_t * classzone)
-{
-	pgd_t *pgdir;
-	unsigned long end;
-
-	/* Don't swap out areas which are reserved */
-	if (vma->vm_flags & VM_RESERVED)
-		return count;
-
-	pgdir = pgd_offset(mm, address);
-
-	end = vma->vm_end;
-	if (address >= end)
-		BUG();
-	do {
-		count = swap_out_pgd(mm, vma, pgdir, address, end, count, classzone);
-		if (!count)
-			break;
-		address = (address + PGDIR_SIZE) & PGDIR_MASK;
-		pgdir++;
-	} while (address && (address < end));
-	return count;
-}
-
-/* Placeholder for swap_out(): may be updated by fork.c:mmput() */
-struct mm_struct *swap_mm = &init_mm;
-
-/*
- * Returns remaining count of pages to be swapped out by followup call.
- */
-static inline int swap_out_mm(struct mm_struct * mm, int count, int * mmcounter, zone_t * classzone)
-{
-	unsigned long address;
-	struct vm_area_struct* vma;
-
-	/*
-	 * Find the proper vm-area after freezing the vma chain 
-	 * and ptes.
-	 */
-	spin_lock(&mm->page_table_lock);
-	address = mm->swap_address;
-	if (address == TASK_SIZE || swap_mm != mm) {
-		/* We raced: don't count this mm but try again */
-		++*mmcounter;
-		goto out_unlock;
-	}
-	vma = find_vma(mm, address);
-	if (vma) {
-		if (address < vma->vm_start)
-			address = vma->vm_start;
-
-		for (;;) {
-			count = swap_out_vma(mm, vma, address, count, classzone);
-			vma = vma->vm_next;
-			if (!vma)
-				break;
-			if (!count)
-				goto out_unlock;
-			address = vma->vm_start;
-		}
-	}
-	/* Indicate that we reached the end of address space */
-	mm->swap_address = TASK_SIZE;
-
-out_unlock:
-	spin_unlock(&mm->page_table_lock);
-	return count;
-}
-
-static int FASTCALL(swap_out(unsigned int priority, unsigned int gfp_mask, zone_t * classzone));
-static int swap_out(unsigned int priority, unsigned int gfp_mask, zone_t * classzone)
-{
-	int counter, nr_pages = SWAP_CLUSTER_MAX;
-	struct mm_struct *mm;
-
-	counter = mmlist_nr;
-	do {
-		if (need_resched()) {
-			__set_current_state(TASK_RUNNING);
-			schedule();
-		}
-
-		spin_lock(&mmlist_lock);
-		mm = swap_mm;
-		while (mm->swap_address == TASK_SIZE || mm == &init_mm) {
-			mm->swap_address = 0;
-			mm = list_entry(mm->mmlist.next, struct mm_struct, mmlist);
-			if (mm == swap_mm)
-				goto empty;
-			swap_mm = mm;
-		}
-
-		/* Make sure the mm doesn't disappear when we drop the lock.. */
-		atomic_inc(&mm->mm_users);
-		spin_unlock(&mmlist_lock);
-
-		nr_pages = swap_out_mm(mm, nr_pages, &counter, classzone);
-
-		mmput(mm);
-
-		if (!nr_pages)
-			return 1;
-	} while (--counter >= 0);
-
-	return 0;
-
-empty:
-	spin_unlock(&mmlist_lock);
 	return 0;
 }
 
@@ -392,7 +68,6 @@ shrink_cache(int nr_pages, zone_t *classzone,
 {
 	struct list_head * entry;
 	struct address_space *mapping;
-	int max_mapped = nr_pages << (9 - priority);
 
 	spin_lock(&pagemap_lru_lock);
 	while (--max_scan >= 0 &&
@@ -428,10 +103,6 @@ shrink_cache(int nr_pages, zone_t *classzone,
 		if (!memclass(page_zone(page), classzone))
 			continue;
 
-		/* Racy check to avoid trylocking when not worthwhile */
-		if (!PagePrivate(page) && (page_count(page) != 1 || !page->mapping))
-			goto page_mapped;
-
 		/*
 		 * swap activity never enters the filesystem and is safe
 		 * for GFP_NOFS allocations.
@@ -461,6 +132,59 @@ shrink_cache(int nr_pages, zone_t *classzone,
 			continue;
 		}
 
+		/*
+		 * The page is in active use or really unfreeable. Move to
+		 * the active list.
+		 */
+		pte_chain_lock(page);
+		if (page_referenced(page) && page_mapping_inuse(page)) {
+			del_page_from_inactive_list(page);
+			add_page_to_active_list(page);
+			pte_chain_unlock(page);
+			unlock_page(page);
+			continue;
+		}
+
+		/*
+		 * Anonymous process memory without backing store. Try to
+		 * allocate it some swap space here.
+		 *
+		 * XXX: implement swap clustering ?
+		 */
+		if (page->pte_chain && !page->mapping && !PagePrivate(page)) {
+			page_cache_get(page);
+			pte_chain_unlock(page);
+			spin_unlock(&pagemap_lru_lock);
+			if (!add_to_swap(page)) {
+				activate_page(page);
+				unlock_page(page);
+				page_cache_release(page);
+				spin_lock(&pagemap_lru_lock);
+				continue;
+			}
+			page_cache_release(page);
+			spin_lock(&pagemap_lru_lock);
+			pte_chain_lock(page);
+		}
+
+		/*
+		 * The page is mapped into the page tables of one or more
+		 * processes. Try to unmap it here.
+		 */
+		if (page->pte_chain) {
+			switch (try_to_unmap(page)) {
+				case SWAP_ERROR:
+				case SWAP_FAIL:
+					goto page_active;
+				case SWAP_AGAIN:
+					pte_chain_unlock(page);
+					unlock_page(page);
+					continue;
+				case SWAP_SUCCESS:
+					; /* try to free the page below */
+			}
+		}
+		pte_chain_unlock(page);
 		mapping = page->mapping;
 
 		if (PageDirty(page) && is_page_cache_freeable(page) &&
@@ -469,7 +193,7 @@ shrink_cache(int nr_pages, zone_t *classzone,
 			 * It is not critical here to write it only if
 			 * the page is unmapped beause any direct writer
 			 * like O_DIRECT would set the page's dirty bitflag
-			 * on the phisical page after having successfully
+			 * on the physical page after having successfully
 			 * pinned it and after the I/O to the page is finished,
 			 * so the direct writes to the page cannot get lost.
 			 */
@@ -557,18 +281,7 @@ shrink_cache(int nr_pages, zone_t *classzone,
 			write_unlock(&mapping->page_lock);
 		}
 		unlock_page(page);
-page_mapped:
-		if (--max_mapped >= 0)
-			continue;
-
-		/*
-		 * Alert! We've found too many mapped pages on the
-		 * inactive list, so we start swapping out now!
-		 */
-		spin_unlock(&pagemap_lru_lock);
-		swap_out(priority, gfp_mask, classzone);
-		return nr_pages;
-
+		continue;
 page_freeable:
 		/*
 		 * It is critical to check PageDirty _after_ we made sure
@@ -597,13 +310,21 @@ page_freeable:
 
 		/* effectively free the page here */
 		page_cache_release(page);
-
 		if (--nr_pages)
 			continue;
-		break;
+		goto out;
+page_active:
+		/*
+		 * OK, we don't know what to do with the page.
+		 * It's no use keeping it here, so we move it to
+		 * the active list.
+		 */
+		del_page_from_inactive_list(page);
+		add_page_to_active_list(page);
+		pte_chain_unlock(page);
+		unlock_page(page);
 	}
-	spin_unlock(&pagemap_lru_lock);
-
+out:	spin_unlock(&pagemap_lru_lock);
 	return nr_pages;
 }
 
@@ -611,8 +332,8 @@ page_freeable:
  * This moves pages from the active list to
  * the inactive list.
  *
- * We move them the other way when we see the
- * reference bit on the page.
+ * We move them the other way if the page is 
+ * referenced by one or more processes, from rmap
  */
 static void refill_inactive(int nr_pages)
 {
@@ -625,15 +346,17 @@ static void refill_inactive(int nr_pages)
 
 		page = list_entry(entry, struct page, lru);
 		entry = entry->prev;
-		if (TestClearPageReferenced(page)) {
+
+		pte_chain_lock(page);
+		if (page->pte_chain && page_referenced(page)) {
 			list_del(&page->lru);
 			list_add(&page->lru, &active_list);
+			pte_chain_unlock(page);
 			continue;
 		}
-
 		del_page_from_active_list(page);
 		add_page_to_inactive_list(page);
-		SetPageReferenced(page);
+		pte_chain_unlock(page);
 	}
 	spin_unlock(&pagemap_lru_lock);
 }
-- 
2.42.0
```
