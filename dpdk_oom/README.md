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
为`set_page_count()`
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

page address 存放在`struct page_frag_cache`的0 offset, 我们尝试找一个特定的page来分析下:
```
crash> kmem -m lru.next,flags,mapping,_mapcount,_refcount|grep 3dfffff000000000|grep 0000ffff|head -3
ffff7fee5b008000  dead000000000100  3dfffff000000000  0000000000000000  -1  0000ffff
ffff7fee5b008040  dead000000000100  3dfffff000000000  0000000000000000  -1  0000ffff
ffff7fee5b008080  dead000000000100  3dfffff000000000  0000000000000000  -1  0000ffff

crash> search ffff7fee5b008000
ffff000061fa9ef0: ffff7fee5b008000
crash> struct page_frag_cache ffff000061fa9ef0
struct page_frag_cache {
  va = 0xffff7fee5b008000,
  offset = 66,
  pagecnt_bias = 65535,
  pfmemalloc = false
}

crash> search ffff7fee5b008040
ffff000061fa9f10: ffff7fee5b008040
crash> struct page_frag_cache ffff000061fa9f10
struct page_frag_cache {
  va = 0xffff7fee5b008040,
  offset = 66,
  pagecnt_bias = 65535,
  pfmemalloc = false
}

crash> search ffff7fee5b008080
ffff000061fa9f30: ffff7fee5b008080
crash> struct page_frag_cache ffff000061fa9f30
struct page_frag_cache {
  va = 0xffff7fee5b008080,
  offset = 66,
  pagecnt_bias = 65535,
  pfmemalloc = false
}
```
可以看到

而调用`page_frag_alloc()`的函数有以下几个, 基本上是驱动(wireless,nvme)和网络模块，这里
主要看下网络模块(因为场景业主要是在dpdk使用场景下
```
__napi_alloc_skb
__netdev_alloc_frag
__napi_alloc_frag
__netdev_alloc_skb
```
看起来像是一个连续的地址
