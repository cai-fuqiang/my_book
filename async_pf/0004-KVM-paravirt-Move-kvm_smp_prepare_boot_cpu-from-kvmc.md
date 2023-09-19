From ca3f10172eea9b95bbb66487656f3c3e93855702 Mon Sep 17 00:00:00 2001
From: Gleb Natapov <gleb@redhat.com>
Date: Thu, 14 Oct 2010 11:22:49 +0200
Subject: [PATCH 04/11] KVM paravirt: Move kvm_smp_prepare_boot_cpu() from
 kvmclock.c to kvm.c.

Async PF also needs to hook into smp_prepare_boot_cpu so move the hook
into generic code.

Acked-by: Rik van Riel <riel@redhat.com>
Signed-off-by: Gleb Natapov <gleb@redhat.com>
Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
---
 arch/x86/include/asm/kvm_para.h |  1 +
 arch/x86/kernel/kvm.c           | 11 +++++++++++
 arch/x86/kernel/kvmclock.c      | 13 +------------
 3 files changed, 13 insertions(+), 12 deletions(-)

diff --git a/arch/x86/include/asm/kvm_para.h b/arch/x86/include/asm/kvm_para.h
index 7b562b6184bc..e3faaaf4301e 100644
--- a/arch/x86/include/asm/kvm_para.h
+++ b/arch/x86/include/asm/kvm_para.h
@@ -65,6 +65,7 @@ struct kvm_mmu_op_release_pt {
 #include <asm/processor.h>
 
 extern void kvmclock_init(void);
+extern int kvm_register_clock(char *txt);
 
 
 /* This instruction is vmcall.  On non-VT architectures, it will generate a
diff --git a/arch/x86/kernel/kvm.c b/arch/x86/kernel/kvm.c
index 63b0ec8d3d4a..e6db17976b82 100644
--- a/arch/x86/kernel/kvm.c
+++ b/arch/x86/kernel/kvm.c
@@ -231,10 +231,21 @@ static void __init paravirt_ops_setup(void)
 #endif
 }
 
+#ifdef CONFIG_SMP
+static void __init kvm_smp_prepare_boot_cpu(void)
+{
+	WARN_ON(kvm_register_clock("primary cpu clock"));
+	native_smp_prepare_boot_cpu();
+}
+#endif
+
 void __init kvm_guest_init(void)
 {
 	if (!kvm_para_available())
 		return;
 
 	paravirt_ops_setup();
+#ifdef CONFIG_SMP
+	smp_ops.smp_prepare_boot_cpu = kvm_smp_prepare_boot_cpu;
+#endif
 }
diff --git a/arch/x86/kernel/kvmclock.c b/arch/x86/kernel/kvmclock.c
index ca43ce31a19c..f98d3eafe07a 100644
--- a/arch/x86/kernel/kvmclock.c
+++ b/arch/x86/kernel/kvmclock.c
@@ -125,7 +125,7 @@ static struct clocksource kvm_clock = {
 	.flags = CLOCK_SOURCE_IS_CONTINUOUS,
 };
 
-static int kvm_register_clock(char *txt)
+int kvm_register_clock(char *txt)
 {
 	int cpu = smp_processor_id();
 	int low, high, ret;
@@ -152,14 +152,6 @@ static void __cpuinit kvm_setup_secondary_clock(void)
 }
 #endif
 
-#ifdef CONFIG_SMP
-static void __init kvm_smp_prepare_boot_cpu(void)
-{
-	WARN_ON(kvm_register_clock("primary cpu clock"));
-	native_smp_prepare_boot_cpu();
-}
-#endif
-
 /*
  * After the clock is registered, the host will keep writing to the
  * registered memory location. If the guest happens to shutdown, this memory
@@ -205,9 +197,6 @@ void __init kvmclock_init(void)
 #ifdef CONFIG_X86_LOCAL_APIC
 	x86_cpuinit.setup_percpu_clockev =
 		kvm_setup_secondary_clock;
-#endif
-#ifdef CONFIG_SMP
-	smp_ops.smp_prepare_boot_cpu = kvm_smp_prepare_boot_cpu;
 #endif
 	machine_ops.shutdown  = kvm_shutdown;
 #ifdef CONFIG_KEXEC
-- 
2.41.0

