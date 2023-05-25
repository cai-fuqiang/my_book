# 内核注释
```
/*
 * from
 * ========================
 * arch/arm64/include/asm/kvm_mmu.h
 * ========================
 */
/*
 * As ARMv8.0 only has the TTBR0_EL2 register, we cannot express
 * "negative" addresses. This makes it impossible to directly share
 * mappings with the kernel.
 *
 * 因为 ARMv8.0 仅仅有TTBR0_EL2 寄存器，所以我们不能 express(表示?)
 * "负的" address. 这样将不能直接和kernel share mappings.
 *
 * Instead, give the HYP mode its own VA region at a fixed offset from
 * the kernel by just masking the top bits (which are all ones for a
 * kernel address). We need to find out how many bits to mask.
 *
 * 相替代的，给定HYP mode 他自己的VA region 在一个固定的offset，这个offset
 * 是由 kernel address 屏蔽掉高位 (对于一个 kernel address 对应一个地址?)
 * 我们需要找到有多少个bits需要被屏蔽
 *
 * We want to build a set of page tables that cover both parts of the
 * idmap (the trampoline page used to initialize EL2), and our normal
 * runtime VA space, at the same time.
 *
 * 我们想要构建一系列的页表，这些页表同时覆盖了 idmap的部分(用于初始化el2
 * 的 trampoline page) 和 我们正常 runtime VA space。
 *
 * Given that the kernel uses VA_BITS for its entire address space,
 * and that half of that space (VA_BITS - 1) is used for the linear
 * mapping, we can also limit the EL2 space to (VA_BITS - 1).
 *
 * The main question is "Within the VA_BITS space, does EL2 use the
 * top or the bottom half of that space to shadow the kernel's linear
 * mapping?". As we need to idmap the trampoline page, this is
 * determined by the range in which this page lives.
 *
 * If the page is in the bottom half, we have to use the top half. If
 * the page is in the top half, we have to use the bottom half:
 *
 * T = __pa_symbol(__hyp_idmap_text_start)
 * if (T & BIT(VA_BITS - 1))
 *      HYP_VA_MIN = 0  //idmap in upper half
 * else
 *      HYP_VA_MIN = 1 << (VA_BITS - 1)
 * HYP_VA_MAX = HYP_VA_MIN + (1 << (VA_BITS - 1)) - 1
 *
 * This of course assumes that the trampoline page exists within the
 * VA_BITS range. If it doesn't, then it means we're in the odd case
 * where the kernel idmap (as well as HYP) uses more levels than the
 * kernel runtime page tables (as seen when the kernel is configured
 * for 4k pages, 39bits VA, and yet memory lives just above that
 * limit, forcing the idmap to use 4 levels of page tables while the
 * kernel itself only uses 3). In this particular case, it doesn't
 * matter which side of VA_BITS we use, as we're guaranteed not to
 * conflict with anything.
 *
 * When using VHE, there are no separate hyp mappings and all KVM
 * functionality is already mapped as part of the main kernel
 * mappings, and none of this applies in that case.
 */
```


# commit
```
commit 2b4d1606aac27f2485061abd953ea1e103b5e26e
Author: Marc Zyngier <maz@kernel.org>
Date:   Sun Dec 3 17:36:55 2017 +0000

    arm64: KVM: Dynamically patch the kernel/hyp VA mask

commit ed57cac83e05f2e93567e4b5c57ee58a1bf8a582
Author: Marc Zyngier <maz@kernel.org>
Date:   Sun Dec 3 18:22:49 2017 +0000

    arm64: KVM: Introduce EL2 VA randomisation
```
## 引入上面patch之前
```cpp
static inline unsigned long __kern_hyp_va(unsigned long v)
{
        asm volatile(ALTERNATIVE("and %0, %0, %1",
                                 "nop",
                                 ARM64_HAS_VIRT_HOST_EXTN)
                     : "+r" (v)
                     : "i" (HYP_PAGE_OFFSET_HIGH_MASK));
        asm volatile(ALTERNATIVE("nop",
                                 "and %0, %0, %1",
                                 ARM64_HYP_OFFSET_LOW)
                     : "+r" (v)
                     : "i" (HYP_PAGE_OFFSET_LOW_MASK));
        return v;
}
```
关于`ALTERNATIVE(oldinstr, newinstr, feature)`, 大概意思如下:
如果cpu有该feature，则替换指令，如果没有则不替换。
整体的代码逻辑，就如注释中提到的那样:
```
* This generates the following sequences:
* - High mask:
*             and x0, x0, #HYP_PAGE_OFFSET_HIGH_MASK
*             nop
* - Low mask:
*             and x0, x0, #HYP_PAGE_OFFSET_HIGH_MASK
*             and x0, x0, #HYP_PAGE_OFFSET_LOW_MASK
* - VHE:
*             nop
*             nop
```
其cpu的各类feature, 我们先看下 `ARM64_HAS_VIRT_HOST_EXTN` vhe feature:
```cpp
static const struct arm64_cpu_capabilities arm64_features[] = {
        {
                .desc = "Virtualization Host Extensions",
                .capability = ARM64_HAS_VIRT_HOST_EXTN,
                .def_scope = SCOPE_SYSTEM,
                .matches = runs_at_el2,
                .enable = cpu_copy_el2regs,
        }
},
static bool runs_at_el2(const struct arm64_cpu_capabilities *entry, int __unused)
{
        return is_kernel_in_hyp_mode();
}
static inline bool is_kernel_in_hyp_mode(void)
{
        return read_sysreg(CurrentEL) == CurrentEL_EL2;
}
```
可以看到, 实际上会去判断当前异常级别(CurrentEL sysreg)是否是 `CurrentEL_EL2`

我们再来看下 `ARM64_HYP_OFFSET_LOW` (lower memory feature)
```cpp
static const struct arm64_cpu_capabilities arm64_features[] = {
        {
                .desc = "Reduced HYP mapping offset",
                .capability = ARM64_HYP_OFFSET_LOW,
                .def_scope = SCOPE_SYSTEM,
                .matches = hyp_offset_low,
        },
}
static bool hyp_offset_low(const struct arm64_cpu_capabilities *entry,
                           int __unused)
{
        phys_addr_t idmap_addr = __pa_symbol(__hyp_idmap_text_start);

        /*
         * Activate the lower HYP offset only if:
         * - the idmap doesn't clash with it,
         * - the kernel is not running at EL2.
         */
        return idmap_addr > GENMASK(VA_BITS - 2, 0) && !is_kernel_in_hyp_mode();
}
```
其中需要满足两个条件:
* `__hyp_idmap_text_start`的物理地址（对于idmap来说，也是虚拟地址), 比 `GENMASK(VA_BITS - 2, 0)`
要大（这里也就是VA_BITS所代表的内存空间/4), 实际上是指 idmap memory 映射到 high memory, 那么
其他的代码段，就需要映射到lower memory
* novhe

关于patch的分析，请见:.......

## mail list
https://marc.info/?l=kvm&m=151870026910204&w=2
