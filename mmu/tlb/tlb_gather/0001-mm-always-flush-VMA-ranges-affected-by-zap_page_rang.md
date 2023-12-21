```diff
From 4647706ebeee6e50f7b9f922b095f4ec94d581c3 Mon Sep 17 00:00:00 2001
From: Mel Gorman <mgorman@techsingularity.net>
Date: Wed, 6 Sep 2017 16:21:05 -0700
Subject: [PATCH] mm: always flush VMA ranges affected by zap_page_range

Nadav Amit report zap_page_range only specifies that the caller protect
the VMA list but does not specify whether it is held for read or write
with callers using either.  madvise holds mmap_sem for read meaning that
a parallel zap operation can unmap PTEs which are then potentially
skipped by madvise which potentially returns with stale TLB entries
present.  While the API could be extended, it would be a difficult API
to use.  This patch causes zap_page_range() to always consider flushing
the full affected range.  For small ranges or sparsely populated
mappings, this may result in one additional spurious TLB flush.  For
larger ranges, it is possible that the TLB has already been flushed and
the overhead is negligible.  Either way, this approach is safer overall
and avoids stale entries being present when madvise returns.

parallel [ˈpærəlel]: 平行的
stale [steɪl] : 不新鲜的;

Nadav Amit 报告了 zap_page_range 只能指定 调用者 保护 VMA list, 但是不能
指定 调用者是持有 读/ 写 (锁). madvise 持有 读 mmap_sem 意味着 平行的 zap 
操作 可以 unmap PTEs, 然后这些 PTE 可能会被madvise 跳过(因为这些已经是
pte_none了), 而madvise 在还存有 stale TLB entries 的情况下返回. 

This can be illustrated with the following program provided by Nadav
Amit and slightly modified. With the patch applied, it has an exit code
of 0 indicating a stale TLB entry did not leak to userspace.

---8<---

volatile int sync_step = 0;
volatile char *p;

static inline unsigned long rdtsc()
{
	unsigned long hi, lo;
	__asm__ __volatile__ ("rdtsc" : "=a"(lo), "=d"(hi));
	 return lo | (hi << 32);
}

static inline void wait_rdtsc(unsigned long cycles)
{
	unsigned long tsc = rdtsc();

	while (rdtsc() - tsc < cycles);
}

void *big_madvise_thread(void *ign)
{
	sync_step = 1;
	while (sync_step != 2);
	madvise((void*)p, PAGE_SIZE * N_PAGES, MADV_DONTNEED);
}

int main(void)
{
	pthread_t aux_thread;

	p = mmap(0, PAGE_SIZE * N_PAGES, PROT_READ|PROT_WRITE,
		 MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);

	memset((void*)p, 8, PAGE_SIZE * N_PAGES);

	pthread_create(&aux_thread, NULL, big_madvise_thread, NULL);
	while (sync_step != 1);

	*p = 8;		// Cache in TLB
	sync_step = 2;
	wait_rdtsc(100000);
	madvise((void*)p, PAGE_SIZE, MADV_DONTNEED);
	printf("data: %d (%s)\n", *p, (*p == 8 ? "stale, broken" : "cleared, fine"));
	return *p == 8 ? -1 : 0;
}
---8<---

Link: http://lkml.kernel.org/r/20170725101230.5v7gvnjmcnkzzql3@techsingularity.net
Signed-off-by: Mel Gorman <mgorman@suse.de>
Reported-by: Nadav Amit <nadav.amit@gmail.com>
Cc: Andy Lutomirski <luto@kernel.org>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>

Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 mm/memory.c | 14 +++++++++++++-
 1 file changed, 13 insertions(+), 1 deletion(-)

diff --git a/mm/memory.c b/mm/memory.c
index 71c0b6f98a62..1416485e278c 100644
--- a/mm/memory.c
+++ b/mm/memory.c
@@ -1513,8 +1513,20 @@ void zap_page_range(struct vm_area_struct *vma, unsigned long start,
 	tlb_gather_mmu(&tlb, mm, start, end);
 	update_hiwater_rss(mm);
 	mmu_notifier_invalidate_range_start(mm, start, end);
-	for ( ; vma && vma->vm_start < end; vma = vma->vm_next)
+	for ( ; vma && vma->vm_start < end; vma = vma->vm_next) {
 		unmap_single_vma(&tlb, vma, start, end, NULL);
+
+		/*
+		 * zap_page_range does not specify whether mmap_sem should be
+		 * held for read or write. That allows parallel zap_page_range
+		 * operations to unmap a PTE and defer a flush meaning that
+		 * this call observes pte_none and fails to flush the TLB.
+		 * Rather than adding a complex API, ensure that no stale
+		 * TLB entries exist when this call returns.
+		 */
+		flush_tlb_range(vma, start, end);
+	}
+
 	mmu_notifier_invalidate_range_end(mm, start, end);
 	tlb_finish_mmu(&tlb, start, end);
 }
-- 
2.42.0
```
