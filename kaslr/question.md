Hello everyone, may I ask a question about arm64 kaslr...

Why does the `kaslr_early_init` function need to be 
executed when mmu is enabled? This will cause the 
page table to be prepared before this. Then, after
calculating the offset, go to recreate the page table. 
If you can calculate the offset before creating the page table, 
you only need to create the page table once.


I guess may be that kernel compilation and linking are 
address independent. The `kaslr_early_init` is C code function, so may 
have some unknown errors.

eg: 
```cpp
u64 __init kaslr_early_init(u64 dt_phys)
{
        void *fdt;
        u64 seed, offset, mask, module_range;
        const u8 *cmdline, *str;
        unsigned long raw;
        int size;

        /*
         * Set a reasonable default for module_alloc_base in case
         * we end up running with module randomization disabled.
         */
        
        //============(1)================
        module_alloc_base = (u64)_etext - MODULES_VSIZE;
        __flush_dcache_area(&module_alloc_base, sizeof(module_alloc_base));
        ...
}
```

Code position 1 will be compiled into an ADRP instruction. This 
instruction is position independent.  When disabling mmu or using 
idmap page table, a physical address will be obtained. But the 
desired result of  this code is a virtual address value, not a 
physical address value.

> NOTE
>
> From RHEL 4.18.0-372 code
