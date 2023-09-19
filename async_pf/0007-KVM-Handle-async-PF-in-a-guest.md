From 631bc4878220932fe67fc46fc7cf7cccdb1ec597 Mon Sep 17 00:00:00 2001
From: Gleb Natapov <gleb@redhat.com>
Date: Thu, 14 Oct 2010 11:22:52 +0200
Subject: [PATCH 07/11] KVM: Handle async PF in a guest.

When async PF capability is detected hook up special page fault handler
that will handle async page fault events and bypass other page faults to
regular page fault handler. Also add async PF handling to nested SVM
emulation. Async PF always generates exit to L1 where vcpu thread will
be scheduled out until page is available.

Acked-by: Rik van Riel <riel@redhat.com>
Signed-off-by: Gleb Natapov <gleb@redhat.com>
Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
---
 arch/x86/include/asm/kvm_para.h |  12 +++
 arch/x86/include/asm/traps.h    |   1 +
 arch/x86/kernel/entry_32.S      |  10 ++
 arch/x86/kernel/entry_64.S      |   3 +
 arch/x86/kernel/kvm.c           | 181 ++++++++++++++++++++++++++++++++
 arch/x86/kvm/svm.c              |  45 ++++++--
 6 files changed, 243 insertions(+), 9 deletions(-)

diff --git a/arch/x86/include/asm/kvm_para.h b/arch/x86/include/asm/kvm_para.h
index 2315398230d1..fbfd3679bc18 100644
--- a/arch/x86/include/asm/kvm_para.h
+++ b/arch/x86/include/asm/kvm_para.h
@@ -65,6 +65,9 @@ struct kvm_mmu_op_release_pt {
 	__u64 pt_phys;
 };
 
+#define KVM_PV_REASON_PAGE_NOT_PRESENT 1
+#define KVM_PV_REASON_PAGE_READY 2
+
 struct kvm_vcpu_pv_apf_data {
 	__u32 reason;
 	__u8 pad[60];
@@ -171,8 +174,17 @@ static inline unsigned int kvm_arch_para_features(void)
 
 #ifdef CONFIG_KVM_GUEST
 void __init kvm_guest_init(void);
+void kvm_async_pf_task_wait(u32 token);
+void kvm_async_pf_task_wake(u32 token);
+u32 kvm_read_and_reset_pf_reason(void);
 #else
 #define kvm_guest_init() do { } while (0)
+#define kvm_async_pf_task_wait(T) do {} while(0)
+#define kvm_async_pf_task_wake(T) do {} while(0)
+static u32 kvm_read_and_reset_pf_reason(void)
+{
+	return 0;
+}
 #endif
 
 #endif /* __KERNEL__ */
diff --git a/arch/x86/include/asm/traps.h b/arch/x86/include/asm/traps.h
index f66cda56781d..0310da67307f 100644
--- a/arch/x86/include/asm/traps.h
+++ b/arch/x86/include/asm/traps.h
@@ -30,6 +30,7 @@ asmlinkage void segment_not_present(void);
 asmlinkage void stack_segment(void);
 asmlinkage void general_protection(void);
 asmlinkage void page_fault(void);
+asmlinkage void async_page_fault(void);
 asmlinkage void spurious_interrupt_bug(void);
 asmlinkage void coprocessor_error(void);
 asmlinkage void alignment_check(void);
diff --git a/arch/x86/kernel/entry_32.S b/arch/x86/kernel/entry_32.S
index 591e60104278..c8b4efad7ebb 100644
--- a/arch/x86/kernel/entry_32.S
+++ b/arch/x86/kernel/entry_32.S
@@ -1406,6 +1406,16 @@ ENTRY(general_protection)
 	CFI_ENDPROC
 END(general_protection)
 
+#ifdef CONFIG_KVM_GUEST
+ENTRY(async_page_fault)
+	RING0_EC_FRAME
+	pushl $do_async_page_fault
+	CFI_ADJUST_CFA_OFFSET 4
+	jmp error_code
+	CFI_ENDPROC
+END(apf_page_fault)
+#endif
+
 /*
  * End of kprobes section
  */
diff --git a/arch/x86/kernel/entry_64.S b/arch/x86/kernel/entry_64.S
index e3ba417e8697..bb3f6e9bfa68 100644
--- a/arch/x86/kernel/entry_64.S
+++ b/arch/x86/kernel/entry_64.S
@@ -1319,6 +1319,9 @@ errorentry xen_stack_segment do_stack_segment
 #endif
 errorentry general_protection do_general_protection
 errorentry page_fault do_page_fault
+#ifdef CONFIG_KVM_GUEST
+errorentry async_page_fault do_async_page_fault
+#endif
 #ifdef CONFIG_X86_MCE
 paranoidzeroentry machine_check *machine_check_vector(%rip)
 #endif
diff --git a/arch/x86/kernel/kvm.c b/arch/x86/kernel/kvm.c
index 032d03b6b54a..d5640634fef6 100644
--- a/arch/x86/kernel/kvm.c
+++ b/arch/x86/kernel/kvm.c
@@ -29,8 +29,14 @@
 #include <linux/hardirq.h>
 #include <linux/notifier.h>
 #include <linux/reboot.h>
+#include <linux/hash.h>
+#include <linux/sched.h>
+#include <linux/slab.h>
+#include <linux/kprobes.h>
 #include <asm/timer.h>
 #include <asm/cpu.h>
+#include <asm/traps.h>
+#include <asm/desc.h>
 
 #define MMU_QUEUE_SIZE 1024
 
@@ -64,6 +70,168 @@ static void kvm_io_delay(void)
 {
 }
 
+#define KVM_TASK_SLEEP_HASHBITS 8
+#define KVM_TASK_SLEEP_HASHSIZE (1<<KVM_TASK_SLEEP_HASHBITS)
+
+struct kvm_task_sleep_node {
+	struct hlist_node link;
+	wait_queue_head_t wq;
+	u32 token;
+	int cpu;
+};
+
+static struct kvm_task_sleep_head {
+	spinlock_t lock;
+	struct hlist_head list;
+} async_pf_sleepers[KVM_TASK_SLEEP_HASHSIZE];
+
+static struct kvm_task_sleep_node *_find_apf_task(struct kvm_task_sleep_head *b,
+						  u32 token)
+{
+	struct hlist_node *p;
+
+	hlist_for_each(p, &b->list) {
+		struct kvm_task_sleep_node *n =
+			hlist_entry(p, typeof(*n), link);
+		if (n->token == token)
+			return n;
+	}
+
+	return NULL;
+}
+
+void kvm_async_pf_task_wait(u32 token)
+{
+	u32 key = hash_32(token, KVM_TASK_SLEEP_HASHBITS);
+	struct kvm_task_sleep_head *b = &async_pf_sleepers[key];
+	struct kvm_task_sleep_node n, *e;
+	DEFINE_WAIT(wait);
+
+	spin_lock(&b->lock);
+	e = _find_apf_task(b, token);
+	if (e) {
+		/* dummy entry exist -> wake up was delivered ahead of PF */
+		hlist_del(&e->link);
+		kfree(e);
+		spin_unlock(&b->lock);
+		return;
+	}
+
+	n.token = token;
+	n.cpu = smp_processor_id();
+	init_waitqueue_head(&n.wq);
+	hlist_add_head(&n.link, &b->list);
+	spin_unlock(&b->lock);
+
+	for (;;) {
+		prepare_to_wait(&n.wq, &wait, TASK_UNINTERRUPTIBLE);
+		if (hlist_unhashed(&n.link))
+			break;
+		local_irq_enable();
+		schedule();
+		local_irq_disable();
+	}
+	finish_wait(&n.wq, &wait);
+
+	return;
+}
+EXPORT_SYMBOL_GPL(kvm_async_pf_task_wait);
+
+static void apf_task_wake_one(struct kvm_task_sleep_node *n)
+{
+	hlist_del_init(&n->link);
+	if (waitqueue_active(&n->wq))
+		wake_up(&n->wq);
+}
+
+static void apf_task_wake_all(void)
+{
+	int i;
+
+	for (i = 0; i < KVM_TASK_SLEEP_HASHSIZE; i++) {
+		struct hlist_node *p, *next;
+		struct kvm_task_sleep_head *b = &async_pf_sleepers[i];
+		spin_lock(&b->lock);
+		hlist_for_each_safe(p, next, &b->list) {
+			struct kvm_task_sleep_node *n =
+				hlist_entry(p, typeof(*n), link);
+			if (n->cpu == smp_processor_id())
+				apf_task_wake_one(n);
+		}
+		spin_unlock(&b->lock);
+	}
+}
+
+void kvm_async_pf_task_wake(u32 token)
+{
+	u32 key = hash_32(token, KVM_TASK_SLEEP_HASHBITS);
+	struct kvm_task_sleep_head *b = &async_pf_sleepers[key];
+	struct kvm_task_sleep_node *n;
+
+	if (token == ~0) {
+		apf_task_wake_all();
+		return;
+	}
+
+again:
+	spin_lock(&b->lock);
+	n = _find_apf_task(b, token);
+	if (!n) {
+		/*
+		 * async PF was not yet handled.
+		 * Add dummy entry for the token.
+		 */
+		n = kmalloc(sizeof(*n), GFP_ATOMIC);
+		if (!n) {
+			/*
+			 * Allocation failed! Busy wait while other cpu
+			 * handles async PF.
+			 */
+			spin_unlock(&b->lock);
+			cpu_relax();
+			goto again;
+		}
+		n->token = token;
+		n->cpu = smp_processor_id();
+		init_waitqueue_head(&n->wq);
+		hlist_add_head(&n->link, &b->list);
+	} else
+		apf_task_wake_one(n);
+	spin_unlock(&b->lock);
+	return;
+}
+EXPORT_SYMBOL_GPL(kvm_async_pf_task_wake);
+
+u32 kvm_read_and_reset_pf_reason(void)
+{
+	u32 reason = 0;
+
+	if (__get_cpu_var(apf_reason).enabled) {
+		reason = __get_cpu_var(apf_reason).reason;
+		__get_cpu_var(apf_reason).reason = 0;
+	}
+
+	return reason;
+}
+EXPORT_SYMBOL_GPL(kvm_read_and_reset_pf_reason);
+
+dotraplinkage void __kprobes
+do_async_page_fault(struct pt_regs *regs, unsigned long error_code)
+{
+	switch (kvm_read_and_reset_pf_reason()) {
+	default:
+		do_page_fault(regs, error_code);
+		break;
+	case KVM_PV_REASON_PAGE_NOT_PRESENT:
+		/* page is swapped out by the host. */
+		kvm_async_pf_task_wait((u32)read_cr2());
+		break;
+	case KVM_PV_REASON_PAGE_READY:
+		kvm_async_pf_task_wake((u32)read_cr2());
+		break;
+	}
+}
+
 static void kvm_mmu_op(void *buffer, unsigned len)
 {
 	int r;
@@ -300,6 +468,7 @@ static void kvm_guest_cpu_online(void *dummy)
 static void kvm_guest_cpu_offline(void *dummy)
 {
 	kvm_pv_disable_apf(NULL);
+	apf_task_wake_all();
 }
 
 static int __cpuinit kvm_cpu_notify(struct notifier_block *self,
@@ -327,13 +496,25 @@ static struct notifier_block __cpuinitdata kvm_cpu_notifier = {
 };
 #endif
 
+static void __init kvm_apf_trap_init(void)
+{
+	set_intr_gate(14, &async_page_fault);
+}
+
 void __init kvm_guest_init(void)
 {
+	int i;
+
 	if (!kvm_para_available())
 		return;
 
 	paravirt_ops_setup();
 	register_reboot_notifier(&kvm_pv_reboot_nb);
+	for (i = 0; i < KVM_TASK_SLEEP_HASHSIZE; i++)
+		spin_lock_init(&async_pf_sleepers[i].lock);
+	if (kvm_para_has_feature(KVM_FEATURE_ASYNC_PF))
+		x86_init.irqs.trap_init = kvm_apf_trap_init;
+
 #ifdef CONFIG_SMP
 	smp_ops.smp_prepare_boot_cpu = kvm_smp_prepare_boot_cpu;
 	register_cpu_notifier(&kvm_cpu_notifier);
diff --git a/arch/x86/kvm/svm.c b/arch/x86/kvm/svm.c
index b81a9b7c2ca4..93e8120b8021 100644
--- a/arch/x86/kvm/svm.c
+++ b/arch/x86/kvm/svm.c
@@ -31,6 +31,7 @@
 
 #include <asm/tlbflush.h>
 #include <asm/desc.h>
+#include <asm/kvm_para.h>
 
 #include <asm/virtext.h>
 #include "trace.h"
@@ -133,6 +134,7 @@ struct vcpu_svm {
 
 	unsigned int3_injected;
 	unsigned long int3_rip;
+	u32 apf_reason;
 };
 
 #define MSR_INVALID			0xffffffffU
@@ -1383,16 +1385,33 @@ static void svm_set_dr7(struct kvm_vcpu *vcpu, unsigned long value)
 
 static int pf_interception(struct vcpu_svm *svm)
 {
-	u64 fault_address;
+	u64 fault_address = svm->vmcb->control.exit_info_2;
 	u32 error_code;
+	int r = 1;
 
-	fault_address  = svm->vmcb->control.exit_info_2;
-	error_code = svm->vmcb->control.exit_info_1;
+	switch (svm->apf_reason) {
+	default:
+		error_code = svm->vmcb->control.exit_info_1;
 
-	trace_kvm_page_fault(fault_address, error_code);
-	if (!npt_enabled && kvm_event_needs_reinjection(&svm->vcpu))
-		kvm_mmu_unprotect_page_virt(&svm->vcpu, fault_address);
-	return kvm_mmu_page_fault(&svm->vcpu, fault_address, error_code);
+		trace_kvm_page_fault(fault_address, error_code);
+		if (!npt_enabled && kvm_event_needs_reinjection(&svm->vcpu))
+			kvm_mmu_unprotect_page_virt(&svm->vcpu, fault_address);
+		r = kvm_mmu_page_fault(&svm->vcpu, fault_address, error_code);
+		break;
+	case KVM_PV_REASON_PAGE_NOT_PRESENT:
+		svm->apf_reason = 0;
+		local_irq_disable();
+		kvm_async_pf_task_wait(fault_address);
+		local_irq_enable();
+		break;
+	case KVM_PV_REASON_PAGE_READY:
+		svm->apf_reason = 0;
+		local_irq_disable();
+		kvm_async_pf_task_wake(fault_address);
+		local_irq_enable();
+		break;
+	}
+	return r;
 }
 
 static int db_interception(struct vcpu_svm *svm)
@@ -1836,8 +1855,8 @@ static int nested_svm_exit_special(struct vcpu_svm *svm)
 			return NESTED_EXIT_HOST;
 		break;
 	case SVM_EXIT_EXCP_BASE + PF_VECTOR:
-		/* When we're shadowing, trap PFs */
-		if (!npt_enabled)
+		/* When we're shadowing, trap PFs, but not async PF */
+		if (!npt_enabled && svm->apf_reason == 0)
 			return NESTED_EXIT_HOST;
 		break;
 	case SVM_EXIT_EXCP_BASE + NM_VECTOR:
@@ -1893,6 +1912,10 @@ static int nested_svm_intercept(struct vcpu_svm *svm)
 		u32 excp_bits = 1 << (exit_code - SVM_EXIT_EXCP_BASE);
 		if (svm->nested.intercept_exceptions & excp_bits)
 			vmexit = NESTED_EXIT_DONE;
+		/* async page fault always cause vmexit */
+		else if ((exit_code == SVM_EXIT_EXCP_BASE + PF_VECTOR) &&
+			 svm->apf_reason != 0)
+			vmexit = NESTED_EXIT_DONE;
 		break;
 	}
 	case SVM_EXIT_ERR: {
@@ -3414,6 +3437,10 @@ static void svm_vcpu_run(struct kvm_vcpu *vcpu)
 
 	svm->next_rip = 0;
 
+	/* if exit due to PF check for async PF */
+	if (svm->vmcb->control.exit_code == SVM_EXIT_EXCP_BASE + PF_VECTOR)
+		svm->apf_reason = kvm_read_and_reset_pf_reason();
+
 	if (npt_enabled) {
 		vcpu->arch.regs_avail &= ~(1 << VCPU_EXREG_PDPTR);
 		vcpu->arch.regs_dirty &= ~(1 << VCPU_EXREG_PDPTR);
-- 
2.41.0

