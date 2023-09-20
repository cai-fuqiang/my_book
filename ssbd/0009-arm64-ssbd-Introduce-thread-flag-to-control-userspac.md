```diff
From 9dd9614f5476687abbff8d4b12cd08ae70d7c2ad Mon Sep 17 00:00:00 2001
From: Marc Zyngier <marc.zyngier@arm.com>
Date: Tue, 29 May 2018 13:11:13 +0100
Subject: [PATCH 09/14] arm64: ssbd: Introduce thread flag to control userspace
 mitigation

In order to allow userspace to be mitigated on demand, let's
introduce a new thread flag that prevents the mitigation from
being turned off when exiting to userspace, and doesn't turn
it on on entry into the kernel (with the assumption that the
mitigation is always enabled in the kernel itself).

为了满足用户态  mitigated的需要，引入了一个新的 thread flags
来阻止 在退回到用户态时 turn off mitigation, 或者 在进入kernel
时 不turn on .

This will be used by a prctl interface introduced in a later
patch.

使用 prctl()接口, 在下一个patch引入

Reviewed-by: Mark Rutland <mark.rutland@arm.com>
Acked-by: Will Deacon <will.deacon@arm.com>
Signed-off-by: Marc Zyngier <marc.zyngier@arm.com>
Signed-off-by: Catalin Marinas <catalin.marinas@arm.com>
---
 arch/arm64/include/asm/thread_info.h | 1 +
 arch/arm64/kernel/entry.S            | 2 ++
 2 files changed, 3 insertions(+)

diff --git a/arch/arm64/include/asm/thread_info.h b/arch/arm64/include/asm/thread_info.h
index 740aa03c5f0d..cbcf11b5e637 100644
--- a/arch/arm64/include/asm/thread_info.h
+++ b/arch/arm64/include/asm/thread_info.h
@@ -94,6 +94,7 @@ void arch_release_task_struct(struct task_struct *tsk);
 #define TIF_32BIT		22	/* 32bit process */
 #define TIF_SVE			23	/* Scalable Vector Extension in use */
 #define TIF_SVE_VL_INHERIT	24	/* Inherit sve_vl_onexec across exec */
+#define TIF_SSBD		25	/* Wants SSB mitigation */
 
 #define _TIF_SIGPENDING		(1 << TIF_SIGPENDING)
 #define _TIF_NEED_RESCHED	(1 << TIF_NEED_RESCHED)
diff --git a/arch/arm64/kernel/entry.S b/arch/arm64/kernel/entry.S
index e6f6e2339b22..28ad8799406f 100644
--- a/arch/arm64/kernel/entry.S
+++ b/arch/arm64/kernel/entry.S
@@ -147,6 +147,8 @@ alternative_cb	arm64_enable_wa2_handling
 alternative_cb_end
 	ldr_this_cpu	\tmp2, arm64_ssbd_callback_required, \tmp1
 	cbz	\tmp2, \targ
    //判断task flags 是否有 TIF_SSBD flags, 如果设置了则跳转出去
    //这里如果设置了说明用户态要ssbd, kernel也是 ssbd的状态，所以
    //不需要更改状态，那么直接跳走
+	ldr	\tmp2, [tsk, #TSK_TI_FLAGS]
+	tbnz	\tmp2, #TIF_SSBD, \targ
 	mov	w0, #ARM_SMCCC_ARCH_WORKAROUND_2
 	mov	w1, #\state
 alternative_cb	arm64_update_smccc_conduit
-- 
2.39.0
```
