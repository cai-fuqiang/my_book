# 思考
在kvm 的overflow流程中需要做什么么?

按照硬件的执行逻辑, 如果这次overflow了, 那么counter会
重置成 0, 所以kvm也应该去做这样的事情

```
commit bead02204e9806807bb290137b1ccabfcb4b16fd
Author: Marc Zyngier <maz@kernel.org>
Date:   Sun Nov 13 16:38:18 2022 +0000

    KVM: arm64: PMU: Align chained counter implementation with architecture pseudocode
```

这个patch就在干这个事情.
```
commit 30d97754b2d1bc4fd20f27c25fed92fc7ce39ce3
Author: Andrew Murray <amurray@thegoodpenguin.co.uk>
Date:   Mon Jun 17 20:01:03 2019 +0100

    KVM: arm/arm64: Re-create event when setting counter value
```
