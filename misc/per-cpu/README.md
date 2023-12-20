# ORG patch
```
commit 3d7af07825c07ddb3fbc27245ff01caae7ce764f
Author: Rusty Russell <rusty@rustcorp.com.au>
Date:   Mon Mar 4 23:04:15 2002 -0800

    [PATCH] per-cpu areas

    This is the Richard Henderson-approved, cleaner, brighter per-cpu patch.
```

该patch比较简单， 我们来看下
* 定义用于全局percpu变量的段
  ```diff
  diff --git a/arch/i386/vmlinux.lds b/arch/i386/vmlinux.lds
  index cd994f0b9b0..dd27a25e0f4 100644
  --- a/arch/i386/vmlinux.lds
  +++ b/arch/i386/vmlinux.lds
  @@ -57,6 +57,10 @@ SECTIONS
          *(.initcall7.init)
     }
     __initcall_end = .;
  +  . = ALIGN(32);
  +  __per_cpu_start = .;
  +  .data.percpu  : { *(.data.percpu) }
  +  __per_cpu_end = .;
     . = ALIGN(4096);
     __init_end = .;
  
  diff --git a/arch/ppc/vmlinux.lds b/arch/ppc/vmlinux.lds
  index 8a12e170654..531ba24f191 100644
  --- a/arch/ppc/vmlinux.lds
  +++ b/arch/ppc/vmlinux.lds
  @@ -111,6 +111,10 @@ SECTIONS
          *(.initcall7.init)
     }
     __initcall_end = .;
  +  . = ALIGN(32);
  +  __per_cpu_start = .;
  +  .data.percpu  : { *(.data.percpu) }
  +  __per_cpu_end = .;
     . = ALIGN(4096);
     __init_end = .;
  ```
* 定义用于全局percpu变量的 gcc section attribute
  ```cpp
  #define __per_cpu_data __attribute__((section(".data.percpu")))
  ```
* percpu offset
  + 声明:
    ```cpp
    extern unsigned long __per_cpu_offset[NR_CPUS];
    ```
  + 定义 && 初始化
    ```cpp
    unsigned long __per_cpu_offset[NR_CPUS];
    
    static void __init setup_per_cpu_areas(void)
    {
           unsigned long size, i;
           char *ptr;
           /* Created by linker magic */
           extern char __per_cpu_start[], __per_cpu_end[];
    
           /* Copy section for each CPU (we discard the original) */
           //size 定义为这个段的大小
           size = ALIGN(__per_cpu_end - __per_cpu_start, SMP_CACHE_BYTES);
           //申请 size * NR_CPUS, 也就是为每个cpu都申请 .data.percpu段大小的空间
           ptr = alloc_bootmem(size * NR_CPUS);
           //offset的计算也很简单, 每个cpu 占用连续的一块空间
           for (i = 0; i < NR_CPUS; i++, ptr += size) {
                   __per_cpu_offset[i] = ptr - __per_cpu_start;
                   memcpy(ptr, __per_cpu_start, size);
           }
    }
    #endif /* !__HAVE_ARCH_PER_CPU */
    ```
    ```diff
    /* Called by boot processor to activate the rest. */
     static void __init smp_init(void)
     {
    @@ -314,6 +338,7 @@ asmlinkage void __init start_kernel(void)
            lock_kernel();
            printk(linux_banner);
            setup_arch(&command_line);
    +       setup_per_cpu_areas();
            printk("Kernel command line: %s\n", saved_command_line);
            parse_options(command_line);
            trap_init();
    ```
  + 获取percpu变量地址
    ```cpp
    //不是，这块能编过???
    /* This macro obfuscates arithmetic on a variable address so that gcc
       shouldn't recognize the original var, and make assumptions about it */
           strcpy(s, "xxx"+X) => memcpy(s, "xxx"+X, 4-X) */
    //这块实际上是为了获取&(var) + off
    #define RELOC_HIDE(var, off)                                           \
      ({ __typeof__(&(var)) __ptr;                                 \
        __asm__ ("" : "=g"(__ptr) : "0"((void *)&(var) + (off)));  \
        *__ptr; })

    /* var is in discarded region: offset to particular copy we want */
    //off为 per_cpu_offset, 这块是不是写错了.., 在代码中没有搜到， 应该是 
    //__per_cpu_offset[cpu] 吧
    #define per_cpu(var, cpu) RELOC_HIDE(var, per_cpu_offset(cpu))
    //不解释
    #define this_cpu(var) per_cpu(var, smp_processor_id())
    ```
