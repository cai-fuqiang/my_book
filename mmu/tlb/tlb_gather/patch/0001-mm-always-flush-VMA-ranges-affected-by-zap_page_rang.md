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
sparsely [spɑ:slɪ]: 稀疏的
populated: 生活于, 居住于,构成...的人口 (这里应该有构成的意思,就是稀疏数据构成)
negligible /ˈneɡlɪdʒəbl/: 可以忽略不计的;微不足道的;不重要的;不值一提的 
either way: 无论哪种方式 ; 怎么都行; 任何的决定
overall: 总体上,总计, 一般来说

Nadav Amit 报告了 zap_page_range 只能指定 调用者 保护 VMA list, 但是不能
指定 调用者是持有 读/ 写 (锁). madvise 持有 读 mmap_sem 意味着 平行的 zap 
操作 可以 unmap PTEs, 然后这些 PTE 可能会被madvise 跳过(因为这些已经是
pte_none了), 而madvise 在还存有 stale TLB entries 的情况下返回. 当 API 被扩展,
这个API将会很难用.(难道是会造成参数改变?) 该patch 将导致 zap_page_range()
始终要考虑 flush 受影响的全部范围. 对于更小的范围或者稀疏填充的映射, 他可能导致
一个额外的 tlb flush. 对于较大的range, tlb可能已经被刷新, 而且开销可以忽略不计.
无论怎样, 该方案总体上是安全的, 并且避免在 madvise 返回时, 存在stale entries

This can be illustrated with the following program provided by Nadav
Amit and slightly modified. With the patch applied, it has an exit code
of 0 indicating a stale TLB entry did not leak to userspace.

可以通过下面由 Nada volatile Amit 提供的程序来解释并且我做了一些微调. 当patch
被应用时, 它的 exit code 是0, 意味着 stale TLB entry 将不会泄露给 userspace.

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

该测试用例出问题的流程:
```
CPU 0                                       CPU 1
mmap
赋值该内存,  全是8
                                            madvise dont need, 全部page
                                            {  
                                               write = madvise_need_mmap_write()
                                               {
                                                    case MADV_DONTNEED: return 0;
                                               }
                                               if (!write)
                                                  down_read(&current->mm->mmap_sem);   
                                               ...
                                               zap_page_range {
                                                   这里会解除映射(也就是clean pte)
                                                    ...

                                                   此时还未执行到tlb_finish_mmu()

wait cycle(100000)
madvise dont need first page
{
    write = 0; //和CPU 1一样
    down_read(&current->mm->mmap_sem);
    zap_page_range {
        pte_none() == TRUE
        所以不会去flush 这个VA 的tlb
    }
    
    return with stale TLB  \
       related to first page
}

read first page first byte is 8
                                                   tlb_finish_mmu() {
                                                      flush_tlb()
                                                      free_pte()
                                                   }//tlb_finish_mmu
                                               } //zap_page_range
                                            } //madvise
```

但是这里, 我们要理解几点:(自己的理解可能有差错)
```
Q: 为什么作者在CPU 0 中 只 madvise 一个页, 而在 CPU 1 中madvise 多个页?
A: 个人感觉, 这样做可以提高 
   CPU 0的madvise 返回时间点 比 CPU 1的 tlb_flush_mmu()中的 flush_tlb() 完成的时间点
   早的几率

Q: 这个问题的触发条件是什么?
A: 必须有两个并行的 madvise

Q: 这个问题大么?
A: 个人感觉不大, 因为这个page 没有被释放,此时从伙伴系统看来,该page 还是属于这个进程,并没
   有分配给其他的进程

Q: 这个在我们正常的编程中, 会不会有影响?
A: madvise 可能会在某些库的 malloc/free中调用到
   我们假设free() 中会调用 madvise()
   并行执行 madvise 也就意味着同时有两个free()操作, 个人感觉一方面是用户程序BUG(),
   另一方面底层的free()接口也应该避免这一情况.

   那么有没有可能在 free(VA1)   VA1=malloc(), 此时VA1还是使用的 stale TLB, 
   个人感觉除非是下面的情况:
   无论malloc() 调用不调用 madvise(), 他都没有等free 该VA的动作完成, malloc()就返回
   了, 个人感觉是底层库的BUG. 

Q: kernel 允许 A 线程 在执行madvise dont need 之后(但是madvise未返回), B线程使用 stale TLB 么?
A: 允许, 例如:
   CPU 0                                       CPU 1
   madvise dont need VA1
   {
       zap_page_range()
       {
           解除映射
                                               read VA1 with stale TLB
           tlb_flush_mmu()
           {
               flush_tlb()
               free_pte()
           }
       }

   }
   和上面一样, 无非就是内存中的pte已经是clean的状态, 但是使用了 stale TLB访问了,
   但是在伙伴系统看来, 该page仍然是被当前task占用, 不会分配给其他task.
```
