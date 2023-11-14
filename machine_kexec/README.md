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

> 本文分析的代码版本为:rhel 8.6 4.18.0-372

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

### kexec_file_ops
```cpp
struct kexec_file_ops {
        kexec_probe_t *probe;
        kexec_load_t *load;
        kexec_cleanup_t *cleanup;
#ifdef CONFIG_KEXEC_SIG
        kexec_verify_sig_t *verify_sig;
#endif
};
```
不同架构,可以自定义一些回调,会在 `kexec_file_load`
的代码流程中调用到

## 代码流程
代码流程主要分为几个部分:
<!--* reserve crash kernel memory-->
* kexec_file_load() syscall
* panic->第二个kernel 引导流程
* 第二个kernel 部分流程

### kexec_file_load - FIRST KERNEL
```
kexec_file_load() {
  //============(1)============
  if (flags & KEXEC_FILE_ON_CRASH) {
    dest_image = &kexec_crash_image;
  }
  kimage_file_alloc_init() {
    //==========(2)============
    kimage_file_prepare_segments()
    //==========(3)============
    kimage_alloc_control_pages()
  }
  for (i = 0; i < image->nr_segments; i++) {
     //==========(4)============
     ret = kimage_load_segment(image, &image->segment[i]);
  }
  //==========(5)============
  kimage_file_post_load_cleanup()
}
```
1. 如果该`kexec()`系统调用是用于 crash, 则操作的目标kimage 为`kexec_crash_image`
2. 该函数会将kernel_img(kernel_fd), initrd_img(initrd_fd), cmdline, 还有其他
有内核初始化的segment( 例如fdt 等) load到一个临时buf中 , 我们接下来会详细分析该函数流程.
3. 从 crash reserved memory 中分配 control pages
4. 将(2)中涉及得到的tmp buf copy 到 crash reserved memory 中. 
5. 释放 tmp buf

#### kimage_file_prepare_segments
```cpp
/*
 * In file mode list of segments is prepared by kernel. Copy relevant
 * data from user space, do error checking, prepare segment list
 */
static int
kimage_file_prepare_segments(struct kimage *image, int kernel_fd, int initrd_fd,
                             const char __user *cmdline_ptr,
                             unsigned long cmdline_len, unsigned flags)
{
        int ret;
        void *ldata;
        loff_t size;
        //===============(1)=================
        ret = kernel_read_file_from_fd(kernel_fd, &image->kernel_buf,
                                       &size, INT_MAX, READING_KEXEC_IMAGE);
        if (ret)
                return ret;
        image->kernel_buf_len = size;

        /* Call arch image probe handlers */
        //===============(2)=================
        ret = arch_kexec_kernel_image_probe(image, image->kernel_buf,
                                            image->kernel_buf_len);
        if (ret)
                goto out;

#ifdef CONFIG_KEXEC_SIG
        ret = kimage_validate_signature(image);

        if (ret)
                goto out;
#endif
        /* It is possible that there no initramfs is being loaded */
        if (!(flags & KEXEC_FILE_NO_INITRAMFS)) {
                //===============(3)=================
                ret = kernel_read_file_from_fd(initrd_fd, &image->initrd_buf,
                                               &size, INT_MAX,
                                               READING_KEXEC_INITRAMFS);
                if (ret)
                        goto out;
                image->initrd_buf_len = size;
        }

        if (cmdline_len) {
                //===============(4)=================
                image->cmdline_buf = memdup_user(cmdline_ptr, cmdline_len);
                if (IS_ERR(image->cmdline_buf)) {
                        ret = PTR_ERR(image->cmdline_buf);
                        image->cmdline_buf = NULL;
                        goto out;
                }

                image->cmdline_buf_len = cmdline_len;

                /* command line should be a string with last byte null */
                if (image->cmdline_buf[cmdline_len - 1] != '\0') {
                        ret = -EINVAL;
                        goto out;
                }

                //===============(5)=================
                ima_kexec_cmdline(image->cmdline_buf,
                                  image->cmdline_buf_len - 1);
        }

        //===============(5)=================
        /* IMA needs to pass the measurement list to the next kernel. */
        ima_add_kexec_buffer(image);

        //===============(6)=================
        /* Call arch image load handlers */
        ldata = arch_kexec_kernel_image_load(image);

        if (IS_ERR(ldata)) {
                ret = PTR_ERR(ldata);
                goto out;
        }

        image->image_loader_data = ldata;
out:
        /* In case of error, free up all allocated memory in this function */
        if (ret)
                kimage_file_post_load_cleanup(image);
        return ret;
}
```
1. 读取kernel img 到 `image->kernel_buf`
2. 执行image probe, 实际上是`kexec_file_ops->probe`, 对于arm64而言为:
```cpp
static int image_probe(const char *kernel_buf, unsigned long kernel_len)
{
        const struct arm64_image_header *h;
        
        h = (const struct arm64_image_header *)(kernel_buf);

        if (!h || (kernel_len < sizeof(*h)) ||
        //赋值 h->magic为`ARM64_IMAGE_MAGIC`
                        memcmp(&h->magic, ARM64_IMAGE_MAGIC,
                                sizeof(h->magic)))
                return -EINVAL;

        return 0;
}
```
但是该版本kernel 代码中编译成的image中, `arm64_image_header->magic`就是
`ARM64_IMAGE_MAGIC`
```cpp
//=====FILE: arch/arm64/kernel/head.S======
_head:
    ...
    .ascii  ARM64_IMAGE_MAGIC
    ...
```

> 在下面的mail list 中有讨论, 不过没看懂, 不是很重要,先不纠结
> https://lore.kernel.org/all/6f0df3a8-a691-80f1-85de-3e0ead852f12@arm.com/

3. 读取 initrd img 到 `image->initrd_buf`
4. 读取 用户空间的cmdline buf, 到 `image->cmdline_buf`
5. 和 ima相关, 暂不看
6. 调用 arch image load handlers , 对于 arm64 为 `image_load()`, 我们接下来详细分析

##### image_load
```cpp
static void *image_load(struct kimage *image,
                                char *kernel, unsigned long kernel_len,
                                char *initrd, unsigned long initrd_len,
                                char *cmdline, unsigned long cmdline_len)
{
        struct arm64_image_header *h;
        u64 flags, value;
        bool be_image, be_kernel;
        struct kexec_buf kbuf;
        unsigned long text_offset;
        struct kexec_segment *kernel_segment;
        int ret;

        /*
         * We require a kernel with an unambiguous Image header. Per
         * Documentation/booting.rst, this is the case when image_size
         * is non-zero (practically speaking, since v3.17).
         */
        h = (struct arm64_image_header *)kernel;
        if (!h->image_size)
                return ERR_PTR(-EINVAL);

        /* Check cpu features */
        flags = le64_to_cpu(h->flags);
        be_image = arm64_image_flag_field(flags, ARM64_IMAGE_FLAG_BE);
        be_kernel = IS_ENABLED(CONFIG_CPU_BIG_ENDIAN);
        if ((be_image != be_kernel) && !system_supports_mixed_endian())
                return ERR_PTR(-EINVAL);

        value = arm64_image_flag_field(flags, ARM64_IMAGE_FLAG_PAGE_SIZE);
        if (((value == ARM64_IMAGE_FLAG_PAGE_SIZE_4K) &&
                        !system_supports_4kb_granule()) ||
            ((value == ARM64_IMAGE_FLAG_PAGE_SIZE_64K) &&
                        !system_supports_64kb_granule()) ||
            ((value == ARM64_IMAGE_FLAG_PAGE_SIZE_16K) &&
                        !system_supports_16kb_granule()))
                return ERR_PTR(-EINVAL);
        //===============(1)================
        /* Load the kernel */
        kbuf.image = image;
        kbuf.buf_min = 0;
        kbuf.buf_max = ULONG_MAX;
        kbuf.top_down = false;

        kbuf.buffer = kernel;
        kbuf.bufsz = kernel_len;
        kbuf.mem = 0;
        kbuf.memsz = le64_to_cpu(h->image_size);
        //===============(1.1)================
        text_offset = le64_to_cpu(h->text_offset);
        kbuf.buf_align = MIN_KIMG_ALIGN;

        /* Adjust kernel segment with TEXT_OFFSET */
        kbuf.memsz += text_offset;
        //===============(2)==================
        ret = kexec_add_buffer(&kbuf);
        if (ret)
                return ERR_PTR(ret);

        //===============(3)==================
        kernel_segment = &image->segment[image->nr_segments - 1];
        kernel_segment->mem += text_offset;
        kernel_segment->memsz -= text_offset;
        image->start = kernel_segment->mem;

        pr_debug("Loaded kernel at 0x%lx bufsz=0x%lx memsz=0x%lx\n",
                                kernel_segment->mem, kbuf.bufsz,
                                kernel_segment->memsz);

        /* Load additional data */
        ret = load_other_segments(image,
                                kernel_segment->mem, kernel_segment->memsz,
                                initrd, initrd_len, cmdline);

        return ERR_PTR(ret);
}
```
1. 初始化`kbuf` , 注意`kbuf.memsz` 会根据 `h->image_size` 和 `h->text_offset`求和得到(1.1)
我们下面会分析为什么要这么做.
2. 调用`kexec_add_buffer()`, 该函数会做以下几件事情
    1. 在 crash reserved  memory 中找到可以存放`kbuf.memsz`大小的内存区域
    2. 初始化 `image->segment[]` 数组, 接下来会分析
3. 将初始化好的 `kernel_segment` 的`kernel_segment->mem += text_offset`, 
   `mem`代表在`reserved memory`中的内存地址, 加上`text_offset`表示将内核加载
   到 距离 `reserved memory base` + `text_offset` 处, 而又将`kernel_segment->memsz 
   -= text_offset`我们结合下面的`kexec_add_buffern`进行分析

   另外我们需要知道`image->start`就是第二个内核的入口地址, 可以看到其就在image的头部
   我们编译出vmlinuz时, 其文件被伪装成 PE 文件,开始部分为:

   ```cpp
           __HEAD
   _head:
           /*
            * DO NOT MODIFY. Image header expected by Linux boot-loaders.
            */
   #ifdef CONFIG_EFI
           /*
            * This add instruction has no meaningful effect except that
            * its opcode forms the magic "MZ" signature required by UEFI.
            */
           add     x13, x18, #0x16
           b       stext
   #else
           b       stext                           // branch to kernel start, magic
           .long   0                               // reserved
   #endif
   ```
   所以入口地址的第一行代码应该是 `add x13, x18 , #0x16`, 接着执行 `b stext`, 
   而pe_header的首个成员应该是 magic `MZ`, 解码成arm64指令正好为提到的第一行
   代码, 因为x13不用做传参, 该指令没有什么副作用.执行了无所谓

4. load其他的 segments, 对于 arm64而言, 有`elfheader`, `initrd`, `dtb`等.

我们先分析`kexec_add_buffer`代码流
##### kexec_add_buffer
```cpp
/**
 * kexec_add_buffer - place a buffer in a kexec segment
 * @kbuf:       Buffer contents and memory parameters.
 *
 * This function assumes that kexec_mutex is held.
 * On successful return, @kbuf->mem will have the physical address of
 * the buffer in memory.
 *
 * Return: 0 on success, negative errno on error.
 */
int kexec_add_buffer(struct kexec_buf *kbuf)
{
        struct kexec_segment *ksegment;
        int ret;

        /* Currently adding segment this way is allowed only in file mode */
        if (!kbuf->image->file_mode)
                return -EINVAL;

        if (kbuf->image->nr_segments >= KEXEC_SEGMENT_MAX)
                return -EINVAL;

        /*
         * Make sure we are not trying to add buffer after allocating
         * control pages. All segments need to be placed first before
         * any control pages are allocated. As control page allocation
         * logic goes through list of segments to make sure there are
         * no destination overlaps.
         */
        if (!list_empty(&kbuf->image->control_pages)) {
                WARN_ON(1);
                return -EINVAL;
        }
        //=========(1)===========
        /* Ensure minimum alignment needed for segments. */
        kbuf->memsz = ALIGN(kbuf->memsz, PAGE_SIZE);
        kbuf->buf_align = max(kbuf->buf_align, PAGE_SIZE);

        //=========(2)===========
        /* Walk the RAM ranges and allocate a suitable range for the buffer */
        ret = arch_kexec_locate_mem_hole(kbuf);
        if (ret)
                return ret;

        //=========(3)===========
        /* Found a suitable memory range */
        ksegment = &kbuf->image->segment[kbuf->image->nr_segments];
        ksegment->kbuf = kbuf->buffer;
        ksegment->bufsz = kbuf->bufsz;
        ksegment->mem = kbuf->mem;
        ksegment->memsz = kbuf->memsz;
        kbuf->image->nr_segments++;
        return 0;
}
```
1. 对其 memsz
2. 查找空闲的内存空间, 并初始化 `kbuf->mem`
3. 初始化 `image->segment[]` 数组成员

我们来详细看下`arch_kexec_locate_mem_hole()`代码流
```cpp
int __weak arch_kexec_locate_mem_hole(struct kexec_buf *kbuf)
{
        return kexec_locate_mem_hole(kbuf);
}

int kexec_locate_mem_hole(struct kexec_buf *kbuf)
{
        int ret;

        /* Arch knows where to place */
        if (kbuf->mem != KEXEC_BUF_MEM_UNKNOWN)
                return 0;

        if (IS_ENABLED(CONFIG_ARCH_DISCARD_MEMBLOCK))
                ret = kexec_walk_resources(kbuf, locate_mem_hole_callback);
        else
                ret = kexec_walk_memblock(kbuf, locate_mem_hole_callback);

        return ret == 1 ? 0 : -EADDRNOTAVAIL;
}

static int kexec_walk_memblock(struct kexec_buf *kbuf,
                               int (*func)(struct resource *, void *))
{
        int ret = 0;
        u64 i;
        phys_addr_t mstart, mend;
        struct resource res = { };

        if (kbuf->image->type == KEXEC_TYPE_CRASH)
                //==========(1)==========
                return func(&crashk_res, kbuf);
        ...
}
```
1. kexec_walk_memblock() 后面还有一些代码, 而当`image->type`
表明是用作 crash kernel 时, 则直接调用`func`, 从 `crashk_res`
中分配内存(后面的一些代码是从free memblock中申请内存)

```cpp
static int locate_mem_hole_callback(struct resource *res, void *arg)
{
        struct kexec_buf *kbuf = (struct kexec_buf *)arg;
        u64 start = res->start, end = res->end;
        unsigned long sz = end - start + 1;

        /* Returning 0 will take to next memory range */
        if (sz < kbuf->memsz)
                return 0;

        if (end < kbuf->buf_min || start > kbuf->buf_max)
                return 0;

        /*
         * Allocate memory top down with-in ram range. Otherwise bottom up
         * allocation.
         */
        if (kbuf->top_down)
                return locate_mem_hole_top_down(start, end, kbuf);
        //==============(1)==================
        return locate_mem_hole_bottom_up(start, end, kbuf);
}
```
1. 这里会根据`kbuf->top_down`, 选择从高往低搜索,还是从低往高搜索. 不同的`kbuf`不一
样, kernel image 是 从低往高. 那么我们以`locate_mem_hole_bottom_up`  为例

```cpp
static int locate_mem_hole_bottom_up(unsigned long start, unsigned long end,
                                     struct kexec_buf *kbuf)
{
        struct kimage *image = kbuf->image;
        unsigned long temp_start, temp_end;

        //================(1)===============
        temp_start = max(start, kbuf->buf_min);

        do {
                //===========(2)============
                temp_start = ALIGN(temp_start, kbuf->buf_align);
                temp_end = temp_start + kbuf->memsz - 1;

                if (temp_end > end || temp_end > kbuf->buf_max)
                        return 0;
                /*
                 * Make sure this does not conflict with any of existing
                 * segments
                 */
                //===========(3)============
                if (kimage_is_destination_range(image, temp_start, temp_end)) {
                        temp_start = temp_start + PAGE_SIZE;
                        continue;
                }

                /* We found a suitable memory range */
                break;
        } while (1);

        /* If we are here, we found a suitable memory range */
        kbuf->mem = temp_start;

        /* Success, stop navigating through remaining System RAM ranges */
        return 1;
}
```
1. 初始化temp_start, 每个kbuf会有一个最低地址要求: `kbuf->buf_min`, 取两者最大值
2. 每个kbuf有对其要求: `kbuf->buf_align`
3. 判断temp_start, temp_end 和image中的其他segment 是否有重叠,如果有则返回true
这是将temp_start 往后更新一个 PAGE_SIZE的大小, 继续该循环

```cpp
int kimage_is_destination_range(struct kimage *image,
                                        unsigned long start,
                                        unsigned long end)
{
        unsigned long i;
        for (i = 0; i < image->nr_segments; i++) {
                unsigned long mstart, mend;

                //========(1)===========
                mstart = image->segment[i].mem;
                mend = mstart + image->segment[i].memsz;
                if ((end > mstart) && (start < mend))
                        return 1;
        }

        return 0;
}
```
1. 可以看到每个 image->segment[i]的边界是`[segment.mem, segment.mem + segment.memsz]`


那么我们可以回头来看, image_load中对于kernel img segment的关于 text_offset的处理
```
image_load() {
    ...
    kbuf.memsz = le64_to_cpu(h->image_size);
    kbuf.memsz += text_offset;
    ret = kexec_add_buffer(&kbuf);
    kernel_segment->mem += text_offset;
    kernel_segment->memsz -= text_offset;
    ...
}
```
可见, 在调用`kexec_add_buffer()`之前,将分配内存代写哦啊`kbuf.memsz`在原本image的大小
之上(`h->image_size`)又增加了`text_offset`. 分配内存后, 将`kernel_segment.mem` 
加上`text_offset`, 并且将`kernel_segment.memsz`又减去了`text_offset`, 这样又把多余的
内存还给了分配器(使之空闲). 这样做的目的就是为了使image加载到一个offset处. 并且
因为 kernel img 是第一个申请segment的, 并且 `top_down == false` ,所以其加载到 
```
[crashk_res.start + text_offset, crash_res.start + text_offset + kernel_image_size]
```
处.

##### load_other_segments
```cpp
int load_other_segments(struct kimage *image,
                        unsigned long kernel_load_addr,
                        unsigned long kernel_size,
                        char *initrd, unsigned long initrd_len,
                        char *cmdline)
{
        struct kexec_buf kbuf;
        void *headers, *dtb = NULL;
        unsigned long headers_sz, initrd_load_addr = 0, dtb_len;
        int ret = 0;

        kbuf.image = image;
        /* not allocate anything below the kernel */
        kbuf.buf_min = kernel_load_addr + kernel_size;

        /* load elf core header */
        if (image->type == KEXEC_TYPE_CRASH) {
                //=================(1)============
                ret = prepare_elf_headers(&headers, &headers_sz);
                if (ret) {
                        pr_err("Preparing elf core header failed\n");
                        goto out_err;
                }

                kbuf.buffer = headers;
                kbuf.bufsz = headers_sz;
                kbuf.mem = KEXEC_BUF_MEM_UNKNOWN;
                kbuf.memsz = headers_sz;
                kbuf.buf_align = SZ_64K; /* largest supported page size */
                kbuf.buf_max = ULONG_MAX;
                kbuf.top_down = true;

                ret = kexec_add_buffer(&kbuf);
                if (ret) {
                        vfree(headers);
                        goto out_err;
                }
                image->arch.elf_headers = headers;
                image->arch.elf_headers_mem = kbuf.mem;
                image->arch.elf_headers_sz = headers_sz;

                pr_debug("Loaded elf core header at 0x%lx bufsz=0x%lx memsz=0x%lx\n",
                         image->arch.elf_headers_mem, headers_sz, headers_sz);
        }

        /* load initrd */
        //=================(2)============
        if (initrd) {
                kbuf.buffer = initrd;
                kbuf.bufsz = initrd_len;
                kbuf.mem = 0;
                kbuf.memsz = initrd_len;
                kbuf.buf_align = 0;
                /* within 1GB-aligned window of up to 32GB in size */
                kbuf.buf_max = round_down(kernel_load_addr, SZ_1G)
                                                + (unsigned long)SZ_1G * 32;
                kbuf.top_down = false;

                ret = kexec_add_buffer(&kbuf);
                if (ret)
                        goto out_err;
                initrd_load_addr = kbuf.mem;

                pr_debug("Loaded initrd at 0x%lx bufsz=0x%lx memsz=0x%lx\n",
                                initrd_load_addr, initrd_len, initrd_len);
        }

        //=================(3)============
        /* load dtb */
        ret = create_dtb(image, initrd_load_addr, initrd_len, cmdline, &dtb);
        if (ret) {
                pr_err("Preparing for new dtb failed\n");
                goto out_err;
        }

        dtb_len = fdt_totalsize(dtb);
        kbuf.buffer = dtb;
        kbuf.bufsz = dtb_len;
        kbuf.mem = 0;
        kbuf.memsz = dtb_len;
        /* not across 2MB boundary */
        kbuf.buf_align = SZ_2M;
        kbuf.buf_max = ULONG_MAX;
        kbuf.top_down = true;

        ret = kexec_add_buffer(&kbuf);
        if (ret)
                goto out_err;
        image->arch.dtb = dtb;
        image->arch.dtb_mem = kbuf.mem;

        pr_debug("Loaded dtb at 0x%lx bufsz=0x%lx memsz=0x%lx\n",
                        kbuf.mem, dtb_len, dtb_len);

        return 0;

out_err:
        vfree(dtb);
        return ret;
}
```
1. 初始化elf_headers, elf_headers 是将当前内核的一些信息, 例如 `memblock.memory`,
cpu 的一些现场信息 放入 一个"elf" 的文件中的各个段,方便第二个内核进行解析, 这部分
代码暂时不看. 另外,该部分代码为该数据结构在 crash reserved memory 中预留了内存
(通过`kexec_add_buffer()`
2. 分配 initrd image 内存
3. 初始化dtb, 并且为dtb分配内存

我们来看下`create_dtb`代码
```cpp
static int create_dtb(struct kimage *image,
                      unsigned long initrd_load_addr, unsigned long initrd_len,
                      char *cmdline, void **dtb)
{
        void *buf;
        size_t buf_size;
        size_t cmdline_len;
        int ret;

        cmdline_len = cmdline ? strlen(cmdline) : 0;
        //=========(1)=============
        buf_size = fdt_totalsize(initial_boot_params)
                        + cmdline_len + DTB_EXTRA_SPACE;

        for (;;) {
                buf = vmalloc(buf_size);
                if (!buf)
                        return -ENOMEM;

                /* duplicate a device tree blob */
                ret = fdt_open_into(initial_boot_params, buf, buf_size);
                if (ret)
                        return -EINVAL;
                //=========(2)=============
                ret = setup_dtb(image, initrd_load_addr, initrd_len,
                                cmdline, buf);
                if (ret) {
                        vfree(buf);
                        if (ret == -ENOMEM) {
                                /* unlikely, but just in case */
                                buf_size += DTB_EXTRA_SPACE;
                                continue;
                        } else {
                                return ret;
                        }
                }

                /* trim it */
                fdt_pack(buf);
                *dtb = buf;

                return 0;
        }
}
```
1. kernel在启动初,将fdt 的首地址赋值给了 `initial_boot_params`,
堆栈为:
```
setup_arch
  setup_machine_fdt
    early_init_dt_scan
      early_init_dt_verify
```

> NOTE
>
> 这里为什么要这样做呢?
> 因为old kernel中有些dtb的path, crashkernel也需要获取,例如`/chosen/linux,uefi-*`,
> 这些是 efi-stub 通过UEFI服务获取的, crash kernel 跳转的点,实际上是 stext, 不走
> efi-stub, 所以需要第一个kernel获取的这些path
>
> 当然, crashkernel fdt中除了第一个kernel的那些path, 还有一些其他的:
> * /chosen/linux.elfcorehdr
> * /chosen/linux, usable-memory-range   --- 因为UEFI的系统会通过UEFI服务报告可用内存,不知道
>   嵌入式设备 会不会用到此path
> * kaslr-seed kaslr种子
2. 初始化 dtb
```cpp
static int setup_dtb(struct kimage *image,
                     unsigned long initrd_load_addr, unsigned long initrd_len,
                     char *cmdline, void *dtb)
{
        int off, ret;

        ret = fdt_path_offset(dtb, "/chosen");
        if (ret < 0)
                goto out;

        off = ret;

        ret = fdt_delprop(dtb, off, FDT_PROP_KEXEC_ELFHDR);
        if (ret && ret != -FDT_ERR_NOTFOUND)
                goto out;
        ret = fdt_delprop(dtb, off, FDT_PROP_MEM_RANGE);
        if (ret && ret != -FDT_ERR_NOTFOUND)
                goto out;

        if (image->type == KEXEC_TYPE_CRASH) {
                /* add linux,elfcorehdr */
                ret = fdt_appendprop_addrrange(dtb, 0, off,
                                FDT_PROP_KEXEC_ELFHDR,
                                image->arch.elf_headers_mem,
                                image->arch.elf_headers_sz);
                if (ret)
                        return (ret == -FDT_ERR_NOSPACE ? -ENOMEM : -EINVAL);
                //=========(1)==============
                /* add linux,usable-memory-range */
                ret = fdt_appendprop_addrrange(dtb, 0, off,
                                FDT_PROP_MEM_RANGE,
                                crashk_res.start,
                                crashk_res.end - crashk_res.start + 1);
                if (ret)
                        return (ret == -FDT_ERR_NOSPACE ? -ENOMEM : -EINVAL);
        }

        /* add bootargs */
        if (cmdline) {
                ret = fdt_setprop_string(dtb, off, FDT_PROP_BOOTARGS, cmdline);
                if (ret)
                        goto out;
        } else {
                ret = fdt_delprop(dtb, off, FDT_PROP_BOOTARGS);
                if (ret && (ret != -FDT_ERR_NOTFOUND))
                        goto out;
        }

        /* add initrd-* */
        if (initrd_load_addr) {
                ret = fdt_setprop_u64(dtb, off, FDT_PROP_INITRD_START,
                                      initrd_load_addr);
                if (ret)
                        goto out;

                ret = fdt_setprop_u64(dtb, off, FDT_PROP_INITRD_END,
                                      initrd_load_addr + initrd_len);
                if (ret)
                        goto out;
        } else {
                ret = fdt_delprop(dtb, off, FDT_PROP_INITRD_START);
                if (ret && (ret != -FDT_ERR_NOTFOUND))
                        goto out;

                ret = fdt_delprop(dtb, off, FDT_PROP_INITRD_END);
                if (ret && (ret != -FDT_ERR_NOTFOUND))
                        goto out;
        }

        /* add kaslr-seed */
        ret = fdt_delprop(dtb, off, FDT_PROP_KASLR_SEED);
        if  (ret == -FDT_ERR_NOTFOUND)
                ret = 0;
        else if (ret)
                goto out;

        if (rng_is_initialized()) {
                u64 seed = get_random_u64();
                ret = fdt_setprop_u64(dtb, off, FDT_PROP_KASLR_SEED, seed);
                if (ret)
                        goto out;
        } else {
                pr_notice("RNG is not initialised: omitting \"%s\" property\n",
                                FDT_PROP_KASLR_SEED);
        }

out:
        if (ret)
                return (ret == -FDT_ERR_NOSPACE) ? -ENOMEM : -EINVAL;

        return 0;
}
```
代码比较多, 但是流程很简单, 就是初始化 dtb中的各个path, 我们这边需要注意(1)

`linux,usable-memory-range`向用户报告了 crash kernel 所能使用的memory range,
区间为`[crashk_res.start, crashk_res.end]`

***

至此,我们分析完了`kimage_file_prepare_segments()`, 我们接下来分析 `control pages`

#### kimage_alloc_control_pages
```cpp
struct page *kimage_alloc_control_pages(struct kimage *image,
                                         unsigned int order)
{
        struct page *pages = NULL;

        switch (image->type) {
        case KEXEC_TYPE_DEFAULT:
                pages = kimage_alloc_normal_control_pages(image, order);
                break;
        case KEXEC_TYPE_CRASH:
                pages = kimage_alloc_crash_control_pages(image, order);
                break;
        }

        return pages;
}

static struct page *kimage_alloc_crash_control_pages(struct kimage *image,
                                                      unsigned int order)
{
        /* Control pages are special, they are the intermediaries
         * that are needed while we copy the rest of the pages
         * to their final resting place.  As such they must
         * not conflict with either the destination addresses
         * or memory the kernel is already using.
         *
         * control pages是特殊的,当我们将剩余的page copy到他们最终
         * resting place?? 时, 他们是中间媒介. 因此,他们不能与目标
         * 地址以及内核正在使用的 memory 重叠.
         *
         * Control pages are also the only pags we must allocate
         * when loading a crash kernel.  All of the other pages
         * are specified by the segments and we just memcpy
         * into them directly.
         * 
         * control pages也是当 loading crash kernel 时唯一需要
         * 必须申请的page. 其他所有的page都在 segment 中制定,我们
         * 仅需要直接 memory 他们进去.
         *
         * The only case where we really need more than one of
         * these are for architectures where we cannot disable
         * the MMU and must instead generate an identity mapped
         * page table for all of the memory.
         *
         * 我们真正需要不止一个的唯一情况是，对于不能禁用MMU的架构，而
         * 必须为所有内存生成一个identity mapped 的 page table.
         *
         * Given the low demand this implements a very simple
         * allocator that finds the first hole of the appropriate
         * size in the reserved memory region, and allocates all
         * of the memory up to and including the hole.
         *
         * 考虑到低需求，这实现了一个非常简单的分配器，它在保留内
         * 存区域中找到合适大小的第一个hole，并分配所有内存，并
         * 包括该孔。 
         */
        unsigned long hole_start, hole_end, size;
        struct page *pages;

        pages = NULL;
        size = (1 << order) << PAGE_SHIFT;
        //===============(1)==============
        hole_start = (image->control_page + (size - 1)) & ~(size - 1);
        hole_end   = hole_start + size - 1;
        //===============(2)==============
        while (hole_end <= crashk_res.end) {
                unsigned long i;

                cond_resched();

                if (hole_end > KEXEC_CRASH_CONTROL_MEMORY_LIMIT)
                        break;
                /* See if I overlap any of the segments */
                for (i = 0; i < image->nr_segments; i++) {
                        unsigned long mstart, mend;

                        mstart = image->segment[i].mem;
                        mend   = mstart + image->segment[i].memsz - 1;
                        //===============(2.1)==============
                        if ((hole_end >= mstart) && (hole_start <= mend)) {
                                /* Advance the hole to the end of the segment */
                                hole_start = (mend + (size - 1)) & ~(size - 1);
                                hole_end   = hole_start + size - 1;
                                break;
                        }
                }
                /* If I don't overlap any segments I have found my hole! */
                //===============(2.2)==============
                if (i == image->nr_segments) {
                        pages = pfn_to_page(hole_start >> PAGE_SHIFT);
                        image->control_page = hole_end;
                        break;
                }
        }

        /* Ensure that these pages are decrypted if SME is enabled. */
        if (pages)
                arch_kexec_post_alloc_pages(page_address(pages), 1 << order, 0);

        return pages;
}
```
1. 分配一个完整页面,所以这里要根据地址, 向上取整 page size
2. 循环遍历, 这个循环逻辑有点抽象, 大概就是在紧接着每个`segment`的后面,寻找
一个hole, 并且看看这个hole 是否和其他的 segment 有重叠, 如果有重叠, (2.1) 就满足,
就在这个 segment 后面 重新选择一个hole,  如果没有重叠, 继续for循环, 查看和其他的hole
有没有重叠. 直到整个for循环退出 (2.2) 条件满足 ,break 整个for循环.

> NOTE
>
> 这里还是不太理解,为什么非得在 crash reserved memory 里面申请内存, 仅从arm64架构来看,
> `control_page`中存储的为一个跳转代码, 用于跳转到第二个kernel的入口. 感觉不必非得分配
> 到 crash reserved memory 中.
>
> 在之后的流程中,我们会展开分析跳转代码

前面我们提到, `kimage_file_prepare_segments()`仅为这些segment
分配内存, 但是还未copy. 在`kimage_load_segment()`流程中,才实际进行copy.

```cpp
int kimage_load_segment(struct kimage *image,
                                struct kexec_segment *segment)
{
        int result = -ENOMEM;

        switch (image->type) {
        case KEXEC_TYPE_DEFAULT:
                result = kimage_load_normal_segment(image, segment);
                break;
        case KEXEC_TYPE_CRASH:
                result = kimage_load_crash_segment(image, segment);
                break;
        }

        return result;
}

static int kimage_load_crash_segment(struct kimage *image,
                                        struct kexec_segment *segment)
{
        /* For crash dumps kernels we simply copy the data from
         * user space to it's destination.
         * We do things a page at a time for the sake of kmap.
         */
        unsigned long maddr;
        size_t ubytes, mbytes;
        int result;
        unsigned char __user *buf = NULL;
        unsigned char *kbuf = NULL;

        result = 0;
        if (image->file_mode)
                kbuf = segment->kbuf;
        else
                buf = segment->buf;
        ubytes = segment->bufsz;
        mbytes = segment->memsz;
        maddr = segment->mem;
        while (mbytes) {
                struct page *page;
                char *ptr;
                size_t uchunk, mchunk;

                page = boot_pfn_to_page(maddr >> PAGE_SHIFT);
                if (!page) {
                        result  = -ENOMEM;
                        goto out;
                }
                arch_kexec_post_alloc_pages(page_address(page), 1, 0);
                //=============(1)=============
                ptr = kmap(page);
                ptr += maddr & ~PAGE_MASK;
                //=============(2)=============
                mchunk = min_t(size_t, mbytes,
                                PAGE_SIZE - (maddr & ~PAGE_MASK));
                //=============(3)=============
                uchunk = min(ubytes, mchunk);
                if (mchunk > uchunk) {
                        /* Zero the trailing part of the page */
                        memset(ptr + uchunk, 0, mchunk - uchunk);
                }

                /* For file based kexec, source pages are in kernel memory */
                //=============(4)=============
                if (image->file_mode)
                        memcpy(ptr, kbuf, uchunk);
                else
                        result = copy_from_user(ptr, buf, uchunk);
                //=============(4)=============
                kexec_flush_icache_page(page);
                kunmap(page);
                arch_kexec_pre_free_pages(page_address(page), 1);
                if (result) {
                        result = -EFAULT;
                        goto out;
                }
                ubytes -= uchunk;
                maddr  += mchunk;
                if (image->file_mode)
                        kbuf += mchunk;
                else
                        buf += mchunk;
                mbytes -= mchunk;

                cond_resched();
        }
out:
        return result;
}
```
了解这个函数之前,我们先了解里面涉及到的局部变量
* ubytes: 还未copy的 buf
* mbytes: 还未copy的 mem 
* uchunk: 从buf中读取, 并且要写入的数据
* mchunk: 写入的数据 (mchunk 可能 比 uchunk大)

我们来看代码
1. 当访问`mem`时,需要通过kmap进行映射.
2. 如果写入的是`mem` 的第一个页面, 而`maddr` 不一定位于页面开始部分,
那么写入区间为 `[maddr, this page + PAGE_SIZE]`
3. 而uchunk取值为`min(ubytes, mchunk)`, 如果`ubytes < mchunk`, 需要
将剩余的部分初始化为0
4. 前面提到过如果是 `kexec_file_load`则复制`kbuf`
5. 这里居然需要`flush icache`, 也是不太懂, 因为该页面是`crash reserved memory`,
不会作为代码段运行代码, 我能想到的是, 可能预测执行会执行到? 这样就产生了`icache`


> NOTE
>
> mem : 表示 crash reserved memory<br/>
> buf : 表示 用户空间传过来的内存 / kernel侧通过fd读取的内存,或者临时存放数据的(例如dtb)

#### kimage_file_post_load_cleanup
```cpp
/*
 * Free up memory used by kernel, initrd, and command line. This is temporary
 * memory allocation which is not needed any more after these buffers have
 * been loaded into separate segments and have been copied elsewhere.
 */
void kimage_file_post_load_cleanup(struct kimage *image)
{
        struct purgatory_info *pi = &image->purgatory_info;

        vfree(image->kernel_buf);
        image->kernel_buf = NULL;

        vfree(image->initrd_buf);
        image->initrd_buf = NULL;

        kfree(image->cmdline_buf);
        image->cmdline_buf = NULL;

        vfree(pi->purgatory_buf);
        pi->purgatory_buf = NULL;

        vfree(pi->sechdrs);
        pi->sechdrs = NULL;

#ifdef CONFIG_IMA_KEXEC
        vfree(image->ima_buffer);
        image->ima_buffer = NULL;
#endif /* CONFIG_IMA_KEXEC */

        /* See if architecture has anything to cleanup post load */
        arch_kimage_file_post_load_cleanup(image);

        /*
         * Above call should have called into bootloader to free up
         * any data stored in kimage->image_loader_data. It should
         * be ok now to free it up.
         */
        kfree(image->image_loader_data);
        image->image_loader_data = NULL;
}
```
由于这些buffer都是 kernel测自己申请的, 所以需要在 syscall 退出之前,释放
这些buffer.

至此, `kexec_file_load()`代码简单分析完了, 接下来, 我们看下panic 流程中是
如何跳转到 crash kernel的

### panic --> crash kernel
```cpp
void panic(const char *fmt, ...)
{
        ...
        /*
         * If we have crashed and we have a crash kernel loaded let it handle
         * everything else.
         * If we want to run this after calling panic_notifiers, pass
         * the "crash_kexec_post_notifiers" option to the kernel.
         *
         * Bypass the panic_cpu check and call __crash_kexec directly.
         */
        if (!_crash_kexec_post_notifiers) {
                printk_safe_flush_on_panic();
                __crash_kexec(NULL);
        
                /*
                 * Note smp_send_stop is the usual smp shutdown function, which
                 * unfortunately means it may not be hardened to work in a
                 * panic situation.
                 */
                smp_send_stop();
        } else {
        ...
}

/*
 * No panic_cpu check version of crash_kexec().  This function is called
 * only when panic_cpu holds the current CPU number; this is the only CPU
 * which processes crash_kexec routines.
 */
void __noclone __crash_kexec(struct pt_regs *regs)
{
        /* Take the kexec_mutex here to prevent sys_kexec_load
         * running on one cpu from replacing the crash kernel
         * we are using after a panic on a different cpu.
         *
         * If the crash kernel was not located in a fixed area
         * of memory the xchg(&kexec_crash_image) would be
         * sufficient.  But since I reuse the memory...
         */
        if (mutex_trylock(&kexec_mutex)) {
                if (kexec_crash_image) {
                        struct pt_regs fixed_regs;
                        //========(1)========
                        crash_setup_regs(&fixed_regs, regs);
                        //========(2)========
                        crash_save_vmcoreinfo();
                        //========(3)========
                        machine_crash_shutdown(&fixed_regs);
                        //========(4)========
                        machine_kexec(kexec_crash_image);
                }
                mutex_unlock(&kexec_mutex);
        }
}
```
1. 保存当前cpu 的 regs
2. 保存vmcoreinfo
3. 让其他cpu保存现场
4. 准备跳转

我们主要看下(3) (4) 

#### machine_crash_shutdown
```cpp
void machine_crash_shutdown(struct pt_regs *regs)
{
        local_irq_disable();
    
        //=======(1)========
        /* shutdown non-crashing cpus */
        crash_smp_send_stop();

        //=======(2)========
        /* for crashing cpu */
        crash_save_cpu(regs, smp_processor_id());
        machine_kexec_mask_interrupts();

        pr_info("Starting crashdump kernel...\n");
}
```
1. 让其他cpu停下来, 保存cpu现场
2. 保存当前regs到`crash_note`

我们先看下是如何通知其他cpu,并且其他cpu是怎么处理的:
```cpp
void crash_smp_send_stop(void)
{
        static int cpus_stopped;
        cpumask_t mask;
        unsigned long timeout;

        /*
         * This function can be called twice in panic path, but obviously
         * we execute this only once.
         */
        if (cpus_stopped)
                return;

        cpus_stopped = 1;

        if (num_online_cpus() == 1) {
                sdei_mask_local_cpu();
                return;
        }
        //========(1)==========
        cpumask_copy(&mask, cpu_online_mask);
        cpumask_clear_cpu(smp_processor_id(), &mask);

        //========(2)==========
        atomic_set(&waiting_for_crash_ipi, num_online_cpus() - 1);

        pr_crit("SMP: stopping secondary CPUs\n");
        //========(3)==========
        smp_cross_call(&mask, IPI_CPU_CRASH_STOP);

        /* Wait up to one second for other CPUs to stop */
        timeout = USEC_PER_SEC;
        //========(2.1)==========
        while ((atomic_read(&waiting_for_crash_ipi) > 0) && timeout--)
                udelay(1);

        //========(4)==========
        if (atomic_read(&waiting_for_crash_ipi) > 0)
                pr_warn("SMP: failed to stop secondary CPUs %*pbl\n",
                        cpumask_pr_args(&mask));

        sdei_mask_local_cpu();
}
```
1. 只发送给 online cpu
2. 这里cpu会等待其他cpu 相应该通知, 在其他cpu的流程中会dec该变量
    1. (2.1) 这里会设置一个超时时间,避免该流程被hung住的cpu 阻塞(关中断了)
3. 发送ipi中断通知其他cpu
4. 如果超时了,并且还有cpu 没有做这个接收到中断, 则会打印下面的报错, 打印出
哪些CPU没有回应该中断.

我们来看下对于中断的处理流程:

```cpp
void handle_IPI(int ipinr, struct pt_regs *regs)
{
        ...
        case IPI_CPU_CRASH_STOP:
                if (IS_ENABLED(CONFIG_KEXEC_CORE)) {
                        irq_enter();
                        ipi_cpu_crash_stop(cpu, regs);
                
                        unreachable();
                }
                break; 
        ...
}

static void ipi_cpu_crash_stop(unsigned int cpu, struct pt_regs *regs)
{
#ifdef CONFIG_KEXEC_CORE
        //=============(1)==============
        crash_save_cpu(regs, cpu);
        //=============(2)==============
        atomic_dec(&waiting_for_crash_ipi);

        //=============(3)==============
        local_irq_disable();
        sdei_mask_local_cpu();

#ifdef CONFIG_HOTPLUG_CPU
        if (cpu_ops[cpu]->cpu_die)
                cpu_ops[cpu]->cpu_die(cpu);
#endif

        //=============(4)==============
        /* just in case */
        cpu_park_loop();
#endif
}
```

1. 同发起的cpu, 这里同样会调用`crash_save_cpu`
2. dec `waiting_for_crash_ipi`
3. 关闭中断
4. 我们先不看`CONFIG_HOTPLUG_CPU`的流程,对于`cpu_park_loop()`比较简单,就是
循环执行低功耗指令
```cpp
static inline void cpu_park_loop(void)
{
        for (;;) {
                wfe();
                wfi();
        }
}
```

我们回头再看下 `crash_save_cpu`:

```cpp
void crash_save_cpu(struct pt_regs *regs, int cpu)
{
        struct elf_prstatus prstatus;
        u32 *buf;

        if ((cpu < 0) || (cpu >= nr_cpu_ids))
                return;

        /* Using ELF notes here is opportunistic.
         * I need a well defined structure format
         * for the data I pass, and I need tags
         * on the data to indicate what information I have
         * squirrelled away.  ELF notes happen to provide
         * all of that, so there is no need to invent something new.
         */
        //========(1)===========
        buf = (u32 *)per_cpu_ptr(crash_notes, cpu);
        if (!buf)
                return;
        memset(&prstatus, 0, sizeof(prstatus));
        prstatus.pr_pid = current->pid;
        //========(2)===========
        elf_core_copy_kernel_regs(&prstatus.pr_reg, regs);
        //========(3)===========
        buf = append_elf_note(buf, KEXEC_CORE_NOTE_NAME, NT_PRSTATUS,
                              &prstatus, sizeof(prstatus));
        final_note(buf);
}
```

1. 存储该信息的是per_cpu变量, 但是该变量的地址已经存储到了 elfcorehdr中,
(这部分不再展开,我们看下, 该变量中存储了哪些内容
2. 这里实际上就是copy regs, 不再展开
3. 代码如下:
```cpp
Elf_Word *append_elf_note(Elf_Word *buf, char *name, unsigned int type,
                          void *data, size_t data_len)
{
        struct elf_note *note = (struct elf_note *)buf;

        note->n_namesz = strlen(name) + 1;
        note->n_descsz = data_len;
        note->n_type   = type;
        buf += DIV_ROUND_UP(sizeof(*note), sizeof(Elf_Word));
        memcpy(buf, name, note->n_namesz);
        buf += DIV_ROUND_UP(note->n_namesz, sizeof(Elf_Word));
        memcpy(buf, data, data_len);
        buf += DIV_ROUND_UP(data_len, sizeof(Elf_Word));

        return buf;
}
```
代码比较简单,不再赘述. 

> NOTE
>
> prstatus.pr_reg 是保存的有ipi中断传递下来的pt_regs, 理论上不含
> 像`handle_ipi`的这样的堆栈, 但是, 在crash中执行`bt -a`却能够发现
> 这些堆栈, 如下:
> ```
>  #0 [ffff80001000fda0] crash_save_cpu at ffff8000101cb570
>  #1 [ffff80001000ff60] handle_IPI at ffff8000100959fc
>  #2 [ffff80001000ffd0] gic_handle_irq at ffff800010081844
> --- <IRQ stack> ---
>  #3 [ffff800011b6fe90] el1_irq at ffff8000100831b4
> ```
> 这里还不清楚是第二个kernel做的处理,还是crash工具处理的.
>
> 另外, 保存的信息仅有当前cpu的pt_regs信息,但是这样就足够还原
> 当时cpu的现场.(内存中的信息不会丢失,但是寄存器信息需要手动
> 保存下)


我们接下来看下`machine_kexec`代码
#### machine_kexec
```cpp
/**
 * machine_kexec - Do the kexec reboot.
 *
 * Called from the core kexec code for a sys_reboot with LINUX_REBOOT_CMD_KEXEC.
 */
void machine_kexec(struct kimage *kimage)
{
        phys_addr_t reboot_code_buffer_phys;
        void *reboot_code_buffer;
        bool in_kexec_crash = (kimage == kexec_crash_image);
        bool stuck_cpus = cpus_are_stuck_in_kernel();

        /*
         * New cpus may have become stuck_in_kernel after we loaded the image.
         */
        BUG_ON(!in_kexec_crash && (stuck_cpus || (num_online_cpus() > 1)));
        WARN(in_kexec_crash && (stuck_cpus || smp_crash_stop_failed()),
                "Some CPUs may be stale, kdump will be unreliable.\n");

        reboot_code_buffer_phys = page_to_phys(kimage->control_code_page);
        reboot_code_buffer = phys_to_virt(reboot_code_buffer_phys);

        ...

        /*
         * Copy arm64_relocate_new_kernel to the reboot_code_buffer for use
         * after the kernel is shut down.
         */
        //===============(1)=============
        memcpy(reboot_code_buffer, arm64_relocate_new_kernel,
                arm64_relocate_new_kernel_size);

        /* Flush the reboot_code_buffer in preparation for its execution. */
        __flush_dcache_area(reboot_code_buffer, arm64_relocate_new_kernel_size);

        /*
         * Although we've killed off the secondary CPUs, we don't update
         * the online mask if we're handling a crash kernel and consequently
         * need to avoid flush_icache_range(), which will attempt to IPI
         * the offline CPUs. Therefore, we must use the __* variant here.
         */
        __flush_icache_range((uintptr_t)reboot_code_buffer,
                             arm64_relocate_new_kernel_size);

        /* Flush the kimage list and its buffers. */
        kexec_list_flush(kimage);

        /* Flush the new image if already in place. */
        if ((kimage != kexec_crash_image) && (kimage->head & IND_DONE))
                kexec_segment_flush(kimage);

        pr_info("Bye!\n");

        local_daif_mask();

        /*
         * cpu_soft_restart will shutdown the MMU, disable data caches, then
         * transfer control to the reboot_code_buffer which contains a copy of
         * the arm64_relocate_new_kernel routine.  arm64_relocate_new_kernel
         * uses physical addressing to relocate the new image to its final
         * position and transfers control to the image entry point when the
         * relocation is complete.
         * In kexec case, kimage->start points to purgatory assuming that
         * kernel entry and dtb address are embedded in purgatory by
         * userspace (kexec-tools).
         * In kexec_file case, the kernel starts directly without purgatory.
         */
        //==============(2)============
        cpu_soft_restart(reboot_code_buffer_phys, kimage->head, kimage->start,
#ifdef CONFIG_KEXEC_FILE
                                                kimage->arch.dtb_mem);
#else
                                                0);
#endif

        BUG(); /* Should never get here. */
}
```
1. 这里涉及到之前提到的`control_code_page`, 将`arm64_relocate_new_kernel`
copy到该page中, 我们随后来看下该部分代码
2. 执行 cpu_soft_restart, 
    * reboot_code_buffer_phys: 刚提到的`control_code_page`的物理地址
    * kimage->head: 这个不太清楚作用
    * kimage->start: 第二个kernel入口地址
    * kimage->arch.dtb_mem : dtb的首地址

我们来看下`cpu_soft_restart`代码:
```cpp
static inline void __noreturn cpu_soft_restart(unsigned long entry,
                                               unsigned long arg0,
                                               unsigned long arg1,
                                               unsigned long arg2)
{
        typeof(__cpu_soft_restart) *restart;
    
        //============(1)============
        unsigned long el2_switch = !is_kernel_in_hyp_mode() &&
                is_hyp_mode_available();
        restart = (void *)__pa_symbol(__cpu_soft_restart);
        //============(2)============
        cpu_install_idmap();
        restart(el2_switch, entry, arg0, arg1, arg2);
        unreachable();
}
```
1. 因为跳转进入kernel stext, 要运行到当前CPU支持的最高异常等级,所以
需要判断当前cpu支不支持 hyp_mode(el2) ,如果支持,当前cpu是不是hyp_mode,
如果不是hyp_mode, 则需要从el1切换到el2
2. cpu_install_idmap()是为了以idmap的方式映射`.idmap.text`段, 这个段在
系统启动初会建立好idmap映射.pgd 为`idmap_pg_dir`
```cpp
static inline void cpu_install_idmap(void)
{
        cpu_set_reserved_ttbr0();
        local_flush_tlb_all();
        cpu_set_idmap_tcr_t0sz();

        cpu_switch_mm(lm_alias(idmap_pg_dir), &init_mm);
}
static inline void cpu_switch_mm(pgd_t *pgd, struct mm_struct *mm)
{
        BUG_ON(pgd == swapper_pg_dir);
        cpu_set_reserved_ttbr0();
        cpu_do_switch_mm(virt_to_phys(pgd),mm);
}

ENTRY(cpu_do_switch_mm)
        mrs     x2, ttbr1_el1
        mmid    x1, x1                          // get mm->context.id
        phys_to_ttbr x3, x0                     //x3为x0为 phys_pgd

alternative_if ARM64_HAS_CNP
        cbz     x1, 1f                          // skip CNP for reserved ASID
        orr     x3, x3, #TTBR_CNP_BIT
1:
alternative_else_nop_endif
#ifdef CONFIG_ARM64_SW_TTBR0_PAN
        bfi     x3, x1, #48, #16                // set the ASID field in TTBR0
#endif
        bfi     x2, x1, #48, #16                // set the ASID
        msr     ttbr1_el1, x2                   // in TTBR1 (since TCR.A1 is set)
        isb
        //=====(1)======
        msr     ttbr0_el1, x3                   // now update TTBR0 
        isb
        b       post_ttbr_update_workaround     // Back to C code...
ENDPROC(cpu_do_switch_mm)
```

1. 最终可以发现仅更新了 `ttbr0_el1`, 这里是为什么呢?难道`.idmap.text`段就不能
   在高地址么, 还真不能. 这部分这里不再展开, 大家在这里只需要知道, `.idmap.text`
   一方面不大,另一方面只会加载到低内存
   > NOTE
   > 这里简单解释下, 为什么需要idmap, 因为代码需要关闭分页, 并且跳转到一个物理
   > 地址处, 关闭分页的这块代码必须是idmap的, 假如不是idmap, 虚拟地址和物理地址
   > 不同,在关闭分页后,还是采用ip++的方式取下一个ip, 这样就可能取道虚拟地址值的
   > 物理地址,从而访问了错误的页面(个人理解)

我们继续看下`restart`代码, `restart`指向`__cpu_soft_restart`, 这部分代码是在`.idmap.text`
段,作用是 根据条件切换el2, 并且关闭分页.我们来看下这部分代码:
```cpp
ENTRY(__cpu_soft_restart)
        /* Clear sctlr_el1 flags. */
        //===========(1)===========
        mrs     x12, sctlr_el1
        mov_q   x13, SCTLR_ELx_FLAGS
        bic     x12, x12, x13
        pre_disable_mmu_workaround
        msr     sctlr_el1, x12
        isb
        //===========(2)===========
        cbz     x0, 1f                          // el2_switch?
        mov     x0, #HVC_SOFT_RESTART
        hvc     #0                              // no return
        //===========(3)===========
1:      mov     x18, x1                         // entry
        mov     x0, x2                          // arg0
        mov     x1, x3                          // arg1
        mov     x2, x4                          // arg2
        br      x18
ENDPROC(__cpu_soft_restart)
```
1. 各个异常等级的资源是相互独立的,所以即使在需要切换
   到el2执行代码跳转的情况下,也需要关闭el1 的分页. 
   ```cpp
   #define SCTLR_ELx_FLAGS (SCTLR_ELx_M  | SCTLR_ELx_A | SCTLR_ELx_C | \
                            SCTLR_ELx_SA | SCTLR_ELx_I | SCTLR_ELx_IESB)
   ```
   `bic`指令会清除`x12`中的`x13`的相应bit, 并赋给`x12`, 那么可以看到
   将会关闭分页(`SCTLR_ELx_M`), disable cache(`SCTLR_ELx_C`)

2. 如果需要switch到el2的话, 调用hvc,  switch el2, 关于el2中
   el1_sync的入口可能有多个(也就是novhe情况下, vectors可能有多个),
   我们这里简单看其中一个
    ```cpp
    el1_sync:
            cmp     x0, #HVC_SET_VECTORS
            b.ne    2f
            msr     vbar_el2, x1
            b       9f
            //===========!!!================
    2:      cmp     x0, #HVC_SOFT_RESTART
            b.ne    3f
            mov     x0, x2
            mov     x2, x4
            mov     x4, x1
            mov     x1, x3
            br      x4                              // no return
    
    3:      cmp     x0, #HVC_RESET_VECTORS
            beq     9f                              // Nothing to reset!
    
            /* Someone called kvm_call_hyp() against the hyp-stub... */
            mov_q   x0, HVC_STUB_ERR
            eret
    
    9:      mov     x0, xzr
            eret
    ENDPROC(el1_sync)
    ```
    可以看到, 如果是`HVC_SOFT_RESTART`, 则最终也是会准备参数,
    并跳转到entry
    
    > NOTE
    >
    > 大家可以看到el2并没有关闭分页

3. 跳转到entry (`arm64_relocate_new_kernel`), 并完成传参


   我们接下来看下`entry`
   ```cpp
   /*
    * arm64_relocate_new_kernel - Put a 2nd stage image in place and boot it.
    *
    * The memory that the old kernel occupies may be overwritten when coping the
    * new image to its final location.  To assure that the
    * arm64_relocate_new_kernel routine which does that copy is not overwritten,
    * all code and data needed by arm64_relocate_new_kernel must be between the
    * symbols arm64_relocate_new_kernel and arm64_relocate_new_kernel_end.  The
    * machine_kexec() routine will copy arm64_relocate_new_kernel to the kexec
    * control_code_page, a special page which has been set up to be preserved
    * during the copy operation.
    */
   ENTRY(arm64_relocate_new_kernel)
   
           /* Setup the list loop variables. */
           mov     x18, x2                         /* x18 = dtb address */
           mov     x17, x1                         /* x17 = kimage_start */
           mov     x16, x0                         /* x16 = kimage_head */
           raw_dcache_line_size x15, x0            /* x15 = dcache line size */
           mov     x14, xzr                        /* x14 = entry ptr */
           mov     x13, xzr                        /* x13 = copy dest */
   
           /* Clear the sctlr_el2 flags. */
           mrs     x0, CurrentEL
           cmp     x0, #CurrentEL_EL2
           //=========(1)===========
           b.ne    1f
           mrs     x0, sctlr_el2
           mov_q   x1, SCTLR_ELx_FLAGS
           bic     x0, x0, x1
           pre_disable_mmu_workaround
           msr     sctlr_el2, x0
           isb
   1:
            //==========(2)==============   
           /* Check if the new image needs relocation. */
           tbnz    x16, IND_DONE_BIT, .Ldone

           ...

   .Ldone:
           /* wait for writes from copy_page to finish */
           dsb     nsh
           ic      iallu
           dsb     nsh
           isb
           //===========(3)============== 
           /* Start new image. */
           mov     x0, x18
           mov     x1, xzr
           mov     x2, xzr
           mov     x3, xzr
           br      x17

   ENDPROC(arm64_relocate_new_kernel)


   ```
   1. 如果是 el2 则会关闭分页,关闭cache(和上面一样)
   2. 这里会判断2nd image, 是否需要 relocation (根据`kimage->head`)
      判断,但是据我目前调试,arm64不会走到, 后续可能还需要看下
   3. 跳转到new image(第二个kernel的_head处: `add x13, x18, #0x16 --- MZ 
      --- pe_header`)

至此, 分析完第一个内核跳转到第二个内核流程

### 第二个kernel部分流程
第二个内核我们主要关注下, 他是怎么找到分配内存的. 同第一个kernel, 
其也会解析fdt中的`/chosen/uefi-mmap-start`路径下的各个region, 从而
建立起最初的memblock范围,但是 会在下面的函数中重新搞一下
```cpp
void __init arm64_memblock_init(void)
{
        s64 linear_region_size = PAGE_END - _PAGE_OFFSET(vabits_actual);

        /*
         * Corner case: 52-bit VA capable systems running KVM in nVHE mode may
         * be limited in their ability to support a linear map that exceeds 51
         * bits of VA space, depending on the placement of the ID map. Given
         * that the placement of the ID map may be randomized, let's simply
         * limit the kernel's linear map to 51 bits as well if we detect this
         * configuration.
         */
        if (IS_ENABLED(CONFIG_KVM) && vabits_actual == 52 &&
            is_hyp_mode_available() && !is_kernel_in_hyp_mode()) {
                pr_info("Capping linear region to 51 bits for KVM in nVHE mode on LVA capable hardware.\n");
                linear_region_size = min_t(u64, linear_region_size, BIT(51));
        }

        /* Handle linux,usable-memory-range property */
        fdt_enforce_memory_region();

        ...
}

static void __init fdt_enforce_memory_region(void)
{
        struct memblock_region reg = {
                .size = 0,
        };

        of_scan_flat_dt(early_init_dt_scan_usablemem, &reg);

        if (reg.size)
                memblock_cap_memory_range(reg.base, reg.size);
}

static int __init early_init_dt_scan_usablemem(unsigned long node,
                const char *uname, int depth, void *data)
{
        struct memblock_region *usablemem = data;
        const __be32 *reg;
        int len;

        if (depth != 1 || strcmp(uname, "chosen") != 0)
                return 0;
        //获取"linux,usable-memory-range" 节点下的base, size
        reg = of_get_flat_dt_prop(node, "linux,usable-memory-range", &len);
        if (!reg || (len < (dt_root_addr_cells + dt_root_size_cells)))
                return 1;

        usablemem->base = dt_mem_next_cell(dt_root_addr_cells, &reg);
        usablemem->size = dt_mem_next_cell(dt_root_size_cells, &reg);

        return 1;
}
```
我们再来看下`memblock_cap_memory_range()`
```cpp
void __init memblock_cap_memory_range(phys_addr_t base, phys_addr_t size)
{
        int start_rgn, end_rgn;
        int i, ret;

        if (!size)
                return;
        //===========(1)===========
        ret = memblock_isolate_range(&memblock.memory, base, size,
                                                &start_rgn, &end_rgn);
        if (ret)
                return;

        /* remove all the MAP regions */
        //===========(2)===========
        for (i = memblock.memory.cnt - 1; i >= end_rgn; i--)
                if (!memblock_is_nomap(&memblock.memory.regions[i]))
                        memblock_remove_region(&memblock.memory, i);

        for (i = start_rgn - 1; i >= 0; i--)
                if (!memblock_is_nomap(&memblock.memory.regions[i]))
                        memblock_remove_region(&memblock.memory, i);

        /* truncate the reserved regions */
        memblock_remove_range(&memblock.reserved, 0, base);
        memblock_remove_range(&memblock.reserved,
                        base + size, PHYS_ADDR_MAX);
}
```
1. 将这该rgn分离成一个单独的 `memblock_region`
2. 将`[start_rgn, end_reg]` 之外的memblock_region, 判断其是否 `memblock_is_nomap`,
   如果是则表示这部分内存,第一个, 第二个内核均不能分配, 则可以不移除"memblock.
   memory"

   如果该条件为假, 则表示第一个kernel可能映射了这部分内存, 则将其 移除"memblock.memory"

所以综上所述, 第二个内核会根据fdt 中`/chosen/linux,usable-memory-range`决定自己
可以分配的内存,而根据之前的分析, fdt的该字段会有第一个kernel初始化为预留内存的`base, size`
--- `crashk_res.start, crashk_res.end - crashk_res.start`

