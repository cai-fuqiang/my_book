From 6adba527420651b6cacaf392541c09fb108711a2 Mon Sep 17 00:00:00 2001
From: Gleb Natapov <gleb@redhat.com>
Date: Thu, 14 Oct 2010 11:22:55 +0200
Subject: [PATCH 10/11] KVM: Let host know whether the guest can handle async
 PF in non-userspace context.

If guest can detect that it runs in non-preemptable context it can
handle async PFs at any time, so let host know that it can send async
PF even if guest cpu is not in userspace.

Acked-by: Rik van Riel <riel@redhat.com>
Signed-off-by: Gleb Natapov <gleb@redhat.com>
Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
---
 Documentation/kvm/msr.txt       | 5 +++--
 arch/x86/include/asm/kvm_host.h | 1 +
 arch/x86/include/asm/kvm_para.h | 1 +
 arch/x86/kernel/kvm.c           | 3 +++
 arch/x86/kvm/x86.c              | 5 +++--
 5 files changed, 11 insertions(+), 4 deletions(-)

diff --git a/Documentation/kvm/msr.txt b/Documentation/kvm/msr.txt
index e67b4a8783df..d079aed27e03 100644
--- a/Documentation/kvm/msr.txt
+++ b/Documentation/kvm/msr.txt
@@ -154,9 +154,10 @@ MSR_KVM_SYSTEM_TIME: 0x12
 MSR_KVM_ASYNC_PF_EN: 0x4b564d02
 	data: Bits 63-6 hold 64-byte aligned physical address of a
 	64 byte memory area which must be in guest RAM and must be
-	zeroed. Bits 5-1 are reserved and should be zero. Bit 0 is 1
+	zeroed. Bits 5-2 are reserved and should be zero. Bit 0 is 1
 	when asynchronous page faults are enabled on the vcpu 0 when
-	disabled.
+	disabled. Bit 2 is 1 if asynchronous page faults can be injected
+	when vcpu is in cpl == 0.
 
 	First 4 byte of 64 byte memory location will be written to by
 	the hypervisor at the time of asynchronous page fault (APF)
diff --git a/arch/x86/include/asm/kvm_host.h b/arch/x86/include/asm/kvm_host.h
index 167375cc49ff..b2ea42870e47 100644
--- a/arch/x86/include/asm/kvm_host.h
+++ b/arch/x86/include/asm/kvm_host.h
@@ -422,6 +422,7 @@ struct kvm_vcpu_arch {
 		struct gfn_to_hva_cache data;
 		u64 msr_val;
 		u32 id;
+		bool send_user_only;
 	} apf;
 };
 
diff --git a/arch/x86/include/asm/kvm_para.h b/arch/x86/include/asm/kvm_para.h
index fbfd3679bc18..d3a1a4805ab8 100644
--- a/arch/x86/include/asm/kvm_para.h
+++ b/arch/x86/include/asm/kvm_para.h
@@ -38,6 +38,7 @@
 #define KVM_MAX_MMU_OP_BATCH           32
 
 #define KVM_ASYNC_PF_ENABLED			(1 << 0)
+#define KVM_ASYNC_PF_SEND_ALWAYS		(1 << 1)
 
 /* Operations for KVM_HC_MMU_OP */
 #define KVM_MMU_OP_WRITE_PTE            1
diff --git a/arch/x86/kernel/kvm.c b/arch/x86/kernel/kvm.c
index 47ea93e6b0d8..91b3d650898c 100644
--- a/arch/x86/kernel/kvm.c
+++ b/arch/x86/kernel/kvm.c
@@ -449,6 +449,9 @@ void __cpuinit kvm_guest_cpu_init(void)
 	if (kvm_para_has_feature(KVM_FEATURE_ASYNC_PF) && kvmapf) {
 		u64 pa = __pa(&__get_cpu_var(apf_reason));
 
+#ifdef CONFIG_PREEMPT
+		pa |= KVM_ASYNC_PF_SEND_ALWAYS;
+#endif
 		wrmsrl(MSR_KVM_ASYNC_PF_EN, pa | KVM_ASYNC_PF_ENABLED);
 		__get_cpu_var(apf_reason).enabled = 1;
 		printk(KERN_INFO"KVM setup async PF for cpu %d\n",
diff --git a/arch/x86/kvm/x86.c b/arch/x86/kvm/x86.c
index ac4c368afd40..fff70b50725c 100644
--- a/arch/x86/kvm/x86.c
+++ b/arch/x86/kvm/x86.c
@@ -1429,8 +1429,8 @@ static int kvm_pv_enable_async_pf(struct kvm_vcpu *vcpu, u64 data)
 {
 	gpa_t gpa = data & ~0x3f;
 
-	/* Bits 1:5 are resrved, Should be zero */
-	if (data & 0x3e)
+	/* Bits 2:5 are resrved, Should be zero */
+	if (data & 0x3c)
 		return 1;
 
 	vcpu->arch.apf.msr_val = data;
@@ -1444,6 +1444,7 @@ static int kvm_pv_enable_async_pf(struct kvm_vcpu *vcpu, u64 data)
 	if (kvm_gfn_to_hva_cache_init(vcpu->kvm, &vcpu->arch.apf.data, gpa))
 		return 1;
 
+	vcpu->arch.apf.send_user_only = !(data & KVM_ASYNC_PF_SEND_ALWAYS);
 	kvm_async_pf_wakeup_all(vcpu);
 	return 0;
 }
-- 
2.41.0

