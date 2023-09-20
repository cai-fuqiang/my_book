```diff
From ca7f686ac9fe87a9175696a8744e095ab9749c49 Mon Sep 17 00:00:00 2001
From: Will Deacon <will.deacon@arm.com>
Date: Fri, 15 Jun 2018 11:36:43 +0100
Subject: [PATCH 1/7] arm64: Fix silly typo in comment

I was passing through and figuered I'd fix this up:

	featuer -> feature

Signed-off-by: Will Deacon <will.deacon@arm.com>
Signed-off-by: Catalin Marinas <catalin.marinas@arm.com>
---
 arch/arm64/include/asm/cpufeature.h | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

diff --git a/arch/arm64/include/asm/cpufeature.h b/arch/arm64/include/asm/cpufeature.h
index 1717ba1db35d..9079715794af 100644
--- a/arch/arm64/include/asm/cpufeature.h
+++ b/arch/arm64/include/asm/cpufeature.h
@@ -262,7 +262,7 @@ extern struct arm64_ftr_reg arm64_ftr_reg_ctrel0;
 /*
  * CPU feature detected at boot time based on system-wide value of a
  * feature. It is safe for a late CPU to have this feature even though
- * the system hasn't enabled it, although the featuer will not be used
+ * the system hasn't enabled it, although the feature will not be used
  * by Linux in this case. If the system has enabled this feature already,
  * then every late CPU must have it.
  */
-- 
2.39.0
```
单词错误
