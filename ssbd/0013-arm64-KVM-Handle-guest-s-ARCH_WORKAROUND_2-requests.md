```diff
From b4f18c063a13dfb33e3a63fe1844823e19c2265e Mon Sep 17 00:00:00 2001
From: Marc Zyngier <marc.zyngier@arm.com>
Date: Tue, 29 May 2018 13:11:17 +0100
Subject: [PATCH 13/14] arm64: KVM: Handle guest's ARCH_WORKAROUND_2 requests

In order to forward the guest's ARCH_WORKAROUND_2 calls to EL3,
add a small(-ish) sequence to handle it at EL2. Special care must
be taken to track the state of the guest itself by updating the
workaround flags. We also rely on patching to enable calls into
the firmware.

为了将 guest's ARCH_WORKAROUND_2 调用 转发到 EL3, 在 EL2中增加了
一个 small(-ish) sequence 来处理他。 必须特别注意通过update workaround flags 
来跟踪来宾本身的状态。我们还依靠patching 启用对固件的调用。 

Note that since we need to execute branches, this always executes
after the Spectre-v2 mitigation has been applied.

Reviewed-by: Mark Rutland <mark.rutland@arm.com>
Signed-off-by: Marc Zyngier <marc.zyngier@arm.com>
Signed-off-by: Catalin Marinas <catalin.marinas@arm.com>
---
 arch/arm64/kernel/asm-offsets.c |  1 +
 arch/arm64/kvm/hyp/hyp-entry.S  | 38 ++++++++++++++++++++++++++++++++-
 2 files changed, 38 insertions(+), 1 deletion(-)

diff --git a/arch/arm64/kernel/asm-offsets.c b/arch/arm64/kernel/asm-offsets.c
index 5bdda651bd05..323aeb5f2fe6 100644
--- a/arch/arm64/kernel/asm-offsets.c
+++ b/arch/arm64/kernel/asm-offsets.c
@@ -136,6 +136,7 @@ int main(void)
 #ifdef CONFIG_KVM_ARM_HOST
   DEFINE(VCPU_CONTEXT,		offsetof(struct kvm_vcpu, arch.ctxt));
   DEFINE(VCPU_FAULT_DISR,	offsetof(struct kvm_vcpu, arch.fault.disr_el1));
+  DEFINE(VCPU_WORKAROUND_FLAGS,	offsetof(struct kvm_vcpu, arch.workaround_flags));
   DEFINE(CPU_GP_REGS,		offsetof(struct kvm_cpu_context, gp_regs));
   DEFINE(CPU_USER_PT_REGS,	offsetof(struct kvm_regs, regs));
   DEFINE(CPU_FP_REGS,		offsetof(struct kvm_regs, fp_regs));
diff --git a/arch/arm64/kvm/hyp/hyp-entry.S b/arch/arm64/kvm/hyp/hyp-entry.S
index bffece27b5c1..05d836979032 100644
--- a/arch/arm64/kvm/hyp/hyp-entry.S
+++ b/arch/arm64/kvm/hyp/hyp-entry.S
@@ -106,8 +106,44 @@ el1_hvc_guest:
 	 */
 	ldr	x1, [sp]				// Guest's x0
	//==============(1)==============
 	eor	w1, w1, #ARM_SMCCC_ARCH_WORKAROUND_1
+	cbz	w1, wa_epilogue
+
+	/* ARM_SMCCC_ARCH_WORKAROUND_2 handling */
	//==============(1)==============
+	eor	w1, w1, #(ARM_SMCCC_ARCH_WORKAROUND_1 ^ \
+			  ARM_SMCCC_ARCH_WORKAROUND_2)
 	cbnz	w1, el1_trap
-	mov	x0, x1
+
+#ifdef CONFIG_ARM64_SSBD
+alternative_cb	arm64_enable_wa2_handling
+	b	wa2_end
+alternative_cb_end
//=================(2)================
+	get_vcpu_ptr	x2, x0
+	ldr	x0, [x2, #VCPU_WORKAROUND_FLAGS]
+
//=================(3)================
+	// Sanitize the argument and update the guest flags
+	ldr	x1, [sp, #8]			// Guest's x1
+	clz	w1, w1				// Murphy's device:
+	lsr	w1, w1, #5			// w1 = !!w1 without using
+	eor	w1, w1, #1			// the flags...
+	bfi	x0, x1, #VCPU_WORKAROUND_2_FLAG_SHIFT, #1
+	str	x0, [x2, #VCPU_WORKAROUND_FLAGS]
+
+	/* Check that we actually need to perform the call */
+	hyp_ldr_this_cpu x0, arm64_ssbd_callback_required, x2
+	cbz	x0, wa2_end
+
//=================(4)================
+	mov	w0, #ARM_SMCCC_ARCH_WORKAROUND_2
+	smc	#0
+
+	/* Don't leak data from the SMC call */
//=================(5)================
+	mov	x3, xzr
+wa2_end:
+	mov	x2, xzr
+	mov	x1, xzr
+#endif
+
+wa_epilogue:
+	mov	x0, xzr
 	add	sp, sp, #16
 	eret
 
-- 
2.39.0
```

1. 异或指令:<br/>
异或指令比较好的地方是，支持类似于回溯的功能, 例如:
```
A ^ B = C       C ^ B = A
也就是
A ^ B ^ B = A ^ (B ^ B) = A ^ 0 = A
```
这里如果执行下面两条指令
```
eor	w1, w1, #ARM_SMCCC_ARCH_WORKAROUND_1
eor	w1, w1, #(ARM_SMCCC_ARCH_WORKAROUND_1 ^ \
		  ARM_SMCCC_ARCH_WORKAROUND_2)
```
实际上最终w1 的值为:
```
(w1 ^ ARM_SMCCC_ARCH_WORKAROUND_1) ^ (ARM_SMCCC_ARCH_WORKAROUND_1  ^ ARM_SMCCC_ARCH_WORKAROUND_2)
= w1 ^ (ARM_SMCCC_ARCH_WORKAROUND_1 ^ ARM_SMCCC_ARCH_WORKAROUND_1) ^  ARM_SMCCC_ARCH_WORKAROUND_2
= w1 ^ 0 ^ ARM_SMCCC_ARCH_WORKAROUND_2
= w1 ^  ARM_SMCCC_ARCH_WORKAROUND_2
```
如果 异或的结果为0 说明 `w1 = ARM_SMCCC_ARCH_WORKAROUND_2`

2. 获取 当前的 `kvm_vcpu_arch` 
3. 说一下各个指令的作用
   + clz : 获取第一个非0位的index (从左向右数)
   + lsr : logical shift 逻辑右移
   + eor : 异或
   + bfi Xn, Xm, imm1, imm2 : 将 xm [imm2 + imm1 - 1, imm1] 赋值给 Xn
 
那么我们分情况来看:
* 如果 w0 > 0
   + clz = [0, 31]
   + lsr = 0
   + eor = 1
   + bfi = 1
* 如果 w0 = 0
   + clz = 32
   + lsr = 1
   + eor = 0
   + bfi = 0

这样做的好处可能是不会有逻辑判断和分支，效率更高一些.
5. 调用SMCCC 
4. 之前提到 SMCCC 不保护[x0, x3]寄存器，这里是为了安全，不泄漏
信息给用户态。
