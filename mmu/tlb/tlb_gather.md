# ORG PATCH 
```
commit a27c6530ff12bab100e64c5b43e84f759fa353ae
Author: Linus Torvalds <torvalds@athlon.transmeta.com>
Date:   Mon Feb 4 20:19:13 2002 -0800

    v2.4.9.12 -> v2.4.9.13

      - Manfred Spraul: /proc/pid/maps cleanup (and bugfix for non-x86)
      - Al Viro: "block device fs" - cleanup of page cache handling
      - Hugh Dickins: VM/shmem cleanups and swap search speedup
      - David Miller: sparc updates, soc driver typo fix, net updates
      - Jeff Garzik: network driver updates (dl2k, yellowfin and tulip)
      - Neil Brown: knfsd cleanups and fixues
      - Ben LaHaise: zap_page_range merge from -ac
```

该patch比较大, 合入的功能较多, 我们只能从中截取改动: 

首先说下该功能引入的目的:

在刷相关虚拟内存区域tlb之前，绝对不能先释放物理页面，否则可能导致不正确
的结果，而mmu-gather（mmu积聚）的作用就是保证这种顺序, 所以正确的解除
映射的顺序是:
1) 解除页表映射
2) 刷新相关tlb
3) 释放物理页面

> NOTE
>
> 1. gather 有收集, 聚集, 积聚的意思, 大概就是要将集中处理mmu 相关流程
> 2. 我们需要思考下, 非SMP(单核)或者单线程 会不会遇到这个情况, 答案是不会.
>    (我们这里先不考虑 kswapd 回收内存)
>
>    我们通过系统调用进入 内核进行unmap 操作, 此时由于是串行执行, 所以
>    进入系统调用后,不再会有用户态代码可以访问将要解除映射的page, 所以
>    该功能主要是为了 SMP 下的多线程, 举个没有mmu-gather的例子:
>    ```
>    CPU 0                  CPU 1               CPU 2
>    运行进程A的线程a1      运行进程A的线程a2     运行进程B
>    madvise(donnotneed)
>    解除页表映射
>    释放物理页面
>                                               申请到CPU 0释放的物理页面
>                           由于没有刷新tlb
>                           访问到old map, 
>                           此时 CPU1 访问到
>                           CPU2 申请的物理页
>                           面
>    刷新tlb
>    ```

在了解mmu-gather的实现之前, 我们简单看下`zap_page_range()`的流程
一般为:
```
zap_page_range {
  while()
    zap_pmd_range()
      while()
        zap_pte_range()
           while() {
             解除映射
           }
}
```
那么可能有同学会说,那直接在 `zap_pte_range()`把所有事情都干了不行么:
```
zap_pte_range() {
    1. 解除映射
    2. 刷新相关tlb
    3. 释放物理页面
}
```
也不是不行, 主要就是在`2. 刷新相关tlb`流程上,可能要花费大量的时间.
为什么? 

如果是SMP架构, 多线程程序, 刷新tlb 不仅要刷新当前CPU的(这个简单,
只需要执行一条指令即可), 而且要刷新其他CPU的, 在 x86 架构下, 没有invalidate
其他cpu tlb 的操作,所以需要软件辅助完成, 该过程叫做tlb shootdown, 
该过程比较复杂大致为:
```
CPU 0                           CPU 1
发起 tlb shootdown

向其他CPU发送IPI, 让
这些CPU 停下来去flush 
tlb
                                收到ipi中断
                                flush tlb
tlb shootdown 完成
```
可以看到一次tlb shootdown 的代价还是很大的. 我们看下 zap_page_range
的定义:
```cpp
void zap_page_range(struct mm_struct *mm, unsigned long address, unsigned long size)
```
可以看到其zap range为`[address, address + size]`, 那么集中做一次tlb shootdown 
就能大大提升效率.
```
zap_page_range {
   while {
     zap_pmd_range
        解除映射
   }
   flush tlb
}
```
那么, 释放物理页面在哪里执行呢, 只能在 flush tlb后面,就变成了
```
zap_page_range {
   while {
     zap_pmd_range
        解除映射
   }
   flush tlb
   释放物理页面
}
```

我们理解了这个之后,再来简单介绍下 mmu-gather的作用:
其目的就是为了记录在`zap_page_range()`过程中, 需要释放的所有
的page, 然后集中在 flush tlb 后面释放.


## 相关数据结构
```cpp
// FILE: include/asm-generic/tlb.h
/* mmu_gather_t is an opaque type used by the mm code for passing around any
 * data needed by arch specific code for tlb_remove_page.  This structure can
 * be per-CPU or per-MM as the page table lock is held for the duration of TLB
 * shootdown.
 * 
 * opaque: 不透明的
 *
 * mmu_gather_t 是mmu ocde 使用的不透明的类型, 用于为 tlb_remove_page 传递 arch
 * specific code 所需的任何数据. 该数据结构可以是 per-CPU 或者 per-MM, 因为在
 * TLB shootdown 期间, page table lock 是持有状态
 */
typedef struct free_pte_ctx {
        struct mm_struct        *mm;
        unsigned long           nr;     /* set to ~0UL means fast mode */
        unsigned long   start_addr, end_addr;
        pte_t   ptes[FREE_PTE_NR];
} mmu_gather_t;
```
可以看到数据结构的命名是 : free pte ctx, 所以该数据结构和pte的free相关.

* **nr**: nr 可以设置为 `~0UL`, 用于意味着要使用fast mode , 我们下面会解释
* **start_addr**, **end_addr**: 本次gather的flush tlb range
* **ptes**: 记录在本次解除映射过程中, 所有的要free的pte 集合

## global vars

* `mmu_gathers`
  ```cpp
  // FILE include/asm-generic/tlb.h
  /* Users of the generic TLB shootdown code must declare this storage space. */
  extern mmu_gather_t     mmu_gathers[NR_CPUS];
  ```
  这里只是 extern 一下, 需要在其他的`.c`文件中定义,

  我们以i386为例:
  ```cpp
  //FILE arch/i386/mm/init.c
  mmu_gather_t mmu_gathers[NR_CPUS];
  ```

## 相关代码流程
### tlb_gather_mmu
该函数用于获取 per-CPU 的 mmu_gather_t
```cpp
/* tlb_gather_mmu
 *      Return a pointer to an initialized mmu_gather_t.
 */
static inline mmu_gather_t *tlb_gather_mmu(struct mm_struct *mm)
{
        mmu_gather_t *tlb = &mmu_gathers[smp_processor_id()];

        tlb->mm = mm;
        /* Use fast mode if there is only one user of this mm (this process) */
        /*
         * 这里当mm->mm_users为1时, 说明是单线程, 前面介绍过, 单线程不需要
         * mmu-gather, 所以可以走fast mode
         */
        tlb->nr = (atomic_read(&(mm)->mm_users) == 1) ? ~0UL : 0UL;
        return tlb;
}
```
其代码主要完成两件事情
* 获取当前cpu的 `mmu_gather`
* 对其进行初始化(主要是初始化mm, nr)

## tlb_remove_page
```cpp
/* void tlb_remove_page(mmu_gather_t *tlb, pte_t *ptep, unsigned long addr)
 *      Must perform the equivalent to __free_pte(pte_get_and_clear(ptep)), while
 *      handling the additional races in SMP caused by other CPUs caching valid
 *      mappings in their TLBs.
 *
 *
 */
#define tlb_remove_page(ctxp, pte, addr) do {\
                /* Handle the common case fast, first. */\
                if ((ctxp)->nr == ~0UL) {\
                        //我们暂时可以理解为 释放物理页面
                        __free_pte(*(pte));\
                        //==(1)==
                        pte_clear((pte));\
                        break;\
                }\
                //如果是第一次使用mmu-gather记录pte, 记录start_addr
                if (!(ctxp)->nr) \
                        (ctxp)->start_addr = (addr);\
                //记录ptes, ptep_get_and_clear的作用是解除映射
                (ctxp)->ptes[(ctxp)->nr++] = ptep_get_and_clear(pte);\
                //记录end_addr
                (ctxp)->end_addr = (addr) + PAGE_SIZE;\
                /*
                 * 这里的流程也就说明了, 为什么要搞ctxp->start_addr,和
                 * ctxp->end_addr, 也就是说其过程可以因为下面的分支中断,
                 * 导致在此过程中可能提前调用 tlb_finish_mmu, 这时start, end
                 * 参数不再生效(0, 0), 而是使用 `ctxp->start_addr, ctxp->end_addr`
                 *
                 * 在介绍 tlb_finish_mmu函数中会再次说明
                 */
                if ((ctxp)->nr >= FREE_PTE_NR)\
                        tlb_finish_mmu((ctxp), 0, 0);\
        } while (0)
```
1. `pte_clear`
   ```cpp
   //FILE include/asm-i386/pgtable.h
   #define pte_clear(xp)   do { set_pte(xp, __pte(0)); } while (0)
   /* Rules for using set_pte: the pte being assigned *must* be
    * either not present or in a state where the hardware will
    * not attempt to update the pte.  In places where this is
    * not possible, use pte_get_and_clear to obtain the old pte
    * value and then use set_pte to update it.  -ben
    */
   static inline void set_pte(pte_t *ptep, pte_t pte)
   {
           ptep->pte_high = pte.pte_high;
           smp_wmb();
           ptep->pte_low = pte.pte_low;
   }
   //FILE include/asm-i386/page.h
   #define __pte(x) ((pte_t) { (x) } )
   ```

   `pte_clear()`目的是为了将指定的pte_t 设置为0, 不过其设置
   时, 不是原子变量, 这也就意味这kernel认为别的cpu 不会
   write 该pte

   另外如果`ctxp->nr` 是`~0`, 意味着可以走fast path, 直接
   释放物理页面, 而不需要将其记录, 在flush tlb 之后在释放
2. `ptep_get_and_clear`
   ```cpp
   //FILE include/asm-i386/pgtable-3level.h
   static inline pte_t ptep_get_and_clear(pte_t *ptep)
   {
           pte_t res;
   
           /* xchg acts as a barrier before the setting of the high bits */
           res.pte_low = xchg(&ptep->pte_low, 0);
           res.pte_high = ptep->pte_high;
           ptep->pte_high = 0;
   
           return res;
   }
   ```

   这里在获取 res.pte_low 时, 使用的是xchg 原子操作,但是注释中提到,
   该原子操作, 其实是为了扮演一个 barrier的角色, 而并非是为了保持原
   子性. (这还需要在理解下)

## tlb_finish_mmu
```cpp
/* tlb_finish_mmu
 *      Called at the end of the shootdown operation to free up any resources
 *      that were required.  The page talbe lock is still held at this point.
 */
static inline void tlb_finish_mmu(struct free_pte_ctx *ctx, unsigned long start, unsigned long end)
{
        unsigned long i, nr;

        /* Handle the fast case first. */
        /*
         * 在 tlb_remove_page 中 解释了 ctx->nr == ~0UL, 意味着可以走
         * fast path, 这时, 是没有用到mmu-gather的,所以直接使用参数
         * start, end 来flush tlb ,因为在 tlb_remove_pages 中已经释放了
         * 物理页, 所以这里可以直接返回
         */
        if (ctx->nr == ~0UL) {
                flush_tlb_range(ctx->mm, start, end);
                return;
        }
        /*
         * 下面的流程就是使用 mmu-gather的情形, 需要依次干以下两件事:
         * 1. flush tlb
         * 2. 释放物理页
         */
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

## 非SMP
我们来看下在没有`CONFIG_SMP`的情况下的代码:
```cpp
/* The uniprocessor functions are quite simple and are inline macros in an
 * attempt to get gcc to generate optimal code since this code is run on each
 * page in a process at exit.
 */
typedef struct mm_struct mmu_gather_t;

#define tlb_gather_mmu(mm)      (mm)
#define tlb_finish_mmu(tlb, start, end) flush_tlb_range(tlb, start, end)
#define tlb_remove_page(tlb, ptep, addr)        do {\
                pte_t __pte = *(ptep);\
                pte_clear(ptep);\
                __free_pte(__pte);\
        } while (0)
```
这里很有意思的是, 将`mmu_gather_t`直接定义为 `mm_struct`
这样在 tlb_finish_mmu() 宏定义中, 就可以直接将 tlb参数,传入
flush_tlb_range()
```cpp
//FILE include/asm-i386/pgalloc.h
static inline void flush_tlb_range(struct mm_struct *mm,
        unsigned long start, unsigned long end)
```

## 合入代码后的调用流程
大致如下:
```
zap_page_range {
  tlb_gather_mmu
  zap_pmd_range
    zap_pmd_range
      zap_pte_range
        tlb_remove_page 
          解除映射
  tlb_finish_mmu
    刷新tlb
    释放物理页
}
```

## 合入该patch之前的调用流程
有点好奇合入该patch之前的调用流程是什么样的:
我们简单看下:
```diff
 void zap_page_range(struct mm_struct *mm, unsigned long address, unsigned long size)
 {
+       mmu_gather_t *tlb;
        pgd_t * dir;
-       unsigned long end = address + size;
+       unsigned long start = address, end = address + size;
        int freed = 0;

        dir = pgd_offset(mm, address);
@@ -373,11 +376,18 @@ void zap_page_range(struct mm_struct *mm, unsigned long address, unsigned long s
        if (address >= end)
                BUG();
        spin_lock(&mm->page_table_lock);
+       flush_cache_range(mm, address, end);
+       tlb = tlb_gather_mmu(mm);
+
        do {
-               freed += zap_pmd_range(mm, dir, address, end - address);
+               freed += zap_pmd_range(tlb, dir, address, end - address);
                address = (address + PGDIR_SIZE) & PGDIR_MASK;
                dir++;
        } while (address && (address < end));
+
+       /* this will flush any remaining tlb entries */
+       tlb_finish_mmu(tlb, start, end);
```

```diff
-static inline int zap_pte_range(struct mm_struct *mm, pmd_t * pmd, unsigned long address, unsigned long size)
+static inline int zap_pte_range(mmu_gather_t *tlb, pmd_t * pmd, unsigned long address, unsigned long size)
 {
-       pte_t * pte;
-       int freed;
+       unsigned long offset;
+       pte_t * ptep;
+       int freed = 0;

        if (pmd_none(*pmd))
                return 0;
@@ -305,27 +306,29 @@ static inline int zap_pte_range(struct mm_struct *mm, pmd_t * pmd, unsigned long
                pmd_clear(pmd);
                return 0;
        }
-       pte = pte_offset(pmd, address);
-       address &= ~PMD_MASK;
-       if (address + size > PMD_SIZE)
-               size = PMD_SIZE - address;
-       size >>= PAGE_SHIFT;
-       freed = 0;
-       for (;;) {
-               pte_t page;
-               if (!size)
-                       break;
-               page = ptep_get_and_clear(pte);
-               pte++;
-               size--;
-               if (pte_none(page))
+       ptep = pte_offset(pmd, address);
+       offset = address & ~PMD_MASK;
+       if (offset + size > PMD_SIZE)
+               size = PMD_SIZE - offset;
+       size &= PAGE_MASK;
+       for (offset=0; offset < size; ptep++, offset += PAGE_SIZE) {
+               pte_t pte = *ptep;
+               if (pte_none(pte))
                        continue;
-               freed += free_pte(page);
+               if (pte_present(pte)) {
+                       freed ++;
+                       /* This will eventually call __free_pte on the pte. */
+                       tlb_remove_page(tlb, ptep, address + offset);
+               } else {
+                       swap_free(pte_to_swp_entry(pte));
+                       pte_clear(ptep);
+               }
        }
+
        return freed;
 }
@@ -357,8 +359,9 @@ static inline int zap_pmd_range(struct mm_struct *mm, pgd_t * dir, unsigned long
  */
```

# 参考链接
1. [ARM64内核源码解读：mmu-gather操作](https://zhuanlan.zhihu.com/p/527074218)
