# commit message
```
commit 9a982250f773cc8c76f1eee68a770b7cbf2faf78
Author: Kirill A. Shutemov <kirill.shutemov@linux.intel.com>
Date:   Fri Jan 15 16:54:17 2016 -0800

    thp: introduce deferred_split_huge_page()

    Currently we don't split huge page on partial unmap.  It's not an ideal
    situation.  It can lead to memory overhead.

    > 当前我们在 partial unmap 时, 不会 split huge page. 这不是一个理想的情况.
    > 他将导致 memory overhead.

    Furtunately, we can detect partial unmap on page_remove_rmap().  But we
    cannot call split_huge_page() from there due to locking context.

    > fortunately /ˈfɔːtʃənətli/: 幸运的
    >
    > 幸运的是, 我们可以在 page_remove_rmap() 上检测 partial unmap. 但是由于 locking 
    > context, 我们不能在这里调用 split_huge_page()

    It's also counterproductive to do directly from munmap() codepath: in
    many cases we will hit this from exit(2) and splitting the huge page
    just to free it up in small pages is not what we really want.

    > counter: v: 反驳, 抵消,反制; adv. 相反地,反对地 adj. 反对的
    > counterproductive: 适得其反
    >
    > 直接从 munmap() 代码路径中执行也会适得其反: 在很多情况下, 我们会从exit(2)
    > 调用它并且 split huge page 只是为了将其释放为较小的页面, 这并不是我们真正想
    > 要的

    The patch introduce deferred_split_huge_page() which put the huge page
    into queue for splitting.  The splitting itself will happen when we get
    memory pressure via shrinker interface.  The page will be dropped from
    list on freeing through compound page destructor.

    > destructor [dɪˈstrʌktər]: 析构函数
    >
    > 该补丁引入了 deferred_split_huge_page(), 它将 huge page 放到了队列进行
    > split. 当我们通过 shrinker interface 感知到 memory pressure 时, split
    > 自身则会发生. 通过 compound page destructor 释放该页面时, 该页面将会从list中
    > drop掉.
```

> NOTE
>
> [MAIL LIST](https://lore.kernel.org/all/1436550130-112636-35-git-send-email-kirill.shutemov@linux.intel.com/)

我们接下来看具体的patch:

# Patch diff
通过上面的描述可知, `page_remove_rmap()`是触发split huge page的入口, 我们先看下该函数的改动

## page_remove_rmap

在看函数改动之前, 我们先来看下函数定义:
```cpp
/**
 * page_remove_rmap - take down pte mapping from a page
 * @page:       page to remove mapping from
 * @compound:   uncharge the page as compound or small page
 *
 * The caller needs to hold the pte lock.
 */
void page_remove_rmap(struct page *page, bool compound)
```
+ `page`: 要unmap的page
+ `compound`: 表示 uncharge的page是 compound 还是 small page

该函数有两个参数, 其中`compound`可以表明, 本次 uncharge page
是要uncharge整个的 复合页, 还是一个small page, 也就是 partial unmap
还是 full unmap.

> NOTE
>
> 大致查看了下 codepath, 调用者如果想unmap huge page 时, 一般
> 会将 compound 置为true.

我们再来看整个的函数, 及其改动
```diff
/**
 * page_remove_rmap - take down pte mapping from a page
 * @page:       page to remove mapping from
 * @compound:   uncharge the page as compound or small page
 *
 * The caller needs to hold the pte lock.
 */
void page_remove_rmap(struct page *page, bool compound)
{
        if (!PageAnon(page)) {
                VM_BUG_ON_PAGE(compound && !PageHuge(page), page);
                page_remove_file_rmap(page);
                return;
        }

        if (compound)
                return page_remove_anon_compound_rmap(page);

        /* page still mapped by someone else? */
        if (!atomic_add_negative(-1, &page->_mapcount))
                return;

        /*
         * We use the irq-unsafe __{inc|mod}_zone_page_stat because
         * these counters are not modified in interrupt context, and
         * pte lock(a spinlock) is held, which implies preemption disabled.
         */
        __dec_zone_page_state(page, NR_ANON_PAGES);

        if (unlikely(PageMlocked(page)))
                clear_page_mlock(page);

+       if (PageTransCompound(page))
+               deferred_split_huge_page(compound_head(page));

        /*
         * It would be tidy to reset the PageAnon mapping here,
         * but that might overwrite a racing page_add_anon_rmap
         * which increments mapcount after us but sets mapping
         * before us: so leave the reset to free_hot_cold_page,
         * and remember that it's only reliable while mapped.
         * Leaving it set also helps swapoff to reinstate ptes
         * faster for those pages still in swapcache.
         */
}
```
