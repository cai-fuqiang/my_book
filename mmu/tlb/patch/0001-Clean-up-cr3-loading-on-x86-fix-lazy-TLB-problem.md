```
From 99ef44b79de47f23869897c11493521a1e42b2d2 Mon Sep 17 00:00:00 2001
From: Linus Torvalds <torvalds@home.transmeta.com>
Date: Mon, 20 May 2002 05:58:03 -0700
Subject: [PATCH] Clean up %cr3 loading on x86, fix lazy TLB problem

---
 arch/i386/kernel/process.c     | 2 +-
 arch/i386/kernel/smp.c         | 4 ++++
 arch/i386/mm/init.c            | 2 +-
 include/asm-i386/mmu_context.h | 6 +++---
 include/asm-i386/processor.h   | 4 ++++
 5 files changed, 13 insertions(+), 5 deletions(-)

diff --git a/arch/i386/kernel/process.c b/arch/i386/kernel/process.c
index b077dc29832..ad92945381e 100644
--- a/arch/i386/kernel/process.c
+++ b/arch/i386/kernel/process.c
@@ -321,7 +321,7 @@ void machine_real_restart(unsigned char *code, int length)
 	/*
 	 * Use `swapper_pg_dir' as our page directory.
 	 */
-	asm volatile("movl %0,%%cr3": :"r" (__pa(swapper_pg_dir)));
+	load_cr3(swapper_pg_dir);
 
 	/* Write 0x1234 to absolute memory location 0x472.  The BIOS reads
 	   this on booting to tell it to "Bypass memory test (also warm
diff --git a/arch/i386/kernel/smp.c b/arch/i386/kernel/smp.c
index a1ce9bfe76e..e269f711311 100644
--- a/arch/i386/kernel/smp.c
+++ b/arch/i386/kernel/smp.c
@@ -299,12 +299,16 @@ static spinlock_t tlbstate_lock = SPIN_LOCK_UNLOCKED;
 /*
  * We cannot call mmdrop() because we are in interrupt context, 
  * instead update mm->cpu_vm_mask.
+ *
+ * We need to reload %cr3 since the page tables may be going
+ * away from under us..
  */
 static void inline leave_mm (unsigned long cpu)
 {
 	if (cpu_tlbstate[cpu].state == TLBSTATE_OK)
 		BUG();
 	clear_bit(cpu, &cpu_tlbstate[cpu].active_mm->cpu_vm_mask);
+	load_cr3(swapper_pg_dir);
 }
 
 /*
diff --git a/arch/i386/mm/init.c b/arch/i386/mm/init.c
index 8e565c1f4c8..cb8a9367e47 100644
--- a/arch/i386/mm/init.c
+++ b/arch/i386/mm/init.c
@@ -307,7 +307,7 @@ void __init paging_init(void)
 {
 	pagetable_init();
 
-	__asm__( "movl %0,%%cr3\n" ::"r"(__pa(swapper_pg_dir)));
+	load_cr3(swapper_pg_dir);
 
 #if CONFIG_X86_PAE
 	/*
diff --git a/include/asm-i386/mmu_context.h b/include/asm-i386/mmu_context.h
index 4b9c0b31220..417f2378659 100644
--- a/include/asm-i386/mmu_context.h
+++ b/include/asm-i386/mmu_context.h
@@ -38,7 +38,7 @@ static inline void switch_mm(struct mm_struct *prev, struct mm_struct *next, str
 		set_bit(cpu, &next->cpu_vm_mask);
 
 		/* Re-load page tables */
-		asm volatile("movl %0,%%cr3": :"r" (__pa(next->pgd)));
+		load_cr3(next->pgd);
 
 		/* load_LDT, if either the previous or next thread
 		 * has a non-default LDT.
@@ -53,9 +53,9 @@ static inline void switch_mm(struct mm_struct *prev, struct mm_struct *next, str
 			BUG();
 		if(!test_and_set_bit(cpu, &next->cpu_vm_mask)) {
 			/* We were in lazy tlb mode and leave_mm disabled 
-			 * tlb flush IPI delivery. We must flush our tlb.
+			 * tlb flush IPI delivery. We must reload %cr3.
 			 */
-			local_flush_tlb();
+			load_cr3(next->pgd);
 			load_LDT(&next->context);
 		}
 	}
diff --git a/include/asm-i386/processor.h b/include/asm-i386/processor.h
index 21fab1d4101..965cba2af24 100644
--- a/include/asm-i386/processor.h
+++ b/include/asm-i386/processor.h
@@ -173,6 +173,10 @@ static inline unsigned int cpuid_edx(unsigned int op)
 	return edx;
 }
 
+#define load_cr3(pgdir) \
+	asm volatile("movl %0,%%cr3": :"r" (__pa(pgdir)))
+
+
 /*
  * Intel CPU features in CR4
  */
-- 
2.41.0
```
