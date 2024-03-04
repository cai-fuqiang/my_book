# tlb batch flush
tlb remote flush (tlb shootdown) 的kernel处理流程，
我们在 `LAZY TLB` 章节中讲到，那么假设这样一个场景:
* kswapd 在回收内存
* 回收的page 被某个进程映射，该进程和 kswapd 在不同的
 cpu上运行
* kswapd 回收的page有很多，当回收内存时，需要进行 unmap操作，
 unmap后，需要进行tlb flush(可能会进行 tlb flush others)

那么大家想像下，在回收大量内存的情形下，需要频繁进行 unmap操作，
也就需要频繁的 tlb flush (tlb flush others), 所以 `Mel Gorman`
提交了几个patch，用来实现 batch flush in kswapd

# PATCH INFORMATION
```
From 5b74283ab251b9db55cbbe31d19ca72482103290 Mon Sep 17 00:00:00 2001
Subject: [PATCH 1/4] x86, mm: trace when an IPI is about to be sent

From 72b252aed506b8f1a03f7abd29caef4cdf6a043b Mon Sep 17 00:00:00 2001
Subject: [PATCH] mm: send one IPI per CPU to TLB flush all entries after
 unmapping pages

From d950c9477d51f0cefc2ed3cf76e695d46af0d9c1 Mon Sep 17 00:00:00 2001
Subject: [PATCH 3/4] mm: defer flush of writable TLB entries

From c7e1e3ccfbd153c890240a391f258efaedfa94d0 Mon Sep 17 00:00:00 2001
Subject: [PATCH 4/4] Documentation/features/vm: add feature description and
 arch support status for batched TLB flush after unmap
```
一共四个patch， 下面是mail list:

[TLB flush multiple pages per IPI v7](https://lore.kernel.org/all/20150709082000.GW6812@suse.de/)


我们来看下具体实现:

# 实现细节

## 数据结构
引入`tlbflush_unmap_batch`
```cpp
+/* Track pages that require TLB flushes */
+struct tlbflush_unmap_batch {
+   /*
+    * Each bit set is a CPU that potentially has a TLB entry for one of
+    * the PFNs being flushed. See set_tlb_ubc_flush_pending().
+    */
+   struct cpumask cpumask;
+
+   /* True if any bit in cpumask is set */
+   bool flush_required;

struct task_struct {
    unsigned long numa_pages_migrated;
 #endif /* CONFIG_NUMA_BALANCING */

+#ifdef CONFIG_ARCH_WANT_BATCHED_UNMAP_TLB_FLUSH
+   struct tlbflush_unmap_batch tlb_ubc;
+
    struct rcu_head rcu;
```

可以看到在 task_struct 中引入 `struct tlbflush_unmap_batch tlb_ubc`成员，
该数据结构有两个成员:
* **cpumask** : 表示要发送给那些cpu
* **flush_required** : 如果`cpumask`任意bit不为0,则设置该field

上面我们介绍过，该patch的目的，是想在kswapd 进程中，实现batch flush
(几个 tlb flush request一起发送), 所以我们将代码流程分成两部分来看.
* 积攒tlb flush request
* batch flush

## 积攒 tlb flush request
什么时候会产生tlb flush request呢 ? 答案是在kswap回收内存，unmap页面时，代码路径
```
shrink_page_list {
  while (!list_empty(page_list)) {
    ...
    if (page_mapped(page) && mapping) {
      try_to_unmap(page,ttu_flags|TTU_BATCH_FLUSH);
      { //try_to_unmap BEG
         struct rmap_walk_control rwc = {
           .rmap_one = g,
           .arg = (void *)flags,
           .done = page_not_mapped,
           .anon_lock = page_lock_anon_vma_read,
        };
        ...
        ret = rmap_walk(page, &rwc);
      } //try_to_unmap END
    }
    ...
  }

} // shrink_page_list END

rmap_walk
  rmap_walk_anon / rmap_walk_file
    try_to_unmap_one
```

`try_to_unmap_one` 改动:
```diff
@@ -1220,7 +1305,24 @@ static int try_to_unmap_one(struct page *page, struct vm_area_struct *vma,

    /* Nuke the page table entry. */
    flush_cache_page(vma, address, page_to_pfn(page));
-   pteval = ptep_clear_flush(vma, address, pte);
+   if (should_defer_flush(mm, flags)) {
+       /*
+        * We clear the PTE but do not flush so potentially a remote
+        * CPU could still be writing to the page. If the entry was
+        * previously clean then the architecture must guarantee that
+        * a clear->dirty transition on a cached TLB entry is written
+        * through and traps if the PTE is unmapped.
+        */
+       pteval = ptep_get_and_clear(mm, address, pte);
+
+       /* Potentially writable TLBs must be flushed before IO */
+       if (pte_dirty(pteval))
+           flush_tlb_page(vma, address);
+       else
+           set_tlb_ubc_flush_pending(mm, page);
+   } else {
+       pteval = ptep_clear_flush(vma, address, pte);
+   }
```

我们来看下 `ptep_clear_flush()`和`ptep_get_and_clear()`实现
```cpp
pte_t ptep_clear_flush(struct vm_area_struct *vma, unsigned long address,
                       pte_t *ptep)
{
        struct mm_struct *mm = (vma)->vm_mm;
        pte_t pte;
        pte = ptep_get_and_clear(mm, address, ptep);
        if (pte_accessible(mm, pte))
                flush_tlb_page(vma, address);
        return pte;
}

static inline pte_t ptep_get_and_clear(struct mm_struct *mm, unsigned long addr,
                                       pte_t *ptep)
{
        pte_t pte = native_ptep_get_and_clear(ptep);
        pte_update(mm, addr, ptep);
        return pte;
}
```
首先看 `ptep_clear_flush()`， 首先执行`ptep_get_and_clear()`, 然后 **根据该pte
是否是 accessible，再决定要不要刷tlb**, Intel SDM `4.10.2.3 Details of TLB use`提到:
```
Because the TLBs cache entries only for linear addresses with translations,
there can be a TLB entry for a page number only if the P flag is 1 and the
reserved bits are 0 in each of the paging-structure entries used to translate
that page number. In addition, the processor does not cache a translation for a
page number unless the accessed flag is 1 in each of the paging-structure
entries used during translation; before caching a translation, the processor
sets any of these accessed flags that is not already 1
```
大概意思是 TLB 只缓存那些 accessed flags 为 1 的 paging-structure entries, 在
缓存一个translation 之前，处理器会设置不为1的那些accessed flags为1。所以这里判
断如果该pte没有 accessble bit, 说明没有人缓存该page translation information(TLB)
也就不用flush。

关于`ptep_get_and_clear()`中调用`native_ptep_get_and_clear`:
```cpp
static inline pte_t native_ptep_get_and_clear(pte_t *xp)
{
#ifdef CONFIG_SMP
        return native_make_pte(xchg(&xp->pte, 0));
#else
        /* native_local_ptep_get_and_clear,
           but duplicated because of cyclic dependency */
        pte_t ret = *xp;
        native_pte_clear(NULL, 0, xp);
        return ret;
#endif
}
```
在 SMP情况下，防止多核竞争，使用 `xchg`原子操作进行交换。

我们在回到该patch，通过`should_defer_flush(mm,flags)`进行判断，如果不需要defer flush，
还是 flush imm, 但是如果需要 defer flush, 但是 `pte_dirty()`为真的情况下, 还是
需要 flush imm。这个我们在下一个章节中讨论。`set_tlb_ubc_flush_pending()`分支，就是
defer flush。我们来看下`should_defer_flush() set_tlb_ubc_flush_pending() ` 这两个函数
```diff
+static bool should_defer_flush(struct mm_struct *mm, enum ttu_flags flags)
+{
+   bool should_defer = false;
+
+   if (!(flags & TTU_BATCH_FLUSH))
+       return false;
+
+   /* If remote CPUs need to be flushed then defer batch the flush */
+   if (cpumask_any_but(mm_cpumask(mm), get_cpu()) < nr_cpu_ids)
+       should_defer = true;
+   put_cpu();
+
+   return should_defer;
```
代码比较简单, `should_defer_flush`有两个判断条件
1. flags 中有 `TTU_BATCH_FLUSH`, 从 `shrink_page_list()`下来的代码路径会带有该flag
2. `mm_cpumask()`中有其他的cpu mask (因为该patch就是解决flush others多次发送ipi的问题，
如果要是只有当前cpu需要flush，就不需要defer)

```diff
+static void set_tlb_ubc_flush_pending(struct mm_struct *mm,
+       struct page *page)
+{
+   struct tlbflush_unmap_batch *tlb_ubc = &current->tlb_ubc;
+
+   cpumask_or(&tlb_ubc->cpumask, &tlb_ubc->cpumask, mm_cpumask(mm));
+   tlb_ubc->flush_required = true;
+}
```
该操作也很简单，将`tlb_ubc-cpumask` 或上，`mm_cpumask`, 另外设置 
`tlb_ubc->flush_required`为`true`。因为这个操作可能在一次 `shrink_page_list()`
中执行多次，所以要采用或操作。而且可以看到，这里只是记录了下，并没有立即flush
tlb。

## batch flush
那么在哪里flush呢? flush操作放在了 `shrink_page_list()`特别靠后的位置.
```diff
@@ -1208,6 +1209,7 @@ static unsigned long shrink_page_list(struct list_head *page_list,
    }

    mem_cgroup_uncharge_list(&free_pages);
+   try_to_unmap_flush();
    free_hot_cold_page_list(&free_pages, true);
```

`try_to_unmap_flush()`:

```diff
+/*
+ * Flush TLB entries for recently unmapped pages from remote CPUs. It is
+ * important if a PTE was dirty when it was unmapped that it's flushed
+ * before any IO is initiated on the page to prevent lost writes. Similarly,
+ * it must be flushed before freeing to prevent data leakage.
+ */
+void try_to_unmap_flush(void)
+{
+   struct tlbflush_unmap_batch *tlb_ubc = &current->tlb_ubc;
+   int cpu;
+
+   if (!tlb_ubc->flush_required)
+       return;
+
+   cpu = get_cpu();
+
+   trace_tlb_flush(TLB_REMOTE_SHOOTDOWN, -1UL);
+
+   if (cpumask_test_cpu(cpu, &tlb_ubc->cpumask))
+       percpu_flush_tlb_batch_pages(&tlb_ubc->cpumask);
+
+   if (cpumask_any_but(&tlb_ubc->cpumask, cpu) < nr_cpu_ids) {
+       smp_call_function_many(&tlb_ubc->cpumask,
+           percpu_flush_tlb_batch_pages, (void *)tlb_ubc, true);
+   }
+   cpumask_clear(&tlb_ubc->cpumask);
+   tlb_ubc->flush_required = false;
+   put_cpu();
+}

+static void percpu_flush_tlb_batch_pages(void *data)
+{
+   /*
+    * All TLB entries are flushed on the assumption that it is
+    * cheaper to flush all TLBs and let them be refilled than
+    * flushing individual PFNs. Note that we do not track mm's
+    * to flush as that might simply be multiple full TLB flushes
+    * for no gain.
+    */
+   count_vm_tlb_event(NR_TLB_REMOTE_FLUSH_RECEIVED);
+   flush_tlb_local();
+
```
这里也提到了，dirty PTE 需要在前面更新该函数流程也很简单:
* 查看本地cpu要不要flush, 如果需要则flush
* 查看除了本地cpu 其他cpu要不要flush, 如果需要调用`smp_call_function_many`通知
  其他cpu去flush, 在` percpu_flush_tlb_batch_pages()` 函数中有段注释，大概意思是:

  我们假设flush all tlbs然后让他们填充，比flush individual PFNs 要更cheaper。
  并且不会track mm flush, 因为那可能只是一些多次full flush, track他们没有收益  (???)

我们下一个章节去讨论 dirty 和 clean page 为什么要不同对待。

# defer flush of DIRTY && CLEAN page
我们首先思考一个问题: 

当cpu 0 有page A pte 的 tlb, 而cpu 1将该 pte clear, 但是 cpu 1没有发起tlb shootdown, 
这时 cpu 0 还能正常访问 page A中的内存地址么?

得分两种情况:
* cpu 0 tlb Dirty flags = 1: 在intel SDM 中有提到:
```
If software modifies a paging-structure entry that identifies the final
 physical address for a linear address(either a PTE or a paging-structure
entry in which the PS flag is 1) to change the dirty flag from 1 to 0,
failure to perform an invalidation may result in the processor not setting
 that bit in response to a subsequent write to a linear address whose
translation uses the entry. Software cannot interpret the bit being clear as
an indication that such a write has not occurred
```
大概的意思是说，如果`PTE dirty 1->0`, 但是没有flush tlb, 再次发生write时，
MMU访问TLB发现 dirty 还是1, 认为不需要修改 PTE dirty bit，所以就直接访存了。
Present bit也是同理，手册中的描述如下:
```
If it is also the case that no invalidation was performed the last time the P
flag was changed from 1 to 0, the processor may use a TLB entry or
paging-structure cache entry that was created when the P flag had earlier been
1.
```
* cpu 0 tlb Dirty flags = 0: 还是上面的场景，但是 cpu 0 tlb本身dirty flags就是0，
那么write操作发生时，需要修改内存中的 dirty flags，这时候会去检查 access flags。
（在手册中没有明确描述，在下面的stackoverflow链接中有讨论)

> NOTE
> 
> [stackoverflow 关于该问题讨论](https://stackoverflow.com/questions/77393983/will-an-x86-64-cpu-notice-that-a-page-table-entry-has-changed-to-not-present-whi)

那么，我们就需要处理 page 原本是dirty的情况。需要立即flush, 那么这个操作能不能defer呢?
能，但是不能那么晚，最晚在`pageout()`之前，我们看接下来的patch:
```
From d950c9477d51f0cefc2ed3cf76e695d46af0d9c1 Mon Sep 17 00:00:00 2001
Subject: [PATCH 3/4] mm: defer flush of writable TLB entries
```

`tlbflush_unmap_batch` 增加 `writeable`成员, 表示该task有没有 `dirty pte`需要defer flush.
```diff
@@ -1354,6 +1354,13 @@ struct tlbflush_unmap_batch {

        /* True if any bit in cpumask is set */
        bool flush_required;
+
+       /*
+        * If true then the PTE was dirty when unmapped. The entry must be
+        * flushed before IO is initiated or a stale TLB entry potentially
+        * allows an update without redirtying the page.
+        */
+       bool writable;
 };
```

* 积攒 tlb flush request

```diff
 static void set_tlb_ubc_flush_pending(struct mm_struct *mm,
-               struct page *page)
+               struct page *page, bool writable)
 {
        struct tlbflush_unmap_batch *tlb_ubc = &current->tlb_ubc;

        cpumask_or(&tlb_ubc->cpumask, &tlb_ubc->cpumask, mm_cpumask(mm));
        tlb_ubc->flush_required = true;
+
+       /*
+        * If the PTE was dirty then it's best to assume it's writable. The
+        * caller must use try_to_unmap_flush_dirty() or try_to_unmap_flush()
+        * before the page is queued for IO.
+        */
+       if (writable)
+               tlb_ubc->writable = true;
 }

 /*
@@ -658,7 +676,7 @@ static bool should_defer_flush(struct mm_struct *mm, enum ttu_flags flags)
 }
 #else
 static void set_tlb_ubc_flush_pending(struct mm_struct *mm,
-               struct page *page)
+               struct page *page, bool writable)
 {
 }

@@ -1315,11 +1333,7 @@ static int try_to_unmap_one(struct page *page, struct vm_area_struct *vma,
                 */
                pteval = ptep_get_and_clear(mm, address, pte);

-               /* Potentially writable TLBs must be flushed before IO */
-               if (pte_dirty(pteval))
-                       flush_tlb_page(vma, address);
-               else
-                       set_tlb_ubc_flush_pending(mm, page);
+               set_tlb_ubc_flush_pending(mm, page, pte_dirty(pteval));
        } else {
                pteval = ptep_clear_flush(vma, address, pte);
        }
```
加这个 patch之前，dirty pte 需要立即flush, 而现在只需要将`tlb_ubc->writeable`修改为true

* batch flush

```diff
@@ -1098,7 +1098,12 @@ static unsigned long shrink_page_list(struct list_head *page_list,
                        if (!sc->may_writepage)
                                goto keep_locked;

-                       /* Page is dirty, try to write it out here */
+                       /*
+                        * Page is dirty. Flush the TLB if a writable entry
+                        * potentially exists to avoid CPU writes after IO
+                        * starts and then write it out here.
+                        */
+                       try_to_unmap_flush_dirty();
                        switch (pageout(page, mapping, sc)) {
                        case PAGE_KEEP:

@@ -626,16 +626,34 @@ void try_to_unmap_flush(void)
        }
        cpumask_clear(&tlb_ubc->cpumask);
        tlb_ubc->flush_required = false;
+       tlb_ubc->writable = false;
        put_cpu();
 }

+/* Flush iff there are potentially writable TLB entries that can race with IO */
+void try_to_unmap_flush_dirty(void)
+{
+       struct tlbflush_unmap_batch *tlb_ubc = &current->tlb_ubc;
+
+       if (tlb_ubc->writable)
+               try_to_unmap_flush();
+}
```

可以看到 在 `pageout()`之前会做tlb flush的操作-- ` try_to_unmap_flush_dirty()`, 
其中会判断`tlb_ubc->writeable`, 如果为真则提前flush (`try_to_umap_flush()`)

那么为什么要选择在 `pageout()`之前呢?

因为这是能选择的最靠后的位置.
因为 `pageout()`要根据页面内容去io, 如果在`pageout()`执行过程中，如果其他的cpu
还能继续写该页面的话，可能会造成数据丢失或者损坏。所以需要在 `pageout()`之前
flush tlb others, 让其他的cpu不能访问到该页面。

# 总结
该patch比较简单，主要目的是实现 kswapd 回收大量页面时，避免频繁进行 flush_tlb_others()
动作。但是需要处理好 dirty的page。
