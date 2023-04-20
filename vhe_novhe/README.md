# NOTE 

## create_hyp_mappings
```
create_hyp_mappings


kvm_arch_init_vm
  create_hyp_mappings

kvm_arch_vcpu_create
  create_hyp_mappings

init_hyp_mode  ---- 做了大量的映射
  --> kvm_host_cpu_state
```

## kern_hyp_va

## ttbr0_el2
```
__kvm_hyp_init (异常向量表)
  __do_hyp_init {
      __do_hyp_init:
        /* Check for a stub HVC call */
        cmp     x0, #HVC_STUB_HCALL_NR
        b.lo    __kvm_handle_stub_hvc

        phys_to_ttbr x4, x0
alternative_if ARM64_HAS_CNP
        orr     x4, x4, #TTBR_CNP_BIT
alternative_else_nop_endif
        msr     ttbr0_el2, x4

        mrs     x4, tcr_el1
        ldr     x5, =TCR_EL2_MASK
        and     x4, x4, x5
        mov     x5, #TCR_EL2_RES1
        orr     x4, x4, x5
  }
```
## hyp_pgd
```
cpu_init_hyp_mode {
   pgd_ptr = kvm_mmu_get_httbr(); {
     if (__kvm_cpu_uses_extended_idmap())
       return virt_to_phys(merged_hyp_pgd);
      else
       return virt_to_phys(hyp_pgd);
   } //END:  kvm_mmu_get_httbr
   ...
   __cpu_init_hyp_mode(pgd_ptr, hyp_stack_ptr, vector_ptr);
}//END: cpu_init_hyp_mode
```

# arm64 spec reference
## arm64 condition code 
C1.2.4 Condition code
##  TPIDR_EL2
D17.2.141 TPIDR_EL2, EL2 Software Thread ID Register

## VBAR_EL2
D17.2.150 VBAR_EL2, Vector Base Address Register (EL2)

## SCTLR_EL2
D17.2.119 SCTLR_EL2, System Control Register (EL2)


## TTBR0_EL2
D17.2.145 TTBR0_EL2, Translation Table Base Register 0 (EL2)

## TTBR0_EL2
D17.2.148 TTBR1_EL2, Translation Table Base Register 1 (EL2)
