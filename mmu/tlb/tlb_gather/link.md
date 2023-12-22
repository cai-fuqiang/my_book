# ORG PATCH
```
commit a27c6530ff12bab100e64c5b43e84f759fa353ae
Author: Linus Torvalds <torvalds@athlon.transmeta.com>
Date:   Mon Feb 4 20:19:13 2002 -0800

    v2.4.9.12 -> v2.4.9.13
```

# mm: always flush VMA ranges affected by zap_page_range
```
From 4647706ebeee6e50f7b9f922b095f4ec94d581c3 Mon Sep 17 00:00:00 2001
From: Mel Gorman <mgorman@techsingularity.net>
Date: Wed, 6 Sep 2017 16:21:05 -0700
Subject: [PATCH] mm: always flush VMA ranges affected by zap_page_range
```

# mm: fix MADV_[FREE|DONTNEED] TLB flush miss problem
```
From 99baac21e4585f4258f919502c6e23f1e5edc98c Mon Sep 17 00:00:00 2001
From: Minchan Kim <minchan@kernel.org>
Date: Thu, 10 Aug 2017 15:24:12 -0700
Subject: [PATCH] mm: fix MADV_[FREE|DONTNEED] TLB flush miss problem
```

# Revert "mm: always flush VMA ranges affected by zap_page_range"
```
From 50c150f26261e723523f077a67378736fa7511a4 Mon Sep 17 00:00:00 2001
From: Rik van Riel <riel@surriel.com>
Date: Fri, 17 Aug 2018 15:48:53 -0700
Subject: [PATCH] Revert "mm: always flush VMA ranges affected by
 zap_page_range"
```

# mm: mmu_gather: remove \__tlb_reset_range() for force flush
```
commit 7a30df49f63ad92318ddf1f7498d1129a77dd4bd
Author: Yang Shi <yang.shi@linux.alibaba.com>
Date:   Thu Jun 13 15:56:05 2019 -0700

    mm: mmu_gather: remove __tlb_reset_range() for force flush
```

# arm64: tlb: Adjust stride and type of TLBI according to mmu_gather 
```
commit f270ab88fdf205be1a7a46ccb61f4a343be543a2
Author: Will Deacon <will@kernel.org>
Date:   Thu Aug 23 21:08:31 2018 +0100

    arm64: tlb: Adjust stride and type of TLBI according to mmu_gather
```


# early
```
commit 7c9d187e950db8c6fbccc9e260b2ed6779845f6d
Author: Linus Torvalds <torvalds@penguin.transmeta.com>
Date:   Wed May 15 03:13:39 2002 -0700

    First cut at proper TLB shootdown for page directory entries.
```
