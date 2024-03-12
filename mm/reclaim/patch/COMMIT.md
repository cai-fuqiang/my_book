# max_mapped
```
commit 9ff086a3d48d6f6e24281e6edb6c804091eda3d1 (HEAD -> max_mapped)
Author: Linus Torvalds <torvalds@athlon.transmeta.com>
Date:   Mon Feb 4 20:24:48 2002 -0800

    v2.4.12.6 -> v2.4.13
```

# before max_mapped
```
commit aed492fcb972130f11cd62fd8ca0b2af95f54d03
Author: Linus Torvalds <torvalds@athlon.transmeta.com>
Date:   Mon Feb 4 20:24:46 2002 -0800

    v2.4.12.5 -> v2.4.12.6

```


# set page dirty in swap_out
```
commit e3576079d9e21a44dee47e6671607f2925829a55 (tag: 2.4.0-test12pre1)
Author: Linus Torvalds <torvalds@linuxfoundation.org>
Date:   Fri Nov 23 15:40:16 2007 -0500

    - pre1: (for ISDN synchronization _ONLY_! Not complete!)
     - Byron Stanoszek: correct decimal precision for CPU MHz in
       /proc/cpuinfo
     - Ollie Lho: SiS pirq routing.
     - Andries Brouwer: isofs cleanups
     - Matt Kraai: /proc read() on directories should return EISDIR, not EINVAL
     - Linus: be stricter about what we accept as a PCI bridge setup.
     - Linus: always set PCI interrupts to be level-triggered when we enable them.
     - Linus: updated PageDirty and swap cache handling
     - Peter Anvin: update A20 code to work without keyboard controller
     - Kai Germaschewski: ISDN updates
     - Russell King: ARM updates
     - Geert Uytterhoeven: m68k updates
```

# add clean dirty in remove swap
```
commit 480eec6cdddc49cc783e0a404d0fe593639f90dd (tag: 2.4.0-test13pre5)
Author: Linus Torvalds <torvalds@linuxfoundation.org>
Date:   Fri Nov 23 15:41:02 2007 -0500

    The main notables are the network fixes (uninitialized skb->dev could and
    did cause oopses in ip_defrag) and the mm fixes (dirty pages without
    mappings etc, causing problems in page_launder).
```
