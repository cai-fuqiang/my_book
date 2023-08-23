```
commit d255f4f2bac81eb798fcf76938147f1f6c756ae2
Author: Zhai, Edwin <edwin.zhai@intel.com>
Date:   Fri Oct 9 18:03:20 2009 +0800

    KVM: introduce kvm_vcpu_on_spin

    Introduce kvm_vcpu_on_spin, to be used by VMX/SVM to yield processing
    once the cpu detects pause-based looping.


commit 4b8d54f9726f1159330201c5ed2ea30bce7e63ea
Author: Zhai, Edwin <edwin.zhai@intel.com>
Date:   Fri Oct 9 18:03:20 2009 +0800

    KVM: VMX: Add support for Pause-Loop Exiting

...

commit b4a2d31da812ce03efaf5d30c6b9d39c1cbd18d8
Author: Radim Krčmář <rkrcmar@redhat.com>
Date:   Thu Aug 21 18:08:08 2014 +0200

    KVM: VMX: dynamise PLE window

...

commit b31c114b82b2b55913d2cf744e6a665c2ca090ac
Author: Wanpeng Li <wanpengli@tencent.com>
Date:   Mon Mar 12 04:53:04 2018 -0700

    KVM: X86: Provide a capability to disable PAUSE intercepts

    Allow to disable pause loop exit/pause filtering on a per VM basis.

    If some VMs have dedicated host CPUs, they won't be negatively affected
    due to needlessly intercepted PAUSE instructions.
```
