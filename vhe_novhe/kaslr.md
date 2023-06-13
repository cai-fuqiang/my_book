# kaslr

## __arm64_rndr
```cpp
static inline bool __arm64_rndr(unsigned long *v)
{
        bool ok;

        /*
         * Reads of RNDR set PSTATE.NZCV to 0b0000 on success,
         * and set PSTATE.NZCV to 0b0100 otherwise.
         */
        asm volatile(
                __mrs_s("%0", SYS_RNDR_EL0) "\n"
        "       cset %w1, ne\n"
        : "=r" (*v), "=r" (ok)
        :
        : "cc");

        return ok;
}
```
这里通过`mrs  rndr`获取随机数，并且通过cset检查，该随机数
是否获取成功。

# VA range
```cpp
u64 __init kaslr_early_init(u64 dt_phys)
{
        ...
        /*
         * OK, so we are proceeding with KASLR enabled. Calculate a suitable
         * kernel image offset from the seed. Let's place the kernel in the
         * middle half of the VMALLOC area (VA_BITS_MIN - 2), and stay clear of
         * the lower and upper quarters to avoid colliding with other
         * allocations.
         * Even if we could randomize at page granularity for 16k and 64k pages,
         * let's always round to 2 MB so we don't interfere with the ability to
         * map using contiguous PTEs
         */
        mask = ((1UL << (VA_BITS_MIN - 2)) - 1) & ~(SZ_2M - 1);
        offset = BIT(VA_BITS_MIN - 3) + (seed & mask);
        ...
}
```
vmalloc的大小是:
BIT(VA_BTS_MIN - 1) 

因为seed是完全随机的，所以seed & mask为:
[0, BIT(VA_BITS_MIN -2)] , 占用 vmalloc size的比例为: [0, 1/2]

offset最后计算为 BIT(VA_BITS_MIN - 3) + seed & mask, 范围为
[0 + 1/4, 1/2 + 1/4] = [1/4, 3/4]

这样vmalloc的上下空间，就余出来了
## vmalloc fixmap ?
```
  Start                 End                     Size            Use
  -----------------------------------------------------------------------
  0000000000000000      0000ffffffffffff         256TB          user
  ffff000000000000      ffff7fffffffffff         128TB          kernel logical memory map
 [ffff600000000000      ffff7fffffffffff]         32TB          [kasan shadow region]
  ffff800000000000      ffff800007ffffff         128MB          bpf jit region
  ffff800008000000      ffff80000fffffff         128MB          modules
  ffff800010000000      fffffdffbffeffff         125TB          vmalloc
```
可以看到,  在`ffff800000000000`后，有两个空间`bpf jit region`, `modules`这两个
空间是固定映射， kaslr 也是为了给这些fixmap 预留足够的空间

# ARM64 arch
## RNDR && RNDRRS
https://poe.com/s/zRphSSaUX7T7Cr2VVfzS

这两个指令生成种子的方式不同

RNDR生成种子，是靠硬件电路，更加随机, RNDRRS需要CPU 生成种子没有那么随机

如果生成失败，将PSTATE.NZCV设置为0b0100(Z为1)

手册中讲到了这两个寄存器，但是没有太细节:
K14.1 Properties of the generated random number

## cset
比较condition, 详细见cset指令，以及conditionholds

## NZCV
C5.2.10 NZCV.Condition Flags
