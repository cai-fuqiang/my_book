```diff
From 7e010df53c80197b23119e7d7b95892aa13629df Mon Sep 17 00:00:00 2001
From: Kirill Tkhai <ktkhai@virtuozzo.com>
Date: Fri, 17 Aug 2018 15:48:34 -0700
Subject: [PATCH] mm: use special value SHRINKER_REGISTERING instead of
 list_empty() check

The patch introduces a special value SHRINKER_REGISTERING to use instead
of list_empty() to differ a registering shrinker from unregistered
shrinker.  Why we need that at all?

> at all: 全然，根本，究竟
>
> 该patch 进入了一个 special value SHRINKER_REGISTERING 来替代 list_empty()
> 来区别 registering(正在注册的/注册未完成的) shrinker 和 unregister shrinker.
> 为什么我们需要它 ?

Shrinker registration is split in two parts.  The first one is
prealloc_shrinker(), which allocates shrinker memory and reserves ID in
shrinker_idr.  This function can fail.  The second is
register_shrinker_prepared(), and it finalizes the registration.  This
function actually makes shrinker available to be used from
shrink_slab(), and it can't fail.

> finalize: 完成;使结束;使落实
>
> Shrinker registration 被分为了两个部分. 第一个部分是 prealloc_shrinker(),
> 其分配了 shrinker memory 并且在 shrinker_idr()中预留了ID. 该function
> 可以失败. 第二个是 register_shrinker_prepared() 并且它完成了这个注册.
> 该function 实际上让shrinker可以用于 shrinker_slab, 并且它不能失败.

One shrinker may be based on more then one LRU lists.  So, we never
clear the bit in memcg shrinker maps, when (one of) corresponding LRU
list becomes empty, since other LRU lists may be not empty.  See
superblock shrinker for example: it is based on two LRU lists:
s_inode_lru and s_dentry_lru.  We do not want to clear shrinker bit,
when there are no inodes in s_inode_lru, as s_dentry_lru may contain
dentries.

> then: than
>
> Shrinker 可能基于超过一个 LRU lists. 所以, 我们从不clear memcg shrinker
> maps中的bit, 当相应的 LRU list(其中一个) 变为 empty, 因为其他的LRU list
> 可能没有变为 empty. 以 superblock shrinker为例: 它基于两个 LRU lists:
> s_inode_lru 和 s_dentry_lru. 我们不想clear shrinker bit, 当在 s_inode_lru
> 中没有inode, 在 s_dentry_lru 可能有一些 dentries.

Instead of that, we use special algorithm to detect shrinkers having no
elements at all its LRU lists, and this is made in shrink_slab_memcg().
See the comment in this function for the details.

> 为了避免它, 我们使用一种特殊的算法来发现在它的所有的LRU lists中没有
> elements, 并且由 shrink_slab_memcg()去做. 请看该function的 comment 
> 了解细节.

Also, in shrink_slab_memcg() we clear shrinker bit in the map, when we
meet unregistered shrinker (bit is set, while there is no a shrinker in
IDR).  Otherwise, we would have done that at the moment of shrinker
unregistration for all memcgs (and this looks worse, since iteration
over all memcg may take much time).  Also this would have imposed
restrictions on shrinker unregistration order for its users: they would
have had to guarantee, there are no new elements after
unregister_shrinker() (otherwise, a new added element would have set a
bit).

> impose [ɪmˈpoʊz] : 把…强加于; 使接受，使意识到; 推行，采用;
>
> 同时, shrink_slab_memcg() 中 我们clear map 中的 shrinker bit, 当我们
> 遇到了 unregistered shrinker (bit is set, 但是在 IDR 中已经没有了
> shrinker). 否则, 我们会在为所有 memcg unregistration shrinker的同时
> 做了该事(但是这看起来很糟糕, 因为会遍历所有的memcg 并且浪费很多时间).
> 并且他会在shrinker unregistration order上增加一些限制: 他们必须保证, 在
> unregsiter_shrinker() 之后不会有new elements (否则, 新增加唉的element
> 会设置一个bit).

So, if we meet a set bit in map and no shrinker in IDR when we're
iterating over the map in shrink_slab_memcg(), this means the
corresponding shrinker is unregistered, and we must clear the bit.

> 所以, 如果我们遇到map中set 了一个 bit 并且 在 IDR 中没有shrinker,
> 当我们在 shrink_slab_memcg() 中遍历 map, 它意味着 相应的 shrinker
> 已经 unregistered, 并且我们必须clear 该 bit.

Another case is shrinker registration.  We want two things there:

> 另一种情况是 shrinker registeration. 我们想要做两件事情(???, 是
> 这么翻译么)

1) do_shrink_slab() can be called only for completely registered
   shrinkers;
   > do_shrink_slab() 只会在 completely registered shrinkers 被调用.

2) shrinker internal lists may be populated in any order with
   register_shrinker_prepared() (let's talk on the example with sb).  Both
   of:
   > shrinker internal(内部的) lists

  a)list_lru_add(&inode->i_sb->s_inode_lru, &inode->i_lru); [cpu0]
    memcg_set_shrinker_bit();                               [cpu0]
    ...
    register_shrinker_prepared();                           [cpu1]

  and

  b)register_shrinker_prepared();                           [cpu0]
    ...
    list_lru_add(&inode->i_sb->s_inode_lru, &inode->i_lru); [cpu1]
    memcg_set_shrinker_bit();                               [cpu1]

   are legitimate.  We don't want to impose restriction here and to
   force people to use only (b) variant.  We don't want to force people to
   care, there is no elements in LRU lists before the shrinker is
   completely registered.  Internal users of LRU lists and shrinker code
   are two different subsystems, and they have to be closed in themselves
   each other.

In (a) case we have the bit set before shrinker is completely
registered.  We don't want do_shrink_slab() is called at this moment, so
we have to detect such the registering shrinkers.

Before this patch list_empty() (shrinker is not linked to the list)
check was used for that.  So, in (a) there could be a bit set, but we
don't call do_shrink_slab() unless shrinker is linked to the list.  It's
just an indicator, I just overloaded linking to the list.

This was not the best solution, since it's better not to touch the
shrinker memory from shrink_slab_memcg() before it's completely
registered (this also will be useful in the future to make shrink_slab()
completely lockless).

So, this patch introduces better way to detect registering shrinker,
which allows not to dereference shrinker memory.  It's just a ~0UL
value, which we insert into the IDR during ID allocation.  After
shrinker is ready to be used, we insert actual shrinker pointer in the
IDR, and it becomes available to shrink_slab_memcg().

We can't use NULL instead of this new value for this purpose as:
shrink_slab_memcg() already uses NULL to detect unregistered shrinkers,
and we don't want the function sees NULL and clears the bit, otherwise
(a) won't work.

This is the only thing the patch makes: the better way to detect
registering shrinker.  Nothing else this patch makes.

Also this gives a better assembler, but it's minor side of the patch:

Before:
  callq  <idr_find>
  mov    %rax,%r15
  test   %rax,%rax
  je     <shrink_slab_memcg+0x1d5>
  mov    0x20(%rax),%rax
  lea    0x20(%r15),%rdx
  cmp    %rax,%rdx
  je     <shrink_slab_memcg+0xbd>
  mov    0x8(%rsp),%edx
  mov    %r15,%rsi
  lea    0x10(%rsp),%rdi
  callq  <do_shrink_slab>

After:
  callq  <idr_find>
  mov    %rax,%r15
  lea    -0x1(%rax),%rax
  cmp    $0xfffffffffffffffd,%rax
  ja     <shrink_slab_memcg+0x1cd>
  mov    0x8(%rsp),%edx
  mov    %r15,%rsi
  lea    0x10(%rsp),%rdi
  callq  ffffffff810cefd0 <do_shrink_slab>

[ktkhai@virtuozzo.com: add #ifdef CONFIG_MEMCG_KMEM around idr_replace()]
  Link: http://lkml.kernel.org/r/758b8fec-7573-47eb-b26a-7b2847ae7b8c@virtuozzo.com
Link: http://lkml.kernel.org/r/153355467546.11522.4518015068123480218.stgit@localhost.localdomain
Signed-off-by: Kirill Tkhai <ktkhai@virtuozzo.com>
Reviewed-by: Andrew Morton <akpm@linux-foundation.org>
Cc: Vladimir Davydov <vdavydov.dev@gmail.com>
Cc: Michal Hocko <mhocko@suse.com>
Cc: Andrey Ryabinin <aryabinin@virtuozzo.com>
Cc: "Huang, Ying" <ying.huang@intel.com>
Cc: Tetsuo Handa <penguin-kernel@I-love.SAKURA.ne.jp>
Cc: Matthew Wilcox <willy@infradead.org>
Cc: Shakeel Butt <shakeelb@google.com>
Cc: Josef Bacik <jbacik@fb.com>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 mm/vmscan.c | 43 +++++++++++++++++++++----------------------
 1 file changed, 21 insertions(+), 22 deletions(-)

diff --git a/mm/vmscan.c b/mm/vmscan.c
index 8fcc86f1d7bc..4375b1e9bd56 100644
--- a/mm/vmscan.c
+++ b/mm/vmscan.c
@@ -170,6 +170,20 @@ static LIST_HEAD(shrinker_list);
 static DECLARE_RWSEM(shrinker_rwsem);
 
 #ifdef CONFIG_MEMCG_KMEM
+
+/*
+ * We allow subsystems to populate their shrinker-related
+ * LRU lists before register_shrinker_prepared() is called
+ * for the shrinker, since we don't want to impose
+ * restrictions on their internal registration order.
+ * In this case shrink_slab_memcg() may find corresponding
+ * bit is set in the shrinkers map.
+ *
+ * This value is used by the function to detect registering
+ * shrinkers and to skip do_shrink_slab() calls for them.
+ */
+#define SHRINKER_REGISTERING ((struct shrinker *)~0UL)
+
 static DEFINE_IDR(shrinker_idr);
 static int shrinker_nr_max;
 
@@ -179,7 +193,7 @@ static int prealloc_memcg_shrinker(struct shrinker *shrinker)
 
 	down_write(&shrinker_rwsem);
 	/* This may call shrinker, so it must use down_read_trylock() */
-	id = idr_alloc(&shrinker_idr, shrinker, 0, 0, GFP_KERNEL);
+	id = idr_alloc(&shrinker_idr, SHRINKER_REGISTERING, 0, 0, GFP_KERNEL);
 	if (id < 0)
 		goto unlock;
 
@@ -364,21 +378,6 @@ int prealloc_shrinker(struct shrinker *shrinker)
 	if (!shrinker->nr_deferred)
 		return -ENOMEM;
 
-	/*
-	 * There is a window between prealloc_shrinker()
-	 * and register_shrinker_prepared(). We don't want
-	 * to clear bit of a shrinker in such the state
-	 * in shrink_slab_memcg(), since this will impose
-	 * restrictions on a code registering a shrinker
-	 * (they would have to guarantee, their LRU lists
-	 * are empty till shrinker is completely registered).
-	 * So, we differ the situation, when 1)a shrinker
-	 * is semi-registered (id is assigned, but it has
-	 * not yet linked to shrinker_list) and 2)shrinker
-	 * is not registered (id is not assigned).
-	 */
-	INIT_LIST_HEAD(&shrinker->list);
-
 	if (shrinker->flags & SHRINKER_MEMCG_AWARE) {
 		if (prealloc_memcg_shrinker(shrinker))
 			goto free_deferred;
@@ -408,6 +407,9 @@ void register_shrinker_prepared(struct shrinker *shrinker)
 {
 	down_write(&shrinker_rwsem);
 	list_add_tail(&shrinker->list, &shrinker_list);
+#ifdef CONFIG_MEMCG_KMEM
+	idr_replace(&shrinker_idr, shrinker, shrinker->id);
+#endif
 	up_write(&shrinker_rwsem);
 }
 
@@ -589,15 +591,12 @@ static unsigned long shrink_slab_memcg(gfp_t gfp_mask, int nid,
 		struct shrinker *shrinker;
 
 		shrinker = idr_find(&shrinker_idr, i);
-		if (unlikely(!shrinker)) {
-			clear_bit(i, map->map);
+		if (unlikely(!shrinker || shrinker == SHRINKER_REGISTERING)) {
+			if (!shrinker)
+				clear_bit(i, map->map);
 			continue;
 		}
 
-		/* See comment in prealloc_shrinker() */
-		if (unlikely(list_empty(&shrinker->list)))
-			continue;
-
 		ret = do_shrink_slab(&sc, shrinker, priority);
 		if (ret == SHRINK_EMPTY) {
 			clear_bit(i, map->map);
-- 
2.42.0
```
