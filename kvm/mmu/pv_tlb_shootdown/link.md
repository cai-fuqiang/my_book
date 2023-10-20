# PV tlb Shootdown
## mail list
https://lore.kernel.org/kvm/1513128784-5924-1-git-send-email-wanpeng.li@hotmail.com/

## commit
```
commit 858a43aae23672d46fe802a41f4748f322965182
Author: Wanpeng Li <wanpeng.li@hotmail.com>
Date:   Tue Dec 12 17:33:02 2017 -0800

    KVM: X86: use paravirtualized TLB Shootdown
```
## release patch
## KVM paravirt remote flush tlb

https://lore.kernel.org/kvm/5045DA00.6090208@redhat.com/

###  xen 实现 tlb

https://lists.linuxcoding.com/kernel/2007-q2/msg06044.html

```
commit f87e4cac4f4e940b328d3deb5b53e642e3881f43
Author: Jeremy Fitzhardinge <jeremy@xensource.com>
Date:   Tue Jul 17 18:37:06 2007 -0700

    xen: SMP guest support
```

### kernel 实现 pv ops 
https://marc.info/?l=kvm&m=134554840005059&w=2
```
commit d4c104771a1c58e3de2a888b73b0ba1b54c0ae76
Author: Jeremy Fitzhardinge <jeremy@goop.org>
Date:   Wed May 2 19:27:15 2007 +0200

    [PATCH] i386: PARAVIRT: add flush_tlb_others paravirt_op
```

