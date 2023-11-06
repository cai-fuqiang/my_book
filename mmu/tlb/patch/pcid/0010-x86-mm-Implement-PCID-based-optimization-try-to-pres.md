```diff
From 10af6235e0d327d42e1bad974385197817923dc1 Mon Sep 17 00:00:00 2001
From: Andy Lutomirski <luto@kernel.org>
Date: Mon, 24 Jul 2017 21:41:38 -0700
Subject: [PATCH] x86/mm: Implement PCID based optimization: try to preserve
 old TLB entries using PCID
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

PCID is a "process context ID" -- it's what other architectures call
an address space ID.  Every non-global TLB entry is tagged with a
PCID, only TLB entries that match the currently selected PCID are
used, and we can switch PGDs without flushing the TLB.  x86's
PCID is 12 bits.

This is an unorthodox approach to using PCID.  x86's PCID is far too
short to uniquely identify a process, and we can't even really
uniquely identify a running process because there are monster
systems with over 4096 CPUs.  To make matters worse, past attempts
to use all 12 PCID bits have resulted in slowdowns instead of
speedups.

unorthodox : 非正统的
monster: 怪物
to make matters worse: 更糟糕的是

This patch uses PCID differently.  We use a PCID to identify a
recently-used mm on a per-cpu basis.  An mm has no fixed PCID
binding at all; instead, we give it a fresh PCID each time it's
loaded except in cases where we want to preserve the TLB, in which
case we reuse a recent value.

preserve : 保留,保存

Here are some benchmark results, done on a Skylake laptop at 2.3 GHz
(turbo off, intel_pstate requesting max performance) under KVM with
the guest using idle=poll (to avoid artifacts when bouncing between
CPUs).  I haven't done any real statistics here -- I just ran them
in a loop and picked the fastest results that didn't look like
outliers.  Unpatched means commit a4eb8b993554, so all the
bookkeeping overhead is gone.

ping-pong between two mms on the same CPU using eventfd:

  patched:         1.22µs
  patched, nopcid: 1.33µs
  unpatched:       1.34µs

Same ping-pong, but now touch 512 pages (all zero-page to minimize
cache misses) each iteration.  dTLB misses are measured by
dtlb_load_misses.miss_causes_a_walk:

  patched:         1.8µs  11M  dTLB misses
  patched, nopcid: 6.2µs, 207M dTLB misses
  unpatched:       6.1µs, 190M dTLB misses

Signed-off-by: Andy Lutomirski <luto@kernel.org>
Reviewed-by: Nadav Amit <nadav.amit@gmail.com>
Cc: Andrew Morton <akpm@linux-foundation.org>
Cc: Arjan van de Ven <arjan@linux.intel.com>
Cc: Borislav Petkov <bp@alien8.de>
Cc: Dave Hansen <dave.hansen@intel.com>
Cc: Linus Torvalds <torvalds@linux-foundation.org>
Cc: Mel Gorman <mgorman@suse.de>
Cc: Peter Zijlstra <peterz@infradead.org>
Cc: Rik van Riel <riel@redhat.com>
Cc: Thomas Gleixner <tglx@linutronix.de>
Cc: linux-mm@kvack.org
Link: http://lkml.kernel.org/r/9ee75f17a81770feed616358e6860d98a2a5b1e7.1500957502.git.luto@kernel.org
Signed-off-by: Ingo Molnar <mingo@kernel.org>
---
 arch/x86/include/asm/mmu_context.h     |  3 +
 arch/x86/include/asm/processor-flags.h |  2 +
 arch/x86/include/asm/tlbflush.h        | 18 +++++-
 arch/x86/mm/init.c                     |  1 +
 arch/x86/mm/tlb.c                      | 80 ++++++++++++++++++++------
 5 files changed, 86 insertions(+), 18 deletions(-)

diff --git a/arch/x86/include/asm/mmu_context.h b/arch/x86/include/asm/mmu_context.h
index 85f6b5575aad..14b3cdccf4f9 100644
--- a/arch/x86/include/asm/mmu_context.h
+++ b/arch/x86/include/asm/mmu_context.h
@@ -300,6 +300,9 @@ static inline unsigned long __get_current_cr3_fast(void)
 {
 	unsigned long cr3 = __pa(this_cpu_read(cpu_tlbstate.loaded_mm)->pgd);
 
+	if (static_cpu_has(X86_FEATURE_PCID))
+		cr3 |= this_cpu_read(cpu_tlbstate.loaded_mm_asid);
+
 	/* For now, be very restrictive about when this can be called. */
 	VM_WARN_ON(in_nmi() || !in_atomic());
 
diff --git a/arch/x86/include/asm/processor-flags.h b/arch/x86/include/asm/processor-flags.h
index f5d3e50af98c..8a6d89fc9a79 100644
--- a/arch/x86/include/asm/processor-flags.h
+++ b/arch/x86/include/asm/processor-flags.h
@@ -36,6 +36,7 @@
 /* Mask off the address space ID and SME encryption bits. */
 #define CR3_ADDR_MASK __sme_clr(0x7FFFFFFFFFFFF000ull)
 #define CR3_PCID_MASK 0xFFFull
+#define CR3_NOFLUSH (1UL << 63)
 #else
 /*
  * CR3_ADDR_MASK needs at least bits 31:5 set on PAE systems, and we save
@@ -43,6 +44,7 @@
  */
 #define CR3_ADDR_MASK 0xFFFFFFFFull
 #define CR3_PCID_MASK 0ull
+#define CR3_NOFLUSH 0
 #endif
 
 #endif /* _ASM_X86_PROCESSOR_FLAGS_H */
diff --git a/arch/x86/include/asm/tlbflush.h b/arch/x86/include/asm/tlbflush.h
index 6397275008db..d23e61dc0640 100644
--- a/arch/x86/include/asm/tlbflush.h
+++ b/arch/x86/include/asm/tlbflush.h
@@ -82,6 +82,12 @@ static inline u64 inc_mm_tlb_gen(struct mm_struct *mm)
 #define __flush_tlb_single(addr) __native_flush_tlb_single(addr)
 #endif
 
+/*
+ * 6 because 6 should be plenty and struct tlb_state will fit in
+ * two cache lines.
+ */
+#define TLB_NR_DYN_ASIDS 6
+
 struct tlb_context {
 	u64 ctx_id;
 	u64 tlb_gen;
@@ -95,6 +101,8 @@ struct tlb_state {
 	 * mode even if we've already switched back to swapper_pg_dir.
 	 */
 	struct mm_struct *loaded_mm;
+	u16 loaded_mm_asid;
+	u16 next_asid;
 
 	/*
 	 * Access to this CR4 shadow and to H/W CR4 is protected by
@@ -104,7 +112,8 @@ struct tlb_state {
 
 	/*
 	 * This is a list of all contexts that might exist in the TLB.
-	 * Since we don't yet use PCID, there is only one context.
+	 * There is one per ASID that we use, and the ASID (what the
+	 * CPU calls PCID) is the index into ctxts.
 	 *
 	 * For each context, ctx_id indicates which mm the TLB's user
 	 * entries came from.  As an invariant, the TLB will never
@@ -114,8 +123,13 @@ struct tlb_state {
 	 * To be clear, this means that it's legal for the TLB code to
 	 * flush the TLB without updating tlb_gen.  This can happen
 	 * (for now, at least) due to paravirt remote flushes.
+	 *
+	 * NB: context 0 is a bit special, since it's also used by
+	 * various bits of init code.  This is fine -- code that
+	 * isn't aware of PCID will end up harmlessly flushing
+	 * context 0.
 	 */
-	struct tlb_context ctxs[1];
+	struct tlb_context ctxs[TLB_NR_DYN_ASIDS];
 };
 DECLARE_PER_CPU_SHARED_ALIGNED(struct tlb_state, cpu_tlbstate);
 
diff --git a/arch/x86/mm/init.c b/arch/x86/mm/init.c
index 4d353efb2838..65ae17d45c4a 100644
--- a/arch/x86/mm/init.c
+++ b/arch/x86/mm/init.c
@@ -812,6 +812,7 @@ void __init zone_sizes_init(void)
 
 DEFINE_PER_CPU_SHARED_ALIGNED(struct tlb_state, cpu_tlbstate) = {
 	.loaded_mm = &init_mm,
+	.next_asid = 1,
 	.cr4 = ~0UL,	/* fail hard if we screw up cr4 shadow initialization */
 };
 EXPORT_SYMBOL_GPL(cpu_tlbstate);
diff --git a/arch/x86/mm/tlb.c b/arch/x86/mm/tlb.c
index 593d2f76a54c..ce104b962a17 100644
--- a/arch/x86/mm/tlb.c
+++ b/arch/x86/mm/tlb.c
@@ -30,6 +30,40 @@
 
 atomic64_t last_mm_ctx_id = ATOMIC64_INIT(1);
 
+static void choose_new_asid(struct mm_struct *next, u64 next_tlb_gen,
+			    u16 *new_asid, bool *need_flush)
+{
+	u16 asid;
+
+	if (!static_cpu_has(X86_FEATURE_PCID)) {
+		*new_asid = 0;
+		*need_flush = true;
+		return;
+	}
+
+	for (asid = 0; asid < TLB_NR_DYN_ASIDS; asid++) {
+		if (this_cpu_read(cpu_tlbstate.ctxs[asid].ctx_id) !=
+		    next->context.ctx_id)
+			continue;
+
+		*new_asid = asid;
+		*need_flush = (this_cpu_read(cpu_tlbstate.ctxs[asid].tlb_gen) <
+			       next_tlb_gen);
+		return;
+	}
+
+	/*
+	 * We don't currently own an ASID slot on this CPU.
+	 * Allocate a slot.
+	 */
+	*new_asid = this_cpu_add_return(cpu_tlbstate.next_asid, 1) - 1;
+	if (*new_asid >= TLB_NR_DYN_ASIDS) {
+		*new_asid = 0;
+		this_cpu_write(cpu_tlbstate.next_asid, 1);
+	}
+	*need_flush = true;
+}
+
 void leave_mm(int cpu)
 {
 	struct mm_struct *loaded_mm = this_cpu_read(cpu_tlbstate.loaded_mm);
@@ -65,6 +99,7 @@ void switch_mm_irqs_off(struct mm_struct *prev, struct mm_struct *next,
 			struct task_struct *tsk)
 {
 	struct mm_struct *real_prev = this_cpu_read(cpu_tlbstate.loaded_mm);
+	u16 prev_asid = this_cpu_read(cpu_tlbstate.loaded_mm_asid);
 	unsigned cpu = smp_processor_id();
 	u64 next_tlb_gen;
 
@@ -84,12 +119,13 @@ void switch_mm_irqs_off(struct mm_struct *prev, struct mm_struct *next,
 	/*
 	 * Verify that CR3 is what we think it is.  This will catch
 	 * hypothetical buggy code that directly switches to swapper_pg_dir
-	 * without going through leave_mm() / switch_mm_irqs_off().
+	 * without going through leave_mm() / switch_mm_irqs_off() or that
+	 * does something like write_cr3(read_cr3_pa()).
 	 */
-	VM_BUG_ON(read_cr3_pa() != __pa(real_prev->pgd));
+	VM_BUG_ON(__read_cr3() != (__sme_pa(real_prev->pgd) | prev_asid));
 
 	if (real_prev == next) {
-		VM_BUG_ON(this_cpu_read(cpu_tlbstate.ctxs[0].ctx_id) !=
+		VM_BUG_ON(this_cpu_read(cpu_tlbstate.ctxs[prev_asid].ctx_id) !=
 			  next->context.ctx_id);
 
 		if (cpumask_test_cpu(cpu, mm_cpumask(next))) {
@@ -106,16 +142,17 @@ void switch_mm_irqs_off(struct mm_struct *prev, struct mm_struct *next,
 		cpumask_set_cpu(cpu, mm_cpumask(next));
 		next_tlb_gen = atomic64_read(&next->context.tlb_gen);
 
-		if (this_cpu_read(cpu_tlbstate.ctxs[0].tlb_gen) < next_tlb_gen) {
+		if (this_cpu_read(cpu_tlbstate.ctxs[prev_asid].tlb_gen) <
+		    next_tlb_gen) {
 			/*
 			 * Ideally, we'd have a flush_tlb() variant that
 			 * takes the known CR3 value as input.  This would
 			 * be faster on Xen PV and on hypothetical CPUs
 			 * on which INVPCID is fast.
 			 */
-			this_cpu_write(cpu_tlbstate.ctxs[0].tlb_gen,
+			this_cpu_write(cpu_tlbstate.ctxs[prev_asid].tlb_gen,
 				       next_tlb_gen);
-			write_cr3(__sme_pa(next->pgd));
+			write_cr3(__sme_pa(next->pgd) | prev_asid);
 			trace_tlb_flush(TLB_FLUSH_ON_TASK_SWITCH,
 					TLB_FLUSH_ALL);
 		}
@@ -126,8 +163,8 @@ void switch_mm_irqs_off(struct mm_struct *prev, struct mm_struct *next,
 		 * are not reflected in tlb_gen.)
 		 */
 	} else {
-		VM_BUG_ON(this_cpu_read(cpu_tlbstate.ctxs[0].ctx_id) ==
-			  next->context.ctx_id);
+		u16 new_asid;
+		bool need_flush;
 
 		if (IS_ENABLED(CONFIG_VMAP_STACK)) {
 			/*
@@ -154,12 +191,22 @@ void switch_mm_irqs_off(struct mm_struct *prev, struct mm_struct *next,
 		cpumask_set_cpu(cpu, mm_cpumask(next));
 		next_tlb_gen = atomic64_read(&next->context.tlb_gen);
 
-		this_cpu_write(cpu_tlbstate.ctxs[0].ctx_id, next->context.ctx_id);
-		this_cpu_write(cpu_tlbstate.ctxs[0].tlb_gen, next_tlb_gen);
-		this_cpu_write(cpu_tlbstate.loaded_mm, next);
-		write_cr3(__sme_pa(next->pgd));
+		choose_new_asid(next, next_tlb_gen, &new_asid, &need_flush);
 
-		trace_tlb_flush(TLB_FLUSH_ON_TASK_SWITCH, TLB_FLUSH_ALL);
+		if (need_flush) {
+			this_cpu_write(cpu_tlbstate.ctxs[new_asid].ctx_id, next->context.ctx_id);
+			this_cpu_write(cpu_tlbstate.ctxs[new_asid].tlb_gen, next_tlb_gen);
+			write_cr3(__sme_pa(next->pgd) | new_asid);
+			trace_tlb_flush(TLB_FLUSH_ON_TASK_SWITCH,
+					TLB_FLUSH_ALL);
+		} else {
+			/* The new ASID is already up to date. */
+			write_cr3(__sme_pa(next->pgd) | new_asid | CR3_NOFLUSH);
+			trace_tlb_flush(TLB_FLUSH_ON_TASK_SWITCH, 0);
+		}
+
+		this_cpu_write(cpu_tlbstate.loaded_mm, next);
+		this_cpu_write(cpu_tlbstate.loaded_mm_asid, new_asid);
 	}
 
 	load_mm_cr4(next);
@@ -186,13 +233,14 @@ static void flush_tlb_func_common(const struct flush_tlb_info *f,
 	 *                   wants us to catch up to.
 	 */
 	struct mm_struct *loaded_mm = this_cpu_read(cpu_tlbstate.loaded_mm);
+	u32 loaded_mm_asid = this_cpu_read(cpu_tlbstate.loaded_mm_asid);
 	u64 mm_tlb_gen = atomic64_read(&loaded_mm->context.tlb_gen);
-	u64 local_tlb_gen = this_cpu_read(cpu_tlbstate.ctxs[0].tlb_gen);
+	u64 local_tlb_gen = this_cpu_read(cpu_tlbstate.ctxs[loaded_mm_asid].tlb_gen);
 
 	/* This code cannot presently handle being reentered. */
 	VM_WARN_ON(!irqs_disabled());
 
-	VM_WARN_ON(this_cpu_read(cpu_tlbstate.ctxs[0].ctx_id) !=
+	VM_WARN_ON(this_cpu_read(cpu_tlbstate.ctxs[loaded_mm_asid].ctx_id) !=
 		   loaded_mm->context.ctx_id);
 
 	if (!cpumask_test_cpu(smp_processor_id(), mm_cpumask(loaded_mm))) {
@@ -280,7 +328,7 @@ static void flush_tlb_func_common(const struct flush_tlb_info *f,
 	}
 
 	/* Both paths above update our state to mm_tlb_gen. */
-	this_cpu_write(cpu_tlbstate.ctxs[0].tlb_gen, mm_tlb_gen);
+	this_cpu_write(cpu_tlbstate.ctxs[loaded_mm_asid].tlb_gen, mm_tlb_gen);
 }
 
 static void flush_tlb_func_local(void *info, enum tlb_flush_reason reason)
-- 
2.41.0
```
