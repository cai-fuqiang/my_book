# ORG PATCH

> NOTE
>
> 最初引入 slub的patch为
> ```
> commit 81819f0fc8285a2a5a921c019e3e3d7b6169d225
>  Author: Christoph Lameter <clameter@sgi.com>
>  Date:   Sun May 6 14:49:36 2007 -0700
>
>      SLUB core
> ```
>

我们来看下 最初引入`SLUB`时, order处理的相关代码:

1. `struct kmem_cache`

   在`kmem_cache`加入 `order`成员
   ```cpp
   struct kmem_cache {
          ...
          unsigned int order;
          ...
   ```
2. 增加两个cmdline, 用来控制order允许取值范围
   ```
   slub_min_order=x        Require a minimum order for slab caches. This
                           increases the managed chunk size and therefore
                           reduces meta data and locking overhead.
   slub_max_order=x        Avoid generating slabs larger than order specified.
   ```
   * **slub_min_order**: 这里会规定一个最小的order, 这个最小的order可能会增加 
     managed chunk size, 也就是增加每个slub的size, 这样可以减少 meta data 
     和减少锁的开销
   * **slub_max_order** : 规定一个最大的order

   > NOTE
   >
   > 关于 slub order 不同的大小的优缺点, 我们在下面的章节中
   > 讨论

   cmdline 初始化代码:
   ```cpp
   static int slub_min_order;
   static int slub_max_order = DEFAULT_MAX_ORDER;
   ...
   static int __init setup_slub_min_order(char *str)
   {
          get_option (&str, &slub_min_order);
   
          return 1;
   }
   
   __setup("slub_min_order=", setup_slub_min_order);
   
   static int __init setup_slub_max_order(char *str)
   {
          get_option (&str, &slub_max_order);
   
          return 1;
   }
   
   __setup("slub_max_order=", setup_slub_max_order);
   ```
   `slub_max_order` 默认为 `DEFAULT_MAX_ORDER`(2)
3. 接下来我们具体分析每个slub的 order是如何计算的

## calculate slub order

调用路径
```
create_kmalloc_cache
  kmem_cache_open
    calculate_sizes {
      ...
      s->order = calculate_order(size)
      ...
    }
```

## HOW TO calculate slub ORDER

我们先详细看下注释部分, 因为注释部分解释了 order 大小的利弊
```cpp
/*
 * Calculate the order of allocation given an slab object size.
 *
 * //============(1)================
 * The order of allocation has significant impact on other elements
 * of the system. Generally order 0 allocations should be preferred
 * since they do not cause fragmentation in the page allocator. Larger
 * objects may have problems with order 0 because there may be too much
 * space left unused in a slab. We go to a higher order if more than 1/8th
 * of the slab would be wasted.
 *
 * fragmentation [ˌfræɡmenˈteɪʃn]  : 碎片
 * problematic : 难以处理的; 难题
 *
 * 分配的 order 已经显著的影响到性能和其他 system elements. 一般来说, order 0
 * allocations 应该性能更好, 因为 order 0 将不会导致在 page allocator 中产生碎片.
 * 大点的object 是难以将他们放到 order 0 slab 因为 他可能会造成比较多的 unused space
 * 剩余. 如果该slab 浪费的空间超过了1/8th, 我们将会使用更高的 order
 *
 * //============(2)================
 * In order to reach satisfactory performance we must ensure that
 * a minimum number of objects is in one slab. Otherwise we may
 * generate too much activity on the partial lists. This is less a
 * concern for large slabs though. slub_max_order specifies the order
 * where we begin to stop considering the number of objects in a slab.
 *
 * satisfactory [ˌsætɪsˈfæktəri] : 令人满意的
 * concern: 与...有关;涉及;影响; 对...担忧
 *
 * 为了达到令人满意的性能, 我们必须确定 一个 slab最少的 objects的数量. 否则,
 * 我们可能会在 partial lists中生成太多 activity(这需要获取 list_lock). 对于
 * large slab 来说就不那么需要担心, 虽然他们很少被使用.
 * slub_max_order指定了我们开始停止将不再考虑 slab 中 object的数量 的 order
 * (也就是如果达到了 slub_max_order, 不再根据slub中的object数量决定order)
 *
 * Higher order allocations also allow the placement of more objects
 * in a slab and thereby reduce object handling overhead. If the user
 * has requested a higher mininum order then we start with that one
 * instead of zero.
 *
 * 更高的 order allocations 也允许将更多的 objects 放置到一个 slab 中 借此
 * 减少object handling overhead. 如果 user 已经请求了 更高的 mininum order,
 * 那么我们从该order 开始, 而不是从 适合该object 更小的order.
 */
```
1. 如果仅从 page allocator 的角度考虑, 肯定是order越低越好, 因为对于
   伙伴系统来说, 越低的order将造成的碎片越少(那order 0 肯定是最好的)

   但是, 对于slub 本身而言, 有些比较大的object, 可能会造成较大的空间浪费, 
   如果调整order, 可能会减少一些浪费

   E.g., 如果page size 为 4096, slub object size为 2049
     * order = 0, 将浪费:
       ```
        4096 % 2049 = 2047
       ```
     * order = 1, 将浪费
       ```
       (4096 * 2) % 2049 = 2045
       ```
     * order = 2, 将浪费
       ```
       (4096 * 4) % 2049 = 2041
       ```

     可以看到在这个例子中, 增加order将减少order浪费(例子比较极端, 减少的
     字节并不是很多)

   在该版代码中, 如果浪费的空间占总空间的1/8th, 则考虑使用更大的order
2. 从 slub 性能来看, 如果order过大, 则可能会造成 partial list 会更活跃
   (也就是说, order过大, object就比较多, 同时释放object的几率可能就会
   增加?), 
   ```cpp
   static void add_partial(struct kmem_cache *s, struct page *page)
   {
          struct kmem_cache_node *n = get_node(s, page_to_nid(page));
   
          spin_lock(&n->list_lock);
          n->nr_partial++;
          list_add(&page->lru, &n->partial);
          spin_unlock(&n->list_lock);
   }
   ```
   (这部分不是很确定)

   作者使用 `slub_max_order` 规定了一个了一个最大值, 来限制这个上面
   提到的问题
3. 更大的order 可能会减少 object handling overhead. (这个好理解,
   会减少调用 伙伴系统代码的次数).

   所以作者使用 `slub_min_order`规定了一个最小值.

***

接下来,我们来分析`calculate_order()`代码: 
```cpp
static int calculate_order(int size)
{
       int order;
       int rem;
       
       //========(1)=======
       for (order = max(slub_min_order, fls(size - 1) - PAGE_SHIFT);
                       order < MAX_ORDER; order++) {
               unsigned long slab_size = PAGE_SIZE << order;

               //========(2)=======
               if (slub_max_order > order &&
                               slab_size < slub_min_objects * size)
                       continue;

               //========(3)=======
               if (slab_size < size)
                       continue;

               //========(4)=======
               rem = slab_size % size;

               if (rem <= (PAGE_SIZE << order) / 8)
                       break;

       }
       //========(1.1)=======
       if (order >= MAX_ORDER)
               return -E2BIG;
       return order;
}
```
1. `order`初始值由`slub_min_order`, 以及 `object size`来决定(计算object
   占用的order), 当然这里要注意, `order  >= max_order`, 则是
   非法情况, 返回`E2BIG`错误 (see 1.1)
2. 计算当前order的`slab_size`, 这里需要判断该`slab_size` 能不能
   容得下`slub_min_objects`个object, 但是同时要满足`order`
   不能超过`slub_max_order`
3. 这个地方.... if判断能不能为true ? (个人感觉不能)
4. `rem` 中 `r`表示`rest`, 也就是`剩余的`意思, 如果剩余的内存(waste)
   大于 slub大小的 1/8th的话,则继续寻找(增大order)

但是这里有个问题, 这个 `slub_max_order` 并不能起到严格限制的
作用,这里只是限制了 `slub_min_objects`所占用的大小, 不能超过 
`slub_max_order`, 但是不能限制因为浪费的空间大于1/8th,所带来的
order的增大, 而这个限制最终被设置为`MAX_ORDER`, 见(1)

# Limit order under slub_max_order

> NOTE
>
> 该section 中讲到的所有的patch, 来自于:
>
> [SLUB fixes and enhancements against 2.6.21-m1](https://lore.kernel.org/all/20070507212240.254911542@sgi.com/)

上面提到, `slub_max_order`不能很好的限制`order`大小, 上游
也意识到这个问题, 并在下面的patch解决.

我们先来看第一个patch

## [\[patch 16/17\]SLUB: include lifetime stats and sets of cpus / nodes in tracking output](https://lore.kernel.org/all/20070507212411.097801338@sgi.com/)
```
commit 45edfa580b8e638c44ec26872bfe75b307ba12d1
Author: Christoph Lameter <clameter@sgi.com>
Date:   Wed May 9 02:32:45 2007 -0700

    SLUB: include lifetime stats and sets of cpus / nodes in tracking output
```

其改动也很简单:

```diff
@@ -1586,13 +1586,16 @@ static int calculate_order(int size)
                        order < MAX_ORDER; order++) {
                unsigned long slab_size = PAGE_SIZE << order;
                //=====(1)=====
-               if (slub_max_order > order &&
+               if (order < slub_max_order &&
                                slab_size < slub_min_objects * size)
                        continue;

                //=====(3)=====
                if (slab_size < size)
                        continue;

                //=====(2)=====
+               if (order >= slub_max_order)
+                       break;
+
                rem = slab_size % size;

                if (rem <= slab_size / 8)
```
1. 这里相当于没改...
2. 这里增加了一个条件限制了order的大小,一定不能大于 `slub_max_order`, 
   但是由于(3)还是有可能 使 `order >= slub_max_order`的, 而该动作是合理
   的, 因为object size本身比较大, 一个object size的order, 就比 
   `slub_max_order`要大了

所以综上所所述, 上面的patch已经解决了这个问题

但是作者还提了一个patch, 也涉及到order计算的改动,我们来看下


## [\[PATCH 17/17\]SLUB: Rework slab order determination](https://lore.kernel.org/all/20070507212411.329013996@sgi.com/)
```
commit 5e6d444ea1f72b8148354a9baf0ea8fa3dd0425b
Author: Christoph Lameter <clameter@sgi.com>
Date:   Wed May 9 02:32:46 2007 -0700

    SLUB: rework slab order determination
```

我们来看下, commit message:
```
In some cases SLUB is creating uselessly slabs that are larger than
slub_max_order. Also the layout of some of the slabs was not satisfactory.

在某些情况下 SLUB 会创建比 slub_max_order更多的 uselessly(很少使用到的)slab.
并且某些slab的布局也不令人满意

Go to an iterarive approach.

iterarive -> iterative : 迭代的(写错了?)
```

看下patch
```diff
//======(1)======
+static inline int slab_order(int size, int min_objects,
+                               int max_order, int fract_leftover)
 {
        int order;
        int rem;

-       for (order = max(slub_min_order, fls(size - 1) - PAGE_SHIFT);
-                       order < MAX_ORDER; order++) {
-               unsigned long slab_size = PAGE_SIZE << order;
        //======(2)======
+       for (order = max(slub_min_order,
+                               fls(min_objects * size - 1) - PAGE_SHIFT);
+                       order <= max_order; order++) {

                //======(2.1)======
-               if (order < slub_max_order &&
-                               slab_size < slub_min_objects * size)
-                       continue;
+               unsigned long slab_size = PAGE_SIZE << order;

-               if (slab_size < size)
+               if (slab_size < min_objects * size)
                        continue;

                //======(2.2)======
-               if (order >= slub_max_order)
-                       break;
-
                rem = slab_size % size;

                //======(3)======
-               if (rem <= slab_size / 8)
+               if (rem <= slab_size / fract_leftover)
                        break;

        }
-       if (order >= MAX_ORDER)
-               return -E2BIG;

        return order;
 }
```
我们首先看新增的 `slab_order()`函数,该函数是在原有的`calculate_order()`基础上改动
而来,我们分析下:
1. 首先我们看下函数参数:
   * **size** : slub object的size
   * **min_object** : 最小的 object的数量
   * **max_order**: 最大的order
   * **fract_leftover** : 可以容忍的waste的最大比例

   > 我们会在`calculate_order()`函数中分析后三个参数是如何传值的.

2. 这里判断退出的条件由`order < MAX_ORDER` 修改为 `order <= max_order`, 并去掉
   循环中和 `slub_max_order`的判断 (2.1) (2.2)

3. 依然是判断waste 的比例,但是这里比例 (`fract_leftover`) 是可以变动的
   (不再固定为`1/8th`)

   > NOTE
   >
   > 但是这里改动之后, 可能会造成 返回的 `order > max_order` 的情况, 例如如果
   > 在`order == max_order`这一轮中循环, 但是还不满足(3)的条件,使得, `order++`
   > 变为`max_order + 1`
```diff
+static inline int calculate_order(int size)
+{
+       int order;
+       int min_objects;
+       int fraction;
+
+       /*
+        * Attempt to find best configuration for a slab. This
+        * works by first attempting to generate a layout with
+        * the best configuration and backing off gradually.
+        *

         * gradually [ˈɡrædʒuəli]: 逐步的
         *
         * 尝试为slab寻找更好的配置. 首先尝试生成最佳配置的layout(布局?)
         * 然后逐步的后退.
         
+        * First we reduce the acceptable waste in a slab. Then
+        * we reduce the minimum objects required in a slab.

         * 首先我们增加slab中的可以接受的浪费比例. 然后我们减少
         * 一个slab中所需的 mininum objects

+        */
        //=====(1)======
+       min_objects = slub_min_objects;
+       while (min_objects > 1) {
+               fraction = 8;
+               while (fraction >= 4) {
+                       order = slab_order(size, min_objects,
+                                               slub_max_order, fraction);
+                       if (order <= slub_max_order)
+                               return order;
+                       fraction /= 2;
+               }
+               min_objects /= 2;
+       }
+
+       /*
+        * We were unable to place multiple objects in a slab. Now
+        * lets see if we can place a single object there.
+        */
        //=====(2)======
+       order = slab_order(size, 1, slub_max_order, 1);
+       if (order <= slub_max_order)
+               return order;
+
+       /*
+        * Doh this slab cannot be placed using slub_max_order.
+        */
        //=====(3)======
+       order = slab_order(size, 1, MAX_ORDER, 1);
+       if (order <= MAX_ORDER)
+               return order;
+       return -ENOSYS;
+}
```
1. 这里采用一个迭代的方式, 首先设置最佳的 `min_objects`和 `fraction`, 
   并调用`slab_order()`, 但是, 可能从`[0, slub_max_order]`都不满足
   这个条件(`(min_objects, fraction)` 按照之前的代码, 就直接返回
   `slub_max_order`了. 但是作者采用了一种折中的方案, 依次测试下面
   的方案
   * (min_objects, fraction / 2)
   * (min_objects / 2, fraction)
   * (min_objects / 2, fraction / 2)
   * (min_objects / 4, fraction)
   * (min_objects / 4, fraction / 2)

   ...

   这样做的作用是什么呢 ? 实际上就是牺牲了 min_objects和 fraction,
   而尽量找到一个比较低的order

   (其实这里 fraction 牺牲比较小, 最多是从8->4, 而min_objects牺牲
   比较大, 可能会从 min_objects -> 1

   > NOTE
   >
   > 作者的 commit message中写到 `In some cases SLUB is creating 
   > uselessly slabs that are larger than slub_max_order.`, 个人感觉
   > 不是larger, 而是equal
2. 如果还没有找到, 将`min_objects`和`fraction`设置为1, (这时
   `min_objects`已经为1了, 然后再去调用`slab_order()`, 
   > NOTE
   >
   > `fraction`为1,也就以为着, 不再关心waste 的比例
3. 如果还是没有找到, 也不关心 `slub_max_order`了, 直接用`MAX_ORDER`

可以看到, `min_objects` 实际上很能影响order, 我们再来看下 `min_objects`
的一些改动

# MIN OBJECTS
## org patch
最初的patch比较简单, 和order 一样 可以由kernel cmdline 控制
```
slub_min_objects=x      Mininum objects per slab. Default is 8
```
代码:
```cpp
static int slub_min_objects = DEFAULT_MIN_OBJECTS;
...

static int __init setup_slub_min_objects(char *str)
{
       get_option (&str, &slub_min_objects);

       return 1;
}

__setup("slub_min_objects=", setup_slub_min_objects);
```
`slub_min_objects` 默认为  `DEFAULT_MIN_OBJECTS` (8)

这时, slub_min_objects是固定的, 但是后面工程师们发现在cpus
个数比较多的情况下, 将 min_objects数量越大, 性能就越好. 
我们看下面的patch

## [slub: Calculate min_objects based on number of processors](https://marc.info/?l=linux-mm&m=120734955909709&w=2)

COMMIT 
```
commit 9b2cd506e5f2117f94c28a0040bf5da058105316
Author: Christoph Lameter <clameter@sgi.com>
Date:   Mon Apr 14 19:11:41 2008 +0300

    slub: Calculate min_objects based on number of processors.
```

我们先看下commit message:
```
    slub: Calculate min_objects based on number of processors.

    The mininum objects per slab is calculated based on the number of processors
    that may come online.

    Processors    min_objects
    ---------------------------
    1             8
    2             12
    4             16
    8             20
    16            24
    32            28
    64            32
    1024          48
    4096          56

    The higher the number of processors the large the order sizes used for various
    slab caches will become. This has been shown to address the performance issues
    in hackbench on 16p etc.

    The calculation is only performed if slub_min_objects is zero (default). If one
    specifies a slub_min_objects on boot then that setting is taken.

    As suggested by Zhang Yanmin's performance tests on 16-core Tigerton, use the
    formula '4 * (fls(nr_cpu_ids) + 1)':

      ./hackbench 100 process 2000:

      1) 2.6.25-rc6slab: 23.5 seconds
      2) 2.6.25-rc7SLUB+slub_min_objects=20: 31 seconds
      3) 2.6.25-rc7SLUB+slub_min_objects=24: 23.5 seconds
```
这里提出了一个方法, 就是根据`nr_cpu_ids`的数量决定`min_objects`, 有一个公式
```
min_objects = 4 * (fls(nr_cpu_ids + 1)
```
会得到如上列表中所描述的(processor number, min_objects) map关系.

我们先看下代码:
```diff
diff --git a/mm/slub.c b/mm/slub.c
index 6572cef0c43c..e2e6ba7a5172 100644
--- a/mm/slub.c
+++ b/mm/slub.c
@@ -1803,7 +1803,7 @@ static struct page *get_object_page(const void *x)
  */
 static int slub_min_order;
 static int slub_max_order = PAGE_ALLOC_COSTLY_ORDER;
-static int slub_min_objects = 4;
+static int slub_min_objects;

 /*
  * Merge control. If this is set then no merging of slab caches will occur.
@@ -1880,6 +1880,8 @@ static inline int calculate_order(int size)
         * we reduce the minimum objects required in a slab.
         */
        min_objects = slub_min_objects;
+       if (!min_objects)
+               min_objects = 4 * (fls(nr_cpu_ids) + 1);
        while (min_objects > 1) {
                fraction = 8;
                while (fraction >= 4) {
```
因为要判断 `min_objects`是否被指定, 所以修改了 `slub_min_objects`的默认值,
并且在 计算 `min_objects` 最终有个 `+ 4`的动作.

> NOTE
>
> 要不要 + 4 在 https://marc.info/?l=linux-mm&m=120755089427202&w=2
> 里面有讨论

这里不知道性能是怎么得到提升的, mail list 和 commit 中也没有提到.
但是, 里面有将slub 和slab 做了对比.所以估计slub是按照slab改得.
之后我们去对比下同时期的slab, 看看有没有说明

> NOTE
>
> 在 commit 3286222fc609dea27bd16ac02c55d3f1c3190063
>
> mm, slub: better heuristic for number of cpus when calculating slab order
>
> 的commit message中有讲到, 我们下面会讲到

## [mm/slub: let number of online CPUs determine the slub page order](https://lore.kernel.org/linux-mm/20201118082759.1413056-1-bharata@linux.ibm.com/)

COMMIT message:
```
commit 045ab8c9487ba099eade6578621e2af4a0d5ba0c
Author: Bharata B Rao <bharata@linux.ibm.com>
Date:   Mon Dec 14 19:04:40 2020 -0800

    mm/slub: let number of online CPUs determine the slub page order

    The page order of the slab that gets chosen for a given slab cache depends
    on the number of objects that can be fit in the slab while meeting other
    requirements.  We start with a value of minimum objects based on
    nr_cpu_ids that is driven by possible number of CPUs and hence could be
    higher than the actual number of CPUs present in the system.  This leads
    to calculate_order() chosing a page order that is on the higher side
    leading to increased slab memory consumption on systems that have bigger
    page sizes.

    meet requirement: 满足要求
    get chosen: 被选中

    为给定的 slab  caches 选择 slab的page order 依赖于 objects 的number,
    这个number 需要在满足其他的需求下, 又能放到这个slab中. 我们开始基于
    nr_cpu_ids 的一个 mininum objects的值, nr_cpu_ids 是 CPUs的 possible
    number ,因此可能比系统中实际的 present 的 CPUs的数量要高. 这导致
    calculate_order 选择 一个较高的 page order, 将导致在较大 page size 的
    系统上增加了 slab 的内存消耗

    Hence rely on the number of online CPUs when determining the mininum
    objects, thereby increasing the chances of chosing a lower conservative
    page order for the slab.

    conservative: 保守的, 守旧的

    因为当确定 mininum objects时, 应基于 online CPUs的数量, 因此增加了为
    slab 选择较低的保守的(???) page order的机会

    Vlastimil said:
      "Ideally, we would react to hotplug events and update existing caches
       accordingly. But for that, recalculation of order for existing caches
       would have to be made safe, while not affecting hot paths. We have
       removed the sysfs interface with 32a6f409b693 ("mm, slub: remove
       runtime allocation order changes") as it didn't seem easy and worth
       the trouble.

       idenlly: 理想的
       react: 反应
       accordingly: 相应的
       worth: <v> 有...的价值

       理想情况下, 我们对热插拔时间做出反应, 并且相应的更新现有的 caches.
       但为此, 从新为现有的 cache计算order必须是安全的, 同时不影响 hot paths.
       我们在 32a6f409b693 ("mm, slub: remove runtime allocation order changes") 
       移除了 sysfs interface , 因为这似乎并不容易 并且也不值得麻烦.

       In case somebody wants to start with a large order right from the
       boot because they know they will hotplug lots of cpus later, they can
       use slub_min_objects= boot param to override this heuristic. So in
       case this change regresses somebody's performance, there's a way
       around it and thus the risk is low IMHO"
       
       right from: 从, right是修饰语，用来表达某种强烈的思想
       heuristic [hjuˈrɪstɪk]: 启发式的
       in case: 如果,也许,万一
       regresses [rɪˈɡresɪz] : 退步,倒退 (三单)

       IMHO: in my humble option    依我拙见; 恕我直言
       humble[ˈhʌmbl]: 谦逊的

       如果有人想从启动出就开始使用一个大的 order, 因为他们知道他们接下来将hotplug
       很多 cpu, 他们可以使用 slub_min_objects= boot param 来覆盖最初的值. 所以万一这
       种变化让某些 性能出现倒退, 这是一种绕过他的方法,并且以我拙见 这样风险很低

    Link: https://lkml.kernel.org/r/20201118082759.1413056-1-bharata@linux.ibm.com
```
作者认为, `nr_cpu_ids`表示possible cpu, 这样在page_size比较大的时候, 会造成slab内存消耗
过大,所以提议使用 online cpus, 但是有hotplug情况, 并且在之前`32a6f409b693 ("mm, slub:
remove runtime allocation order changes")`合入的情况下, 启动后,不能再调整slab order.
所以 Vlastimil 建议 如果知道之后要hotplug, 可以通过设置kernel cmdline `slub_min_objects=`
来设置 slub 的 `min_objects`

我们来看下patch:
```diff
diff --git a/mm/slub.c b/mm/slub.c
index 79afc8a38ebf..6326b98c2164 100644
--- a/mm/slub.c
+++ b/mm/slub.c
@@ -3431,7 +3431,7 @@ static inline int calculate_order(unsigned int size)
         */
        min_objects = slub_min_objects;
        if (!min_objects)
-               min_objects = 4 * (fls(nr_cpu_ids) + 1);
+               min_objects = 4 * (fls(num_online_cpus()) + 1);
        max_objects = order_objects(slub_max_order, size);
        min_objects = min(min_objects, max_objects);
```

但是关于cpu possible和 online 的讨论并没有停止,我们看下面的一个patch

## [mm, slub: better heuristic for number of cpus when calculating slab order](https://lore.kernel.org/all/20210209214232.hlVJaEmRu%25akpm@linux-foundation.org/)

我们还是先来看下 commit message:
```
commit 3286222fc609dea27bd16ac02c55d3f1c3190063
Author: Vlastimil Babka <vbabka@suse.cz>
Date:   Tue Feb 9 13:42:32 2021 -0800

    mm, slub: better heuristic for number of cpus when calculating slab order

    heuristic [hjuˈrɪstɪk]: 启发式的

    When creating a new kmem cache, SLUB determines how large the slab pages
    will based on number of inputs, including the number of CPUs in the
    system.  Larger slab pages mean that more objects can be allocated/free
    from per-cpu slabs before accessing shared structures, but also
    potentially more memory can be wasted due to low slab usage and
    fragmentation.  The rough idea of using number of CPUs is that larger
    systems will be more likely to benefit from reduced contention, and also
    should have enough memory to spare.

    fragmentation [ˌfræɡmenˈteɪʃn] : 碎片
    potentially [pə'tenʃəli]: 潜在的,可能的
    rough [rʌf]: 粗糙的, 大致的, 粗暴的, 粗略的
    spare [sper] : 剩余的, 空闲的

    当创建了一个新的 kmem cache, SLUB 需要基于 inputs的数量确定 slab page 多大, 
    (inputs)包括 系统中 CPUs的个数.更大的slab pages 意味着 更多的 在访问 shared
    structures之前, 可以从 per-cpu的slabs中 allocated/free 更多objects, 但是
    可能也存在 因为较少的 slab在被使用而存在更多的内存被他浪费, 以及更多的碎片
    这样的情况. 使用CPUs的数量的粗略的想法是: 较大的系统更有可能从减少 contention
    中受益, 并且也应该有足够的空闲内存.

    Number of CPUs used to be determined as nr_cpu_ids, which is number of
    possible cpus, but on some systems many will never be onlined, thus
    commit 045ab8c9487b ("mm/slub: let number of online CPUs determine the
    slub page order") changed it to nr_online_cpus().  However, for kmem
    caches created early before CPUs are onlined, this may lead to
    permamently low slab page sizes.

    used to be: 过去是
    permamently --> permanently: [ˈpɜːmənəntli]: 永久的

    过去通过 nr_cpu_ids 确定 CPUs的数量, 这个是 possiable cpus的数量, 但是
    在某些系统中, 许多(cpus) 将从来不会被onlined, 因此 045ab8c9487b ("mm/slub: 
    let number of online CPUs determine the slub page order") 将其(nr_cpu_ids)
    修改为 `nr_online_cpus()`. 但是, 对于在 CPUs online之前 创建的 kmem cache
    来说, 这可能会永久导致 slab page size 较低.

    Vincent reports a regression [1] of hackbench on arm64 systems:

      "I'm facing significant performances regression on a large arm64
       server system (224 CPUs). Regressions is also present on small arm64
       system (8 CPUs) but in a far smaller order of magnitude

       On 224 CPUs system : 9 iterations of hackbench -l 16000 -g 16
       v5.11-rc4 : 9.135sec (+/- 0.45%)
       v5.11-rc4 + revert this patch: 3.173sec (+/- 0.48%)
       v5.10: 3.136sec (+/- 0.40%)"
        
       magnitude [ˈmæɡnɪtjuːd] : 巨大的

       我在 large arm64 server system (224 CPUs) 系统上, 面临一个显著的
       性能倒退. 该倒退也会在small arm64 system (8 CPUs) 中也存在, 但是
       数量级要远小的多

       > NOTE
       >
       > 045ab8c9487b 在 v5.11-rc1 tag中包含, 所以 Vincent 使用 v5.10 和 v5.11-rc4
       > 版本做对比测试

    Mel reports a regression [2] of hackbench on x86_64, with lockstat suggesting
    page allocator contention:

      "i.e. the patch incurs a 7% to 32% performance penalty. This bisected
       cleanly yesterday when I was looking for the regression and then
       found the thread.

       penalty [ˈpenəlti]: 刑罚,惩罚
       bisect  [baɪˈsekt]: 平分, 对半分

       i.e. 该patch 带来了 7% ~ 32%的性能惩罚. 昨天当我们在寻找该回退时,
       它被干净的一分为二, 然后我们就找到了这个thread(线索?)

       Numerous caches change size. For example, kmalloc-512 goes from
       order-0 (vanilla) to order-2 with the revert.

       大量的caches 更改了大小. 例如, 在该revert下(这个revert不太清楚是啥, 
       可以看[2]),  kmalloc-512 从 order-0 (vanilla (alse see [2])) 变为 
       order-2.

       So mostly this is down to the number of times SLUB calls into the
       page allocator which only caches order-0 pages on a per-cpu basis"
       
       be down to : 因为, 可归因为

       因此, 这主要是由于 SLUB 调用到 page allocator 的次数, 他只在 per-cpu
       的基础上 缓存了 order-0 pages (也就是每个cpu都缓存了一个 order-0 pages)

    Clearly num_online_cpus() doesn't work too early in bootup.  We could
    change the order dynamically in a memory hotplug callback, but runtime
    order changing for existing kmem caches has been already shown as
    dangerous, and removed in 32a6f409b693 ("mm, slub: remove runtime
    allocation order changes").

    显然的, num_online_cpus() 在bootup 时 不会工作的太早. 我们可以在 memory
    hotplug callback中动态的调整order, 但是对于已经存在的 kmem cache 进行 
    runtime order change 已经被视为 dangerous, 并且在  
    32a6f409b693 ("mm, slub: remove runtime allocation order changes")移除.

    It could be resurrected in a safe manner with some effort, but to fix
    the regression we need something simpler.

    resurrect: 使...复活;起死回生; 重新使用;恢复使用

    他可以通过一些努力以安全的方式 resurrect, 但是fix 该 regresses, 我们需要
    一些更简单的东西

    We could use num_present_cpus() that should be the number of physically
    present CPUs even before they are onlined.  That would work for PowerPC
    [3], which triggered the original commit, but that still doesn't work on
    arm64 [4] as explained in [5].

    我们可以使用 num_present_cpus(), 他应该为物理上的存在的 CPUs数量, 甚至
    在他们 online之前. 他可以在 PowerPC[3] 上使用, 这 trigger 了原来的commit, 
    但是他仍然不能在 arm64[4]上使用 , 正如在 [5] 中解释的那样

    So this patch tries to determine the best available value without
    specific arch knowledge.

    所以该patch 尝试在没有知道特定架构的基础上, 确定最好的 available value

     - num_present_cpus() if the number is larger than 1, as that means the
       arch is likely setting it properly

       如果 num_present_cpus() > 1, 这意味着 arch 很可能正确的设置了它.

     - nr_cpu_ids otherwise
       
       其他情况使用 nr_cpu_ids

    This should fix the reported regressions while also keeping the effect
    of 045ab8c9487b for PowerPC systems.  It's possible there are
    configurations where num_present_cpus() is 1 during boot while
    nr_cpu_ids is at the same time bloated, so these (if they exist) would
    keep the large orders based on nr_cpu_ids as was before 045ab8c9487b.

    bloate[ˈbloʊtɪd] : 膨胀; 臃肿    

    这应该 fix reported regression, 同时也保持了 045ab8c9487b 对于 PowerPC system
    带来的收益. 可能存在一些配置, 其中 num_present_cpus() 在启动初是1, 而
    nr_cpu_ids 同时也很膨胀(也就是比实际online的CPUs number大很多), 因此这些
    配置(如果存在)将像 045ab8c9487b 之前一样, 保持基于 nr_cpu_ids 的 较大的 orders.

    [1] https://lore.kernel.org/linux-mm/CAKfTPtA_JgMf_+zdFbcb_V9rM7JBWNPjAz9irgwFj7Rou=xzZg@mail.gmail.com/
    [2] https://lore.kernel.org/linux-mm/20210128134512.GF3592@techsingularity.net/
    [3] https://lore.kernel.org/linux-mm/20210123051607.GC2587010@in.ibm.com/
    [4] https://lore.kernel.org/linux-mm/CAKfTPtAjyVmS5VYvU6DBxg4-JEo5bdmWbngf-03YsY18cmWv_g@mail.gmail.com/
    [5] https://lore.kernel.org/linux-mm/20210126230305.GD30941@willie-the-truck/
```

emmm, 上一章节提到的commit 想法是好的, 但是很多架构 cpu online的行为,可能发生在
某些slub已经创建之后(`kmem_cache_create()`), 这样获取的 online cpu 数量就是1了,
导致很多slub 的order 分配的是1, 在cpu个数比较多的大型系统上, 造成了严重的性能倒退...

里面有些链接没有分析, 例如Mel 报告的[2], 里面列出了一些性能测试结果,之后可以分析下.

那这里说下,为什么cpu越多, 使用`min_objects`越大越好, 作者这里只是简单的提了下:
因为cpu越多,假设系统中分配的slub的数量就比较多, 为了避免去频繁走伙伴系统路径,
所以最好将order设置的大一些.

关于解决方法, 作者则采用了中庸之道. 如果在slub create时,发现 `num_present_cpus()`
返回的不是1, 那么极有可能该值已经初始化好了, 将用该值作为cpu的数量去计算`min_objects`,
如果不是1, 那就使用 `nr_cpu_ids`, 这就相当于没有和`045ab8c9487b`, 并且不允许动态
调整 slub order, 正如`045ab8c9487b`中提到的, 实际运行的cpu数量 (online) 可能一直
会低于 `nr_cpu_ids`...

很郁闷, 是不是, 相当于在某些架构上回退了`045ab8c9487b`, 但是迄今为止(2023-11-19),
仍然还是这样的算法.

我们还是先来看下patch
```diff
diff --git a/mm/slub.c b/mm/slub.c
index 7ecbbbe5bc0c..b22a4b101c84 100644
--- a/mm/slub.c
+++ b/mm/slub.c
@@ -3423,6 +3423,7 @@ static inline int calculate_order(unsigned int size)
        unsigned int order;
        unsigned int min_objects;
        unsigned int max_objects;
+       unsigned int nr_cpus;

        /*
         * Attempt to find best configuration for a slab. This
@@ -3433,8 +3434,21 @@ static inline int calculate_order(unsigned int size)
         * we reduce the minimum objects required in a slab.
         */
        min_objects = slub_min_objects;
-       if (!min_objects)
-               min_objects = 4 * (fls(num_online_cpus()) + 1);
+       if (!min_objects) {
+               /*
+                * Some architectures will only update present cpus when
+                * onlining them, so don't trust the number if it's just 1. But
+                * we also don't want to use nr_cpu_ids always, as on some other
+                * architectures, there can be many possible cpus, but never
+                * onlined. Here we compromise between trying to avoid too high
+                * order on systems that appear larger than they are, and too
+                * low order on systems that appear smaller than they are.
+                */
                 /*
                  * compromise /ˈkɒmprəmaɪz/: 妥协;折中;和解;达成妥协(或和解);
                  */

                 /*
                  * 某些架构只会更新 present cpus 当 onlining 他们时, 如果
                  * 他们仅仅为1, 不要相信这个值. 但是我们也不想一直使用 
                  * nr_cpu_ids, 因为在某些架构上, 可能有 很多 possible cpus,
                  * 但是 从来不onlined. 在这里，我们在试图避免看起来比实际情况更大的
                  * 系统上的出现order过高和看起来比实际实际情况更小的系统上出现 
                  * order过低之间做出妥协。
                  */
+               nr_cpus = num_present_cpus();
+               if (nr_cpus <= 1)
+                       nr_cpus = nr_cpu_ids;
+               min_objects = 4 * (fls(nr_cpus) + 1);
+       }
        max_objects = order_objects(slub_max_order, size);
        min_objects = min(min_objects, max_objects);
```

patch 就不多说. 和 commit message中描述的一样


# 总结
slub order的值大多是基于性能考虑(时间复杂度,空间复杂度):

一方面, slub order变小,有利于伙伴系统产生较少的碎片.同时, 也不会出现过多的内存浪费

而另一方面, slub order变大,可能有利于 slub 产生较少的无法使用的 memory. 并且
减少对伙伴系统的调用. 而cpu越多, 调用次数可能就越多, 所以 大佬们基于cpu数量
计算 `min_objects`, 再根据 `min_objects`以及容忍浪费的内存比例 综合选择出一个
合适的order.

我们这篇笔记只是从代码改动的角度,走读了 slub order 代码流程变动的历史, 
但是未从性能影响的细节去分析(之后可能会去测试, 分析)
