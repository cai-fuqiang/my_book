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

## slub: Calculate min_objects based on number of processors

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

