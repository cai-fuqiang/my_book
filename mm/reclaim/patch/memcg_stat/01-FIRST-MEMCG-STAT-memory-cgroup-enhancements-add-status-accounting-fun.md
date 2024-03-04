```diff
From d52aa412d43827033a8e2ce4415ef6e8f8d53635 Mon Sep 17 00:00:00 2001
From: KAMEZAWA Hiroyuki <kamezawa.hiroyu@jp.fujitsu.com>
Date: Thu, 7 Feb 2008 00:14:24 -0800
Subject: [PATCH] memory cgroup enhancements: add status accounting function
 for memory cgroup

Add statistics account infrastructure for memory controller.  All account
information is stored per-cpu and caller will not have to take lock or use
atomic ops.  This will be used by memory.stat file later.

CACHE includes swapcache now. I'd like to divide it to
PAGECACHE and SWAPCACHE later.

This patch adds 3 functions for accounting.
 * __mem_cgroup_stat_add() ... for usual routine.
 * __mem_cgroup_stat_add_safe ... for calling under irq_disabled section.
 * mem_cgroup_read_stat() ... for reading stat value.
 * renamed PAGECACHE to CACHE (because it may include swapcache *now*)

[akpm@linux-foundation.org: coding-style fixes]
[akpm@linux-foundation.org: fix smp_processor_id-in-preemptible]
[akpm@linux-foundation.org: uninline things]
[akpm@linux-foundation.org: remove dead code]
Signed-off-by: KAMEZAWA Hiroyuki <kamezawa.hiroyu@jp.fujitsu.com>
Signed-off-by: YAMAMOTO Takashi <yamamoto@valinux.co.jp>
Cc: Balbir Singh <balbir@linux.vnet.ibm.com>
Cc: Pavel Emelianov <xemul@openvz.org>
Cc: Paul Menage <menage@google.com>
Cc: Peter Zijlstra <a.p.zijlstra@chello.nl>
Cc: "Eric W. Biederman" <ebiederm@xmission.com>
Cc: Nick Piggin <nickpiggin@yahoo.com.au>
Cc: Kirill Korotaev <dev@sw.ru>
Cc: Herbert Poetzl <herbert@13thfloor.at>
Cc: David Rientjes <rientjes@google.com>
Cc: Vaidyanathan Srinivasan <svaidy@linux.vnet.ibm.com>
Cc: Kirill Korotaev <dev@sw.ru>
Cc: Nick Piggin <nickpiggin@yahoo.com.au>
Cc: Paul Menage <menage@google.com>
Cc: Pavel Emelianov <xemul@openvz.org>
Cc: Peter Zijlstra <a.p.zijlstra@chello.nl>
Cc: Vaidyanathan Srinivasan <svaidy@linux.vnet.ibm.com>
Cc: YAMAMOTO Takashi <yamamoto@valinux.co.jp>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 mm/memcontrol.c | 77 +++++++++++++++++++++++++++++++++++++++++++++----
 1 file changed, 72 insertions(+), 5 deletions(-)

diff --git a/mm/memcontrol.c b/mm/memcontrol.c
index 31c4f0cefdee..5f3ad9c37bea 100644
--- a/mm/memcontrol.c
+++ b/mm/memcontrol.c
@@ -21,6 +21,7 @@
 #include <linux/memcontrol.h>
 #include <linux/cgroup.h>
 #include <linux/mm.h>
+#include <linux/smp.h>
 #include <linux/page-flags.h>
 #include <linux/backing-dev.h>
 #include <linux/bit_spinlock.h>
@@ -34,6 +35,47 @@
 struct cgroup_subsys mem_cgroup_subsys;
 static const int MEM_CGROUP_RECLAIM_RETRIES = 5;
 
+/*
+ * Statistics for memory cgroup.
+ */
+enum mem_cgroup_stat_index {
+	/*
+	 * For MEM_CONTAINER_TYPE_ALL, usage = pagecache + rss.
+	 */
+	MEM_CGROUP_STAT_CACHE, 	   /* # of pages charged as cache */
+	MEM_CGROUP_STAT_RSS,	   /* # of pages charged as rss */
+
+	MEM_CGROUP_STAT_NSTATS,
+};
+
+struct mem_cgroup_stat_cpu {
+	s64 count[MEM_CGROUP_STAT_NSTATS];
+} ____cacheline_aligned_in_smp;
+
+struct mem_cgroup_stat {
+	struct mem_cgroup_stat_cpu cpustat[NR_CPUS];
+};
+
+/*
+ * For accounting under irq disable, no need for increment preempt count.
+ */
+static void __mem_cgroup_stat_add_safe(struct mem_cgroup_stat *stat,
+		enum mem_cgroup_stat_index idx, int val)
+{
+	int cpu = smp_processor_id();
+	stat->cpustat[cpu].count[idx] += val;
+}
+
+static s64 mem_cgroup_read_stat(struct mem_cgroup_stat *stat,
+		enum mem_cgroup_stat_index idx)
+{
+	int cpu;
+	s64 ret = 0;
+	for_each_possible_cpu(cpu)
+		ret += stat->cpustat[cpu].count[idx];
+	return ret;
+}
+
 /*
  * The memory controller data structure. The memory controller controls both
  * page cache and RSS per cgroup. We would eventually like to provide
@@ -63,6 +105,10 @@ struct mem_cgroup {
 	 */
 	spinlock_t lru_lock;
 	unsigned long control_type;	/* control RSS or RSS+Pagecache */
+	/*
+	 * statistics.
+	 */
+	struct mem_cgroup_stat stat;
 };
 
 /*
@@ -101,6 +147,24 @@ enum charge_type {
 	MEM_CGROUP_CHARGE_TYPE_MAPPED,
 };
 
+/*
+ * Always modified under lru lock. Then, not necessary to preempt_disable()
+ */
+static void mem_cgroup_charge_statistics(struct mem_cgroup *mem, int flags,
+					bool charge)
+{
+	int val = (charge)? 1 : -1;
+	struct mem_cgroup_stat *stat = &mem->stat;
+	VM_BUG_ON(!irqs_disabled());
+
+	if (flags & PAGE_CGROUP_FLAG_CACHE)
+		__mem_cgroup_stat_add_safe(stat,
+					MEM_CGROUP_STAT_CACHE, val);
+	else
+		__mem_cgroup_stat_add_safe(stat, MEM_CGROUP_STAT_RSS, val);
+
+}
+
 static struct mem_cgroup init_mem_cgroup;
 
 static inline
@@ -175,8 +239,8 @@ static void __always_inline unlock_page_cgroup(struct page *page)
  * This can fail if the page has been tied to a page_cgroup.
  * If success, returns 0.
  */
-static inline int
-page_cgroup_assign_new_page_cgroup(struct page *page, struct page_cgroup *pc)
+static int page_cgroup_assign_new_page_cgroup(struct page *page,
+						struct page_cgroup *pc)
 {
 	int ret = 0;
 
@@ -198,8 +262,8 @@ page_cgroup_assign_new_page_cgroup(struct page *page, struct page_cgroup *pc)
  *  clear_page_cgroup(page, pc) == pc
  */
 
-static inline struct page_cgroup *
-clear_page_cgroup(struct page *page, struct page_cgroup *pc)
+static struct page_cgroup *clear_page_cgroup(struct page *page,
+						struct page_cgroup *pc)
 {
 	struct page_cgroup *ret;
 	/* lock and clear */
@@ -211,7 +275,6 @@ clear_page_cgroup(struct page *page, struct page_cgroup *pc)
 	return ret;
 }
 
-
 static void __mem_cgroup_move_lists(struct page_cgroup *pc, bool active)
 {
 	if (active) {
@@ -426,6 +489,8 @@ static int mem_cgroup_charge_common(struct page *page, struct mm_struct *mm,
 	}
 
 	spin_lock_irqsave(&mem->lru_lock, flags);
+	/* Update statistics vector */
+	mem_cgroup_charge_statistics(mem, pc->flags, true);
 	list_add(&pc->lru, &mem->active_list);
 	spin_unlock_irqrestore(&mem->lru_lock, flags);
 
@@ -496,6 +561,7 @@ void mem_cgroup_uncharge(struct page_cgroup *pc)
 			res_counter_uncharge(&mem->res, PAGE_SIZE);
 			spin_lock_irqsave(&mem->lru_lock, flags);
 			list_del_init(&pc->lru);
+			mem_cgroup_charge_statistics(mem, pc->flags, false);
 			spin_unlock_irqrestore(&mem->lru_lock, flags);
 			kfree(pc);
 		}
@@ -572,6 +638,7 @@ mem_cgroup_force_empty_list(struct mem_cgroup *mem, struct list_head *list)
 			css_put(&mem->css);
 			res_counter_uncharge(&mem->res, PAGE_SIZE);
 			list_del_init(&pc->lru);
+			mem_cgroup_charge_statistics(mem, pc->flags, false);
 			kfree(pc);
 		} else 	/* being uncharged ? ...do relax */
 			break;
-- 
2.42.0
```
