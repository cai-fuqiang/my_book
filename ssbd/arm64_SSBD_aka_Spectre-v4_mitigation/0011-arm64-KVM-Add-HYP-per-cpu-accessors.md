```diff
From 85478bab409171de501b719971fd25a3d5d639f9 Mon Sep 17 00:00:00 2001
From: Marc Zyngier <marc.zyngier@arm.com>
Date: Tue, 29 May 2018 13:11:15 +0100
Subject: [PATCH 11/14] arm64: KVM: Add HYP per-cpu accessors

As we're going to require to access per-cpu variables at EL2,
let's craft the minimum set of accessors required to implement
reading a per-cpu variable, relying on tpidr_el2 to contain the
per-cpu offset.

Reviewed-by: Christoffer Dall <christoffer.dall@arm.com>
Reviewed-by: Mark Rutland <mark.rutland@arm.com>
Signed-off-by: Marc Zyngier <marc.zyngier@arm.com>
Signed-off-by: Catalin Marinas <catalin.marinas@arm.com>
---
 arch/arm64/include/asm/kvm_asm.h | 27 +++++++++++++++++++++++++--
 1 file changed, 25 insertions(+), 2 deletions(-)

diff --git a/arch/arm64/include/asm/kvm_asm.h b/arch/arm64/include/asm/kvm_asm.h
index f6648a3e4152..fefd8cf42c35 100644
--- a/arch/arm64/include/asm/kvm_asm.h
+++ b/arch/arm64/include/asm/kvm_asm.h
@@ -71,14 +71,37 @@ extern u32 __kvm_get_mdcr_el2(void);
 
 extern u32 __init_stage2_translation(void);
 
+/* Home-grown __this_cpu_{ptr,read} variants that always work at HYP */
+#define __hyp_this_cpu_ptr(sym)						\
+	({								\
+		void *__ptr = hyp_symbol_addr(sym);			\
+		__ptr += read_sysreg(tpidr_el2);			\
+		(typeof(&sym))__ptr;					\
+	 })
+
+#define __hyp_this_cpu_read(sym)					\
+	({								\
+		*__hyp_this_cpu_ptr(sym);				\
+	 })
+
 #else /* __ASSEMBLY__ */
 
-.macro get_host_ctxt reg, tmp
-	adr_l	\reg, kvm_host_cpu_state

+.macro hyp_adr_this_cpu reg, sym, tmp
+	adr_l	\reg, \sym
 	mrs	\tmp, tpidr_el2
 	add	\reg, \reg, \tmp
 .endm
 
+.macro hyp_ldr_this_cpu reg, sym, tmp
+	adr_l	\reg, \sym
+	mrs	\tmp, tpidr_el2
+	ldr	\reg,  [\reg, \tmp]
+.endm
+
+.macro get_host_ctxt reg, tmp
+	hyp_adr_this_cpu \reg, kvm_host_cpu_state, \tmp
+.endm
+
//============(1)=============
 .macro get_vcpu_ptr vcpu, ctxt
 	get_host_ctxt \ctxt, \vcpu
 	ldr	\vcpu, [\ctxt, #HOST_CONTEXT_VCPU]
-- 
2.39.0
```

1. 该宏为了获取 per cpu (kvm_host_cpu_state)->__hyp_running_vcpu (kvm_vcpu)
其中 tpdir_el2 表示 

```
this per cpu addr(&kvm_host_cpu_state) - &kvm_host_cpu_state
```
我们以4.18代码为例:
```cpp
static inline void __cpu_init_hyp_mode(phys_addr_t pgd_ptr,
                                       unsigned long hyp_stack_ptr,
                                       unsigned long vector_ptr)
{
    ...
    u64 tpidr_el2 = ((u64)this_cpu_ptr(&kvm_host_cpu_state) -
                     (u64)kvm_ksym_ref(kvm_host_cpu_state));
    ...
}
```

所以这里要获取到 el2 中读取 per cpu addr (kvm_host_cpu_state) ：
```
this_per_cpu - &kvm_host_cpu_state = tpidr_el2

this_per_cpu = tpdir_el2 + &kvm_host_cpu_state 
```
> NOTE
>
> kvm_ksym_ref 是后来引入的，表示 el2 和 el1 地址之间的偏移
>
> 在这个patch中，el1 address = el2 address
