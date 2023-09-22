```diff
From fc5f06fac6fb8ce469ea173370f2cd398f1d9f9a Mon Sep 17 00:00:00 2001
From: Gleb Natapov <gleb@redhat.com>
Date: Thu, 14 Oct 2010 11:22:56 +0200
Subject: [PATCH 11/11] KVM: Send async PF when guest is not in userspace too.

If guest indicates that it can handle async pf in kernel mode too send
it, but only if interrupts are enabled.

Acked-by: Rik van Riel <riel@redhat.com>
Signed-off-by: Gleb Natapov <gleb@redhat.com>
Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
---
 arch/x86/kvm/x86.c | 3 ++-
 1 file changed, 2 insertions(+), 1 deletion(-)

diff --git a/arch/x86/kvm/x86.c b/arch/x86/kvm/x86.c
index fff70b50725c..c0bd2a2b3c0f 100644
--- a/arch/x86/kvm/x86.c
+++ b/arch/x86/kvm/x86.c
@@ -6263,7 +6263,8 @@ void kvm_arch_async_page_not_present(struct kvm_vcpu *vcpu,
 	kvm_add_async_pf_gfn(vcpu, work->arch.gfn);
 
 	if (!(vcpu->arch.apf.msr_val & KVM_ASYNC_PF_ENABLED) ||
-	    kvm_x86_ops->get_cpl(vcpu) == 0)
+	    (vcpu->arch.apf.send_user_only &&
+	     kvm_x86_ops->get_cpl(vcpu) == 0))
 		kvm_make_request(KVM_REQ_APF_HALT, vcpu);
 	else if (!apf_put_user(vcpu, KVM_PV_REASON_PAGE_NOT_PRESENT)) {
 		vcpu->arch.fault.error_code = 0;
-- 
2.41.0
```
