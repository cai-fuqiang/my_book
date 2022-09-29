# 问题现象
在启用dpdk后，会出现进程oom的情况，并在一段时间之后，kernel
申请内存也会申请不到，最终导致系统panic.

# 调试信息获取
## vmcore-dmesg
[vmcore-dmesg.txt](./vmcore-dmesg.txt)

# 问题分析
## 对vmcore-dmesg分析
从上面信息可见，lru链表上并没有太多内存，而slab也没有占用太多，
而大页占用量较大，大概为（57+59*7+58*8）*512/1024=467G，
所以大概还有40多G的内存，不知道被谁占用，然而这些大页并没有被使用。
（每个node上的 hugepages_total== hugepages_free）。

## 通过vmcore进行分析
执行`kmem -i`
```
crash> kmem -i
                 PAGES        TOTAL      PERCENTAGE
    TOTAL MEM  8362460     510.4 GB         ----
         FREE       29       1.8 MB    0% of TOTAL MEM
         USED  8362431     510.4 GB   99% of TOTAL MEM
       SHARED   666625      40.7 GB    7% of TOTAL MEM
      BUFFERS        0            0    0% of TOTAL MEM
       CACHED     1328        83 MB    0% of TOTAL MEM
         SLAB    20234       1.2 GB    0% of TOTAL MEM

   TOTAL HUGE  7651328       467 GB         ----
    HUGE FREE  7651328       467 GB  100% of TOTAL HUGE

   TOTAL SWAP        0            0         ----
    SWAP USED        0            0    0% of TOTAL SWAP
    SWAP FREE        0            0    0% of TOTAL SWAP

 COMMIT LIMIT   355566      21.7 GB         ----
    COMMITTED     2120     132.5 MB    0% of TOTAL LIMIT
```
可以看到shared内存，占用大概40.7G，如果加上huge page 的大小（467G），
基本上等于系统内存大小，所以剩余的内存应该是shared内存。

## 在本地环境上调试(未发生oom)
在node-1 环境中执行crash, 查看当前内存使用情况
```
crash> kmem -i 
                 PAGES        TOTAL      PERCENTAGE
    TOTAL MEM  8362461     510.4 GB         ----
         FREE  1767677     107.9 GB   21% of TOTAL MEM
         USED  6594784     402.5 GB   78% of TOTAL MEM
       SHARED   206158      12.6 GB    2% of TOTAL MEM
      BUFFERS       90       5.6 MB    0% of TOTAL MEM
       CACHED   202899      12.4 GB    2% of TOTAL MEM
         SLAB    47364       2.9 GB    0% of TOTAL MEM

   TOTAL HUGE  6258688       382 GB         ----
    HUGE FREE    98304         6 GB    1% of TOTAL HUGE

   TOTAL SWAP        0            0         ----
    SWAP USED        0            0    0% of TOTAL SWAP
    SWAP FREE        0            0    0% of TOTAL SWAP

 COMMIT LIMIT  1051886      64.2 GB         ----
    COMMITTED   107260       6.5 GB   10% of TOTAL LIMIT
```

可以看到 shared内存大小大概为12.6G，
执行 echo 3 > /proc/sys/vm/drop_caches
```
crash> kmem -i
                 PAGES        TOTAL      PERCENTAGE
    TOTAL MEM  8362461     510.4 GB         ----
         FREE  1964837     119.9 GB   23% of TOTAL MEM
         USED  6397624     390.5 GB   76% of TOTAL MEM
       SHARED    19788       1.2 GB    0% of TOTAL MEM
      BUFFERS        2       128 KB    0% of TOTAL MEM
       CACHED    16601         1 GB    0% of TOTAL MEM
         SLAB    34582       2.1 GB    0% of TOTAL MEM

   TOTAL HUGE  6258688       382 GB         ----
    HUGE FREE    98304         6 GB    1% of TOTAL HUGE

   TOTAL SWAP        0            0         ----
    SWAP USED        0            0    0% of TOTAL SWAP
    SWAP FREE        0            0    0% of TOTAL SWAP

 COMMIT LIMIT  1051886      64.2 GB         ----
    COMMITTED   108299       6.6 GB   10% of TOTAL LIMIT
```
可以看到`CACHED`内存和`SHARED`内存都有明显下降(12G->1G)，
下降比例也基本相同，所以可以判断这个`CACHED`和`SHARED`
大部分是同一内存。

## 再次分析vmcore
从上面的信息可以看到，大部分的内存并没有在lru链表上，
我们来看下`page.lru.next`为`0xdead000000000100`的
page数量

> NOTE
>
> 关于 0xdead000000000100值
> ```
> ====arch/arm64/Kconfig
> config ILLEGAL_POINTER_VALUE
>         hex
>         default 0xdead000000000000
> ====include/linux/poison.h
> # define POISON_POINTER_DELTA _AC(CONFIG_ILLEGAL_POINTER_VALUE, UL)
> #define LIST_POISON1  ((void *) 0x100 + POISON_POINTER_DELTA)
> #define LIST_POISON2  ((void *) 0x200 + POISON_POINTER_DELTA)
> 
> ====include/linux/list.h
> static inline void list_del(struct list_head *entry)
> {
>         __list_del_entry(entry);
>         entry->next = LIST_POISON1;
>         entry->prev = LIST_POISON2;
> }
> ```
> 这个LIST_POISON1的赋值只在 `list del`相关函数中

```
crash> kmem -m lru.next |grep dead000 |wc -l
696512
```
通过计算可得
```
696512 * 64K = 42G
```
可以看到这个内存和kmem -i 中的内存很接近

通过类似的手段, 过滤了一部分内存最终找到了相关的page,
```
lru.next  flags  mapping  _mapcount  _refcount
dead000000000100  3dfffff000000000  0000000000000000  -1  0000ffff 45788
dead000000000100  39fffff000000000  0000000000000000  -1  0000ffff 47697
dead000000000100  35fffff000000000  0000000000000000  -1  0000ffff 47075
dead000000000100  31fffff000000000  0000000000000000  -1  0000ffff 47022
dead000000000100  2dfffff000000000  0000000000000000  -1  0000ffff 46971
dead000000000100  29fffff000000000  0000000000000000  -1  0000ffff 46808
dead000000000100  25fffff000000000  0000000000000000  -1  0000ffff 46892
dead000000000100  21fffff000000000  0000000000000000  -1  0000ffff 43058
dead000000000100  1dfffff000000000  0000000000000000  -1  0000ffff 36569
dead000000000100  19fffff000000000  0000000000000000  -1  0000ffff 38351
dead000000000100  15fffff000000000  0000000000000000  -1  0000ffff 37636
dead000000000100  11fffff000000000  0000000000000000  -1  0000ffff 30459
dead000000000100  0dfffff000000000  0000000000000000  -1  0000ffff 37683
dead000000000100  09fffff000000000  0000000000000000  -1  0000ffff 37898
dead000000000100  05fffff000000000  0000000000000000  -1  0000ffff 37757
dead000000000100  01fffff000000000  0000000000000000  -1  0000ffff 15744
dead000000000100  00fffff000000000  0000000000000000  -1  0000ffff 18305
```
最后一列是该行在整个文本中出现的次数
可以计算下最后一列的和
```
[root@node-1 wangfuqiang_copy]# cat dead.txt|awk 'BEGIN{SUM=0}{SUM=SUM+$6}END{print SUM}'
661713
```
代表的值约为:
```
661713 * 64 K= 40G
```
上面的page属性很相似`mapping=0,_mapcount=-1,_refcount=ffff`,
但是无法和`kmem -i`中提示的`SHARED`联系起来

## 查看crash源码, 了解SHARED计算方式
crash源码中，是通过调用`dump_kmeminfo()`
函数打印`kmem -i`输出
```cpp
static void
dump_kmeminfo(void)
{
	...
	struct meminfo meminfo;

	BZERO(&meminfo, sizeof(struct meminfo));
	meminfo.flags = GET_ALL;
	dump_mem_map(&meminfo);
	get_totalram = meminfo.get_totalram;
	shared_pages = meminfo.get_shared;
	get_buffers = meminfo.get_buffers;
	get_slabs = meminfo.get_slabs;
	...
	
	fprintf(fp, "%13s  %7ld  %11s  %3ld%% of TOTAL MEM\n",
	        "SHARED", shared_pages, pages_to_size(shared_pages, buf), pct);
	...
}
```

可以看到打印的值，是`meminfo.get_shared`, 而meminfo是一个局部变量，
在`dump_mem_map()`函数中初始化
```cpp
static void
dump_mem_map(struct meminfo *mi)
{
	...
	for (n = 0; n < vt->numnodes; n++) {
		...
		for (i = 0; i < node_size;
		    i++, pp += SIZE(page), phys += PAGESIZE()) {
			...
			flags = ULONG(pcache + OFFSET(page_flags));
			if (SIZE(page_flags) == 4)
			        flags &= 0xffffffff;
			count = UINT(pcache + OFFSET(page_count));

			switch (mi->flags)
			{
			...
			case GET_ALL:
			...
			case GET_TOTALRAM_PAGES:
			       if (vt->PG_reserved)
			               PG_reserved_flag = vt->PG_reserved;
			       else
			              PG_reserved_flag = v22 ?
			                     1 << v22_PG_reserved :
			                     1 << v24_PG_reserved;
			
			       if (flags & PG_reserved_flag) {
			              reserved++;
			       } else {
			               if ((int)count >
			                  (vt->flags & PGCNT_ADJ ? 0 : 1))
			                       shared++;
			       }
			       continue;
						
			}
		}
	}
	switch (mi->flags)
	{
	case GET_ALL:
	        mi->get_totalram = total_pages - reserved;
	        mi->get_shared = shared;
	        mi->get_buffers = buffers;
	        mi->get_slabs = slabs;
	        break;
	...	
	}
	...
}
```

可以代码比较多，不一一分析，可以看到当判断到`count > 0或者1`时，则会`shared++`
所以`SHARED`标识和`page._refcount`相关。

从上面过滤的信息可以看出`page._refcount = 0xffff`满足这一条件。

所以基本可以断定, 我们需要关注的page 就是上面列表中提到的那些page。

## 分析kernel源码
从上面信息可以看到`page._refcount = 0xffff`, 而kernel中设置`_refcount`的接口
为`set_page_count()`,`page_ref_add()`

### set_page_count
```cpp
static inline void set_page_count(struct page *page, int v)
{
        atomic_set(&page->_refcount, v);
        if (page_ref_tracepoint_active(__tracepoint_page_ref_set))
                __page_ref_set(page, v);
}
```

而这里的set的值为`0xffff`,查找kernel代码，发现只有一个函数会
设置`v`参数为非`0/1` ---- `page_frag_alloc()`
```cpp
void *page_frag_alloc(struct page_frag_cache *nc,
                      unsigned int fragsz, gfp_t gfp_mask)
{
        unsigned int size = PAGE_SIZE;
        struct page *page;
        int offset;
	...
	
	offset = nc->offset - fragsz;
        if (unlikely(offset < 0)) {
                page = virt_to_page(nc->va);

                if (!page_ref_sub_and_test(page, nc->pagecnt_bias))
                        goto refill;

#if (PAGE_SIZE < PAGE_FRAG_CACHE_MAX_SIZE)
                /* if size can vary use size else just use PAGE_SIZE */
                size = nc->size;
#endif
                /* OK, page count is 0, we can safely set it */
                set_page_count(page, size);

                /* reset page count bias and offset to start of new frag */
                nc->pagecnt_bias = size;
                offset = size - fragsz;
        }

        nc->pagecnt_bias--;
        nc->offset = offset;
	...
}
```
可以看到里面有一个重要的数据结构,`struct page_frag_cache`,

```cpp
//kernel 中定义:
struct page_frag_cache {
        void * va;
#if (PAGE_SIZE < PAGE_FRAG_CACHE_MAX_SIZE)
        __u16 offset;
        __u16 size;
#else
        __u32 offset;
#endif
        /* we maintain a pagecount bias, so that we dont dirty cache line
        ¦* containing page->_refcount every time we allocate a fragment.
        ¦*/
        unsigned int            pagecnt_bias;
        bool pfmemalloc;
};
```
在arm64 config中`PAGE_SIZE`为`65536`,所以，没有size成员，在`page_frag_alloc`流程中,
执行下面步骤
1. `size = PAGE_SIZE`
2. `set_page_count(page,size)`
3. `nc->pagecnt_bias = size`

而这里`page = virt_to_page(nc->va);`
所以 page所代表页的虚拟地址肯定是存放在nc->va中，search 可以search到。

page address 存放在`struct page_frag_cache`的0 offset, 我们尝试找一个特定的page来分析下:
```
crash> kmem -m lru.next,flags,mapping,_mapcount,_refcount|grep 3dfffff000000000|grep 0000ffff|head -3
ffff7fee5b008000  dead000000000100  3dfffff000000000  0000000000000000  -1  0000ffff
ffff7fee5b008040  dead000000000100  3dfffff000000000  0000000000000000  -1  0000ffff
ffff7fee5b008080  dead000000000100  3dfffff000000000  0000000000000000  -1  0000ffff

crash> kmem ffff7fee5b008000
      PAGE         PHYSICAL      MAPPING       INDEX CNT FLAGS
ffff7fee5b008000 37002000000                0        0 65535 3dfffff000000000
crash> ptov 37002000000
VIRTUAL           PHYSICAL
ffffb96c02000000  37002000000
crash> search ffffb96c02000000
crash>
```
可以看到search 该地址找不到，所以应该不是这个代码路径, 我们再继续验证下

而调用`page_frag_alloc()`的函数有以下几个, 基本上是驱动(wireless,nvme)和网络模块，这里
主要看下网络模块(因为场景业主要是在dpdk使用场景下
```
__napi_alloc_skb
__netdev_alloc_frag
__napi_alloc_frag
__netdev_alloc_skb
```
这里不展开代码，`__napi_alloc_skb`/`__napi_alloc_frag`使用的`struct page_frag_cache`
是per cpu 变量 `napi_alloc_cache`, 而`__netdev_alloc_frag`, `__netdev_alloc_skb`
使用的`struct page_frag_cache`是per cpu 变量`netdev_alloc_cache`

我们这里随意看几个`napi_alloc_cache` per cpu变量
```
PER-CPU DATA TYPE:
  struct napi_alloc_cache napi_alloc_cache;
PER-CPU ADDRESSES:
  [0]: ffffb707fde4cde0
  [1]: ffffb707fde7cde0
  [2]: ffffb707fdeacde0
  [3]: ffffb707fdedcde0
  ...
crash> struct page_frag_cache ffffb707fde4cde0
struct page_frag_cache {
  va = 0x0,
  offset = 0,
  pagecnt_bias = 0,
  pfmemalloc = false
}
crash> struct page_frag_cache ffffb707fde7cde0
struct page_frag_cache {
  va = 0x0,
  offset = 0,
  pagecnt_bias = 0,
  pfmemalloc = false
}
crash> struct page_frag_cache ffffb707fdeacde0
struct page_frag_cache {
  va = 0x0,
  offset = 0,
  pagecnt_bias = 0,
  pfmemalloc = false
}
crash> struct page_frag_cache ffffb707fdedcde0
struct page_frag_cache {
  va = 0x0,
  offset = 0,
  pagecnt_bias = 0,
  pfmemalloc = false
}
```
可见都是空的，我们再来看下`netdev_alloc_cache`
```
PER-CPU DATA TYPE:
  struct page_frag_cache netdev_alloc_cache;
PER-CPU ADDRESSES:
  [0]: ffffb707fde4d000
  [1]: ffffb707fde7d000
  [2]: ffffb707fdead000
  [3]: ffffb707fdedd000
  ...
crash> struct page_frag_cache ffffb707fde4d000
struct page_frag_cache {
  va = 0x0,
  offset = 0,
  pagecnt_bias = 0,
  pfmemalloc = false
}
crash> struct page_frag_cache ffffb707fde7d000
struct page_frag_cache {
  va = 0x0,
  offset = 0,
  pagecnt_bias = 0,
  pfmemalloc = false
}
crash> struct page_frag_cache ffffb707fdead000
struct page_frag_cache {
  va = 0x0,
  offset = 0,
  pagecnt_bias = 0,
  pfmemalloc = false
}
crash> struct page_frag_cache ffffb707fdedd000
struct page_frag_cache {
  va = 0x0,
  offset = 0,
  pagecnt_bias = 0,
  pfmemalloc = false
}
```
我们这里简单判断，不是该代码路径导致。
### page_ref_add
在分析kernel代码之前，我们先看看上述提到的page在什么地址可以search到`struct page`
address地址,拿上面提到的一个page 地址来说`ffff7fee5b008000`
```
crash> search ffff7fee5b008000
ffff000061fa9ef0: ffff7fee5b008000

crash> x/20xg 0xffff000061fa9ef0
0xffff000061fa9ef0:     0xffff7fee5b008000      0x0000ffff00000042
0xffff000061fa9f00:     0x0000000000000000      0x0000037002010000
0xffff000061fa9f10:     0xffff7fee5b008040      0x0000ffff00000042
0xffff000061fa9f20:     0x0000000000000000      0x0000037002020000
0xffff000061fa9f30:     0xffff7fee5b008080      0x0000ffff00000042
0xffff000061fa9f40:     0x0000000000000000      0x0000037002030000
0xffff000061fa9f50:     0xffff7fee5b0080c0      0x0000ffff00000042
0xffff000061fa9f60:     0x0000000000000000      0x0000037002040000
0xffff000061fa9f70:     0xffff7fee5b008100      0x0000ffff00000042
0xffff000061fa9f80:     0x0000000000000000      0x0000037002050000

crash> p sizeof(struct page)
$1 = 64
```

可以看到，上面的地址里面的数据包含了很多的page address
```
0xffff7fee5b008000
0xffff7fee5b008040
0xffff7fee5b008080
0xffff7fee5b0080c0
0xffff7fee5b008100
```
而且因为`sizeof(struct page)`为64(0x40),所以上面的page地址是连续的。
那么这样的数据结构看起来像是一个数组，大小为32(0x20)

那么我们再来看下有哪些函数调用了`page_ref_add`
有很多网卡驱动调用了, 还有hugepage vhost, 这里我们
主要分析下网卡驱动。

看下53环境上网卡驱动类型:
```
[root@node-1 wangfuqiang_copy]# lspci |grep Net
0000:07:00.0 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
0000:07:00.1 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
0000:0d:00.0 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
0000:0d:00.1 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
0000:0d:00.2 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
0000:0d:00.3 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
0001:01:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
0001:01:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
0001:03:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
0001:03:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)

[root@node-1 wangfuqiang_copy]# lspci -v -s 0000:07:00.0
0000:07:00.0 Ethernet controller: Intel Corporation I350 Gigabit Network Connection (rev 01)
        Subsystem: Intel Corporation Ethernet Server Adapter I350-T2
        Flags: bus master, fast devsel, latency 0, IRQ 12, NUMA node 0
        Memory at 61a00000 (32-bit, non-prefetchable) [size=1M]
        Memory at 61d00000 (32-bit, non-prefetchable) [size=16K]
        Expansion ROM at 61c00000 [size=512K]
        Capabilities: [40] Power Management version 3
        Capabilities: [50] MSI: Enable- Count=1/1 Maskable+ 64bit+
        Capabilities: [70] MSI-X: Enable+ Count=10 Masked-
        Capabilities: [a0] Express Endpoint, MSI 00
        Capabilities: [100] Advanced Error Reporting
        Capabilities: [140] Device Serial Number 9c-69-b4-ff-ff-63-01-c0
        Capabilities: [150] Alternative Routing-ID Interpretation (ARI)
        Capabilities: [160] Single Root I/O Virtualization (SR-IOV)
        Capabilities: [1a0] Transaction Processing Hints
        Capabilities: [1c0] Latency Tolerance Reporting
        Capabilities: [1d0] Access Control Services
        Kernel driver in use: igb
        Kernel modules: igb

[root@node-1 wangfuqiang_copy]# lspci -v -s 0001:01:00.0
0001:01:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
        Subsystem: Intel Corporation Ethernet Server Adapter X520-2
        Flags: bus master, fast devsel, latency 0, IRQ 16, NUMA node 8, IOMMU group 1
        Memory at 20060000000 (64-bit, non-prefetchable) [size=1M]
        I/O ports at 800000 [virtual] [size=32]
        Memory at 20060300000 (64-bit, non-prefetchable) [virtual] [size=16K]
        Expansion ROM at 20060200000 [size=512K]
        Capabilities: [40] Power Management version 3
        Capabilities: [50] MSI: Enable- Count=1/1 Maskable+ 64bit+
        Capabilities: [70] MSI-X: Enable+ Count=64 Masked-
        Capabilities: [a0] Express Endpoint, MSI 00
        Capabilities: [100] Advanced Error Reporting
        Capabilities: [140] Device Serial Number 9c-69-b4-ff-ff-62-e1-48
        Capabilities: [150] Alternative Routing-ID Interpretation (ARI)
        Capabilities: [160] Single Root I/O Virtualization (SR-IOV)
        Kernel driver in use: vfio-pci
        Kernel modules: ixgbe
```
主要有`igb`,`ixgbe`两种网卡驱动驱动的网卡。

找天浩了解了下，QA 同事测试的网卡是`82599ES`, `ixgbe`驱动的网卡
我们这边主要分析下ixgbe驱动调用 `page_ref_add`的代码路径。
拿其中一个代码路径举例
```cpp
static bool ixgbe_alloc_mapped_page(struct ixgbe_ring *rx_ring,
                                ¦   struct ixgbe_rx_buffer *bi)
{
	struct page *page = bi->page;
	dma_addr_t dma;
	
	/* since we are recycling buffers we should seldom need to alloc */
	if (likely(page))
	        return true;

	page = dev_alloc_pages(ixgbe_rx_pg_order(rx_ring));
	...
	if (unlikely(!page)) {
        rx_ring->rx_stats.alloc_rx_page_failed++;
        return false;
	}
	
	/* map page for use */
	dma = dma_map_page_attrs(rx_ring->dev, page, 0,
	                        ¦ixgbe_rx_pg_size(rx_ring),
	                        ¦DMA_FROM_DEVICE,
	                        ¦IXGBE_RX_DMA_ATTR);
	
	/*
	¦* if mapping failed free memory back to system since
	¦* there isn't much point in holding memory we can't 
	¦*/
	if (dma_mapping_error(rx_ring->dev, dma)) {
	        __free_pages(page, ixgbe_rx_pg_order(rx_ring)
	
	        rx_ring->rx_stats.alloc_rx_page_failed++;
	        return false;
	}
	
	bi->dma = dma;
	bi->page = page;
	bi->page_offset = ixgbe_rx_offset(rx_ring);
	page_ref_add(page, USHRT_MAX - 1);
	bi->pagecnt_bias = USHRT_MAX;
	rx_ring->rx_stats.alloc_rx_page++;
	
	return true;
}
static inline struct page *dev_alloc_pages(unsigned int order)
{
        return __dev_alloc_pages(GFP_ATOMIC | __GFP_NOWARN, order);
}
static inline struct page *__dev_alloc_pages(gfp_t gfp_mask,
                                        ¦    unsigned int order)
{
        /* This piece of code contains several assumptions.
        ¦* 1.  This is for device Rx, therefor a cold page is preferred.
        ¦* 2.  The expectation is the user wants a compound page.
        ¦* 3.  If requesting a order 0 page it will not be compound
        ¦*     due to the check to see if order has a value in prep_new_page
        ¦* 4.  __GFP_MEMALLOC is ignored if __GFP_NOMEMALLOC is set due to
        ¦*     code in gfp_to_alloc_flags that should be enforcing this.
        ¦*/
        gfp_mask |= __GFP_COMP | __GFP_MEMALLOC;

        return alloc_pages_node(NUMA_NO_NODE, gfp_mask, order);
}
static inline struct page *alloc_pages_node(int nid, gfp_t gfp_mask,
                                                unsigned int order)
{
        if (nid == NUMA_NO_NODE)
                nid = numa_mem_id();

        return __alloc_pages_node(nid, gfp_mask, order);
}
///////////////struct ixgbe_rx_buffer
struct ixgbe_rx_buffer {
        struct sk_buff *skb;
        dma_addr_t dma;
        union {
                struct {
                        struct page *page;
                        __u32 page_offset;
                        __u16 pagecnt_bias;
                };
                struct {
                        void *addr;
                        u64 handle;
                };
        };
};

//ixgbe_alloc_rx_buffers()->ixgbe_alloc_mapped_page()
void ixgbe_alloc_rx_buffers(struct ixgbe_ring *rx_ring, u16 cleaned_count)
{
	...
	u16 i = rx_ring->next_to_use;
	...
	bi = &rx_ring->rx_buffer_info[i];
	i -= rx_ring->count;
	do {
        	if (!ixgbe_alloc_mapped_page(rx_ring, bi))
        	        break;
		...
		bi++;
		i++;
		if (unlikely(!i)) {
		        rx_desc = IXGBE_RX_DESC(rx_ring, 0);
		        bi = rx_ring->rx_buffer_info;
		        i -= rx_ring->count;
		}
		...
		cleaned_count--;
	} while(cleaned_count);
	i += rx_ring->count;

	if (rx_ring->next_to_use != i) {
	        rx_ring->next_to_use = i;
	
	        /* update next to alloc since we have filled the ring */
	        rx_ring->next_to_alloc = i;
	
	        /* Force memory writes to complete before letting h/w
	        ¦* know there are new descriptors to fetch.  (Only
	        ¦* applicable for weak-ordered memory model archs,
	        ¦* such as IA-64).
	        ¦*/
	        wmb();
	        writel(i, rx_ring->tail);
	}
}
//struct ixgbe_ring
struct ixgbe_ring {
	...
	union {
        	struct ixgbe_tx_buffer *tx_buffer_info;
        	struct ixgbe_rx_buffer *rx_buffer_info;
	};
	...
};
//init struct ixgbe_ring->ixgbe_rx_buffer
int ixgbe_setup_rx_resources(struct ixgbe_adapter *adapter,
                        ¦    struct ixgbe_ring *rx_ring)
{
	...
	rx_ring->rx_buffer_info = vmalloc_node(size, ring_node);
	...
}
```
从上面的函数我们能看出来几点:
* 分配的page 是 根据numa id 分配的
* `page_ref_add(page, USHRT_MAX -1)` 中`USHRT_MAX`为65535,
 而`bi->pagecnt_bias`也赋值了该值
* `bi->dma`赋值的为`page`的物理地址
* `sizeof(struct ixgbe_rx_buffer)` = 32
* 通过`ixgbe_alloc_rx_buffers()`可以看出，bi来自于`struct ixgbe_ring->rx_buffer_info[i]`,
而`rx_buffer_info`数组是通过`vmalloc_node`获得

我们再来看下上面`ffff7fee5b008000`内存区间里面的值，满足
* 每组数据大小为32
* 拿`0xffff000061fa9f00`地址处的数据来看
```
bi->skb = 0x0
bi->dma = 0x0000037002010000
bi->page = 0xffff7fee5b008040
bi->page_offset= 42
bi->pagecnt_bias = 0xffff
```
我们再来看下`0xffff7fee5b008040`对应的物理地址:
```
crash> kmem 0xffff7fee5b008040
      PAGE         PHYSICAL      MAPPING       INDEX CNT FLAGS
ffff7fee5b008040 37002010000                0        0 65535 3dfffff000000000
```
可以看到满足`struct ixgbe_rx_buffer`的成员解释。

我们再来看下`0xffff000061fa9ef0`所在的地址空间:
```
crash> kmem -v |grep ffff000061fa
ffffb777cac15400  ffffb777cac1c080  ffff000061f70000 - ffff000061fa0000   196608
ffffb777cac10d00  ffffb777cac16780  ffff000061fa0000 - ffff000061fd0000   196608
```
可以看到vmalloc的空间并没有释放。

我们来看下ixgbe 驱动相关数据结构的构成，这里我们不在
展开
```
struct ixgbe_ring->struct ixgbe_tx_buffer *tx_buffer_info
struct ixgbe_adapter->struct ixgbe_ring *rx_ring[MAX_RX_QUEUES]

//struct net_device 和 struct ixgbe_adapter 的关系

+------------------------------------------------------+
|struct net_device                                     |
|                                                      |
|                                                      |
+------------------------------------------------------+ 
|struct ixgbe_adapter                                  |
|                                                      |
|struct ixgbe_ring *rx_ring[MAX_RX_QUEUES]             +----------+
+------------------------------------------------------+          |
                                                                  |
                                                                  |
                                                                  |
                                    +-----------------------------+
                                    |
                                    |
+-----------------------------------+------------+
|struct ixgbe_ring                               |
|                                                |
|struct ixgbe_rx_buffer * rx_buffer_info         |
+------------------------------------------------+
```

在crash工具中有`net` 命令可以查看 Ethernet device 的 `struct net_device`
结构的地址:
```
crash> net |grep enP
ffffb907c2ef4000  enP1p1s0f0
ffffb907c2eac000  enP1p1s0f1
ffffb907c2ec0000  enP1p3s0f0
ffffb907c2ee0000  enP1p3s0f1
```
> PS: enP 开头的为 `82599ES`网卡

我们以 `enP1p3s0f0`来看:
```
crash> p (char *)(0xffffb907c2ef4000 + sizeof(struct net_device))
$1 = 0xffffb907c2ef4ac0 "\001"
crash> struct ixgbe_adapter 0xffffb907c2ef4ac0
struct ixgbe_adapter {
	...
	rx_ring = {0xffffb70408d65d40, 0xffffb70408d72d40, 0xffffb70408d69d40,
	...
	},
	...
	alloc_rx_page = 154006,
	alloc_rx_page_failed = 16079,
	alloc_rx_buff_failed = 0,
	...
}

struct ixgbe_ring {
  next = 0x0,
  q_vector = 0xffffb70408d65800,
  netdev = 0xffffb907c2ef4000,
  xdp_prog = 0x0,
  dev = 0xffffb757c16710b0,
  desc = 0xffffb747c9200000,
  {
    tx_buffer_info = 0xffff000063fe0000,
    rx_buffer_info = 0xffff000063fe0000
  },
  ...
}

crash> struct ixgbe_adapter ffffb907c2eacac0
struct ixgbe_adapter {
  ...
  alloc_rx_page = 9851,
  alloc_rx_page_failed = 43,
  alloc_rx_buff_failed = 0,
  ...
}

crash> struct ixgbe_adapter ffffb907c2ec0ac0
struct ixgbe_adapter {
  ...
  alloc_rx_page = 273005,
  alloc_rx_page_failed = 396,
  alloc_rx_buff_failed = 0,
  ...
}
crash> struct ixgbe_adapter ffffb907c2ee0ac0
struct ixgbe_adapter {
  alloc_rx_page = 273106,
  alloc_rx_page_failed = 425,
  alloc_rx_buff_failed = 0,
}
```
alloc_rx_page sum : 709968
占用内存约43G
alloc_rx_page_failed: 16943
