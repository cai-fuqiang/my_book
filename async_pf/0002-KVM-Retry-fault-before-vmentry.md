From 56028d0861e48f7cc9c573d79f2d8a0a933a2bba Mon Sep 17 00:00:00 2001
From: Gleb Natapov <gleb@redhat.com>
Date: Sun, 17 Oct 2010 18:13:42 +0200
Subject: [PATCH 02/11] KVM: Retry fault before vmentry

When page is swapped in it is mapped into guest memory only after guest
tries to access it again and generate another fault. To save this fault
we can map it immediately since we know that guest is going to access
the page. Do it only when tdp is enabled for now. Shadow paging case is
more complicated. CR[034] and EFER registers should be switched before
doing mapping and then switched back.

Acked-by: Rik van Riel <riel@redhat.com>
Signed-off-by: Gleb Natapov <gleb@redhat.com>
Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
---
 arch/x86/include/asm/kvm_host.h |  4 +++-
 arch/x86/kvm/mmu.c              | 16 ++++++++--------
 arch/x86/kvm/paging_tmpl.h      |  6 +++---
 arch/x86/kvm/x86.c              | 14 ++++++++++++++
 virt/kvm/async_pf.c             |  2 ++
 5 files changed, 30 insertions(+), 12 deletions(-)

diff --git a/arch/x86/include/asm/kvm_host.h b/arch/x86/include/asm/kvm_host.h
index b5f4c1a36d65..c3076bcf5ef7 100644
--- a/arch/x86/include/asm/kvm_host.h
+++ b/arch/x86/include/asm/kvm_host.h
@@ -241,7 +241,7 @@ struct kvm_mmu {
 	void (*new_cr3)(struct kvm_vcpu *vcpu);
 	void (*set_cr3)(struct kvm_vcpu *vcpu, unsigned long root);
 	unsigned long (*get_cr3)(struct kvm_vcpu *vcpu);
-	int (*page_fault)(struct kvm_vcpu *vcpu, gva_t gva, u32 err);
+	int (*page_fault)(struct kvm_vcpu *vcpu, gva_t gva, u32 err, bool no_apf);
 	void (*inject_page_fault)(struct kvm_vcpu *vcpu);
 	void (*free)(struct kvm_vcpu *vcpu);
 	gpa_t (*gva_to_gpa)(struct kvm_vcpu *vcpu, gva_t gva, u32 access,
@@ -815,6 +815,8 @@ void kvm_arch_async_page_not_present(struct kvm_vcpu *vcpu,
 				     struct kvm_async_pf *work);
 void kvm_arch_async_page_present(struct kvm_vcpu *vcpu,
 				 struct kvm_async_pf *work);
+void kvm_arch_async_page_ready(struct kvm_vcpu *vcpu,
+			       struct kvm_async_pf *work);
 extern bool kvm_find_async_pf_gfn(struct kvm_vcpu *vcpu, gfn_t gfn);
 
 #endif /* _ASM_X86_KVM_HOST_H */
diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index 4ab04de5a76a..b2c60986a7ce 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -2570,7 +2570,7 @@ static gpa_t nonpaging_gva_to_gpa_nested(struct kvm_vcpu *vcpu, gva_t vaddr,
 }
 
 static int nonpaging_page_fault(struct kvm_vcpu *vcpu, gva_t gva,
-				u32 error_code)
+				u32 error_code, bool no_apf)
 {
 	gfn_t gfn;
 	int r;
@@ -2606,8 +2606,8 @@ static bool can_do_async_pf(struct kvm_vcpu *vcpu)
 	return kvm_x86_ops->interrupt_allowed(vcpu);
 }
 
-static bool try_async_pf(struct kvm_vcpu *vcpu, gfn_t gfn, gva_t gva,
-			 pfn_t *pfn)
+static bool try_async_pf(struct kvm_vcpu *vcpu, bool no_apf, gfn_t gfn,
+			 gva_t gva, pfn_t *pfn)
 {
 	bool async;
 
@@ -2618,7 +2618,7 @@ static bool try_async_pf(struct kvm_vcpu *vcpu, gfn_t gfn, gva_t gva,
 
 	put_page(pfn_to_page(*pfn));
 
-	if (can_do_async_pf(vcpu)) {
+	if (!no_apf && can_do_async_pf(vcpu)) {
 		trace_kvm_try_async_get_page(async, *pfn);
 		if (kvm_find_async_pf_gfn(vcpu, gfn)) {
 			trace_kvm_async_pf_doublefault(gva, gfn);
@@ -2633,8 +2633,8 @@ static bool try_async_pf(struct kvm_vcpu *vcpu, gfn_t gfn, gva_t gva,
 	return false;
 }
 
-static int tdp_page_fault(struct kvm_vcpu *vcpu, gva_t gpa,
-				u32 error_code)
+static int tdp_page_fault(struct kvm_vcpu *vcpu, gva_t gpa, u32 error_code,
+			  bool no_apf)
 {
 	pfn_t pfn;
 	int r;
@@ -2656,7 +2656,7 @@ static int tdp_page_fault(struct kvm_vcpu *vcpu, gva_t gpa,
 	mmu_seq = vcpu->kvm->mmu_notifier_seq;
 	smp_rmb();
 
-	if (try_async_pf(vcpu, gfn, gpa, &pfn))
+	if (try_async_pf(vcpu, no_apf, gfn, gpa, &pfn))
 		return 0;
 
 	/* mmio */
@@ -3319,7 +3319,7 @@ int kvm_mmu_page_fault(struct kvm_vcpu *vcpu, gva_t cr2, u32 error_code)
 	int r;
 	enum emulation_result er;
 
-	r = vcpu->arch.mmu.page_fault(vcpu, cr2, error_code);
+	r = vcpu->arch.mmu.page_fault(vcpu, cr2, error_code, false);
 	if (r < 0)
 		goto out;
 
diff --git a/arch/x86/kvm/paging_tmpl.h b/arch/x86/kvm/paging_tmpl.h
index c45376dd041a..d6b281e989b1 100644
--- a/arch/x86/kvm/paging_tmpl.h
+++ b/arch/x86/kvm/paging_tmpl.h
@@ -527,8 +527,8 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
  *  Returns: 1 if we need to emulate the instruction, 0 otherwise, or
  *           a negative value on error.
  */
-static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr,
-			       u32 error_code)
+static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr, u32 error_code,
+			     bool no_apf)
 {
 	int write_fault = error_code & PFERR_WRITE_MASK;
 	int user_fault = error_code & PFERR_USER_MASK;
@@ -569,7 +569,7 @@ static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr,
 	mmu_seq = vcpu->kvm->mmu_notifier_seq;
 	smp_rmb();
 
-	if (try_async_pf(vcpu, walker.gfn, addr, &pfn))
+	if (try_async_pf(vcpu, no_apf, walker.gfn, addr, &pfn))
 		return 0;
 
 	/* mmio */
diff --git a/arch/x86/kvm/x86.c b/arch/x86/kvm/x86.c
index 3cd4d091c2f3..71beb27597fd 100644
--- a/arch/x86/kvm/x86.c
+++ b/arch/x86/kvm/x86.c
@@ -6138,6 +6138,20 @@ void kvm_set_rflags(struct kvm_vcpu *vcpu, unsigned long rflags)
 }
 EXPORT_SYMBOL_GPL(kvm_set_rflags);
 
+void kvm_arch_async_page_ready(struct kvm_vcpu *vcpu, struct kvm_async_pf *work)
+{
+	int r;
+
+	if (!vcpu->arch.mmu.direct_map || is_error_page(work->page))
+		return;
+
+	r = kvm_mmu_reload(vcpu);
+	if (unlikely(r))
+		return;
+
+	vcpu->arch.mmu.page_fault(vcpu, work->gva, 0, true);
+}
+
 static inline u32 kvm_async_pf_hash_fn(gfn_t gfn)
 {
 	return hash_32(gfn & 0xffffffff, order_base_2(ASYNC_PF_PER_VCPU));
diff --git a/virt/kvm/async_pf.c b/virt/kvm/async_pf.c
index 857d63431cb7..e97eae965a4c 100644
--- a/virt/kvm/async_pf.c
+++ b/virt/kvm/async_pf.c
@@ -132,6 +132,8 @@ void kvm_check_async_pf_completion(struct kvm_vcpu *vcpu)
 	list_del(&work->link);
 	spin_unlock(&vcpu->async_pf.lock);
 
+	if (work->page)
+		kvm_arch_async_page_ready(vcpu, work);
 	kvm_arch_async_page_present(vcpu, work);
 
 	list_del(&work->queue);
-- 
2.41.0

