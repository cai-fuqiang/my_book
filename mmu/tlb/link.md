# active_mm
https://www.kernel.org/doc/html/latest/mm/active_mm.html

# LAZY TLB
history tag 2.3.43pre3 introduce

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


# PCID and improved laziness
https://lore.kernel.org/all/cover.1498751203.git.luto@kernel.org/


COMMIT:
```
bc0d5a89fbe3c83ac45438d7ba88309f4713615d x86/mm: Don't reenter flush_tlb_func_common()

...

10af6235e0d327d42e1bad974385197817923dc1  x86/mm: Implement PCID based optimization:
```
