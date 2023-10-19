[KVM MMU Virtualization](https://events.static.linuxfound.org/slides/2011/linuxcon-japan/lcj2011_guangrong.pdf)

# KVM: MMU :large page support
[\[PATCH 08/35\] KVM: MMU: large page support](https://marc.info/?l=linux-kernel&m=120725194206911&w=2)
commit 


# kvm userspace interface
```
commit 6aa8b732ca01c3d7a54e93f4d701b8aabbe60fb7
Author: Avi Kivity <avi@qumranet.com>
Date:   Sun Dec 10 02:21:36 2006 -0800

    [PATCH] kvm: userspace interface

    web site: http://kvm.sourceforge.net

    mailing list: kvm-devel@lists.sourceforge.net
      (http://lists.sourceforge.net/lists/listinfo/kvm-devel)
```
https://lore.kernel.org/kvm/86802c440611070859g5bb3c8b0q6b05b4ef2782d682@mail.gmail.com/

# [PATCH 0/33] KVM: MMU: Cache shadow page tables
https://lore.kernel.org/all/459D21DD.5090506@qumranet.com/
## KVM: MMU: Implement simple reverse mapping
commit cd4a4e5374110444dc38831af517e51ff5a053c3
Author: Avi Kivity <avi@qumranet.com>
Date:   Fri Jan 5 16:36:38 2007 -0800

    [PATCH] KVM: MMU: Implement simple reverse mapping


## Replace atomic allocations by preallocated objects
commit 714b93da1a6d97307dfafb9915517879d8a66c0d
Author: Avi Kivity <avi@qumranet.com>
Date:   Fri Jan 5 16:36:53 2007 -0800

    [PATCH] KVM: MMU: Replace atomic allocations by preallocated objects
