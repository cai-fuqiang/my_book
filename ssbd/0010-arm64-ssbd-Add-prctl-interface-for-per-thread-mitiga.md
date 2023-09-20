```diff
From 9cdc0108baa8ef87c76ed834619886a46bd70cbe Mon Sep 17 00:00:00 2001
From: Marc Zyngier <marc.zyngier@arm.com>
Date: Tue, 29 May 2018 13:11:14 +0100
Subject: [PATCH 10/14] arm64: ssbd: Add prctl interface for per-thread
 mitigation

If running on a system that performs dynamic SSBD mitigation, allow
userspace to request the mitigation for itself. This is implemented
as a prctl call, allowing the mitigation to be enabled or disabled at
will for this particular thread.

允许 在其特定的线程上 enable disable mitgation

Acked-by: Will Deacon <will.deacon@arm.com>
Signed-off-by: Marc Zyngier <marc.zyngier@arm.com>
Signed-off-by: Catalin Marinas <catalin.marinas@arm.com>
---
 arch/arm64/kernel/Makefile |   1 +
 arch/arm64/kernel/ssbd.c   | 110 +++++++++++++++++++++++++++++++++++++
 2 files changed, 111 insertions(+)
 create mode 100644 arch/arm64/kernel/ssbd.c

diff --git a/arch/arm64/kernel/Makefile b/arch/arm64/kernel/Makefile
index bf825f38d206..0025f8691046 100644
--- a/arch/arm64/kernel/Makefile
+++ b/arch/arm64/kernel/Makefile
@@ -54,6 +54,7 @@ arm64-obj-$(CONFIG_ARM64_RELOC_TEST)	+= arm64-reloc-test.o
 arm64-reloc-test-y := reloc_test_core.o reloc_test_syms.o
 arm64-obj-$(CONFIG_CRASH_DUMP)		+= crash_dump.o
 arm64-obj-$(CONFIG_ARM_SDE_INTERFACE)	+= sdei.o
+arm64-obj-$(CONFIG_ARM64_SSBD)		+= ssbd.o
 
 obj-y					+= $(arm64-obj-y) vdso/ probes/
 obj-m					+= $(arm64-obj-m)
diff --git a/arch/arm64/kernel/ssbd.c b/arch/arm64/kernel/ssbd.c
new file mode 100644
index 000000000000..3432e5ef9f41
--- /dev/null
+++ b/arch/arm64/kernel/ssbd.c
@@ -0,0 +1,110 @@
+// SPDX-License-Identifier: GPL-2.0
+/*
+ * Copyright (C) 2018 ARM Ltd, All Rights Reserved.
+ */
+
+#include <linux/errno.h>
+#include <linux/sched.h>
+#include <linux/thread_info.h>
+
+#include <asm/cpufeature.h>
+
+/*
+ * prctl interface for SSBD
+ * FIXME: Drop the below ifdefery once merged in 4.18.
+ */
+#ifdef PR_SPEC_STORE_BYPASS
+static int ssbd_prctl_set(struct task_struct *task, unsigned long ctrl)
+{
+	int state = arm64_get_ssbd_state();
+
+	/* Unsupported */
+	if (state == ARM64_SSBD_UNKNOWN)
+		return -EINVAL;
+
    //============(1)================
+	/* Treat the unaffected/mitigated state separately */
+	if (state == ARM64_SSBD_MITIGATED) {
+		switch (ctrl) {
+		case PR_SPEC_ENABLE:
+			return -EPERM;
+		case PR_SPEC_DISABLE:
+		case PR_SPEC_FORCE_DISABLE:
+			return 0;
+		}
+	}
+
+	/*
+	 * Things are a bit backward here: the arm64 internal API
+	 * *enables the mitigation* when the userspace API *disables
+	 * speculation*. So much fun.
+	 */
+	switch (ctrl) {
    //============(2)================
+	case PR_SPEC_ENABLE:
+		/* If speculation is force disabled, enable is not allowed */
+		if (state == ARM64_SSBD_FORCE_ENABLE ||
+		    task_spec_ssb_force_disable(task))
+			return -EPERM;
+		task_clear_spec_ssb_disable(task);
+		clear_tsk_thread_flag(task, TIF_SSBD);
+		break;
    //============(3)================
+	case PR_SPEC_DISABLE:
+		if (state == ARM64_SSBD_FORCE_DISABLE)
+			return -EPERM;
+		task_set_spec_ssb_disable(task);
+		set_tsk_thread_flag(task, TIF_SSBD);
+		break;
    //============(4)================
+	case PR_SPEC_FORCE_DISABLE:
+		if (state == ARM64_SSBD_FORCE_DISABLE)
+			return -EPERM;
+		task_set_spec_ssb_disable(task);
+		task_set_spec_ssb_force_disable(task);
+		set_tsk_thread_flag(task, TIF_SSBD);
+		break;
+	default:
+		return -ERANGE;
+	}
+
+	return 0;
+}
+
+int arch_prctl_spec_ctrl_set(struct task_struct *task, unsigned long which,
+			     unsigned long ctrl)
+{
+	switch (which) {
+	case PR_SPEC_STORE_BYPASS:
+		return ssbd_prctl_set(task, ctrl);
+	default:
+		return -ENODEV;
+	}
+}
+
+static int ssbd_prctl_get(struct task_struct *task)
+{
+	switch (arm64_get_ssbd_state()) {
+	case ARM64_SSBD_UNKNOWN:
+		return -EINVAL;
+	case ARM64_SSBD_FORCE_ENABLE:
+		return PR_SPEC_DISABLE;
+	case ARM64_SSBD_KERNEL:
+		if (task_spec_ssb_force_disable(task))
+			return PR_SPEC_PRCTL | PR_SPEC_FORCE_DISABLE;
+		if (task_spec_ssb_disable(task))
+			return PR_SPEC_PRCTL | PR_SPEC_DISABLE;
+		return PR_SPEC_PRCTL | PR_SPEC_ENABLE;
+	case ARM64_SSBD_FORCE_DISABLE:
+		return PR_SPEC_ENABLE;
+	default:
+		return PR_SPEC_NOT_AFFECTED;
+	}
+}
+
+int arch_prctl_spec_ctrl_get(struct task_struct *task, unsigned long which)
+{
+	switch (which) {
+	case PR_SPEC_STORE_BYPASS:
+		return ssbd_prctl_get(task);
+	default:
+		return -ENODEV;
+	}
+}
+#endif	/* PR_SPEC_STORE_BYPASS */
-- 
2.39.0
```
1. 如果是 `ARM64_SSBD_MITIGATED`, 说明该cpu是 不受SSB影响的.所以, 
只能允许 disable 或者 force disable (ssb) 不能 enable 
2. 当 `ssbd_state`为 FORCE ENABLE 时(注意这里是 ssbd_state force enable, 也就是
ssb force disable)，或者已经 force disable ssb 了, 不能在 
ENABLE, 否则 将会 清空 `ssb_disable`, 并且清空 `TIF_SSBD`
3. 当 `ssbd_state` 为 FORCE DISABLE(ssbd force disable, ssb force enable), 
这时，不能在 disable, 否则 将设置 ssb disable, 并且 设置 TIF_SSBD
4. 同3, 不过要设置 ssb force disable

> NOTE
>
> `task_set_spec_ssb_disable()` / `....enable()` 定义:
> 以 disable 为例 :
> ```cpp
> TASK_PFA_TEST(SPEC_SSB_DISABLE, spec_ssb_disable)
> TASK_PFA_SET(SPEC_SSB_DISABLE, spec_ssb_disable)
> TASK_PFA_CLEAR(SPEC_SSB_DISABLE, spec_ssb_disable)
> #define TASK_PFA_TEST(name, func)                                       \
>         static inline bool task_##func(struct task_struct *p)           \
>         { return test_bit(PFA_##name, &p->atomic_flags); }
> 
> #define TASK_PFA_SET(name, func)                                        \
>         static inline void task_set_##func(struct task_struct *p)       \
>         { set_bit(PFA_##name, &p->atomic_flags); }
> 
> #define TASK_PFA_CLEAR(name, func)                                      \
>         static inline void task_clear_##func(struct task_struct *p)     \
>         { clear_bit(PFA_##name, &p->atomic_flags); }
> ```
> 可以看到是对 `task_struct->atomic_flags`做操作。这个操作是atmoic的，主要
> 用于 在 (1)
