# 简介
前面我们详细了解过, 关于 mmu-gather 最原始的patch, 那本文主要了解
关于flush tlb时, 要关于使用 full flush / partial flush 的相关演进.

这里说明下所谓的 tlb full/partial flush 
* tlb FULL flush: 刷新当前CPU 所有的 TLB
* partial flush: 以x86 为例, 可以通过 `invlpg` 指令刷新某一段va的相关tlb

> NOTE
>
> <font color="red">
>
> 以下将 tlb full flush 简称 **FF**
>
> tlb partial flush 简称 **PF**
> </font>

关于这两个flush tlb API(这个API来自早期的代码)
* FF: `flush_tlb_mm`
* PF: `flush_tlb_range`

这里, 我这边无法从性能的角度评估 full flush / partial flush 的优劣(主要是
功力不够)
> NOTE 
> 并不一定 partial flush 更能提升性能, 详细可以看之前写过的 PCID 的相关patch,
> 并且这个对性能的影响一方面跟软件设计相关, 另一方面跟架构强相关)

前文讲到过, mmu-gather 会在`free_pte()`之前`flush tlb`, 那么我们回忆下, ORG patch
是如何flush tlb的.
# ORG patch
前文我们讲到过, `mmu-gather`使用`tlb_finish_mmu()`做两件事情(非fast mode):
* flush tlb 
* 释放物理页面

代码如下:
```cpp
/* tlb_finish_mmu
 *      Called at the end of the shootdown operation to free up any resources
 *      that were required.  The page talbe lock is still held at this point.
 */
static inline void tlb_finish_mmu(struct free_pte_ctx *ctx, unsigned long start, unsigned long end)
{
        unsigned long i, nr;

        /* Handle the fast case first. */
        if (ctx->nr == ~0UL) {
                flush_tlb_range(ctx->mm, start, end);
                return;
        }
        nr = ctx->nr;
        ctx->nr = 0;
        if (nr)
                flush_tlb_range(ctx->mm, ctx->start_addr, ctx->end_addr);
        for (i=0; i < nr; i++) {
                pte_t pte = ctx->ptes[i];
                __free_pte(pte);
        }
}
```
可以看到是使用`flush_tlb_range()`接口, 是一个 `partial flush`, 当然,可能不同架构实现`partial flush`,
不同, 也不排除有的架构不支持, 只支持`full flush`(猜测的), 这里不再展开,大家可以
以 某一个架构展开(我自己验证过 i386, 是 partial flush)

# change PF -> FF
linus 在下面的patch中, 将 mmu-gather flush tlb 由 PF -> FF
```
commit 7c9d187e950db8c6fbccc9e260b2ed6779845f6d (HEAD -> pmd_tlb_shootdown)
Author: Linus Torvalds <torvalds@penguin.transmeta.com>
Date:   Wed May 15 03:13:39 2002 -0700

    First cut at proper TLB shootdown for page directory entries.
```
> NOTE
>
> 这个COMMIT SUBJECT 什么意思呢, 我思考良久, 未得出答案.
> 我们直接来看下面代码

该patch改动的点较多, 我们直入主题,先看 `PF -> FF`的相关改动.

## PF -> FF
```diff
-static inline void tlb_finish_mmu(struct free_pte_ctx *ctx, unsigned long start, unsigned long end)
+static inline void tlb_flush_mmu(mmu_gather_t *tlb, unsigned long start, unsigned long end)
 {
        unsigned long i, nr;

        /* Handle the fast case first. */
-       if (ctx->nr == ~0UL) {
-               flush_tlb_range(ctx->vma, start, end);
+       if (tlb->nr == ~0UL) {
+               flush_tlb_mm(tlb->mm);
                return;
        }
-       nr = ctx->nr;
-       ctx->nr = 0;
+       nr = tlb->nr;
+       tlb->nr = 0;
        //====(2)====
        if (nr)
-               flush_tlb_range(ctx->vma, ctx->start_addr, ctx->end_addr);
+               flush_tlb_mm(tlb->mm);
        for (i=0; i < nr; i++) {
-               pte_t pte = ctx->ptes[i];
+               pte_t pte = tlb->ptes[i];
                __free_pte(pte);
        }
 }
+static inline void tlb_finish_mmu(mmu_gather_t *tlb, unsigned long start, unsigned long end)
+{
+       int freed = tlb->freed;
+       struct mm_struct *mm = tlb->mm;
+       int rss = mm->rss;
        //====(1)====
+       if (rss < freed)
+               freed = rss;
+       mm->rss = rss - freed;
+       tlb_flush_mmu(tlb, start, end);
+}
```
1. 新增了, 在原有 `tlb_finish_mmu()` 功能的基础上, 新增了对 本轮释放物理页面数目`freed`的处理,这里
涉及数据结构的改动, 我们下面会讲到.
2. 这里将 `flush_tlb_range()` -> `flush_tlb_mm()`, 为什么要这样改呢, 个人猜测可能linus认为,
partial flush的代价要比full flush要大.(因为我们下面会看到, 某些函数调用`tlb_finish_mmu()`
的范围就是整个进程的虚拟地址空间)

## 数据结构变动
```cpp
 typedef struct free_pte_ctx {
-       struct vm_area_struct   *vma;
+       struct mm_struct        *mm;
        unsigned long           nr;     /* set to ~0UL means fast mode */
-       unsigned long   start_addr, end_addr;
+       unsigned long           freed;
+       unsigned long           start_addr, end_addr;
        pte_t   ptes[FREE_PTE_NR];
 } mmu_gather_t;
```
* `vma -> mm`

  在 ORG patch中, 没有`vma`成员, 反而是 `mm`成员,做过 `mm -> vma`, 是在下面的patch:
  ```
  commit d694597ed5e1f6613d0933ee692333ab2542b603
  Author: Linus Torvalds <torvalds@athlon.transmeta.com>
  Date:   Tue Feb 5 00:13:42 2002 -0800
  
      v2.5.2 -> v2.5.2.1
  ```
  又是这种难搞的patchset, 我们这里 不展开太多, 看下`zap_page_range()`接口, 和 
  `mmu_gather_t`的改变:
  ```diff
  //FILE  include/linux/mm.h
  -extern void zap_page_range(struct mm_struct *mm, unsigned long address, unsigned long size);
  +extern void zap_page_range(struct vm_area_struct *vma, unsigned long address, unsigned long size);
  //FILE include/asm-generic/tlb.h
  typedef struct free_pte_ctx {
  -       struct mm_struct        *mm;
  +       struct vm_area_struct   *vma;
          unsigned long           nr;     /* set to ~0UL means fast mode */
          unsigned long   start_addr, end_addr;
          pte_t   ptes[FREE_PTE_NR];
  ```

  可以看到, `mmu_gahter_t`(`free_pte_ctx`) 变动的原因是因为其调用接口 `zap_page_range()`
  参数的变动.(当然变动的原因如上, 就是tlb_finish_mmu() flush的范围不再限于一个vma, 而是整个mm)

* add freed

  freed 会记录在该过程中释放的物理页面,从而在释放物理页面后,修改`mm->rss`, 将释放的物理页面
  数目减去
  ```diff
  @@ -432,25 +434,10 @@ void zap_page_range(struct vm_area_struct *vma, unsigned long address, unsigned
                  BUG();
          spin_lock(&mm->page_table_lock);
          flush_cache_range(vma, address, end);
  -       tlb = tlb_gather_mmu(vma);
  
  -       do {
  -               freed += zap_pmd_range(tlb, dir, address, end - address);
  -               address = (address + PGDIR_SIZE) & PGDIR_MASK;
  -               dir++;
  -       } while (address && (address < end));
  -
  -       /* this will flush any remaining tlb entries */
  +       tlb = tlb_gather_mmu(mm);
  +       unmap_page_range(tlb, vma, address, end);
          tlb_finish_mmu(tlb, start, end);
  -
  -       /*
  -        * Update rss for the mm_struct (not necessarily current->mm)
  -        * Notice that rss is an unsigned long.
  -        */
  -       if (mm->rss > freed)
  -               mm->rss -= freed;
  -       else
  -               mm->rss = 0;
          spin_unlock(&mm->page_table_lock);
   }
  ```

  可以看到, 在合入该patch之前, `zap_pmd_range()`会将该函数执行过程中想要free的
  page的数量以返回值返回. 然后在`tlb_flush_mmu()` 执行完成后,在 `mm->rss`中将该累计
  的值减去.

  那么 mmu_gather_t->freed什么时候处理呢?

  在 tlb_remove_page()中增加了该流程
  ```diff
  @@ -363,13 +362,6 @@ static inline int zap_pte_range(mmu_gather_t *tlb, pmd_t * pmd, unsigned long ad
                  if (pte_none(pte))
                          continue;
                  if (pte_present(pte)) {
  -                       struct page *page;
  -                       unsigned long pfn = pte_pfn(pte);
  -                       if (pfn_valid(pfn)) {
  -                               page = pfn_to_page(pfn);
  -                               if (!PageReserved(page))
  -                                       freed++;

  + static inline void tlb_remove_page(mmu_gather_t *tlb, pte_t *pte, unsigned long addr)
  + {
  +        struct page *page;
  +        unsigned long pfn = pte_pfn(*pte);
  + 
  +        if (pfn_valid(pfn)) {
  +                page = pfn_to_page(pfn);
  +                if (!PageReserved(page))
  +                        tlb->freed++;
  +        }
  +        ...

  ```
  而上面也提到了, 在 `tlb_finish_mmu`中, 会执行类似于`mm->rss -= freed`

那么, 我们接下来会看,做这些的目的是什么

## PURPOSE
之前的patch中, 在 zap_page_range()中执行 mmu-gather, 而在现在
zap_page_range() 是指针对一个vma, 所以要是zap多个vma, 就需要多次
调用mmu-gather, 该patch设计的目的就是为了在一次mmu-gather流程中,
处理多个vma

这也就能说明上面数据结构中为什么要`vma -> mm`,  我们来看下具体改动

* 抽象 `zap_page_range`中的非mmu-gather相关流程, 增加 `unmap_page_range` 接口
  ```diff
  +void unmap_page_range(mmu_gather_t *tlb, struct vm_area_struct *vma, unsigned long address, unsigned long e
  nd)
  +{
  +       pgd_t * dir;
  +
  +       if (address >= end)
  +               BUG();
  +       dir = pgd_offset(vma->vm_mm, address);
  +       tlb_start_vma(tlb, vma);
  +       do {
  +               zap_pmd_range(tlb, dir, address, end - address);
  +               address = (address + PGDIR_SIZE) & PGDIR_MASK;
  +               dir++;
  +       } while (address && (address < end));
  +       tlb_end_vma(tlb, vma);
   }
  @@ -432,25 +434,10 @@ void zap_page_range(struct vm_area_struct *vma, unsigned long address, unsigned
                  BUG();
          spin_lock(&mm->page_table_lock);
          flush_cache_range(vma, address, end);
  -       tlb = tlb_gather_mmu(vma);
  
  -       do {
  -               freed += zap_pmd_range(tlb, dir, address, end - address);
  -               address = (address + PGDIR_SIZE) & PGDIR_MASK;
  -               dir++;
  -       } while (address && (address < end));
  -
  -       /* this will flush any remaining tlb entries */
  +       tlb = tlb_gather_mmu(mm);
  +       unmap_page_range(tlb, vma, address, end);
          tlb_finish_mmu(tlb, start, end);
  -
  -       /*
  -        * Update rss for the mm_struct (not necessarily current->mm)
  -        * Notice that rss is an unsigned long.
  -        */
  -       if (mm->rss > freed)
  -               mm->rss -= freed;
  -       else
  -               mm->rss = 0;
          spin_unlock(&mm->page_table_lock);
   }
  ```
* 有一些zap操作会跨多个vma, 不再调用zap_page_range, 而是采用
  ```
  tlb_gather_mmu()
  LOOP some VMA
  {
     unmap_page_range()
  }
  tlb_finish_mmu()
  ```
  例如:
  1. do_munmap()
     ```diff
      int do_munmap(struct mm_struct *mm, unsigned long addr, size_t len)
      {
     +       mmu_gather_t *tlb;
             struct vm_area_struct *mpnt, *prev, **npp, *free, *extra;
     
             if ((addr & ~PAGE_MASK) || addr > TASK_SIZE || len > TASK_SIZE-addr)
     @@ -933,7 +932,8 @@ int do_munmap(struct mm_struct *mm, unsigned long addr, size_t len)
                     rb_erase(&mpnt->vm_rb, &mm->mm_rb);
             }
             mm->mmap_cache = NULL;  /* Kill the cache. */
     -       spin_unlock(&mm->page_table_lock);
     +
     +       tlb = tlb_gather_mmu(mm);
     
             /* Ok - we have the memory areas we should free on the 'free' list,
              * so release them, and unmap the page range..
     @@ -942,7 +942,7 @@ int do_munmap(struct mm_struct *mm, unsigned long addr, size_t len)
              * In that case we have to be careful with VM_DENYWRITE.
              */
             while ((mpnt = free) != NULL) {
     -               unsigned long st, end, size;
     +               unsigned long st, end;
                     struct file *file = NULL;
     
                     free = free->vm_next;
     @@ -950,7 +950,6 @@ int do_munmap(struct mm_struct *mm, unsigned long addr, size_t len)
                     st = addr < mpnt->vm_start ? mpnt->vm_start : addr;
                     end = addr+len;
                     end = end > mpnt->vm_end ? mpnt->vm_end : end;
     -               size = end - st;
     
                     if (mpnt->vm_flags & VM_DENYWRITE &&
                         (st != mpnt->vm_start || end != mpnt->vm_end) &&
     @@ -960,12 +959,12 @@ int do_munmap(struct mm_struct *mm, unsigned long addr, size_t len)
                     remove_shared_vm_struct(mpnt);
                     mm->map_count--;
     
     -               zap_page_range(mpnt, st, size);
     +               unmap_page_range(tlb, mpnt, st, end);
     
                     /*
                      * Fix the mapping, and free the old area if it wasn't reused.
                      */
     -               extra = unmap_fixup(mm, mpnt, st, size, extra);
     +               extra = unmap_fixup(mm, mpnt, st, end-st, extra);
                     if (file)
                             atomic_inc(&file->f_dentry->d_inode->i_writecount);
             }
     @@ -976,6 +975,8 @@ int do_munmap(struct mm_struct *mm, unsigned long addr, size_t len)
                     kmem_cache_free(vm_area_cachep, extra);
     
             free_pgtables(mm, prev, addr, addr+len);
     +       tlb_finish_mmu(tlb, addr, addr+len);
     +       spin_unlock(&mm->page_table_lock);
     
             return 0;
      }

     ```
  2. exit_mmap
     ```diff
      void exit_mmap(struct mm_struct * mm)
      {
     +       mmu_gather_t *tlb;
             struct vm_area_struct * mpnt;
     
             release_segments(mm);
     @@ -1100,16 +1102,16 @@ void exit_mmap(struct mm_struct * mm)
             mm->mmap = mm->mmap_cache = NULL;
             mm->mm_rb = RB_ROOT;
             mm->rss = 0;
     -       spin_unlock(&mm->page_table_lock);
             mm->total_vm = 0;
             mm->locked_vm = 0;
     
     +       tlb = tlb_gather_mmu(mm);
     +
             flush_cache_mm(mm);
             while (mpnt) {
                     struct vm_area_struct * next = mpnt->vm_next;
                     unsigned long start = mpnt->vm_start;
                     unsigned long end = mpnt->vm_end;
     -               unsigned long size = end - start;
     
                     if (mpnt->vm_ops) {
                             if (mpnt->vm_ops->close)
     @@ -1117,19 +1119,20 @@ void exit_mmap(struct mm_struct * mm)
                     }
                     mm->map_count--;
                     remove_shared_vm_struct(mpnt);
     -               zap_page_range(mpnt, start, size);
     +               unmap_page_range(tlb, mpnt, start, end);
                     if (mpnt->vm_file)
                             fput(mpnt->vm_file);
                     kmem_cache_free(vm_area_cachep, mpnt);
                     mpnt = next;
             }
     -       flush_tlb_mm(mm);
     
             /* This is just debugging */
             if (mm->map_count)
                     BUG();
     
             clear_page_tables(mm, FIRST_USER_PGD_NR, USER_PTRS_PER_PGD);
     +       tlb_finish_mmu(tlb, FIRST_USER_PGD_NR*PGDIR_SIZE, USER_PTRS_PER_PGD*PGDIR_SIZE);
     +       spin_unlock(&mm->page_table_lock);
      }
     ```

可以看到ORG patch, 只支持FF, 现在加了这个patch之后,只支持 PF, 那么能两个都支持么?
可以, 我们来看下面的patch

# support FF && PF both
Patch 信息:
```
commit e403d5b9233407f17836c1fdda1febd3a2912b7a
Author: David S. Miller <davem@nuts.ninka.net>
Date:   Thu Jun 6 10:53:51 2002 -0700

    TLB gather: Distinguish between full-mm and partial-mm flushes.
```

## 数据结构变动
```cpp
diff --git a/include/asm-generic/tlb.h b/include/asm-generic/tlb.h
index f6a028acdeb..8a2f3ac45b7 100644
--- a/include/asm-generic/tlb.h
+++ b/include/asm-generic/tlb.h
@@ -22,7 +22,7 @@
  */
 #ifdef CONFIG_SMP
   #define FREE_PTE_NR  507
-  #define tlb_fast_mode(tlb) ((tlb)->nr == ~0UL)
+  #define tlb_fast_mode(tlb) ((tlb)->nr == ~0U)
 #else
   #define FREE_PTE_NR  1
   #define tlb_fast_mode(tlb) 1
@@ -35,7 +35,8 @@
  */
 typedef struct free_pte_ctx {
        struct mm_struct        *mm;
-       unsigned long           nr;     /* set to ~0UL means fast mode */
+       unsigned int            nr;     /* set to ~0U means fast mode */
+       unsigned int            fullmm; /* non-zero means full mm flush */
        unsigned long           freed;
        struct page *           pages[FREE_PTE_NR];
 } mmu_gather_t;
```

* `unsigned long nr` -> `unsigned int nr`: 这里作者未说明缘由, 只能猜测
  作者是不是想让 nr的大小固定, 而不是随不同arch变动 (^ ^)
* fullmm: 这其实是一个bool类型的数据,表示是 FF, 还是 PF
  + 0:      FF
  + != 0:   PF

我们来看下, 相关函数/接口变动:
> NOTE
>
> 在该patch合入之前 tlb_flush_mmu变动如下:
> ```diff
> tlb_flush_mmu () {
>   ...
> + flush_tlb_mm
> - tlb_flush
>   ...
> }
> ```

* tlb_gather_mmu
  ```diff
  -static inline mmu_gather_t *tlb_gather_mmu(struct mm_struct *mm)
  +static inline mmu_gather_t *tlb_gather_mmu(struct mm_struct *mm, unsigned int full_mm_flush)
   {
          mmu_gather_t *tlb = &mmu_gathers[smp_processor_id()];
  
          tlb->mm = mm;
  -       tlb->freed = 0;
  
          /* Use fast mode if only one CPU is online */
          tlb->nr = smp_num_cpus > 1 ? 0UL : ~0UL;
  +
  +       tlb->fullmm = full_mm_flush;
  +       tlb->freed = 0;
  +
          return tlb;
   }
  ```

  在调用`tlb_gather_mmu`初始化时, 可以指定 `fullmm`, 使其之后的, tlb_flush(), 选择FF 还是 PF
* tlb_gather_mmu 调用者
  ```diff
  diff --git a/mm/memory.c b/mm/memory.c
  index ff1be5c5afb..2525d544e91 100644
  --- a/mm/memory.c
  +++ b/mm/memory.c
  @@ -427,7 +427,7 @@ void zap_page_range(struct vm_area_struct *vma, unsigned long address, unsigned
          spin_lock(&mm->page_table_lock);
          flush_cache_range(vma, address, end);
  
  -       tlb = tlb_gather_mmu(mm);
  +       tlb = tlb_gather_mmu(mm, 0);
          unmap_page_range(tlb, vma, address, end);
          tlb_finish_mmu(tlb, start, end);
          spin_unlock(&mm->page_table_lock);
  diff --git a/mm/mmap.c b/mm/mmap.c
  index d6f010bb8e8..4c884e4bcb6 100644
  --- a/mm/mmap.c
  +++ b/mm/mmap.c
  @@ -848,7 +848,7 @@ static void unmap_region(struct mm_struct *mm,
   {
          mmu_gather_t *tlb;
  
  -       tlb = tlb_gather_mmu(mm);
  +       tlb = tlb_gather_mmu(mm, 0);
  
          do {
                  unsigned long from, to;
  @@ -1105,7 +1105,7 @@ void exit_mmap(struct mm_struct * mm)
          release_segments(mm);
          spin_lock(&mm->page_table_lock);
  
  -       tlb = tlb_gather_mmu(mm);
  +       tlb = tlb_gather_mmu(mm, 1);
  
          flush_cache_mm(mm);
          mpnt = mm->mmap;

  ```
  除了 `exit_mmap` 使用 FF, 其余的流程(`zap_page_range`,`unmap_region`)都使用
  PF

  也就是说作者想根据实际情况, 如果真的是要flush全部, 那么在这则使用 FF, 
  否则则是用PF(能使用PF就是用PF), 

* flush_tlb
  ```diff
  --- a/include/asm-sparc64/tlb.h
  +++ b/include/asm-sparc64/tlb.h
  @@ -1,14 +1,23 @@
   #ifndef _SPARC64_TLB_H
   #define _SPARC64_TLB_H
  //之前是总是使用 FF
  -#define tlb_flush(tlb)         flush_tlb_mm((tlb)->mm)
  /*
   * 现在根据情况,只有在 tlb->fullmm为真的情况下使用 FF,
   * 其余情况都只使用PF, 但是这里这里并没有调用 PF的接口
   * 其实际实在 tlb_end_vma中做的
   */
  +#define tlb_flush(tlb)                 \
  +do {   if ((tlb)->fullmm)              \
  +               flush_tlb_mm((tlb)->mm);\
  +} while (0)
  
   #define tlb_start_vma(tlb, vma) \
  -       flush_cache_range(vma, vma->vm_start, vma->vm_end)
  -#define tlb_end_vma(tlb, vma) \
  -       flush_tlb_range(vma, vma->vm_start, vma->vm_end)
  +do {   if (!(tlb)->fullmm)     \
  +               flush_cache_range(vma, vma->vm_start, vma->vm_end); \
  +} while (0)
  
  -#define tlb_remove_tlb_entry(tlb, pte, address) do { } while (0)
  /*
   * 如果判断 tlb->fullmm是假, 说明不要FF, 会进行PF
   */
  +#define tlb_end_vma(tlb, vma)  \
  +do {   if (!(tlb)->fullmm)     \
  +               flush_tlb_range(vma, vma->vm_start, vma->vm_end); \
  +} while (0)
  +
  +#define tlb_remove_tlb_entry(tlb, pte, address) \
  +       do { } while (0)
  ```

  > NOTE
  >
  > 1. 在当前patch下,只有 sparc64 架构会判断使用PF / FF.
  > 2. 具体为什么这么做呢, 猜测作者做了性能评估, 在sparc64 架构下,
  >    FF 相比PF 性能损失有点大.
# other ARCH
## x86_64
相关commit:
```
commit 611ae8e3f5204f7480b3b405993b3352cfa16662
Author: Alex Shi <alex.shi@linux.alibaba.com>
Date:   Thu Jun 28 09:02:22 2012 +0800

    x86/tlb: enable tlb flush range support for x86

    Not every tlb_flush execution moment is really need to evacuate all
    TLB entries, like in munmap, just few 'invlpg' is better for whole
    process performance, since it leaves most of TLB entries for later
    accessing.
```
代码改动
```diff
diff --git a/arch/x86/include/asm/tlb.h b/arch/x86/include/asm/tlb.h
index 829215fef9ee..4fef20773b8f 100644
--- a/arch/x86/include/asm/tlb.h
+++ b/arch/x86/include/asm/tlb.h
@@ -4,7 +4,14 @@
 #define tlb_start_vma(tlb, vma) do { } while (0)
 #define tlb_end_vma(tlb, vma) do { } while (0)
 #define __tlb_remove_tlb_entry(tlb, ptep, address) do { } while (0)
-#define tlb_flush(tlb) flush_tlb_mm((tlb)->mm)
+
+#define tlb_flush(tlb)                                                 \
+{                                                                      \
+       if (tlb->fullmm == 0)                                           \
+               flush_tlb_mm_range(tlb->mm, tlb->start, tlb->end, 0UL); \
+       else                                                            \
+               flush_tlb_mm_range(tlb->mm, 0UL, TLB_FLUSH_ALL, 0UL);   \
+}

 #include <asm-generic/tlb.h>
```
> NOTE
>
> 该改动也是非常晚了, 作者在 COMMIT MESSAGE中 做了详细的性能分析. 我们这里由于
> 时间关系, 暂不分析
>
> !!!!!!!!
> !!!!!!!!
> 遗留问题
> !!!!!!!!
> !!!!!!!!

## arm64
