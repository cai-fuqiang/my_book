# arch/arm64/Makefile
```
 ifeq ($(CONFIG_RELOCATABLE), y)
 # Pass --no-apply-dynamic-relocs to restore pre-binutils-2.27 behaviour
 # for relative relocs, since this leads to better Image compression
 # with the relocation offsets always being zero.
 LDFLAGS_vmlinux         += -pie -shared -Bsymbolic \
                         $(call ld-option, --no-apply-dynamic-relocs)
 endif
```

各个参数含义:
```
-shared
-Bshareable
    Create a shared library.  This is currently only supported on ELF, XCOFF and SunOS platforms.  
    On SunOS, the linker will automatically create a shared library if the -e option is not used 
    and there are undefined symbols in the link.

    创建共享库, 不太清楚这个有什么用。

-pie
--pic-executable
    Create a position independent executable.  This is currently only supported on ELF platforms.  
    Position independent executables are similar to shared libraries in that they are relocated 
    by the dynamic linker to the virtual address the OS chooses for them (which can vary between 
    invocations).  Like normal dynamically linked executables they can be executed and symbols 
    defined in the executable cannot be overridden by shared libraries.

    创建与位置无关的代码, 但是和fpic不同的是，这个代码是可执行的。

-Bsymbolic
    When creating a shared library, bind references to global symbols to the definition within the shared library, 
    if any.  Normally, it is possible for a program linked against a shared library to override the definition within
    the shared library.  This option can also be used with the --export-dynamic option, when creating a position 
    independent executable, to bind references to global symbols to the definition within the executable.  This option
    is only meaningful on ELF platforms which support shared libraries and position independent executables.

--no-apply-dynamic-relocs
    (aarch64 only) Do not apply link-time values for dynamic relocations
    对于 dynamic relocations 不会在链接时候，连接的值放进去
```

# 简单写个程序测试
```cpp
#include <stdio.h>

int a = 0;
int main()
{
        printf("the a is %lx\n", (unsigned long )&a);
        return 0;
}
```

使用gcc -fpie 编译
```
(gdb) disassemble main
Dump of assembler code for function main:
   0x0000000000401126 <+0>:     push   %rbp
   0x0000000000401127 <+1>:     mov    %rsp,%rbp
   0x000000000040112a <+4>:     lea    0x2edf(%rip),%rax        # 0x404010 <a>
   0x0000000000401131 <+11>:    mov    %rax,%rsi
   0x0000000000401134 <+14>:    lea    0xed5(%rip),%rax        # 0x402010
   0x000000000040113b <+21>:    mov    %rax,%rdi
   0x000000000040113e <+24>:    mov    $0x0,%eax
   0x0000000000401143 <+29>:    call   0x401030 <printf@plt>
   0x0000000000401148 <+34>:    mov    $0x0,%eax
   0x000000000040114d <+39>:    pop    %rbp
   0x000000000040114e <+40>:    ret
```

不使用-fpic编译:
```

(gdb) disassemble main
Dump of assembler code for function main:
   0x0000000000401126 <+0>:     push   %rbp
   0x0000000000401127 <+1>:     mov    %rsp,%rbp
   0x000000000040112a <+4>:     mov    $0x404010,%eax
   0x000000000040112f <+9>:     mov    %rax,%rsi
   0x0000000000401132 <+12>:    mov    $0x402010,%edi
   0x0000000000401137 <+17>:    mov    $0x0,%eax
   0x000000000040113c <+22>:    call   0x401030 <printf@plt>
   0x0000000000401141 <+27>:    mov    $0x0,%eax
   0x0000000000401146 <+32>:    pop    %rbp
   0x0000000000401147 <+33>:    ret
```

可以看到这两种方式，访问a这个全局变量的方式不同。
在使用-fpie -pie 的方式下，使用 lea  指令（类似于arm64 adrp指令)
进行根据ip相对偏移取值，所以此时ip 是什么值都无所谓，因为硬编码
中记录的是距当前ip的offset。
