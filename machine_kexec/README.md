# 简介
kexec 可以在当前内核运行的情况下, 直接跳转到新内核, 不会出发
系统reset.

这样做的好处是:
* 快
* 可以不reset 硬件(例如memory), 当第一个内核崩溃时,可以通过这样
 的方式, 直接启动第二个内核, 获取第一个内核的问题现场.

我们这里主要分析, crash kexec的功能.

以centos8为例,用户态工具包为:
```
kexec-tools
```
文件比较多,大致分为三类:
* 第一个kernel服务配置及 kexec 相关工具
* 第二个kernel服务配置及 makedumpfile 相关工具

在第一个内核中有kdump服务, 最终会调用`kexec`工具, 该工具最终会调用
相关系统调用, 根据配置, 将kernel, initrd, cmdline, (dtb) 以通过
系统调用传递给内核(我们下面会介绍到). 第二个内核启动后, 相关的kdump
服务则负责将 第一个内核的现场信息转储到文件中.

系统调用主要有两个
```
SYSCALL_DEFINE4(kexec_load, unsigned long, entry, unsigned long, nr_segments,
                struct kexec_segment __user *, segments, unsigned long, flags)

SYSCALL_DEFINE5(kexec_file_load, int, kernel_fd, int, initrd_fd,
                unsigned long, cmdline_len, const char __user *, cmdline_ptr,
                unsigned long, flags)
```

第一种方式是kexec工具负责解析kernel的各个段, 还包括一些其他的信息(例如 dtb, cmdline), 
作为segments参数传递给内核

第二种方式则是通过传入 kernel_fd, initrd_fd 等文件句柄, 由kernel负责读取, 可以通过
`kexec -s `参数选择该方式. 我们主要看下该方式的流程

# 相关代码
## 接口

我们首先来看下接口参数
|成员|类型|作用|
|---|---|---|
|kernel_fd|int| kernel image 文件句柄|
|initrd_fd|int|initramfs image 文件句柄|
|cmdline_len|unsigned long| 第二个内核cmdline buf 大小|
|cmdline_ptr| char *| 第二个内核 cmdline buf 地址|
| flags| unsigned int | 见下面|

PRARM **flags** value:
```cpp
/*
 * Kexec file load interface flags.
 * KEXEC_FILE_UNLOAD : Unload already loaded kexec/kdump image.
 * KEXEC_FILE_ON_CRASH : Load/unload operation belongs to kdump image.
 * KEXEC_FILE_NO_INITRAMFS : No initramfs is being loaded. Ignore the initrd
 *                           fd field.
 */
#define KEXEC_FILE_UNLOAD       0x00000001
#define KEXEC_FILE_ON_CRASH     0x00000002
#define KEXEC_FILE_NO_INITRAMFS 0x00000004
```
* KEXEC_FILE_UNLOAD :   unload interface
* KEXEC_FILE_ON_CRASH : 表明该kexec的第二个内核是用于crash
* KEXEC_FILE_NO_INITRAMFS : 表明本次kexec 不会传入initrd, 忽略 initrd fd param

## 相关数据结构
### kimage
```cpp
struct kimage {
        kimage_entry_t head;
        kimage_entry_t *entry;
        kimage_entry_t *last_entry;

        unsigned long start;                //第二个kernel 启动的起始位置
        /*
         * 跳转到第二个kernel之前, 可能有一些中间跳转代码,
         * 放到该page中, 改指针为第一个control_code page 的首地址
         */
        struct page *control_code_page;     
        struct page *swap_page;
        void *vmcoreinfo_data_copy; /* locates in the crash memory */

        unsigned long nr_segments;          //段总数
        struct kexec_segment segment[KEXEC_SEGMENT_MAX];    //段的个数

        struct list_head control_pages;
        struct list_head dest_pages;
        struct list_head unusable_pages;

        /* Address of next control page to allocate for crash kernels. */
        unsigned long control_page;

        /* Flags to indicate special processing */
        unsigned int type : 1;
#define KEXEC_TYPE_DEFAULT 0
#define KEXEC_TYPE_CRASH   1
        unsigned int preserve_context : 1;
        /* If set, we are using file mode kexec syscall */
        unsigned int file_mode:1;
        
        // 架构特定
#ifdef ARCH_HAS_KIMAGE_ARCH
        struct kimage_arch arch;
#endif
        
        /*
         * 如果是编译了 CONFIG_KEXEC_FILE, 则增加下面字段
         * (大部分字段是用于函数间的参数传递, 有一些字段
         * 在使用后, 可能会被释放), 例如 kernel_buf, initrd_buf,
         * cmdline_buf
         */
#ifdef CONFIG_KEXEC_FILE
        /* Additional fields for file based kexec syscall */
        void *kernel_buf;
        unsigned long kernel_buf_len;

        void *initrd_buf;
        unsigned long initrd_buf_len;

        char *cmdline_buf;
        unsigned long cmdline_buf_len;

        /* File operations provided by image loader */
        const struct kexec_file_ops *fops;

        /* Image loader handling the kernel can store a pointer here */
        void *image_loader_data;

        /* Information for loading purgatory */
        struct purgatory_info purgatory_info;
#endif
        //未了解
#ifdef CONFIG_IMA_KEXEC
        /* Virtual address of IMA measurement buffer for kexec syscall */
        void *ima_buffer;
#endif
}
```
### kexec_segment
```cpp
struct kexec_segment {
        /*
         * This pointer can point to user memory if kexec_load() system
         * call is used or will point to kernel memory if
         * kexec_file_load() system call is used.
         *
         * Use ->buf when expecting to deal with user memory and use ->kbuf
         * when expecting to deal with kernel memory.
         */
        union {
                void __user *buf;
                void *kbuf;
        };
        size_t bufsz;
        unsigned long mem;
        size_t memsz;
};
```
* **buf**: 其作用是存储这个segment, 而如果使用 `kexec_load()` syscall, kexec工具会
 完成对某些段的读取/初始化,这样kernel侧就可以直接用,此时使用`buf`表示指向
 用户空间内存 . 而如果使用 `kexec_file_load()` syscall, 则需要kernel自己读取
 /初始化这些segment, 所以使用`kbuf`指向内核空间内存
* **mem**: 指向该段实际的存储地址.


