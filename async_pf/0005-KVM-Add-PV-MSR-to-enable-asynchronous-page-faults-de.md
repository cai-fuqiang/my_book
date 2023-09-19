From 344d9588a9df06182684168be4f1408b55c7da3e Mon Sep 17 00:00:00 2001
From: Gleb Natapov <gleb@redhat.com>
Date: Thu, 14 Oct 2010 11:22:50 +0200
Subject: [PATCH 05/11] KVM: Add PV MSR to enable asynchronous page faults
 delivery.

Guest enables async PF vcpu functionality using this MSR.

Reviewed-by: Rik van Riel <riel@redhat.com>
Signed-off-by: Gleb Natapov <gleb@redhat.com>
Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
---
 Documentation/kvm/cpuid.txt     |  3 +++
 Documentation/kvm/msr.txt       | 35 +++++++++++++++++++++++++++++-
 arch/x86/include/asm/kvm_host.h |  2 ++
 arch/x86/include/asm/kvm_para.h |  4 ++++
 arch/x86/kvm/x86.c              | 38 +++++++++++++++++++++++++++++++--
 include/linux/kvm.h             |  1 +
 include/linux/kvm_host.h        |  1 +
 virt/kvm/async_pf.c             | 20 +++++++++++++++++
 8 files changed, 101 insertions(+), 3 deletions(-)

diff --git a/Documentation/kvm/cpuid.txt b/Documentation/kvm/cpuid.txt
index 14a12ea92b7f..882068538c9c 100644
--- a/Documentation/kvm/cpuid.txt
+++ b/Documentation/kvm/cpuid.txt
@@ -36,6 +36,9 @@ KVM_FEATURE_MMU_OP                 ||     2 || deprecated.
 KVM_FEATURE_CLOCKSOURCE2           ||     3 || kvmclock available at msrs
                                    ||       || 0x4b564d00 and 0x4b564d01
 ------------------------------------------------------------------------------
+KVM_FEATURE_ASYNC_PF               ||     4 || async pf can be enabled by
+                                   ||       || writing to msr 0x4b564d02
+------------------------------------------------------------------------------
 KVM_FEATURE_CLOCKSOURCE_STABLE_BIT ||    24 || host will warn if no guest-side
                                    ||       || per-cpu warps are expected in
                                    ||       || kvmclock.
diff --git a/Documentation/kvm/msr.txt b/Documentation/kvm/msr.txt
index 8ddcfe84c09a..e67b4a8783df 100644
--- a/Documentation/kvm/msr.txt
+++ b/Documentation/kvm/msr.txt
@@ -3,7 +3,6 @@ Glauber Costa <glommer@redhat.com>, Red Hat Inc, 2010
 =====================================================
 
 KVM makes use of some custom MSRs to service some requests.
-At present, this facility is only used by kvmclock.
 
 Custom MSRs have a range reserved for them, that goes from
 0x4b564d00 to 0x4b564dff. There are MSRs outside this area,
@@ -151,3 +150,37 @@ MSR_KVM_SYSTEM_TIME: 0x12
 			return PRESENT;
 		} else
 			return NON_PRESENT;
+
+MSR_KVM_ASYNC_PF_EN: 0x4b564d02
+	data: Bits 63-6 hold 64-byte aligned physical address of a
+	64 byte memory area which must be in guest RAM and must be
+	zeroed. Bits 5-1 are reserved and should be zero. Bit 0 is 1
+	when asynchronous page faults are enabled on the vcpu 0 when
+	disabled.
+
+	First 4 byte of 64 byte memory location will be written to by
+	the hypervisor at the time of asynchronous page fault (APF)
+	injection to indicate type of asynchronous page fault. Value
+	of 1 means that the page referred to by the page fault is not
+	present. Value 2 means that the page is now available. Disabling
+	interrupt inhibits APFs. Guest must not enable interrupt
+	before the reason is read, or it may be overwritten by another
+	APF. Since APF uses the same exception vector as regular page
+	fault guest must reset the reason to 0 before it does
+	something that can generate normal page fault.  If during page
+	fault APF reason is 0 it means that this is regular page
+	fault.
+
+	During delivery of type 1 APF cr2 contains a token that will
+	be used to notify a guest when missing page becomes
+	available. When page becomes available type 2 APF is sent with
+	cr2 set to the token associated with the page. There is special
+	kind of token 0xffffffff which tells vcpu that it should wake
+	up all processes waiting for APFs and no individual type 2 APFs
+	will be sent.
+
+	If APF is disabled while there are outstanding APFs, they will
+	not be delivered.
+
+	Currently type 2 APF will be always delivered on the same vcpu as
+	type 1 was, but guest should not rely on that.
diff --git a/arch/x86/include/asm/kvm_host.h b/arch/x86/include/asm/kvm_host.h
index c3076bcf5ef7..0d7039804b4c 100644
--- a/arch/x86/include/asm/kvm_host.h
+++ b/arch/x86/include/asm/kvm_host.h
@@ -419,6 +419,8 @@ struct kvm_vcpu_arch {
 	struct {
 		bool halted;
 		gfn_t gfns[roundup_pow_of_two(ASYNC_PF_PER_VCPU)];
+		struct gfn_to_hva_cache data;
+		u64 msr_val;
 	} apf;
 };
 
diff --git a/arch/x86/include/asm/kvm_para.h b/arch/x86/include/asm/kvm_para.h
index e3faaaf4301e..8662ae0a035c 100644
--- a/arch/x86/include/asm/kvm_para.h
+++ b/arch/x86/include/asm/kvm_para.h
@@ -20,6 +20,7 @@
  * are available. The use of 0x11 and 0x12 is deprecated
  */
 #define KVM_FEATURE_CLOCKSOURCE2        3
+#define KVM_FEATURE_ASYNC_PF		4
 
 /* The last 8 bits are used to indicate how to interpret the flags field
  * in pvclock structure. If no bits are set, all flags are ignored.
@@ -32,9 +33,12 @@
 /* Custom MSRs falls in the range 0x4b564d00-0x4b564dff */
 #define MSR_KVM_WALL_CLOCK_NEW  0x4b564d00
 #define MSR_KVM_SYSTEM_TIME_NEW 0x4b564d01
+#define MSR_KVM_ASYNC_PF_EN 0x4b564d02
 
 #define KVM_MAX_MMU_OP_BATCH           32
 
+#define KVM_ASYNC_PF_ENABLED			(1 << 0)
+
 /* Operations for KVM_HC_MMU_OP */
 #define KVM_MMU_OP_WRITE_PTE            1
 #define KVM_MMU_OP_FLUSH_TLB	        2
diff --git a/arch/x86/kvm/x86.c b/arch/x86/kvm/x86.c
index bd254779d1cc..063c07296764 100644
--- a/arch/x86/kvm/x86.c
+++ b/arch/x86/kvm/x86.c
@@ -783,12 +783,12 @@ EXPORT_SYMBOL_GPL(kvm_get_dr);
  * kvm-specific. Those are put in the beginning of the list.
  */
 
-#define KVM_SAVE_MSRS_BEGIN	7
+#define KVM_SAVE_MSRS_BEGIN	8
 static u32 msrs_to_save[] = {
 	MSR_KVM_SYSTEM_TIME, MSR_KVM_WALL_CLOCK,
 	MSR_KVM_SYSTEM_TIME_NEW, MSR_KVM_WALL_CLOCK_NEW,
 	HV_X64_MSR_GUEST_OS_ID, HV_X64_MSR_HYPERCALL,
-	HV_X64_MSR_APIC_ASSIST_PAGE,
+	HV_X64_MSR_APIC_ASSIST_PAGE, MSR_KVM_ASYNC_PF_EN,
 	MSR_IA32_SYSENTER_CS, MSR_IA32_SYSENTER_ESP, MSR_IA32_SYSENTER_EIP,
 	MSR_STAR,
 #ifdef CONFIG_X86_64
@@ -1425,6 +1425,29 @@ static int set_msr_hyperv(struct kvm_vcpu *vcpu, u32 msr, u64 data)
 	return 0;
 }
 
+static int kvm_pv_enable_async_pf(struct kvm_vcpu *vcpu, u64 data)
+{
+	gpa_t gpa = data & ~0x3f;
+
+	/* Bits 1:5 are resrved, Should be zero */
+	if (data & 0x3e)
+		return 1;
+
+	vcpu->arch.apf.msr_val = data;
+
+	if (!(data & KVM_ASYNC_PF_ENABLED)) {
+		kvm_clear_async_pf_completion_queue(vcpu);
+		kvm_async_pf_hash_reset(vcpu);
+		return 0;
+	}
+
+	if (kvm_gfn_to_hva_cache_init(vcpu->kvm, &vcpu->arch.apf.data, gpa))
+		return 1;
+
+	kvm_async_pf_wakeup_all(vcpu);
+	return 0;
+}
+
 int kvm_set_msr_common(struct kvm_vcpu *vcpu, u32 msr, u64 data)
 {
 	switch (msr) {
@@ -1506,6 +1529,10 @@ int kvm_set_msr_common(struct kvm_vcpu *vcpu, u32 msr, u64 data)
 		}
 		break;
 	}
+	case MSR_KVM_ASYNC_PF_EN:
+		if (kvm_pv_enable_async_pf(vcpu, data))
+			return 1;
+		break;
 	case MSR_IA32_MCG_CTL:
 	case MSR_IA32_MCG_STATUS:
 	case MSR_IA32_MC0_CTL ... MSR_IA32_MC0_CTL + 4 * KVM_MAX_MCE_BANKS - 1:
@@ -1782,6 +1809,9 @@ int kvm_get_msr_common(struct kvm_vcpu *vcpu, u32 msr, u64 *pdata)
 	case MSR_KVM_SYSTEM_TIME_NEW:
 		data = vcpu->arch.time;
 		break;
+	case MSR_KVM_ASYNC_PF_EN:
+		data = vcpu->arch.apf.msr_val;
+		break;
 	case MSR_IA32_P5_MC_ADDR:
 	case MSR_IA32_P5_MC_TYPE:
 	case MSR_IA32_MCG_CAP:
@@ -1929,6 +1959,7 @@ int kvm_dev_ioctl_check_extension(long ext)
 	case KVM_CAP_DEBUGREGS:
 	case KVM_CAP_X86_ROBUST_SINGLESTEP:
 	case KVM_CAP_XSAVE:
+	case KVM_CAP_ASYNC_PF:
 		r = 1;
 		break;
 	case KVM_CAP_COALESCED_MMIO:
@@ -5792,6 +5823,8 @@ int kvm_arch_vcpu_setup(struct kvm_vcpu *vcpu)
 
 void kvm_arch_vcpu_destroy(struct kvm_vcpu *vcpu)
 {
+	vcpu->arch.apf.msr_val = 0;
+
 	vcpu_load(vcpu);
 	kvm_mmu_unload(vcpu);
 	vcpu_put(vcpu);
@@ -5811,6 +5844,7 @@ int kvm_arch_vcpu_reset(struct kvm_vcpu *vcpu)
 	vcpu->arch.dr7 = DR7_FIXED_1;
 
 	kvm_make_request(KVM_REQ_EVENT, vcpu);
+	vcpu->arch.apf.msr_val = 0;
 
 	kvm_clear_async_pf_completion_queue(vcpu);
 	kvm_async_pf_hash_reset(vcpu);
diff --git a/include/linux/kvm.h b/include/linux/kvm.h
index 919ae53adc5c..ea2dc1a2e13d 100644
--- a/include/linux/kvm.h
+++ b/include/linux/kvm.h
@@ -540,6 +540,7 @@ struct kvm_ppc_pvinfo {
 #endif
 #define KVM_CAP_PPC_GET_PVINFO 57
 #define KVM_CAP_PPC_IRQ_LEVEL 58
+#define KVM_CAP_ASYNC_PF 59
 
 #ifdef KVM_CAP_IRQ_ROUTING
 
diff --git a/include/linux/kvm_host.h b/include/linux/kvm_host.h
index e6748204cd56..ee4314e15ead 100644
--- a/include/linux/kvm_host.h
+++ b/include/linux/kvm_host.h
@@ -93,6 +93,7 @@ void kvm_clear_async_pf_completion_queue(struct kvm_vcpu *vcpu);
 void kvm_check_async_pf_completion(struct kvm_vcpu *vcpu);
 int kvm_setup_async_pf(struct kvm_vcpu *vcpu, gva_t gva, gfn_t gfn,
 		       struct kvm_arch_async_pf *arch);
+int kvm_async_pf_wakeup_all(struct kvm_vcpu *vcpu);
 #endif
 
 struct kvm_vcpu {
diff --git a/virt/kvm/async_pf.c b/virt/kvm/async_pf.c
index e97eae965a4c..1f59498561b2 100644
--- a/virt/kvm/async_pf.c
+++ b/virt/kvm/async_pf.c
@@ -190,3 +190,23 @@ int kvm_setup_async_pf(struct kvm_vcpu *vcpu, gva_t gva, gfn_t gfn,
 	kmem_cache_free(async_pf_cache, work);
 	return 0;
 }
+
+int kvm_async_pf_wakeup_all(struct kvm_vcpu *vcpu)
+{
+	struct kvm_async_pf *work;
+
+	if (!list_empty(&vcpu->async_pf.done))
+		return 0;
+
+	work = kmem_cache_zalloc(async_pf_cache, GFP_ATOMIC);
+	if (!work)
+		return -ENOMEM;
+
+	work->page = bad_page;
+	get_page(bad_page);
+	INIT_LIST_HEAD(&work->queue); /* for list_del to work */
+
+	list_add_tail(&work->link, &vcpu->async_pf.done);
+	vcpu->async_pf.queued++;
+	return 0;
+}
-- 
2.41.0

