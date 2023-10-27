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
```

# PCID and improved laziness
https://lore.kernel.org/all/cover.1498751203.git.luto@kernel.org/


COMMIT:
```
bc0d5a89fbe3c83ac45438d7ba88309f4713615d x86/mm: Don't reenter flush_tlb_func_common()

...

10af6235e0d327d42e1bad974385197817923dc1  x86/mm: Implement PCID based optimization:
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
