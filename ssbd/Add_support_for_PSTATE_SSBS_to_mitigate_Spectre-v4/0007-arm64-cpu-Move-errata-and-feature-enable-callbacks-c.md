From b8925ee2e12d1cb9a11d6f28b5814f2bfa59dce1 Mon Sep 17 00:00:00 2001
From: Will Deacon <will.deacon@arm.com>
Date: Tue, 7 Aug 2018 13:53:41 +0100
Subject: [PATCH 7/7] arm64: cpu: Move errata and feature enable callbacks
 closer to callers

The cpu errata and feature enable callbacks are only called via their
respective arm64_cpu_capabilities structure and therefore shouldn't
exist in the global namespace.

Move the PAN, RAS and cache maintenance emulation enable callbacks into
the same files as their corresponding arm64_cpu_capabilities structures,
making them static in the process.

Signed-off-by: Will Deacon <will.deacon@arm.com>
Signed-off-by: Catalin Marinas <catalin.marinas@arm.com>
---
 arch/arm64/include/asm/processor.h |  4 ----
 arch/arm64/kernel/cpu_errata.c     |  6 ++++++
 arch/arm64/kernel/cpufeature.c     | 28 ++++++++++++++++++++++------
 arch/arm64/kernel/traps.c          |  5 -----
 arch/arm64/mm/fault.c              | 14 --------------
 5 files changed, 28 insertions(+), 29 deletions(-)

diff --git a/arch/arm64/include/asm/processor.h b/arch/arm64/include/asm/processor.h
index f6835374ed9f..2bf6691371c2 100644
--- a/arch/arm64/include/asm/processor.h
+++ b/arch/arm64/include/asm/processor.h
@@ -251,10 +251,6 @@ static inline void spin_lock_prefetch(const void *ptr)
 
 #endif
 
-void cpu_enable_pan(const struct arm64_cpu_capabilities *__unused);
-void cpu_enable_cache_maint_trap(const struct arm64_cpu_capabilities *__unused);
-void cpu_clear_disr(const struct arm64_cpu_capabilities *__unused);
-
 extern unsigned long __ro_after_init signal_minsigstksz; /* sigframe size */
 extern void __init minsigstksz_setup(void);
 
diff --git a/arch/arm64/kernel/cpu_errata.c b/arch/arm64/kernel/cpu_errata.c
index c063490d7b51..8900cb0615f8 100644
--- a/arch/arm64/kernel/cpu_errata.c
+++ b/arch/arm64/kernel/cpu_errata.c
@@ -433,6 +433,12 @@ static bool has_ssbd_mitigation(const struct arm64_cpu_capabilities *entry,
 }
 #endif	/* CONFIG_ARM64_SSBD */
 
+static void __maybe_unused
+cpu_enable_cache_maint_trap(const struct arm64_cpu_capabilities *__unused)
+{
+	sysreg_clear_set(sctlr_el1, SCTLR_EL1_UCI, 0);
+}
+
 #define CAP_MIDR_RANGE(model, v_min, r_min, v_max, r_max)	\
 	.matches = is_affected_midr_range,			\
 	.midr_range = MIDR_RANGE(model, v_min, r_min, v_max, r_max)
diff --git a/arch/arm64/kernel/cpufeature.c b/arch/arm64/kernel/cpufeature.c
index 9aa18a0df0d7..35796ca1db50 100644
--- a/arch/arm64/kernel/cpufeature.c
+++ b/arch/arm64/kernel/cpufeature.c
@@ -1081,6 +1081,28 @@ static void cpu_enable_ssbs(const struct arm64_cpu_capabilities *__unused)
 }
 #endif /* CONFIG_ARM64_SSBD */
 
+#ifdef CONFIG_ARM64_PAN
+static void cpu_enable_pan(const struct arm64_cpu_capabilities *__unused)
+{
+	/*
+	 * We modify PSTATE. This won't work from irq context as the PSTATE
+	 * is discarded once we return from the exception.
+	 */
+	WARN_ON_ONCE(in_interrupt());
+
+	sysreg_clear_set(sctlr_el1, SCTLR_EL1_SPAN, 0);
+	asm(SET_PSTATE_PAN(1));
+}
+#endif /* CONFIG_ARM64_PAN */
+
+#ifdef CONFIG_ARM64_RAS_EXTN
+static void cpu_clear_disr(const struct arm64_cpu_capabilities *__unused)
+{
+	/* Firmware may have left a deferred SError in this register. */
+	write_sysreg_s(0, SYS_DISR_EL1);
+}
+#endif /* CONFIG_ARM64_RAS_EXTN */
+
 static const struct arm64_cpu_capabilities arm64_features[] = {
 	{
 		.desc = "GIC system register CPU interface",
@@ -1824,9 +1846,3 @@ static int __init enable_mrs_emulation(void)
 }
 
 core_initcall(enable_mrs_emulation);
-
-void cpu_clear_disr(const struct arm64_cpu_capabilities *__unused)
-{
-	/* Firmware may have left a deferred SError in this register. */
-	write_sysreg_s(0, SYS_DISR_EL1);
-}
diff --git a/arch/arm64/kernel/traps.c b/arch/arm64/kernel/traps.c
index b9da093e0341..148de417ed3e 100644
--- a/arch/arm64/kernel/traps.c
+++ b/arch/arm64/kernel/traps.c
@@ -412,11 +412,6 @@ asmlinkage void __exception do_undefinstr(struct pt_regs *regs)
 	BUG_ON(!user_mode(regs));
 }
 
-void cpu_enable_cache_maint_trap(const struct arm64_cpu_capabilities *__unused)
-{
-	sysreg_clear_set(sctlr_el1, SCTLR_EL1_UCI, 0);
-}
-
 #define __user_cache_maint(insn, address, res)			\
 	if (address >= user_addr_max()) {			\
 		res = -EFAULT;					\
diff --git a/arch/arm64/mm/fault.c b/arch/arm64/mm/fault.c
index 50b30ff30de4..6342f1793c70 100644
--- a/arch/arm64/mm/fault.c
+++ b/arch/arm64/mm/fault.c
@@ -864,17 +864,3 @@ asmlinkage int __exception do_debug_exception(unsigned long addr,
 	return rv;
 }
 NOKPROBE_SYMBOL(do_debug_exception);
-
-#ifdef CONFIG_ARM64_PAN
-void cpu_enable_pan(const struct arm64_cpu_capabilities *__unused)
-{
-	/*
-	 * We modify PSTATE. This won't work from irq context as the PSTATE
-	 * is discarded once we return from the exception.
-	 */
-	WARN_ON_ONCE(in_interrupt());
-
-	sysreg_clear_set(sctlr_el1, SCTLR_EL1_SPAN, 0);
-	asm(SET_PSTATE_PAN(1));
-}
-#endif /* CONFIG_ARM64_PAN */
-- 
2.39.0

