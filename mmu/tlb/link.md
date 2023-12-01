# active_mm
https://www.kernel.org/doc/html/latest/mm/active_mm.html

# LAZY TLB
history tag 2.3.30pre2 introduce

history tag 2.3.43pre3 em



# add load
```
Why ???

v2.6.12-rc2-pre

commit 99ef44b79de47f23869897c11493521a1e42b2d2
Author: Linus Torvalds <torvalds@home.transmeta.com>
Date:   Mon May 20 05:58:03 2002 -0700

    Clean up %cr3 loading on x86, fix lazy TLB problem
```
https://lore.kernel.org/all/Pine.LNX.4.44.0205202211040.949-100000@home.transmeta.com/


```
commit c976d98851345bee96dc2e419685f8a96e515119 (tag: 2.4.0-test5pre5)
Author: Linus Torvalds <torvalds@linuxfoundation.org>
Date:   Fri Nov 23 15:37:06 2007 -0500

    Import 2.4.0-test5pre5

commit 3d28ebceaffab40f30afa87e33331560148d7b8b
Author: Andy Lutomirski <luto@kernel.org>
Date:   Sun May 28 10:00:15 2017 -0700

    x86/mm: Rework lazy TLB to track the actual loaded mm
```



# PCID and improved laziness
https://lore.kernel.org/all/cover.1498751203.git.luto@kernel.org/


COMMIT:
```
commit bc0d5a89fbe3c83ac45438d7ba88309f4713615d
Author: Andy Lutomirski <luto@kernel.org>
Date:   Thu Jun 29 08:53:13 2017 -0700

    x86/mm: Don't reenter flush_tlb_func_common()

commit 8781fb7e9749da424e01daacd14834b674658c63
Author: Andy Lutomirski <luto@kernel.org>
Date:   Thu Jun 29 08:53:14 2017 -0700

    x86/mm: Delete a big outdated comment about TLB flushing

commit f39681ed0f48498b80455095376f11535feea332
Author: Andy Lutomirski <luto@kernel.org>
Date:   Thu Jun 29 08:53:15 2017 -0700

    x86/mm: Give each mm TLB flush generation a unique ID


commit b0579ade7cd82391360e959cc844e50a160e8a96
Author: Andy Lutomirski <luto@kernel.org>
Date:   Thu Jun 29 08:53:16 2017 -0700

    x86/mm: Track the TLB's tlb_gen and update the flushing algorithm


commit 94b1b03b519b81c494900cb112aa00ed205cc2d9
Author: Andy Lutomirski <luto@kernel.org>
Date:   Thu Jun 29 08:53:17 2017 -0700

    x86/mm: Rework lazy TLB mode and TLB freshness tracking


commit 43858b4f25cf0adc5c2ca9cf5ce5fdf2532941e5
Author: Andy Lutomirski <luto@kernel.org>
Date:   Thu Jun 29 08:53:18 2017 -0700

    x86/mm: Stop calling leave_mm() in idle code

commit cba4671af7550e008f7a7835f06df0763825bf3e
Author: Andy Lutomirski <luto@kernel.org>
Date:   Thu Jun 29 08:53:19 2017 -0700

    x86/mm: Disable PCID on 32-bit kernels

commit 0790c9aad84901ca1bdc14746175549c8b5da215
Author: Andy Lutomirski <luto@kernel.org>
Date:   Thu Jun 29 08:53:20 2017 -0700

    x86/mm: Add the 'nopcid' boot option to turn off PCID


commit 660da7c9228f685b2ebe664f9fd69aaddcc420b5
Author: Andy Lutomirski <luto@kernel.org>
Date:   Thu Jun 29 08:53:21 2017 -0700

    x86/mm: Enable CR4.PCIDE on supported systems


commit 10af6235e0d327d42e1bad974385197817923dc1
Author: Andy Lutomirski <luto@kernel.org>
Date:   Mon Jul 24 21:41:38 2017 -0700
    x86/mm: Implement PCID based optimization: try to preserve old TLB entries using PCID
```

# tag 1
```
introduce before smp_invalidate_interrupt() long comment
    ...
    [cpu0: the cpu that switches]
    ...
commit c976d98851345bee96dc2e419685f8a96e515119 (tag: 2.4.0-test5pre5)
```


# tag2
```
introduce before smp_invalidate_interrupt() long comment
    ...
    The flush IPI assumes that a thread switch happens in this order:
    ...
commit 3814ee6865ea6d63e594eeeb17ce8bed86951766 (tag: 2.3.43pre2)
```

# _PAGE_GLOBAL
