# 简介
早期linux kernel 在arm64架构上之有`CONFIG_ZONE_DMA32`, 无`CONFIG_ZONE_DMA`
```
//FILE ===arch/arm64/Kconfig====

config GENERIC_CALIBRATE_DELAY
        def_bool y

config ZONE_DMA32
        bool "Support DMA32 zone" if EXPERT
        default y

config ARCH_ENABLE_MEMORY_HOTPLUG
        def_bool y
```
所以arm64分配内存的时候, 如果要分配低内存, 只能在 `ZONE_DMA32`的范围内分配

> NOTE
>
> 大家想下zone设计的目的, 就是为了将内存化片, 分配内存的时候,可以选择
> 在哪一片分配

但是, Nicolas 发现在新的`Raspberry Pi 4`(树梅派?)机器上可能会有一些异常的
情况

Mail list:

[\[PATCH v3 0/4\] Raspberry Pi 4 DMA addressing support](https://lore.kernel.org/all/20190902141043.27210-1-nsaenzjulienne@suse.de/)

我们来看下, MAIL LIST MESSAGE:
```
The new Raspberry Pi 4 has up to 4GB of memory but most peripherals can
only address the first GB: their DMA address range is
0xc0000000-0xfc000000 which is aliased to the first GB of physical
memory 0x00000000-0x3c000000. Note that only some peripherals have these
limitations: the PCIe, V3D, GENET, and 40-bit DMA channels have a wider
view of the address space by virtue of being hooked up trough a second
interconnect.

virtue [ˈvɜːtʃuː] : 美德,优点

新的 Raspberry Pi 4 已经达到了4GB的内存,但是大部分的外围设备只能寻址
第一个GB: 他们的dma address range 是 0xc0000000-0xfc000000, 这个地址范围
是物理地址内存 0x00000000-0x3c000000 的别名???. 注意只有某些外围设备有
这些限制,PCIe, V3D, GENET, 和40位DMA通道通过第二个(channels互相链接) 
有更宽的地址空间视角

> 这里是不是说没有这个限制才对

Part of this is solved on arm32 by setting up the machine specific
'.dma_zone_size = SZ_1G', which takes care of reserving the coherent
memory area at the right spot. That said no buffer bouncing (needed for
dma streaming) is available at the moment, but that's a story for
another series.

take care of: 关心,照顾
spot: 地方,场所,地点

他们中的某些在arm32 上通过 设置 machine specific(定制)'.dma_zone_size = SZ_1G'
解决该问题, 它负责在正确的位置保留 coherent(一致性?) memory area. 也就是
说目前没有 available 的 buffer bouncing (dma streaming 需要) , 但是
这是另外一个 series.

Unfortunately there is no such thing as 'dma_zone_size' in arm64. Only
ZONE_DMA32 is created which is interpreted by dma-direct and the arm64
arch code as if all peripherals where be able to address the first 4GB
of memory.

interpreted [ɪnˈtɜːrprətɪd] : 诠释, 说明,把...理解为

不幸的是, 现在在arm64 中没有 "dma_zone_size". 只有ZONE_DMA32 被创建,
其由 dma-direct和arm64 arch code 解释的那样,就好象所有的外围设备都
能够寻址内存中的第一个4GB

In the light of this, the series implements the following changes:

In the light of this : 鉴于此

- Create both DMA zones in arm64, ZONE_DMA will contain the first 1G
  area and ZONE_DMA32 the rest of the 32 bit addressable memory. So far
  the RPi4 is the only arm64 device with such DMA addressing limitations
  so this hardcoded solution was deemed preferable.

  deemed [diːmd] : 认为,视为
  preferable [ˈprefrəbl] : 更合适

  在arm64中同时创建DMA zones, ZONE_DMA 将包含第一个1G area 并且 ZONE_DMA32
  则包含剩余的32 bit的可寻址的memory. 到目前为止，RPi4是唯一具有这种DMA寻址
  限制的arm64设备，因此这种硬编码解决方案被认为是更合适的.

- Properly set ARCH_ZONE_DMA_BITS.
-
  正确的设置 ARCH_ZONE_DMA_BITS

- Reserve the CMA area in a place suitable for all peripherals.
  
  将CMA区域保留在适合所有外围设备的位置。

This series has been tested on multiple devices both by checking the
zones setup matches the expectations and by double-checking physical
addresses on pages allocated on the three relevant areas GFP_DMA,
GFP_DMA32, GFP_KERNEL:

该系列已经在多个设备上测试过, 一方面检查zones setup 是否符合预期, 另一方面
检查三个相关区域GFP_DMA, GFP_DMA32, GFP_KERNEL 分配的 pages的物理地址

- On an RPi4 with variations on the ram memory size. But also forcing
  the situation where all three memory zones are nonempty by setting a 3G
  ZONE_DMA32 ceiling on a 4G setup. Both with and without NUMA support.

  variations : 变化
  ceiling: 天花板, 上限

  但也通过在4G的设置上设置3G ZONE_DMA32 上线, 强制使三个memory zones 都
  不为空 ???
  
- On a Synquacer box[1] with 32G of memory.

- On an ACPI based Huawei TaiShan server[2] with 256G of memory.

- On a QEMU virtual machine running arm64's OpenSUSE Tumbleweed.

That's all.

Regards,
Nicolas
```

根据上述描述, 该patch引入的目的,就是`Raspberry Pi 4`机器 要分配1GB之内的
内存,但是现在ARM64 只支持 ZONE_DMA32(4G), 所以作者增加了 ZONE_DMA (1g)
的zone

# 具体patch
该patch集一共4个:我们具体分析

* [\[PATCH v3 1/4\] arm64: mm: use arm64_dma_phys_limit instead of calling max_zone_dma_phys()](https://lore.kernel.org/all/20190902141043.27210-2-nsaenzjulienne@suse.de/)

  该patch 主要是说, `arm64_dma_phys_limit`变量已经初始化被设置好了,直接用就行,
  不用再调用`max_zone_dma_phys()`获取了
  ```diff
  diff --git a/arch/arm64/mm/init.c b/arch/arm64/mm/init.c
  index f3c795278def..6112d6c90fa8 100644
  --- a/arch/arm64/mm/init.c
  +++ b/arch/arm64/mm/init.c
  @@ -181,7 +181,7 @@ static void __init zone_sizes_init(unsigned long min, unsigned long max)
   	unsigned long max_zone_pfns[MAX_NR_ZONES]  = {0};
   
   #ifdef CONFIG_ZONE_DMA32
  -	max_zone_pfns[ZONE_DMA32] = PFN_DOWN(max_zone_dma_phys());
  +	max_zone_pfns[ZONE_DMA32] = PFN_DOWN(arm64_dma_phys_limit);
   #endif
    max_zone_pfns[ZONE_NORMAL] = max;
  ```
* [\[PATCH v3 2/4\] arm64: rename variables used to calculate ZONE_DMA32's size](https://lore.kernel.org/all/20190902141043.27210-3-nsaenzjulienne@suse.de/)
  
  该patch主要是更改 `arm64_dma_phys_limit -> arm64_dma32_phys_limit`
  因为之前的`arm64_dma_phys_limit` 就是代表 DMA32的上限, 现在要加入DMA, 
  避免引起变量名歧义
  ```diff
  diff --git a/arch/arm64/mm/init.c b/arch/arm64/mm/init.c
  index 6112d6c90fa8..8956c22634dd 100644
  --- a/arch/arm64/mm/init.c
  +++ b/arch/arm64/mm/init.c
  @@ -50,7 +50,7 @@
   s64 memstart_addr __ro_after_init = -1;
   EXPORT_SYMBOL(memstart_addr);
   
  -phys_addr_t arm64_dma_phys_limit __ro_after_init;
  +phys_addr_t arm64_dma32_phys_limit __ro_after_init;
   
   #ifdef CONFIG_KEXEC_CORE
   /*
  @@ -168,7 +168,7 @@ static void __init reserve_elfcorehdr(void)
    * currently assumes that for memory starting above 4G, 32-bit devices will
    * use a DMA offset.
    */
  -static phys_addr_t __init max_zone_dma_phys(void)
  +static phys_addr_t __init max_zone_dma32_phys(void)
   {
   	phys_addr_t offset = memblock_start_of_DRAM() & GENMASK_ULL(63, 32);
   	return min(offset + (1ULL << 32), memblock_end_of_DRAM());
  @@ -181,7 +181,7 @@ static void __init zone_sizes_init(unsigned long min, unsigned long max)
   	unsigned long max_zone_pfns[MAX_NR_ZONES]  = {0};
   
   #ifdef CONFIG_ZONE_DMA32
  -	max_zone_pfns[ZONE_DMA32] = PFN_DOWN(arm64_dma_phys_limit);
  +	max_zone_pfns[ZONE_DMA32] = PFN_DOWN(arm64_dma32_phys_limit);
   #endif
   	max_zone_pfns[ZONE_NORMAL] = max;

   ...//截取部分
  ```
   > NOTE
   >
   > 我们这里截取一部分, 底下的改动大相径庭
* [\[PATCH v3 3/4\] arm64: use both ZONE_DMA and ZONE_DMA32](https://lore.kernel.org/all/20190902141043.27210-4-nsaenzjulienne@suse.de/ )
  + 增加`ZONE_DMA`配置项
    ```diff
    diff --git a/arch/arm64/Kconfig b/arch/arm64/Kconfig
    index 3adcec05b1f6..a9fd71d3bc8e 100644
    --- a/arch/arm64/Kconfig
    +++ b/arch/arm64/Kconfig
    @@ -266,6 +266,10 @@ config GENERIC_CSUM
     config GENERIC_CALIBRATE_DELAY
     	def_bool y
     
    +config ZONE_DMA
    +	bool "Support DMA zone" if EXPERT
    +	default y
    + 
    ```
  + 增加`arm64_dma_phys_limit`变量
    ```diff
    +/*
    + * We create both ZONE_DMA and ZONE_DMA32. ZONE_DMA covers the first 1G of
    + * memory as some devices, namely the Raspberry Pi 4, have peripherals with
    + * this limited view of the memory. ZONE_DMA32 will cover the rest of the 32
    + * bit addressable memory area.
    + */
    +phys_addr_t arm64_dma_phys_limit __ro_after_init; 
    ```
  + 初始化`arm64_dma_phys_limit`
    ```diff
    diff --git a/arch/arm64/include/asm/page.h b/arch/arm64/include/asm/page.h
    index d39ddb258a04..7b8c98830101 100644
    --- a/arch/arm64/include/asm/page.h
    +++ b/arch/arm64/include/asm/page.h
    @@ -38,4 +38,6 @@ extern int pfn_valid(unsigned long);
     
     #include <asm-generic/getorder.h>
     
    +#define ARCH_ZONE_DMA_BITS 30

    ...

    diff --git a/arch/arm64/mm/init.c b/arch/arm64/mm/init.c
    index 8956c22634dd..f02a4945aeac 100644
    --- a/arch/arm64/mm/init.c
    +++ b/arch/arm64/mm/init.c
    +static phys_addr_t __init max_zone_dma_phys(void)
    +{
    +	phys_addr_t offset = memblock_start_of_DRAM() & GENMASK_ULL(63, 32);
    +
    +	return min(offset + (1ULL << ARCH_ZONE_DMA_BITS),
    +		   memblock_end_of_DRAM());
    +}

    ...

    @@ -405,7 +433,9 @@ void __init arm64_memblock_init(void)
     
     	early_init_fdt_scan_reserved_mem();
     
    -	/* 4GB maximum for 32-bit only capable devices */
    +	if (IS_ENABLED(CONFIG_ZONE_DMA))
    +		arm64_dma_phys_limit = max_zone_dma_phys();
    ```
  + 使用该变量初始化`zone_size[]`
    ```diff
     static void __init zone_sizes_init(unsigned long min, unsigned long max)
     {
     	unsigned long max_zone_pfns[MAX_NR_ZONES]  = {0};
     
    +#ifdef CONFIG_ZONE_DMA
    +	max_zone_pfns[ZONE_DMA] = PFN_DOWN(arm64_dma_phys_limit);
    +#endif
     #ifdef CONFIG_ZONE_DMA32
     	max_zone_pfns[ZONE_DMA32] = PFN_DOWN(arm64_dma32_phys_limit);
     #endif
    @@ -195,13 +213,17 @@ static void __init zone_sizes_init(unsigned long min, unsigned long max)
     	struct memblock_region *reg;
     	unsigned long zone_size[MAX_NR_ZONES], zhole_size[MAX_NR_ZONES];
     	unsigned long max_dma32 = min;
    +	unsigned long max_dma = min;
     
     	memset(zone_size, 0, sizeof(zone_size));
     
    -	/* 4GB maximum for 32-bit only capable devices */
    +#ifdef CONFIG_ZONE_DMA
    +	max_dma = PFN_DOWN(arm64_dma_phys_limit);
    +	zone_size[ZONE_DMA] = max_dma - min;
    +#endif
     #ifdef CONFIG_ZONE_DMA32
     	max_dma32 = PFN_DOWN(arm64_dma32_phys_limit);
    -	zone_size[ZONE_DMA32] = max_dma32 - min;
        //这个地方需要注意下, 目前ZONE_DMA32范围为 [dma_max, dma32_max]
    +	zone_size[ZONE_DMA32] = max_dma32 - max_dma;
     #endif
     	zone_size[ZONE_NORMAL] = max - max_dma32;
     
    @@ -213,11 +235,17 @@ static void __init zone_sizes_init(unsigned long min, unsigned long max)
     
     		if (start >= max)
     			continue;
    -
    +#ifdef CONFIG_ZONE_DMA
    +		if (start < max_dma) {
    +			unsigned long dma_end = min_not_zero(end, max_dma);
    +			zhole_size[ZONE_DMA] -= dma_end - start;
    +		}
    +#endif
     #ifdef CONFIG_ZONE_DMA32
     		if (start < max_dma32) {
    -			unsigned long dma_end = min(end, max_dma32);
    -			zhole_size[ZONE_DMA32] -= dma_end - start;
    +			unsigned long dma32_end = min(end, max_dma32);
    +			unsigned long dma32_start = max(start, max_dma);
    +			zhole_size[ZONE_DMA32] -= dma32_end - dma32_start;
     		}
     #endif
     		if (end > max_dma32) {
    ```

  主要的改动, 如上.

* [\[PATCH v3 4/4\] mm: refresh ZONE_DMA and ZONE_DMA32 comments in 'enum zone_type'](https://lore.kernel.org/all/20190902141043.27210-5-nsaenzjulienne@suse.de/)
  
  主要再更新一些注释, 不展开.

# RHEL 8.6 kernel - 4.18.0-372.19.1 合入情况
目前该代码合入了一部分patch !, patch 1, patch 2合入了.
但是 patch 3没有合入,这就导致目前RHEL 8.6 kernel,
虽然已经有了`arm64_dma32_phys_limit`变量, 但是未支持
`ZONE_DMA`

# 结论
[\[PATCH v24 0/6\] support reserving crashkernel above 4G on arm64 kdump](https://lore.kernel.org/all/20220506114402.365-1-thunder.leizhen@huawei.com/)
是在
[\[PATCH v3 0/4\] Raspberry Pi 4 DMA addressing support](https://lore.kernel.org/all/20190902141043.27210-1-nsaenzjulienne@suse.de/)
之前合入,所以在upstream patch中使用`arm64_dma_phys_limit`就是dma32 的limit, 在rhel 8.6 kernel中应该使用`arm64_dma32_phys_limit`变量
