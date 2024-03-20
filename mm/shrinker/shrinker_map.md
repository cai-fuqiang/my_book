# COMMIT message

> [\[PATCH v9 00/17\] Improve shrink_slab() scalability (old complexity
> was O(n^2), new is O(n))](https://lore.kernel.org/all/153112469064.4097.2581798353485457328.stgit@localhost.localdomain/)
```
Hi,

this patches solves the problem with slow shrink_slab() occuring
on the machines having many shrinkers and memory cgroups (i.e.,
with many containers). The problem is complexity of shrink_slab()
is O(n^2) and it grows too fast with the growth of containers
numbers.

> complexity /kəmˈpleksəti/ :  复杂性
>
> 该patch解决了在有许多shrinkers和memory cgroups 上的机器上, 当
> shrink_slab()发生时, 该流程很慢的问题.(i.e., 有许多的 containers
> 的环境). 该问题是由于 shrink_slab() 的复杂度为 O(n^2) 并且该复杂度
> 随着container数量的增加而快速增长

Let we have 200 containers, and every container has 10 mounts
and 10 cgroups. All container tasks are isolated, and they don't
touch foreign containers mounts.

> 让我们有 200 个容器, 并且每个容器有 10 mounts 和 10 cgroups. 所有容器
> 任务都是 isolated, 并且他们都不会访问 外面容器的挂载点.

In case of global reclaim, a task has to iterate all over the memcgs
and to call all the memcg-aware shrinkers for all of them. This means,
the task has to visit 200 * 10 = 2000 shrinkers for every memcg,
and since there are 2000 memcgs, the total calls of do_shrink_slab()
are 2000 * 2000 = 4000000.

> 在 global reclaim 中, task 必须遍历所有的 memcgs 并且对他们全部调用所有 
> 的 memcg-aware shrinkers. 这意味着, task 必须为每个 memcg 访问 200 * 10 
> = 2000 个shrinker, 并且因为有2000个memcgs, 调用 do_shrink_slab() 的总数
> 为 2000 * 2000 = 4000000

4 million calls are not a number operations, which can takes 1 cpu cycle.
E.g., super_cache_count() accesses at least two lists, and makes arifmetical
calculations. Even, if there are no charged objects, we do these calculations,
and replaces cpu caches by read memory. I observed nodes spending almost 100%
time in kernel, in case of intensive writing and global reclaim. The writer
consumes pages fast, but it's need to shrink_slab() before the reclaimer
reached shrink pages function (and frees SWAP_CLUSTER_MAX pages). Even if
there is no writing, the iterations just waste the time, and slows reclaim down.

> arithmetical [ˌærɪθˈmetɪkl]: 算数的
> in case of: 万一, 如果发生, 在...的情况下
>
> 4 million 调用不是一个数字操作, 可能需要花费1个cpu cycle. E.g., super_cache_count()
> 至少访问两个list, 并进行算数运算. 甚至, 如果没有charge objects, 我们做这些计算,并且
> 会因read memory 而 replaces cpu cache. 我观察到, 在密集写入和global reclaim 的情况下,
> 节点在kernel中将花费近 100% 的时间. writer 消耗page很快, 但是他需要在 relaimer 执行到
> shrink pages function (并且释放 SWAP_CLUSTER_MAX 页面) 之前 执行shrink_slab(). 即使
> 这没有writing, 该 iterations 只会 浪费时间, 并且减慢 reclaim.

Let's see the small test below:

$echo 1 > /sys/fs/cgroup/memory/memory.use_hierarchy
$mkdir /sys/fs/cgroup/memory/ct
$echo 4000M > /sys/fs/cgroup/memory/ct/memory.kmem.limit_in_bytes
$for i in `seq 0 4000`;
        do mkdir /sys/fs/cgroup/memory/ct/$i;
        echo $$ > /sys/fs/cgroup/memory/ct/$i/cgroup.procs;
        mkdir -p s/$i; mount -t tmpfs $i s/$i; touch s/$i/file;
done

Then, let's see drop caches time (5 sequential calls):

> sequential /sɪˈkwenʃl/: 顺序的, 按次序的

$time echo 3 > /proc/sys/vm/drop_caches

0.00user 13.78system 0:13.78elapsed 99%CPU
0.00user 5.59system 0:05.60elapsed 99%CPU
0.00user 5.48system 0:05.48elapsed 99%CPU
0.00user 8.35system 0:08.35elapsed 99%CPU
0.00user 8.34system 0:08.35elapsed 99%CPU

Last four calls don't actually shrink something. So, the iterations
over slab shrinkers take 5.48 seconds. Not so good for scalability.

> scalability  /skeɪləˈbɪlɪti/
>
> 后四次 调用 实际上 并不会 shrinker 什么. 所以对 slab shrinker的遍历,
> 将会花费5.48s. 可扩展性不太好.

The patchset solves the problem by making shrink_slab() of O(n)
complexity. There are following functional actions:
> 该patchset 通过将 shrink_slab() 的复杂度降为 0(n) 解决了这个问题.
> 这有以下 function actions

1)Assign id to every registered memcg-aware shrinker.
2)Maintain per-memcgroup bitmap of memcg-aware shrinkers,
  and set a shrinker-related bit after the first element
  is added to lru list (also, when removed child memcg
  elements are reparanted).
  > 维护 memcg-aware shrinker的 per-memcgroup bitmap 并且
  > 在第一个 element 加到 lru list 时, 设置一个 shrinker_related
  > bit(当remove child memcg 时, 也会将其 reparanted)

3)Split memcg-aware shrinkers and !memcg-aware shrinkers,
  and call a shrinker if its bit is set in memcg's shrinker
  bitmap.
  (Also, there is a functionality to clear the bit, after
  last element is shrinked).
  > 将 memcg-aware shrinker 和 !memcg-aware shrinker 分开.
  > 并且如果 memcg's shrinker bitmap中 如果该位被设置, 则调用
  > shrinker.

This gives signify performance increase. The result after patchset is applied:

> signify /ˈsɪɡnɪfaɪ/ : [v] To signify means to "mean." (这里是不是想表示 significant)
> 
> 这带来了明显的性能提升. 应用patchset后的结果如下:

$time echo 3 > /proc/sys/vm/drop_caches

0.00user 1.10system 0:01.10elapsed 99%CPU
0.00user 0.00system 0:00.01elapsed 64%CPU
0.00user 0.01system 0:00.01elapsed 82%CPU
0.00user 0.00system 0:00.01elapsed 64%CPU
0.00user 0.01system 0:00.01elapsed 82%CPU

The results show the performance increases at least in 548 times.

> 该结果表明至少有548 倍的性能提升.

So, the patchset makes shrink_slab() of less complexity and improves
the performance in such types of load I pointed. This will give a profit
in case of !global reclaim case, since there also will be less
do_shrink_slab() calls.

> profit: 利润;收益
>
> 所以, 该patchset 减少了 shrink_slab()的复杂度, 并且提高了 我上面指出的此类负载
> 的性能. 他也会在 !global reclaim 的情况下受益, 因为他也会减少 do_shrink_slab的调用.
```

# Before patch
我们主要关心两个路径:`add`, `reclaim`

`add`我们关注下 d_lru_list
## d_lru_add

> NOTE
>
> 我们这里从`d_lru_add()` 开始看, 不再看其之前的调用堆栈, 另外, 也不额外关注
> list lru 的相关数据结构和流程. 只看和 shrinker 相关的.

```cpp
static void d_lru_add(struct dentry *dentry)
{
        D_FLAG_VERIFY(dentry, 0);
        dentry->d_flags |= DCACHE_LRU_LIST;
        this_cpu_inc(nr_dentry_unused);
        WARN_ON_ONCE(!list_lru_add(&dentry->d_sb->s_dentry_lru, &dentry->d_lru));
}
```
在发现该`dentry`没有人引用时, 说明该`dentry` 作为`dcache` 而言是一个可以被释放的状态.
在内存紧张的时候, 可以找到该`dentry`, 然后进行释放, 而这里的动作就是将这些dentry
串起来, 以便之后查找.

```cpp
bool list_lru_add(struct list_lru *lru, struct list_head *item)
{
        int nid = page_to_nid(virt_to_page(item));
        struct list_lru_node *nlru = &lru->node[nid];
        struct list_lru_one *l;

        spin_lock(&nlru->lock);
        if (list_empty(item)) {
                l = list_lru_from_kmem(nlru, item);
                list_add_tail(item, &l->list);
                l->nr_items++;
                nlru->nr_items++;
                spin_unlock(&nlru->lock);
                return true;
        }
        spin_unlock(&nlru->lock);
        return false;
}
EXPORT_SYMBOL_GPL(list_lru_add);

static inline struct list_lru_one *
list_lru_from_kmem(struct list_lru_node *nlru, void *ptr)
{
        struct mem_cgroup *memcg;

        if (!nlru->memcg_lrus)
        }|    return &nlru->lru;

        memcg = mem_cgroup_from_kmem(ptr);
        if (!memcg)
                return &nlru->lru;

        return list_lru_from_memcg_idx(nlru, memcg_cache_id(memcg));
}
#
```
执行`list_lru_add`时, 会首先调用`list_lru_from_kmem()`获取一个 `list_lru_one`,
将后, 将该`dentry`加入到这个链表中.

而`list_lru_from_kmem` 则会根据该 `dentry slab object` 所在的page的mem_cgroup
的`memcg_id`, 在 `list_lru_node->memcg_lrus`中找到其所属的`list_lru_one`

我们再来看下`shrink_node`
```cpp

shrink_node
{
    ...
    do {
        //===(1)===
        memcg = mem_cgroup_iter()

        do {
            ...
            //==(2)==
            shrink_node_memcg() {
                shrink_list()
            }
            shrink_slab(sc->gfp_mask, pgdat->node_id, 
                    memcg, sc->priority);
            ...
            //==(3)==
            if (!global_reclaim(sc) &&
                sc->nr_reclaimed >= sc->nr_to_reclaim) {
                mem_cgroup_iter_break(root, memcg);
                break;
            }
        //===(1.1)===
        } while ((memcg = mem_cgroup_iter()));

    }while (should_continue_reclaim()
    //==(4)==
    if (global_reclaim(sc))
        shrink_slab(sc->gfp_mask, pgdat->node_id, NULL,
                    sc->priority);
    ...
}
```
1. 在`shrink_node()`中, 将会从`root_mem_cgroup`开始, 遍历所有的子cgroup
2. 每个cgroup调用`shrink_list()`, `shrink_slab()` 进行内存回收. 
3. 对于`global_reclaim`而言, 并不会有因为回收内存够了而break. 
   所以像`global_reclaim` 会将所有cgroup都遍历一遍.
4. 如果是`global reclaim`, 还会在循环外, 额外调用一次 `shrink_slab()`, 
   其中将`memcg`参数设置为`NULL`, 目的是为了无条件的将所有`shrinker`
   都回收一遍.

我们再来看下`shrink_slab`

```cpp
static unsigned long shrink_slab(gfp_t gfp_mask, int nid,
                                 struct mem_cgroup *memcg,
                                 int priority)
{
        struct shrinker *shrinker;
        unsigned long freed = 0;

        if (memcg && (!memcg_kmem_enabled() || !mem_cgroup_online(memcg)))
                return 0;

        if (!down_read_trylock(&shrinker_rwsem))
                goto out;
        //==(1)==
        list_for_each_entry(shrinker, &shrinker_list, list) {
                struct shrink_control sc = {
                        .gfp_mask = gfp_mask,
                        .nid = nid,
                        .memcg = memcg,
                };

                /*
                 * If kernel memory accounting is disabled, we ignore
                 * SHRINKER_MEMCG_AWARE flag and call all shrinkers
                 * passing NULL for memcg.
                 */
                if (memcg_kmem_enabled() &&
                    !!memcg != !!(shrinker->flags & SHRINKER_MEMCG_AWARE))
                        continue;

                if (!(shrinker->flags & SHRINKER_NUMA_AWARE))
                        sc.nid = 0;
                //==(2)==
                freed += do_shrink_slab(&sc, shrinker, priority);
                /*
                 * Bail out if someone want to register a new shrinker to
                 * prevent the regsitration from being stalled for long periods
                 * by parallel ongoing shrinking.
                 */
                if (rwsem_is_contended(&shrinker_rwsem)) {
                        freed = freed ? : 1;
                        break;
                }
        }

        up_read(&shrinker_rwsem);
out:
        cond_resched();
        return freed;
}
```

该代码和`rhel 4.18.0-372`的代码区别不大:
1. 遍历所有memcg
2. 调用`do_shrink_slab`, 对该`shrinker`进行回收

踪上, 可以看到, 在没有该patch之前, 如果要进行global reclaim, 需要在每一次`shrink_node`
时, 至少要
```
shrink_node {
    AT LEAST LOOP ONE TIME {
        shrink all memcg {
            shrink all MEMCG AWARE shrinker
        }
    }
}
```

# 具体PATCH 改动

## [Assign id to every memcg-aware shrinker](https://lore.kernel.org/all/153112546435.4097.10607140323811756557.stgit@localhost.localdomain/)
`struct shrinker` change:
```diff
@@ -66,6 +66,10 @@ struct shrinker {
 
 	/* These are for internal use */
 	struct list_head list;
+#ifdef CONFIG_MEMCG_KMEM
+	/* ID in shrinker_idr */
+	int id;
+#endif
 	/* objs pending delete, per node */
 	atomic_long_t *nr_deferred;
 };
```
增加了 shrinker_idr成员, 我们看看其分配和释放
```cpp
static int prealloc_memcg_shrinker(struct shrinker *shrinker)
{
	int id, ret = -ENOMEM;

	down_write(&shrinker_rwsem);
	/* This may call shrinker, so it must use down_read_trylock() */
	id = idr_alloc(&shrinker_idr, shrinker, 0, 0, GFP_KERNEL);
	if (id < 0)
		goto unlock;

	if (id >= shrinker_nr_max)
		shrinker_nr_max = id + 1;
	shrinker->id = id;
	ret = 0;
unlock:
	up_write(&shrinker_rwsem);
	return ret;
}

static void unregister_memcg_shrinker(struct shrinker *shrinker)
{
	int id = shrinker->id;

	BUG_ON(id < 0);

	down_write(&shrinker_rwsem);
	idr_remove(&shrinker_idr, id);
	up_write(&shrinker_rwsem);
}
```
使用的是`idr`机制来管理id, 并且使用`shrinker_nr_max`来记录当前分配到的最大的
id(我们下面会看到如何使用)

接下来, 我们看看这些函数在哪调用
```cpp
@@ -313,11 +357,28 @@ int prealloc_shrinker(struct shrinker *shrinker)
 	shrinker->nr_deferred = kzalloc(size, GFP_KERNEL);
 	if (!shrinker->nr_deferred)
 		return -ENOMEM;
+
+	if (shrinker->flags & SHRINKER_MEMCG_AWARE) {
+		if (prealloc_memcg_shrinker(shrinker))
+			goto free_deferred;
+	}
+
 	return 0;
+
+free_deferred:
+	kfree(shrinker->nr_deferred);
+	shrinker->nr_deferred = NULL;
+	return -ENOMEM;
 }
 void free_prealloced_shrinker(struct shrinker *shrinker)
 {
+	if (!shrinker->nr_deferred)
+		return;
+
+	if (shrinker->flags & SHRINKER_MEMCG_AWARE)
+		unregister_memcg_shrinker(shrinker);
+
 	kfree(shrinker->nr_deferred);
 	shrinker->nr_deferred = NULL;
 }
@@ -347,6 +408,8 @@ void unregister_shrinker(struct shrinker *shrinker)
 {
 	if (!shrinker->nr_deferred)
 		return;
+	if (shrinker->flags & SHRINKER_MEMCG_AWARE)
+		unregister_memcg_shrinker(shrinker);
 	down_write(&shrinker_rwsem);
 	list_del(&shrinker->list);
 	up_write(&shrinker_rwsem);
```
这里看似有两套相互重叠的流程, 我们这里简单说下:
目前使用的`shrinker`分配主要有两种方式:
* `global variables`: 全局变量
* `alloc`: 动态分配
目前使用 `alloc`方式的, 只有super block, (用来管理dcache,inode).
而`prealloced`相关接口就是用在`alloc`方式分配的`shrinker`(不如说就是
给 superblock 使用)
> !!!
>
> 还需要再看下这部分


那现在为每个shrinker 分配了id, 如果在memcg中标记呢, 我们来看下一个patch

## [Assign memcg-aware shrinkers bitmap to memcg](https://lore.kernel.org/all/153112549031.4097.3576147070498769979.stgit@localhost.localdomain/)
我们先看下commit message:
```
magine a big node with many cpus, memory cgroups and containers.
Let we have 200 containers, every container has 10 mounts,
and 10 cgroups. All container tasks don't touch foreign
containers mounts. If there is intensive pages write,
and global reclaim happens, a writing task has to iterate
over all memcgs to shrink slab, before it's able to go
to shrink_page_list().

Iteration over all the memcg slabs is very expensive:
the task has to visit 200 * 10 = 2000 shrinkers
for every memcg, and since there are 2000 memcgs,
the total calls are 2000 * 2000 = 4000000.

So, the shrinker makes 4 million do_shrink_slab() calls
just to try to isolate SWAP_CLUSTER_MAX pages in one
of the actively writing memcg via shrink_page_list().
I've observed a node spending almost 100% in kernel,
making useless iteration over already shrinked slab.

> 前面就不说了, patch 0 中已经描述了.

This patch adds bitmap of memcg-aware shrinkers to memcg.
The size of the bitmap depends on bitmap_nr_ids, and during
memcg life it's maintained to be enough to fit bitmap_nr_ids
shrinkers. Every bit in the map is related to corresponding
shrinker id.

> 该patch增加了  memcg-aware shrinker bitmap 到memcg 中.
> 该bitmap的大小以来 bitmap_nr_ids(这里我感觉应该是 shrinker_nr_max), 
> 并且在memcg的生命周期中, 他将维持足够容纳 bitmap_nr_ids shrinker.
> map中的每个bit将关联相应的 shrinker id.

Next patches will maintain set bit only for really charged
memcg. This will allow shrink_slab() to increase its
performance in significant way. See the last patch for
the numbers.

> 下一个patch 将只在真正 charge memcg 时候 set bit. 这将使得
> shrink_slab()以显著的方式提升性能. 在最后一个patch中可以看到其
> 数值(性能提升的)
```
### 数据结构变动:
```diff
+/*
+ * Bitmap of shrinker::id corresponding to memcg-aware shrinkers,
+ * which have elements charged to this memcg.
+ */
+struct memcg_shrinker_map {
+	struct rcu_head rcu;
+	unsigned long map[0];
+};
+
 /*
  * per-zone information in memory controller.
  */
@@ -124,6 +133,9 @@ struct mem_cgroup_per_node {
 
 	struct mem_cgroup_reclaim_iter	iter[DEF_PRIORITY + 1];
 
+#ifdef CONFIG_MEMCG_KMEM
+	struct memcg_shrinker_map __rcu	*shrinker_map;
+#endif
 	struct rb_node		tree_node;	/* RB tree node */
 	unsigned long		usage_in_excess;/* Set to the value by which */
 						/* the soft limit is exceeded*/
@@ -1225,6 +1237,8 @@ static inline int memcg_cache_id(struct mem_cgroup *memcg)
 	return memcg ? memcg->kmemcg_id : -1;
 }
```
在 `mem_cgroup_per_node`中, 增加 `memcg_shrinker_map::shrinker_map`

> NOTE
>
> 这里为什么要在`mem_cgroup_per_node`中增加这一数据结构呢, 因为 `list_lru_add()`时, 
> 本身就是指定node的. 所以这样更能减少loop的次数.

`memcg_shrinker_map::map` 则是一个`bitmap`, 记录当shrinker first charge to this cgroup of 
node 时,  则设置上. 我们来看下具体代码:

### alloc
```diff
 /**
@@ -4305,6 +4418,11 @@ static int mem_cgroup_css_online(struct cgroup_subsys_state *css)
 {
 	struct mem_cgroup *memcg = mem_cgroup_from_css(css);
 
+	if (memcg_alloc_shrinker_maps(memcg)) {
+		mem_cgroup_id_remove(memcg);
+		return -ENOMEM;
+	}
+
 	/* Online state pins memcg ID, memcg ID pins CSS */
 	atomic_set(&memcg->id.ref, 1);
 	css_get(css);
```
在 css online 借口中, 调用`memcg_alloc_shrinker_maps()`

```cpp
static int memcg_shrinker_map_size;
static DEFINE_MUTEX(memcg_shrinker_map_mutex);
...

static int memcg_alloc_shrinker_maps(struct mem_cgroup *memcg)
{
	struct memcg_shrinker_map *map;
	int nid, size, ret = 0;

	if (mem_cgroup_is_root(memcg))
		return 0;

	mutex_lock(&memcg_shrinker_map_mutex);
	size = memcg_shrinker_map_size;
	for_each_node(nid) {
		map = kvzalloc(sizeof(*map) + size, GFP_KERNEL);
		if (!map) {
			memcg_free_shrinker_maps(memcg);
			ret = -ENOMEM;
			break;
		}
		rcu_assign_pointer(memcg->nodeinfo[nid]->shrinker_map, map);
	}
	mutex_unlock(&memcg_shrinker_map_mutex);

	return ret;
}
```
代码流程也比较简单, 为一个node 分配 `memcg_shrinker_map`, 
注意这里的结构是
```
|struct memcg_shrinker_map| map |
```
而`map`的大小由全局变量`memcg_shrinker_map_size`指定. 整个过程由
`memcg_shrinker_map_mutex` 信号量保护.

> NOTE
>
> Q: 这里和哪部分流程有race呢
>
> A: memcg_expand_shrinker_maps(), 我们下面会看到

### free
```cpp
@@ -4357,6 +4475,7 @@ static void mem_cgroup_css_free(struct cgroup_subsys_state *css)
 	vmpressure_cleanup(&memcg->vmpressure);
 	cancel_work_sync(&memcg->high_work);
 	mem_cgroup_remove_from_trees(memcg);
+	memcg_free_shrinker_maps(memcg);
 	memcg_free_kmem(memcg);
 	mem_cgroup_free(memcg);
 }
```
```cpp
static void memcg_free_shrinker_maps(struct mem_cgroup *memcg)
{
	struct mem_cgroup_per_node *pn;
	struct memcg_shrinker_map *map;
	int nid;

	if (mem_cgroup_is_root(memcg))
		return;

	for_each_node(nid) {
		pn = mem_cgroup_nodeinfo(memcg, nid);
		map = rcu_dereference_protected(pn->shrinker_map, true);
		if (map)
			kvfree(map);
		rcu_assign_pointer(pn->shrinker_map, NULL);
	}
}
```
代码比较简单, 不赘述.

`memcg_shrinker_map_size`是全局变量, 默认是0, 那该值什么时候会增加呢?

map的容量实际上和shrinker_id的数量(最大值)相关, 那一定是在申请shrinker_id
的时候,会去变动该值, 该流程发生在 register/prealloc  shrinker. 那么变动该值时,
每个cgroup per node shrinker map 也应该需要变动. 

我们来看下相关流程.

### expand shrinker map
```
@@ -183,8 +183,14 @@ static int prealloc_memcg_shrinker(struct shrinker *shrinker)
 	if (id < 0)
 		goto unlock;
 
-	if (id >= shrinker_nr_max)
+	if (id >= shrinker_nr_max) {
+		if (memcg_expand_shrinker_maps(id)) {
+			idr_remove(&shrinker_idr, id);
+			goto unlock;
+		}
+
 		shrinker_nr_max = id + 1;
+	}
 	shrinker->id = id;
 	ret = 0;
```

> NOTE
>
> 这里只有这个函数会调用`memcg_expand_shrinker_maps`, 实际上, 
> register_shrinker()会调用`peralloc_memcg_shrinker()`

`memcg_expand_shrinker_maps`
```cpp
int memcg_expand_shrinker_maps(int new_id)
{
	int size, old_size, ret = 0;
	struct mem_cgroup *memcg;
    //==(1)==
	size = DIV_ROUND_UP(new_id + 1, BITS_PER_LONG) * sizeof(unsigned long);
	old_size = memcg_shrinker_map_size;
	if (size <= old_size)
		return 0;

	mutex_lock(&memcg_shrinker_map_mutex);
	if (!root_mem_cgroup)
		goto unlock;

	for_each_mem_cgroup(memcg) {
		if (mem_cgroup_is_root(memcg))
			continue;
        //==(2)==
		ret = memcg_expand_one_shrinker_map(memcg, size, old_size);
		if (ret)
			goto unlock;
	}
unlock:
	if (!ret)
        //==(3)==
		memcg_shrinker_map_size = size;
	mutex_unlock(&memcg_shrinker_map_mutex);
	return ret;
}
```
1. 会根据`new_id + 1`, 计算新的 map size, 然后和`old_size`比较,如果发现增长了, 这里的
   信号量的使用也很精确. 因为这里是读操作, 而除了该函数流程, 其他地方也都只是读操作, 
   所以信号量没有必要囊括这个对`memcg_shrinker_map_size`的读操作.
2. 遍历每个 memcg, 扩展其 shrinker map
3. 将`memcg_shrinker_map_size`赋值为新的`size`

`memcg_expand_one_shrinker_map`:
```cpp
static int memcg_expand_one_shrinker_map(struct mem_cgroup *memcg,
					 int size, int old_size)
{
	struct memcg_shrinker_map *new, *old;
	int nid;

	lockdep_assert_held(&memcg_shrinker_map_mutex);

	for_each_node(nid) {
        //==(1)==
		old = rcu_dereference_protected(
			mem_cgroup_nodeinfo(memcg, nid)->shrinker_map, true);
		/* Not yet online memcg */
		if (!old)
			return 0;

        //==(2)==
		new = kvmalloc(sizeof(*new) + size, GFP_KERNEL);
		if (!new)
			return -ENOMEM;

		/* Set all old bits, clear all new bits */
		memset(new->map, (int)0xff, old_size);
		memset((void *)new->map + old_size, 0, size - old_size);

		rcu_assign_pointer(memcg->nodeinfo[nid]->shrinker_map, new);
        //==(3)==
		call_rcu(&old->rcu, memcg_free_shrinker_map_rcu);
	}

	return 0;
}
```
1. 获取old map
2. 申请new map, 并将old bit 全部设置为 1, 将新增加的 bit全部设置为0
   > NOTE
   >
   > 大家想想为什么要这么做, 而不是使用memcpy(new, old, old_size)呢, 
   > 我个人认为可以从两个方面考虑:
   > 1. 执行memcpy时, 由于不是atomic, 此时, 可能会有其他cpu并行执行
   >    set_shrinker_bit(), 从而导致set bit的丢失.
   > 2. 即便 1  中的行为没有发生, 但是在其之后, old->rcucallbak 执行
   >    之前. 还是会有可能set_shrinker_bit() 访问到了 old map.
3. rcu free old map

接下来, 我们去看下在什么时候 set/clean shrinker bit 

## [set shrinker bit](https://lore.kernel.org/all/153112557572.4097.17315791419810749985.stgit@localhost.localdomain/#t)

COMMIT message:
```
Introduce set_shrinker_bit() function to set shrinker-related
bit in memcg shrinker bitmap, and set the bit after the first
item is added and in case of reparenting destroyed memcg's items.

> 引入 set_shrinker_bit() function 来 set memcg shrinker bitmap 中
> 和该shrinker-related 的bit. 在 item 第一次被add 和 destroy memcg's 
> items 时 而执行 reparent操作时 会执行到set bit

This will allow next patch to make shrinkers be called only,
in case of they have charged objects at the moment, and
to improve shrink_slab() performance.

> 这将使下一个patch可以让shrinkers 只在其已经charge object时,
> 才被调用到,并且提升了 shrink_slab()的性能.
```
set bit主要函数
```cpp
void memcg_set_shrinker_bit(struct mem_cgroup *memcg, int nid, int shrinker_id)
{
    //==(1)==
	if (shrinker_id >= 0 && memcg && !mem_cgroup_is_root(memcg)) {
		struct memcg_shrinker_map *map;

		rcu_read_lock();
        //==(2)==
		map = rcu_dereference(memcg->nodeinfo[nid]->shrinker_map);
		set_bit(shrinker_id, map->map);
		rcu_read_unlock();
	}
}
```

1. 这里有一些检查, 需要注意的是, 在 nokmem 的情况下, memcg 传入的为NULL, 不会走下面的流程.
2. 可以看到这里和 `memcg_expand_one_shrinker_map`有race的情况.

从COMMIT message中可以得知, 该函数的调用者主要有两个:
* object add
  ```diff
  @@ -118,13 +128,17 @@ bool list_lru_add(struct list_lru *lru, struct list_head *item)
   {
   	int nid = page_to_nid(virt_to_page(item));
   	struct list_lru_node *nlru = &lru->node[nid];
  +	struct mem_cgroup *memcg;
   	struct list_lru_one *l;
   
   	spin_lock(&nlru->lock);
   	if (list_empty(item)) {
  -		l = list_lru_from_kmem(nlru, item, NULL);
  +		l = list_lru_from_kmem(nlru, item, &memcg);
   		list_add_tail(item, &l->list);
  -		l->nr_items++;
  +		/* Set shrinker bit if the first element was added */
        //==(1)==
  +		if (!l->nr_items++)
  +			memcg_set_shrinker_bit(memcg, nid,
  +					       lru_shrinker_id(lru));
   		nlru->nr_items++;
   		spin_unlock(&nlru->lock);
   		return true;
  ```
   > NOTE
   >
   > (1) 这里的作用是, 只有第一次object加入的时候, 才会去set_bit, 避免了频繁set bit.
* reparent
  ```diff
  @@ -507,6 +521,7 @@ static void memcg_drain_list_lru_node(struct list_lru *lru, int nid,
   	struct list_lru_node *nlru = &lru->node[nid];
   	int dst_idx = dst_memcg->kmemcg_id;
   	struct list_lru_one *src, *dst;
  +	bool set;
   
   	/*
   	 * Since list_lru_{add,del} may be called under an IRQ-safe lock,
  @@ -518,7 +533,10 @@ static void memcg_drain_list_lru_node(struct list_lru *lru, int nid,
   	dst = list_lru_from_memcg_idx(nlru, dst_idx);
   
   	list_splice_init(&src->list, &dst->list);
  +	set = (!dst->nr_items && src->nr_items);
   	dst->nr_items += src->nr_items;
  +	if (set)
  +		memcg_set_shrinker_bit(dst_memcg, nid, lru_shrinker_id(lru));
   	src->nr_items = 0;
  ```
  > NOTE
  >
  > 该流程发生的流程是 offline children cgroup, reparent. 所以不会有上面我们所说的race情况.
  > 也就是不会有 src->nr_items 在这个过程中change的情况.

### [clear shrinker bit  1](https://lore.kernel.org/all/153112558507.4097.12713813335683345488.stgit@localhost.localdomain/)

COMMIT MESSAGE
```
Using the preparations made in previous patches, in case of memcg
shrink, we may avoid shrinkers, which are not set in memcg's shrinkers
bitmap. To do that, we separate iterations over memcg-aware and
!memcg-aware shrinkers, and memcg-aware shrinkers are chosen
via for_each_set_bit() from the bitmap. In case of big nodes,
having many isolated environments, this gives significant
performance growth. See next patches for the details.

> preparation /ˈprɛpəˌreɪʃən/ : preparation is the act of preparing 
> separate /ˈsɛpəˌreɪt/: Things that are separate are kept apart from other things. 
>
> 使用前一个patch中的准备工作, 在 memcg shrink的情况下, 我们可以避免
> 那些没有在 shrinker bitmap设置的 shrinkers. 为了做到这些, 我们将
> memcg-aware和 !memcg-aware 的shrinker进行分类, 并通过 for_each_set_bit() 从
> bitmap 中选择 shrinkers. 在 big nodes的情况下, 会有很多 isolate environments,
> 这带来了显著的性能提升. 请看下一个patchs了解更多细节.

Note, that the patch does not respect to empty memcg shrinkers,
since we never clear the bitmap bits after we set it once.
Their shrinkers will be called again, with no shrinked objects
as result. This functionality is provided by next patches.

> 注意, 那个patch不去考虑 empty memcg shrinkers. 因为我们一旦设置了
> 之后, 从不clear bitmap bits. 这些 shrinkers 将会再次被调用, 结果不会有
> 被 shrink 的objects. 该功能将会在下一个patch中被提供.
```

我们先来看 `shrink_slab`对比
```diff
 /**
  * shrink_slab - shrink slab caches
  * @gfp_mask: allocation context
@@ -572,8 +644,8 @@ static unsigned long shrink_slab(gfp_t gfp_mask, int nid,
 	struct shrinker *shrinker;
 	unsigned long freed = 0;
 
-	if (memcg && (!memcg_kmem_enabled() || !mem_cgroup_online(memcg)))
-		return 0;
    //==(1)==
+	if (memcg && !mem_cgroup_is_root(memcg))
+		return shrink_slab_memcg(gfp_mask, nid, memcg, priority);
 
 	if (!down_read_trylock(&shrinker_rwsem))
 		goto out;
@@ -585,13 +657,7 @@ static unsigned long shrink_slab(gfp_t gfp_mask, int nid,
 			.memcg = memcg,
 		};
 
-		/*
-		 * If kernel memory accounting is disabled, we ignore
-		 * SHRINKER_MEMCG_AWARE flag and call all shrinkers
-		 * passing NULL for memcg.
-		 */
-		if (memcg_kmem_enabled() &&
-		    !!memcg != !!(shrinker->flags & SHRINKER_MEMCG_AWARE))
        //==(2)==
+		if (!!memcg != !!(shrinker->flags & SHRINKER_MEMCG_AWARE))
 			continue;
 
```

1. `memcg && ! root memcg`会直接调用`shrink_slab_memcg`
2. 在没有引入shrinker->map时, 我们分情况考虑需要处理的情况
   + `memcg_kmem_enabled()`, 有两种情况需要处理
       * memcg && shrinker->flags & SHRINKER_MEMCG_AWARE <br/>
         这种情况是要回memcg相关的 shrinker(相当于指定memcg回收)
       + !memcg && !shrinker->flags & SHRINKER_MEMCG_AWARE<br/>
         这种情况是, 不要回收和memcg 相关的shrinker(相当于global)
   + `!memcg_kmem_enabled()`<br/>
     忽略 SHRINKER_MEMCG_AWARE, 对于!memcg 情况下call all shrinker
     (其实能走到这, 说明是!memcg, 可以见(1)中的条件)

   那么在引入该patch, 能走到这里来, 只有两种情况:
   + !memcg : call UNWARE shrineker
   + root memcg : call AWARE shrinker

> NOTE
>
> 这个函数逻辑很乱, 但是在
> ```
> commit aeed1d325d429ac9699c4bf62d17156d60905519
> Author: Vladimir Davydov <vdavydov.dev@gmail.com>
> Date:   Fri Aug 17 15:48:17 2018 -0700
> 
>     mm/vmscan.c: generalize shrink_slab() calls in shrink_node()
> ```
> 该patch中进一步优化了这部分代码, 删除 传入 memcg NULL的代码,
> 只传入 root memcg 或者 !root memcg, 只在 root memcg的情况下, 
> call UNWARE shrinker
>
> 另外, 在后续版本的代码中(rhel 8.6 372 kernel) `root_mem_cgroup`
> 很特殊. 在 `get_obj_cgroup_from_current()`中可以看到, 当为
> `root_mem_cgroup`时, objcg返回NULL.
>
>> NOTE
>> 
>> 看了下mail list, 这个patch, 确实是`Vladimir Davydov`, 但是 Kirill
>> 发出来了, 也在这个maillist中.
>>
>> [LINK](https://lore.kernel.org/all/153112559593.4097.7399035563205590079.stgit@localhost.localdomain/)
>>
>> 不再展开

我们接下来看`shrinker_slab_memcg()`相关代码
```cpp
#ifdef CONFIG_MEMCG_KMEM
static unsigned long shrink_slab_memcg(gfp_t gfp_mask, int nid,
			struct mem_cgroup *memcg, int priority)
{
	struct memcg_shrinker_map *map;
	unsigned long freed = 0;
	int ret, i;

	if (!memcg_kmem_enabled() || !mem_cgroup_online(memcg))
		return 0;

	if (!down_read_trylock(&shrinker_rwsem))
		return 0;

	map = rcu_dereference_protected(memcg->nodeinfo[nid]->shrinker_map,
					true);
	if (unlikely(!map))
		goto unlock;

	for_each_set_bit(i, map->map, shrinker_nr_max) {
		struct shrink_control sc = {
			.gfp_mask = gfp_mask,
			.nid = nid,
			.memcg = memcg,
		};
		struct shrinker *shrinker;
        //==(1)==
		shrinker = idr_find(&shrinker_idr, i);
		if (unlikely(!shrinker)) {
			clear_bit(i, map->map);
			continue;
		}

        //==(2)==
		/* See comment in prealloc_shrinker() */
		if (unlikely(list_empty(&shrinker->list)))
			continue;

		ret = do_shrink_slab(&sc, shrinker, priority);
		freed += ret;

		if (rwsem_is_contended(&shrinker_rwsem)) {
			freed = freed ? : 1;
			break;
		}
	}
unlock:
	up_read(&shrinker_rwsem);
	return freed;
}
```
1. 如果map中设置了, 但是 shrinker已经不在 idr中了, 那就说明
   走了unregister的流程, 需要clear_bit()
2. 理解这部分代码, 我们得需要看, 该patch中的另外一个改动

```diff
diff --git a/mm/vmscan.c b/mm/vmscan.c
index db0970ba340d..d7a5b8566869 100644
--- a/mm/vmscan.c
+++ b/mm/vmscan.c
@@ -364,6 +364,21 @@ int prealloc_shrinker(struct shrinker *shrinker)
 	if (!shrinker->nr_deferred)
 		return -ENOMEM;
 
+	/*
+	 * There is a window between prealloc_shrinker()
+	 * and register_shrinker_prepared(). We don't want
+	 * to clear bit of a shrinker in such the state
+	 * in shrink_slab_memcg(), since this will impose
+	 * restrictions on a code registering a shrinker
+	 * (they would have to guarantee, their LRU lists
+	 * are empty till shrinker is completely registered).
+	 * So, we differ the situation, when 1)a shrinker
+	 * is semi-registered (id is assigned, but it has
+	 * not yet linked to shrinker_list) and 2)shrinker
+	 * is not registered (id is not assigned).
+	 * 
+	 * 在prealloc_shrinker()和 register_shrinker_prepared()
+	 * 之前有一个window. 我们不想在这样的状态下, 在shrink_slab_memcg()中
+	 * clear_bit(). 因为这将会在register a shrinker是增加一些
+	 * 限制(他们必须去保证, 他们的LRU lists在 shrinker 完全
+	 * register 之前是empty的. 所以, 我们下面两种情况不同, 当 
+	 * 1) shrinker 是半register的状态(id 已经被分配, 但是还没有linked
+	 * 到 shrinker_list) 
+	 * 2) shrinker还没有被注册 (id 还未分配)
+	 */
+	INIT_LIST_HEAD(&shrinker->list);
+
 	if (shrinker->flags & SHRINKER_MEMCG_AWARE) {
 		if (prealloc_memcg_shrinker(shrinker))
 			goto free_deferred;
```

大概就是通过`shrinker->list`是不是null, 用来判断, 有没有注册完全该shrinker,
如果注册了一半(执行了 `prealloc_shrinker()`但是没有执行 `register_shrinker_prepared()`
则不能clear_bit()

所以,这个patch仅仅是让其在 unregister 时, 去`clear_bit()`, 我们在看看下面的patch


### [clear shrinker bit 2 -- BEFORE MAGIC ](https://lore.kernel.org/all/153112560649.4097.6012718861285659974.stgit@localhost.localdomain/)

COMMIT MESSAGE:
```
mm: Add SHRINK_EMPTY shrinker methods return value

We need to differ the situations, when shrinker has
very small amount of objects (see vfs_pressure_ratio()
called from super_cache_count()), and when it has no
objects at all. Currently, in the both of these cases,
shrinker::count_objects() returns 0.

> 我们需要区分两种情况,  当 shrinker 已经有非常小的object
> 总量(请看 super_cache_count()->vfs_pressure_ratio()).
> 和已经彻底没有object. 在当前的这两种情况下, 
> shrinker::count_objects() 都返回0

The patch introduces new SHRINK_EMPTY return value,
which will be used for "no objects at all" case.
It's is a refactoring mostly, as SHRINK_EMPTY is replaced
by 0 by all callers of do_shrink_slab() in this patch,
and all the magic will happen in further.

> 该patch 引入了新的返回值: SHRINK_EMPTY, 用于表示 "no objects
> at all"的情况. 这主要是一次重构, 在这个patch中,所有 do_shrink_slab()
> 的callers 都将 SHRINK_EMPTY 替换为0, all the magic 将会在未来发生(
> 所有的魔法, 幽默)
```

通过commit message得知, 该patch 主要是增加了一个返回值 `SHRINK_EMPTY`, 
```diff
 #define SHRINK_STOP (~0UL)
+#define SHRINK_EMPTY (~0UL - 1)
```
现在有两个特殊的返回值`SHRINK_EMPTY`, `0`
* SHRINK_EMPTY : no objects at all
* 0 : very small amount of objects
```diff
 /*
  * A callback you can register to apply pressure to ageable caches.
  *
  * @count_objects should return the number of freeable items in the cache. If
- * there are no objects to free or the number of freeable items cannot be
- * determined, it should return 0. No deadlock checks should be done during the
+ * there are no objects to free, it should return SHRINK_EMPTY, while 0 is
+ * returned in cases of the number of freeable items cannot be determined
+ * or shrinker should skip this cache for this time (e.g., their number
+ * is below shrinkable limit). No deadlock checks should be done during the
  * count callback - the shrinker relies on aggregating scan counts that couldn't
  * be executed due to potential deadlocks to be run at a later call when the
  * deadlock condition is no longer pending.
```

然后, 该patch只是一个中间版本, 在`do_shrink_slab`调用者检测到`SHRINK_EMPTY`时,
先当作`0`处理.

```diff
@@ -456,8 +456,8 @@ static unsigned long do_shrink_slab(struct shrink_control *shrinkctl,
 	long scanned = 0, next_deferred;
 	freeable = shrinker->count_objects(shrinker, shrinkctl);
-	if (freeable == 0)
-		return 0;
+	if (freeable == 0 || freeable == SHRINK_EMPTY)
+		return freeable;
 
 	/*
 	 * copy the current shrinker scan count into a local variable
@@ -596,6 +596,8 @@ static unsigned long shrink_slab_memcg(gfp_t gfp_mask, int nid,
 			continue;
 
 		ret = do_shrink_slab(&sc, shrinker, priority);
+		if (ret == SHRINK_EMPTY)
+			ret = 0;
 		freed += ret;
 
 		if (rwsem_is_contended(&shrinker_rwsem)) {
@@ -641,6 +643,7 @@ static unsigned long shrink_slab(gfp_t gfp_mask, int nid,
 {
 	struct shrinker *shrinker;
 	unsigned long freed = 0;
+	int ret;
 
 	if (!mem_cgroup_is_root(memcg))
 		return shrink_slab_memcg(gfp_mask, nid, memcg, priority);
@@ -658,7 +661,10 @@ static unsigned long shrink_slab(gfp_t gfp_mask, int nid,
 		if (!(shrinker->flags & SHRINKER_NUMA_AWARE))
 			sc.nid = 0;
 
-		freed += do_shrink_slab(&sc, shrinker, priority);
+		ret = do_shrink_slab(&sc, shrinker, priority);
+		if (ret == SHRINK_EMPTY)
+			ret = 0;
+		freed += ret;
```

我们来看其`SHRINK_EMPTY`的赋值:
```diff
diff --git a/fs/super.c b/fs/super.c
index f5f96e52e0cd..7429588d6b49 100644
--- a/fs/super.c
+++ b/fs/super.c
@@ -144,6 +144,9 @@ static unsigned long super_cache_count(struct shrinker *shrink,
 	total_objects += list_lru_shrink_count(&sb->s_dentry_lru, sc);
 	total_objects += list_lru_shrink_count(&sb->s_inode_lru, sc);
 
+	if (!total_objects)
+		return SHRINK_EMPTY;
+
 	total_objects = vfs_pressure_ratio(total_objects);
 	return total_objects;
 }

diff --git a/mm/workingset.c b/mm/workingset.c
index cd0b2ae615e4..bc72ad029b3e 100644
--- a/mm/workingset.c
+++ b/mm/workingset.c
@@ -399,6 +399,9 @@ static unsigned long count_shadow_nodes(struct shrinker *shrinker,
 	}
 	max_nodes = cache >> (RADIX_TREE_MAP_SHIFT - 3);
 
+	if (!nodes)
+		return SHRINK_EMPTY;
+
 	if (nodes <= max_nodes)
 		return 0;
 	return nodes - max_nodes;
```


### [clear shrinker bit 3 -- PERFORM MAGIC ](https://lore.kernel.org/all/153112560649.4097.6012718861285659974.stgit@localhost.localdomain/)

COMMIT MESSAGE:
```
To avoid further unneed calls of do_shrink_slab()
for shrinkers, which already do not have any charged
objects in a memcg, their bits have to be cleared.

> 为了避免未来不必要的shrinkers对 do_shrink_slab的调用,
> 这些shrinker在一个memcg中并没有charge 任何的objects, 
> 他们的bits 应该被cleared

This patch introduces a lockless mechanism to do that
without races without parallel list lru add. After
do_shrink_slab() returns SHRINK_EMPTY the first time,
we clear the bit and call it once again. Then we restore
the bit, if the new return value is different.

> 该patch 引入了一个lockless 机制, 可以在没有race 没有并行的 
> list lru add 来做这件事情. 在 do_shrink_slab() 第一次返回 
> SHRINK_EMPTY后, 我们 clear 该 bit, 并且再一次调用它. 然后
> 如果返回值不一样, 我们 restore 该 bit.

Note, that single smp_mb__after_atomic() in shrink_slab_memcg()
covers two situations:

> 注意: 这个 shrink_slab_memcg 中的 smp_mb__after_atomic() 覆盖了
> 两种情况:

1)list_lru_add()     shrink_slab_memcg
    list_add_tail()    for_each_set_bit() <--- read bit
                         do_shrink_slab() <--- missed list update (no barrier)
    <MB>                 <MB>
    set_bit()            do_shrink_slab() <--- seen list update

This situation, when the first do_shrink_slab() sees set bit,
but it doesn't see list update (i.e., race with the first element
queueing), is rare. So we don't add <MB> before the first call
of do_shrink_slab() instead of this to do not slow down generic
case. Also, it's need the second call as seen in below in (2).

> 这种情况, 当 第一次 do_shrink_slab()看到了该bit, 但是其看不到 list update
> (i.e., 和第一次的 element queueing 冲突), 是罕见的. 所以我们没有在
> do_shrink_slab()第一次调用之前增加 <MB>, 而是这样做, 以避免
> 减慢一般情况的速度. 此外, 他需要第二个调用, 如下面(2)所示:

2)list_lru_add()      shrink_slab_memcg()
    list_add_tail()     ...
    set_bit()           ...
  ...                   for_each_set_bit()
  do_shrink_slab()        do_shrink_slab()
    clear_bit()           ...
  ...                     ...
  list_lru_add()          ...
    list_add_tail()       clear_bit()
    <MB>                  <MB>
    set_bit()             do_shrink_slab()

The barriers guarantees, the second do_shrink_slab()
in the right side task sees list update if really
cleared the bit. This case is drawn in the code comment.

> drawn: 描绘绘画
>
> barriers 保证了右侧tasks中的第二个 do_shrink_slab()可以看到
> list 更新,如果真的clear了该bit. 这种情况, 在 code comment
> 中描述.

[Results/performance of the patchset]

After the whole patchset applied the below test shows signify
increase of performance:

> 在整个patchset被引用后, 下面的test 展示出显著的 性能提升

$echo 1 > /sys/fs/cgroup/memory/memory.use_hierarchy
$mkdir /sys/fs/cgroup/memory/ct
$echo 4000M > /sys/fs/cgroup/memory/ct/memory.kmem.limit_in_bytes
    $for i in `seq 0 4000`; do mkdir /sys/fs/cgroup/memory/ct/$i;
			    echo $$ > /sys/fs/cgroup/memory/ct/$i/cgroup.procs;
			    mkdir -p s/$i; mount -t tmpfs $i s/$i;
			    touch s/$i/file; done

Then, 5 sequential calls of drop caches:
$time echo 3 > /proc/sys/vm/drop_caches

1)Before:
0.00user 13.78system 0:13.78elapsed 99%CPU
0.00user 5.59system 0:05.60elapsed 99%CPU
0.00user 5.48system 0:05.48elapsed 99%CPU
0.00user 8.35system 0:08.35elapsed 99%CPU
0.00user 8.34system 0:08.35elapsed 99%CPU

2)After
0.00user 1.10system 0:01.10elapsed 99%CPU
0.00user 0.00system 0:00.01elapsed 64%CPU
0.00user 0.01system 0:00.01elapsed 82%CPU
0.00user 0.00system 0:00.01elapsed 64%CPU
0.00user 0.01system 0:00.01elapsed 82%CPU

The results show the performance increases at least in 548 times.

> 性能提升了 548 倍

Shakeel Butt tested this patchset with fork-bomb on his configuration:

> Shakeel Butt 在他的配置中带该patchset测试 fork-bomb

 > I created 255 memcgs, 255 ext4 mounts and made each memcg create a
 > file containing few KiBs on corresponding mount. Then in a separate
 > memcg of 200 MiB limit ran a fork-bomb.
 >
 >> 然后在一个单独限制为200M的memcg中运行一个 fork-bomb.
 >
 > I ran the "perf record -ag -- sleep 60" and below are the results:
 >
 > Without the patch series:
 > Samples: 4M of event 'cycles', Event count (approx.): 3279403076005
 > +  36.40%            fb.sh  [kernel.kallsyms]    [k] shrink_slab
 > +  18.97%            fb.sh  [kernel.kallsyms]    [k] list_lru_count_one
 > +   6.75%            fb.sh  [kernel.kallsyms]    [k] super_cache_count
 > +   0.49%            fb.sh  [kernel.kallsyms]    [k] down_read_trylock
 > +   0.44%            fb.sh  [kernel.kallsyms]    [k] mem_cgroup_iter
 > +   0.27%            fb.sh  [kernel.kallsyms]    [k] up_read
 > +   0.21%            fb.sh  [kernel.kallsyms]    [k] osq_lock
 > +   0.13%            fb.sh  [kernel.kallsyms]    [k] shmem_unused_huge_count
 > +   0.08%            fb.sh  [kernel.kallsyms]    [k] shrink_node_memcg
 > +   0.08%            fb.sh  [kernel.kallsyms]    [k] shrink_node
 >
 > With the patch series:
 > Samples: 4M of event 'cycles', Event count (approx.): 2756866824946
 > +  47.49%            fb.sh  [kernel.kallsyms]    [k] down_read_trylock
 > +  30.72%            fb.sh  [kernel.kallsyms]    [k] up_read
 > +   9.51%            fb.sh  [kernel.kallsyms]    [k] mem_cgroup_iter
 > +   1.69%            fb.sh  [kernel.kallsyms]    [k] shrink_node_memcg
 > +   1.35%            fb.sh  [kernel.kallsyms]    [k] mem_cgroup_protected
 > +   1.05%            fb.sh  [kernel.kallsyms]    [k] queued_spin_lock_slowpath
 > +   0.85%            fb.sh  [kernel.kallsyms]    [k] _raw_spin_lock
 > +   0.78%            fb.sh  [kernel.kallsyms]    [k] lruvec_lru_size
 > +   0.57%            fb.sh  [kernel.kallsyms]    [k] shrink_node
 > +   0.54%            fb.sh  [kernel.kallsyms]    [k] queue_work_on
 > +   0.46%            fb.sh  [kernel.kallsyms]    [k] shrink_slab_memcg
```
Patch diff:
```diff
@@ -430,6 +430,8 @@ void memcg_set_shrinker_bit(struct mem_cgroup *memcg, int nid, int shrinker_id)
 
 		rcu_read_lock();
 		map = rcu_dereference(memcg->nodeinfo[nid]->shrinker_map);
+		/* Pairs with smp mb in shrink_slab() */
+		smp_mb__before_atomic();
 		set_bit(shrinker_id, map->map);
 		rcu_read_unlock();
 	}
@@ -596,8 +596,30 @@ static unsigned long shrink_slab_memcg(gfp_t gfp_mask, int nid,
 			continue;
 
 		ret = do_shrink_slab(&sc, shrinker, priority);
-		if (ret == SHRINK_EMPTY)
-			ret = 0;
+		if (ret == SHRINK_EMPTY) {
+			clear_bit(i, map->map);
+			/*
+			 * After the shrinker reported that it had no objects to
+			 * free, but before we cleared the corresponding bit in
+			 * the memcg shrinker map, a new object might have been
+			 * added. To make sure, we have the bit set in this
+			 * case, we invoke the shrinker one more time and reset
+			 * the bit if it reports that it is not empty anymore.
+			 * The memory barrier here pairs with the barrier in
+			 * memcg_set_shrinker_bit():
             * 
             * 在shrinker 报告了已经没有objects 来free, 但是在我们clear
             * memcg shrinker map 中的相应的bit之前, 一个新的objects可能
             * 已经add. 为了确保 在这种情况下, 我们会 set bit, 我们调用
             * shrinker 多次 并且 reset该bit, 如果报告了它不是empty.
             * 这里的memory barrier 和 memcg_set_shrinker_bit() 是一对.
+			 *
+			 * list_lru_add()     shrink_slab_memcg()
+			 *   list_add_tail()    clear_bit()
+			 *   <MB>               <MB>
+			 *   set_bit()          do_shrink_slab()
+			 */
+			smp_mb__after_atomic();
+			ret = do_shrink_slab(&sc, shrinker, priority);
+			if (ret == SHRINK_EMPTY)
+				ret = 0;
+			else
+				memcg_set_shrinker_bit(memcg, nid, i);
+		}
 		freed += ret;
 
 		if (rwsem_is_contended(&shrinker_rwsem)) {
```
