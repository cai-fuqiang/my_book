
```diff
From 00f3ca2c2d6635d85108571c4dd9a29088668662 Mon Sep 17 00:00:00 2001
From: Johannes Weiner <hannes@cmpxchg.org>
Date: Thu, 6 Jul 2017 15:40:52 -0700
Subject: [PATCH] mm: memcontrol: per-lruvec stats infrastructure

lruvecs are at the intersection of the NUMA node and memcg, which is the
scope for most paging activity.

> intersection : 十字路口;相交;交点;交叉;

Introduce a convenient accounting infrastructure that maintains
statistics per node, per memcg, and the lruvec itself.

> convenient [kənˈviːniənt]: 方便的
> infrastructure  /ˈɪnfrəstrʌktʃər/ : 基础设施

Then convert over accounting sites for statistics that are already
tracked in both nodes and memcgs and can be easily switched.

[hannes@cmpxchg.org: fix crash in the new cgroup stat keeping code]
  Link: http://lkml.kernel.org/r/20170531171450.GA10481@cmpxchg.org
[hannes@cmpxchg.org: don't track uncharged pages at all
  Link: http://lkml.kernel.org/r/20170605175254.GA8547@cmpxchg.org
[hannes@cmpxchg.org: add missing free_percpu()]
  Link: http://lkml.kernel.org/r/20170605175354.GB8547@cmpxchg.org
[linux@roeck-us.net: hexagon: fix build error caused by include file order]
  Link: http://lkml.kernel.org/r/20170617153721.GA4382@roeck-us.net
Link: http://lkml.kernel.org/r/20170530181724.27197-6-hannes@cmpxchg.org
Signed-off-by: Johannes Weiner <hannes@cmpxchg.org>
Signed-off-by: Guenter Roeck <linux@roeck-us.net>
Acked-by: Vladimir Davydov <vdavydov.dev@gmail.com>
Cc: Josef Bacik <josef@toxicpanda.com>
Cc: Michal Hocko <mhocko@suse.com>
Cc: Rik van Riel <riel@redhat.com>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 arch/hexagon/include/asm/pgtable.h |   1 -
 arch/hexagon/kernel/asm-offsets.c  |   1 -
 arch/hexagon/mm/vm_tlb.c           |   1 +
 include/linux/memcontrol.h         | 246 +++++++++++++++++++++++++----
 include/linux/vmstat.h             |   1 -
 mm/memcontrol.c                    |  11 +-
 mm/page-writeback.c                |  15 +-
 mm/rmap.c                          |   8 +-
 mm/workingset.c                    |   9 +-
 9 files changed, 238 insertions(+), 55 deletions(-)

diff --git a/arch/hexagon/include/asm/pgtable.h b/arch/hexagon/include/asm/pgtable.h
index 24a9177fb897..aef02f7ca8aa 100644
--- a/arch/hexagon/include/asm/pgtable.h
+++ b/arch/hexagon/include/asm/pgtable.h
@@ -24,7 +24,6 @@
 /*
  * Page table definitions for Qualcomm Hexagon processor.
  */
-#include <linux/swap.h>
 #include <asm/page.h>
 #define __ARCH_USE_5LEVEL_HACK
 #include <asm-generic/pgtable-nopmd.h>
diff --git a/arch/hexagon/kernel/asm-offsets.c b/arch/hexagon/kernel/asm-offsets.c
index 308be68d4fb3..3980c0407aa1 100644
--- a/arch/hexagon/kernel/asm-offsets.c
+++ b/arch/hexagon/kernel/asm-offsets.c
@@ -25,7 +25,6 @@
 #include <linux/compat.h>
 #include <linux/types.h>
 #include <linux/sched.h>
-#include <linux/mm.h>
 #include <linux/interrupt.h>
 #include <linux/kbuild.h>
 #include <asm/ptrace.h>
diff --git a/arch/hexagon/mm/vm_tlb.c b/arch/hexagon/mm/vm_tlb.c
index 9647d00cb761..b474065533ce 100644
--- a/arch/hexagon/mm/vm_tlb.c
+++ b/arch/hexagon/mm/vm_tlb.c
@@ -24,6 +24,7 @@
  * be instantiated for it, differently from a native build.
  */
 #include <linux/mm.h>
+#include <linux/sched.h>
 #include <asm/page.h>
 #include <asm/hexagon_vm.h>
 
diff --git a/include/linux/memcontrol.h b/include/linux/memcontrol.h
index 5a72d8377942..3914e3dd6168 100644
--- a/include/linux/memcontrol.h
+++ b/include/linux/memcontrol.h
@@ -26,7 +26,8 @@
 #include <linux/page_counter.h>
 #include <linux/vmpressure.h>
 #include <linux/eventfd.h>
-#include <linux/mmzone.h>
+#include <linux/mm.h>
+#include <linux/vmstat.h>
 #include <linux/writeback.h>
 #include <linux/page-flags.h>
 
@@ -98,11 +99,16 @@ struct mem_cgroup_reclaim_iter {
 	unsigned int generation;
 };
 
+struct lruvec_stat {
+	long count[NR_VM_NODE_STAT_ITEMS];
+};
+
 /*
  * per-zone information in memory controller.
  */
 struct mem_cgroup_per_node {
 	struct lruvec		lruvec;
+	struct lruvec_stat __percpu *lruvec_stat;
 	unsigned long		lru_zone_size[MAX_NR_ZONES][NR_LRU_LISTS];
 
 	struct mem_cgroup_reclaim_iter	iter[DEF_PRIORITY + 1];
@@ -496,23 +502,18 @@ static inline unsigned long memcg_page_state(struct mem_cgroup *memcg,
 	return val;
 }
 
-static inline void mod_memcg_state(struct mem_cgroup *memcg,
-				   enum memcg_stat_item idx, int val)
+static inline void __mod_memcg_state(struct mem_cgroup *memcg,
+				     enum memcg_stat_item idx, int val)
 {
 	if (!mem_cgroup_disabled())
-		this_cpu_add(memcg->stat->count[idx], val);
-}
-
-static inline void inc_memcg_state(struct mem_cgroup *memcg,
-				   enum memcg_stat_item idx)
-{
-	mod_memcg_state(memcg, idx, 1);
+		__this_cpu_add(memcg->stat->count[idx], val);
 }
 
-static inline void dec_memcg_state(struct mem_cgroup *memcg,
-				   enum memcg_stat_item idx)
+static inline void mod_memcg_state(struct mem_cgroup *memcg,
+				   enum memcg_stat_item idx, int val)
 {
-	mod_memcg_state(memcg, idx, -1);
+	if (!mem_cgroup_disabled())
+		this_cpu_add(memcg->stat->count[idx], val);
 }
 
 /**
@@ -532,6 +533,13 @@ static inline void dec_memcg_state(struct mem_cgroup *memcg,
  *
  * Kernel pages are an exception to this, since they'll never move.
  */
+static inline void __mod_memcg_page_state(struct page *page,
+					  enum memcg_stat_item idx, int val)
+{
+	if (page->mem_cgroup)
+		__mod_memcg_state(page->mem_cgroup, idx, val);
+}
+
 static inline void mod_memcg_page_state(struct page *page,
 					enum memcg_stat_item idx, int val)
 {
@@ -539,16 +547,76 @@ static inline void mod_memcg_page_state(struct page *page,
 		mod_memcg_state(page->mem_cgroup, idx, val);
 }
 
-static inline void inc_memcg_page_state(struct page *page,
-					enum memcg_stat_item idx)
+static inline unsigned long lruvec_page_state(struct lruvec *lruvec,
+					      enum node_stat_item idx)
 {
-	mod_memcg_page_state(page, idx, 1);
+	struct mem_cgroup_per_node *pn;
+	long val = 0;
+	int cpu;
+
+	if (mem_cgroup_disabled())
+		return node_page_state(lruvec_pgdat(lruvec), idx);
+
+	pn = container_of(lruvec, struct mem_cgroup_per_node, lruvec);
+	for_each_possible_cpu(cpu)
+		val += per_cpu(pn->lruvec_stat->count[idx], cpu);
+
+	if (val < 0)
+		val = 0;
+
+	return val;
 }
 
-static inline void dec_memcg_page_state(struct page *page,
-					enum memcg_stat_item idx)
+static inline void __mod_lruvec_state(struct lruvec *lruvec,
+				      enum node_stat_item idx, int val)
 {
-	mod_memcg_page_state(page, idx, -1);
+	struct mem_cgroup_per_node *pn;
+
+	__mod_node_page_state(lruvec_pgdat(lruvec), idx, val);
+	if (mem_cgroup_disabled())
+		return;
+	pn = container_of(lruvec, struct mem_cgroup_per_node, lruvec);
+	__mod_memcg_state(pn->memcg, idx, val);
+	__this_cpu_add(pn->lruvec_stat->count[idx], val);
+}
+
+static inline void mod_lruvec_state(struct lruvec *lruvec,
+				    enum node_stat_item idx, int val)
+{
+	struct mem_cgroup_per_node *pn;
+
+	mod_node_page_state(lruvec_pgdat(lruvec), idx, val);
+	if (mem_cgroup_disabled())
+		return;
+	pn = container_of(lruvec, struct mem_cgroup_per_node, lruvec);
+	mod_memcg_state(pn->memcg, idx, val);
+	this_cpu_add(pn->lruvec_stat->count[idx], val);
+}
+
+static inline void __mod_lruvec_page_state(struct page *page,
+					   enum node_stat_item idx, int val)
+{
+	struct mem_cgroup_per_node *pn;
+
+	__mod_node_page_state(page_pgdat(page), idx, val);
+	if (mem_cgroup_disabled() || !page->mem_cgroup)
+		return;
+	__mod_memcg_state(page->mem_cgroup, idx, val);
+	pn = page->mem_cgroup->nodeinfo[page_to_nid(page)];
+	__this_cpu_add(pn->lruvec_stat->count[idx], val);
+}
+
+static inline void mod_lruvec_page_state(struct page *page,
+					 enum node_stat_item idx, int val)
+{
+	struct mem_cgroup_per_node *pn;
+
+	mod_node_page_state(page_pgdat(page), idx, val);
+	if (mem_cgroup_disabled() || !page->mem_cgroup)
+		return;
+	mod_memcg_state(page->mem_cgroup, idx, val);
+	pn = page->mem_cgroup->nodeinfo[page_to_nid(page)];
+	this_cpu_add(pn->lruvec_stat->count[idx], val);
 }
 
 unsigned long mem_cgroup_soft_limit_reclaim(pg_data_t *pgdat, int order,
@@ -777,19 +845,21 @@ static inline unsigned long memcg_page_state(struct mem_cgroup *memcg,
 	return 0;
 }
 
-static inline void mod_memcg_state(struct mem_cgroup *memcg,
-				   enum memcg_stat_item idx,
-				   int nr)
+static inline void __mod_memcg_state(struct mem_cgroup *memcg,
+				     enum memcg_stat_item idx,
+				     int nr)
 {
 }
 
-static inline void inc_memcg_state(struct mem_cgroup *memcg,
-				   enum memcg_stat_item idx)
+static inline void mod_memcg_state(struct mem_cgroup *memcg,
+				   enum memcg_stat_item idx,
+				   int nr)
 {
 }
 
-static inline void dec_memcg_state(struct mem_cgroup *memcg,
-				   enum memcg_stat_item idx)
+static inline void __mod_memcg_page_state(struct page *page,
+					  enum memcg_stat_item idx,
+					  int nr)
 {
 }
 
@@ -799,14 +869,34 @@ static inline void mod_memcg_page_state(struct page *page,
 {
 }
 
-static inline void inc_memcg_page_state(struct page *page,
-					enum memcg_stat_item idx)
+static inline unsigned long lruvec_page_state(struct lruvec *lruvec,
+					      enum node_stat_item idx)
 {
+	return node_page_state(lruvec_pgdat(lruvec), idx);
 }
 
-static inline void dec_memcg_page_state(struct page *page,
-					enum memcg_stat_item idx)
+static inline void __mod_lruvec_state(struct lruvec *lruvec,
+				      enum node_stat_item idx, int val)
 {
+	__mod_node_page_state(lruvec_pgdat(lruvec), idx, val);
+}
+
+static inline void mod_lruvec_state(struct lruvec *lruvec,
+				    enum node_stat_item idx, int val)
+{
+	mod_node_page_state(lruvec_pgdat(lruvec), idx, val);
+}
+
+static inline void __mod_lruvec_page_state(struct page *page,
+					   enum node_stat_item idx, int val)
+{
+	__mod_node_page_state(page_pgdat(page), idx, val);
+}
+
+static inline void mod_lruvec_page_state(struct page *page,
+					 enum node_stat_item idx, int val)
+{
+	mod_node_page_state(page_pgdat(page), idx, val);
 }
 
 static inline
@@ -838,6 +928,102 @@ void count_memcg_event_mm(struct mm_struct *mm, enum vm_event_item idx)
 }
 #endif /* CONFIG_MEMCG */
 
+static inline void __inc_memcg_state(struct mem_cgroup *memcg,
+				     enum memcg_stat_item idx)
+{
+	__mod_memcg_state(memcg, idx, 1);
+}
+
+static inline void __dec_memcg_state(struct mem_cgroup *memcg,
+				     enum memcg_stat_item idx)
+{
+	__mod_memcg_state(memcg, idx, -1);
+}
+
+static inline void __inc_memcg_page_state(struct page *page,
+					  enum memcg_stat_item idx)
+{
+	__mod_memcg_page_state(page, idx, 1);
+}
+
+static inline void __dec_memcg_page_state(struct page *page,
+					  enum memcg_stat_item idx)
+{
+	__mod_memcg_page_state(page, idx, -1);
+}
+
+static inline void __inc_lruvec_state(struct lruvec *lruvec,
+				      enum node_stat_item idx)
+{
+	__mod_lruvec_state(lruvec, idx, 1);
+}
+
+static inline void __dec_lruvec_state(struct lruvec *lruvec,
+				      enum node_stat_item idx)
+{
+	__mod_lruvec_state(lruvec, idx, -1);
+}
+
+static inline void __inc_lruvec_page_state(struct page *page,
+					   enum node_stat_item idx)
+{
+	__mod_lruvec_page_state(page, idx, 1);
+}
+
+static inline void __dec_lruvec_page_state(struct page *page,
+					   enum node_stat_item idx)
+{
+	__mod_lruvec_page_state(page, idx, -1);
+}
+
+static inline void inc_memcg_state(struct mem_cgroup *memcg,
+				   enum memcg_stat_item idx)
+{
+	mod_memcg_state(memcg, idx, 1);
+}
+
+static inline void dec_memcg_state(struct mem_cgroup *memcg,
+				   enum memcg_stat_item idx)
+{
+	mod_memcg_state(memcg, idx, -1);
+}
+
+static inline void inc_memcg_page_state(struct page *page,
+					enum memcg_stat_item idx)
+{
+	mod_memcg_page_state(page, idx, 1);
+}
+
+static inline void dec_memcg_page_state(struct page *page,
+					enum memcg_stat_item idx)
+{
+	mod_memcg_page_state(page, idx, -1);
+}
+
+static inline void inc_lruvec_state(struct lruvec *lruvec,
+				    enum node_stat_item idx)
+{
+	mod_lruvec_state(lruvec, idx, 1);
+}
+
+static inline void dec_lruvec_state(struct lruvec *lruvec,
+				    enum node_stat_item idx)
+{
+	mod_lruvec_state(lruvec, idx, -1);
+}
+
+static inline void inc_lruvec_page_state(struct page *page,
+					 enum node_stat_item idx)
+{
+	mod_lruvec_page_state(page, idx, 1);
+}
+
+static inline void dec_lruvec_page_state(struct page *page,
+					 enum node_stat_item idx)
+{
+	mod_lruvec_page_state(page, idx, -1);
+}
+
 #ifdef CONFIG_CGROUP_WRITEBACK
 
 struct list_head *mem_cgroup_cgwb_list(struct mem_cgroup *memcg);
diff --git a/include/linux/vmstat.h b/include/linux/vmstat.h
index 613771909b6e..b3d85f30d424 100644
--- a/include/linux/vmstat.h
+++ b/include/linux/vmstat.h
@@ -3,7 +3,6 @@
 
 #include <linux/types.h>
 #include <linux/percpu.h>
-#include <linux/mm.h>
 #include <linux/mmzone.h>
 #include <linux/vm_event_item.h>
 #include <linux/atomic.h>
diff --git a/mm/memcontrol.c b/mm/memcontrol.c
index dceb0deb8d5e..425aa0caa712 100644
--- a/mm/memcontrol.c
+++ b/mm/memcontrol.c
@@ -4122,6 +4122,12 @@ static int alloc_mem_cgroup_per_node_info(struct mem_cgroup *memcg, int node)
 	if (!pn)
 		return 1;
 
+	pn->lruvec_stat = alloc_percpu(struct lruvec_stat);
+	if (!pn->lruvec_stat) {
+		kfree(pn);
+		return 1;
+	}
+
 	lruvec_init(&pn->lruvec);
 	pn->usage_in_excess = 0;
 	pn->on_tree = false;
@@ -4133,7 +4139,10 @@ static int alloc_mem_cgroup_per_node_info(struct mem_cgroup *memcg, int node)
 
 static void free_mem_cgroup_per_node_info(struct mem_cgroup *memcg, int node)
 {
-	kfree(memcg->nodeinfo[node]);
+	struct mem_cgroup_per_node *pn = memcg->nodeinfo[node];
+
+	free_percpu(pn->lruvec_stat);
+	kfree(pn);
 }
 
 static void __mem_cgroup_free(struct mem_cgroup *memcg)
diff --git a/mm/page-writeback.c b/mm/page-writeback.c
index 143c1c25d680..8989eada0ef7 100644
--- a/mm/page-writeback.c
+++ b/mm/page-writeback.c
@@ -2433,8 +2433,7 @@ void account_page_dirtied(struct page *page, struct address_space *mapping)
 		inode_attach_wb(inode, page);
 		wb = inode_to_wb(inode);
 
-		inc_memcg_page_state(page, NR_FILE_DIRTY);
-		__inc_node_page_state(page, NR_FILE_DIRTY);
+		__inc_lruvec_page_state(page, NR_FILE_DIRTY);
 		__inc_zone_page_state(page, NR_ZONE_WRITE_PENDING);
 		__inc_node_page_state(page, NR_DIRTIED);
 		__inc_wb_stat(wb, WB_RECLAIMABLE);
@@ -2455,8 +2454,7 @@ void account_page_cleaned(struct page *page, struct address_space *mapping,
 			  struct bdi_writeback *wb)
 {
 	if (mapping_cap_account_dirty(mapping)) {
-		dec_memcg_page_state(page, NR_FILE_DIRTY);
-		dec_node_page_state(page, NR_FILE_DIRTY);
+		dec_lruvec_page_state(page, NR_FILE_DIRTY);
 		dec_zone_page_state(page, NR_ZONE_WRITE_PENDING);
 		dec_wb_stat(wb, WB_RECLAIMABLE);
 		task_io_account_cancelled_write(PAGE_SIZE);
@@ -2712,8 +2710,7 @@ int clear_page_dirty_for_io(struct page *page)
 		 */
 		wb = unlocked_inode_to_wb_begin(inode, &locked);
 		if (TestClearPageDirty(page)) {
-			dec_memcg_page_state(page, NR_FILE_DIRTY);
-			dec_node_page_state(page, NR_FILE_DIRTY);
+			dec_lruvec_page_state(page, NR_FILE_DIRTY);
 			dec_zone_page_state(page, NR_ZONE_WRITE_PENDING);
 			dec_wb_stat(wb, WB_RECLAIMABLE);
 			ret = 1;
@@ -2759,8 +2756,7 @@ int test_clear_page_writeback(struct page *page)
 		ret = TestClearPageWriteback(page);
 	}
 	if (ret) {
-		dec_memcg_page_state(page, NR_WRITEBACK);
-		dec_node_page_state(page, NR_WRITEBACK);
+		dec_lruvec_page_state(page, NR_WRITEBACK);
 		dec_zone_page_state(page, NR_ZONE_WRITE_PENDING);
 		inc_node_page_state(page, NR_WRITTEN);
 	}
@@ -2814,8 +2810,7 @@ int __test_set_page_writeback(struct page *page, bool keep_write)
 		ret = TestSetPageWriteback(page);
 	}
 	if (!ret) {
-		inc_memcg_page_state(page, NR_WRITEBACK);
-		inc_node_page_state(page, NR_WRITEBACK);
+		inc_lruvec_page_state(page, NR_WRITEBACK);
 		inc_zone_page_state(page, NR_ZONE_WRITE_PENDING);
 	}
 	unlock_page_memcg(page);
diff --git a/mm/rmap.c b/mm/rmap.c
index b255743351e5..ced14f1af6dc 100644
--- a/mm/rmap.c
+++ b/mm/rmap.c
@@ -1145,8 +1145,7 @@ void page_add_file_rmap(struct page *page, bool compound)
 		if (!atomic_inc_and_test(&page->_mapcount))
 			goto out;
 	}
-	__mod_node_page_state(page_pgdat(page), NR_FILE_MAPPED, nr);
-	mod_memcg_page_state(page, NR_FILE_MAPPED, nr);
+	__mod_lruvec_page_state(page, NR_FILE_MAPPED, nr);
 out:
 	unlock_page_memcg(page);
 }
@@ -1181,12 +1180,11 @@ static void page_remove_file_rmap(struct page *page, bool compound)
 	}
 
 	/*
-	 * We use the irq-unsafe __{inc|mod}_zone_page_state because
+	 * We use the irq-unsafe __{inc|mod}_lruvec_page_state because
 	 * these counters are not modified in interrupt context, and
 	 * pte lock(a spinlock) is held, which implies preemption disabled.
 	 */
-	__mod_node_page_state(page_pgdat(page), NR_FILE_MAPPED, -nr);
-	mod_memcg_page_state(page, NR_FILE_MAPPED, -nr);
+	__mod_lruvec_page_state(page, NR_FILE_MAPPED, -nr);
 
 	if (unlikely(PageMlocked(page)))
 		clear_page_mlock(page);
diff --git a/mm/workingset.c b/mm/workingset.c
index b8c9ab678479..7119cd745ace 100644
--- a/mm/workingset.c
+++ b/mm/workingset.c
@@ -288,12 +288,10 @@ bool workingset_refault(void *shadow)
 	 */
 	refault_distance = (refault - eviction) & EVICTION_MASK;
 
-	inc_node_state(pgdat, WORKINGSET_REFAULT);
-	inc_memcg_state(memcg, WORKINGSET_REFAULT);
+	inc_lruvec_state(lruvec, WORKINGSET_REFAULT);
 
 	if (refault_distance <= active_file) {
-		inc_node_state(pgdat, WORKINGSET_ACTIVATE);
-		inc_memcg_state(memcg, WORKINGSET_ACTIVATE);
+		inc_lruvec_state(lruvec, WORKINGSET_ACTIVATE);
 		rcu_read_unlock();
 		return true;
 	}
@@ -474,8 +472,7 @@ static enum lru_status shadow_lru_isolate(struct list_head *item,
 	}
 	if (WARN_ON_ONCE(node->exceptional))
 		goto out_invalid;
-	inc_node_state(page_pgdat(virt_to_page(node)), WORKINGSET_NODERECLAIM);
-	inc_memcg_page_state(virt_to_page(node), WORKINGSET_NODERECLAIM);
+	inc_lruvec_page_state(virt_to_page(node), WORKINGSET_NODERECLAIM);
 	__radix_tree_delete_node(&mapping->page_tree, node,
 				 workingset_update_node, mapping);
 
-- 
2.42.0
```
