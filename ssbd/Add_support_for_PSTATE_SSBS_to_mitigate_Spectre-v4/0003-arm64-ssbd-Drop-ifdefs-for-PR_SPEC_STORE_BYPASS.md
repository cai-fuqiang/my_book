```diff
From 2d1b2a91d56b19636b740ea70c8399d1df249f20 Mon Sep 17 00:00:00 2001
From: Will Deacon <will.deacon@arm.com>
Date: Fri, 15 Jun 2018 11:50:42 +0100
Subject: [PATCH 3/7] arm64: ssbd: Drop #ifdefs for PR_SPEC_STORE_BYPASS

Now that we're all merged nicely into mainline, there's no need to check
to see if PR_SPEC_STORE_BYPASS is defined.

Signed-off-by: Will Deacon <will.deacon@arm.com>
Signed-off-by: Catalin Marinas <catalin.marinas@arm.com>
---
 arch/arm64/kernel/ssbd.c | 3 ---
 1 file changed, 3 deletions(-)

diff --git a/arch/arm64/kernel/ssbd.c b/arch/arm64/kernel/ssbd.c
index 3432e5ef9f41..07b12c034ec2 100644
--- a/arch/arm64/kernel/ssbd.c
+++ b/arch/arm64/kernel/ssbd.c
@@ -11,9 +11,7 @@
 
 /*
  * prctl interface for SSBD
- * FIXME: Drop the below ifdefery once merged in 4.18.
  */
-#ifdef PR_SPEC_STORE_BYPASS
 static int ssbd_prctl_set(struct task_struct *task, unsigned long ctrl)
 {
 	int state = arm64_get_ssbd_state();
@@ -107,4 +105,3 @@ int arch_prctl_spec_ctrl_get(struct task_struct *task, unsigned long which)
 		return -ENODEV;
 	}
 }
-#endif	/* PR_SPEC_STORE_BYPASS */
-- 
2.39.0
```

这个没太看懂
