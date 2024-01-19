# MAIL LIST

[MAIL LIST](https://lore.kernel.org/all/1456290520-10012-1-git-send-email-zhaoshenglong@huawei.com/)

# Patch 分析
## Patch 0 commit message
我们先看Patch 0 的 commit message:
```
Subject: [PATCH v13 00/20] KVM: ARM64: Add guest PMU support
Date: Wed, 24 Feb 2016 13:08:20 +0800	[thread overview]
Message-ID: <1456290520-10012-1-git-send-email-zhaoshenglong@huawei.com> (raw)

From: Shannon Zhao <shannon.zhao@linaro.org>

This patchset adds guest PMU support for KVM on ARM64. It takes
trap-and-emulate approach. When guest wants to monitor one event, it
will be trapped by KVM and KVM will call perf_event API to create a perf
event and call relevant perf_event APIs to get the count value of event.

> relevant [ˈreləvənt] : 相关的; 有意义的
>
> 该patchset 增加了在ARM64上的KVM对 guest PMU 的支持. 它采用 trap-and-emulate
> 的方式实现. 当 guest想要 monitor一个event, 他将会trap到KVM, 然后 KVM将会
> call perf_event API 来 create 一个 perf event, 并且调用相关的 perf_event APIs
> 来获取 event 的 count value.

Use perf to test this patchset in guest. When using "perf list", it
shows the list of the hardware events and hardware cache events perf
supports. Then use "perf stat -e EVENT" to monitor some event. For
example, use "perf stat -e cycles" to count cpu cycles and
"perf stat -e cache-misses" to count cache misses.

> 使用 perf 在 guest中测试此补丁集. 当使用 "perf list", 他展示 hardware events
> 和 hardware cache event的 perf支持的列表. 然后使用 "perf stat -e EVENT" 来监控
> 某些事件. 例如, 使用 "perf stat -e cycles" 来计算 cpu cycles 并且使用 "perf stat 
> -e cache-misses" 来计算 cache misses.
```
后续的commit message 展示了作者在host上和guest上做的一些测试
* `perf stat -r 5 sleep 5` in guest && host
  ```
  Below are the outputs of "perf stat -r 5 sleep 5" when running in host
  and guest.
  
  
  Host:
   Performance counter stats for 'sleep 5' (5 runs):
  
            0.529248      task-clock (msec)         #    0.000 CPUs utilized            ( +-  1.65% )
                   1      context-switches          #    0.002 M/sec
                   0      cpu-migrations            #    0.000 K/sec
                  49      page-faults               #    0.092 M/sec                    ( +-  1.05% )
             1104279      cycles                    #    2.087 GHz                      ( +-  1.65% )
     <not supported>      stalled-cycles-frontend
     <not supported>      stalled-cycles-backend
              528112      instructions              #    0.48  insns per cycle          ( +-  1.12% )
     <not supported>      branches
                9579      branch-misses             #   18.099 M/sec                    ( +-  2.40% )
  
         5.000851904 seconds time elapsed                                          ( +-  0.00% )
  
  Guest:
   Performance counter stats for 'sleep 5' (5 runs):
  
            0.695412      task-clock (msec)         #    0.000 CPUs utilized            ( +-  1.26% )
                   1      context-switches          #    0.001 M/sec
                   0      cpu-migrations            #    0.000 K/sec
                  49      page-faults               #    0.070 M/sec                    ( +-  1.29% )
             1430471      cycles                    #    2.057 GHz                      ( +-  1.25% )
     <not supported>      stalled-cycles-frontend
     <not supported>      stalled-cycles-backend
              659173      instructions              #    0.46  insns per cycle          ( +-  2.64% )
     <not supported>      branches
               10893      branch-misses             #   15.664 M/sec                    ( +-  1.23% )
  
         5.001277044 seconds time elapsed                                          ( +-  0.00% )
  
  ```
* 在 guest host 上 都执行 read cycle counter
  ```
  Have a cycle counter read test like below in guest and host:
  static void test(void)
  {
  	unsigned long count, count1, count2;
  	count1 = read_cycles();
  	count++;
  	count2 = read_cycles();
  }
  
  Host:
  count1: 3046505444
  count2: 3046505575
  delta: 131
  
  Guest:
  count1: 5932773531
  count2: 5932773668
  delta: 137
  
  The gap between guest and host is very small. One reason for this I
  think is that it doesn't count the cycles in EL2 and host since we add
  exclude_hv = 1. So the cycles spent to store/restore registers which
  happens at EL2 are not included.
  
  > 在 guest 和host中的gap 是非常小的. 对于此的一个原因,我认为是 他不计算
  > EL2和host中的cycle, 因为我们增加了 exclude_hv = 1, 所以 发生在 EL2的 
  > store/restore registers 消耗的cycle 将不会被包括
  
  This patchset can be fetched from [1] and the relevant QEMU version for
  test can be fetched from [2].
  
  The results of 'perf test' can be found from [3][4].
  The results of perf_event_tests test suite can be found from [5][6].
  
  > 这些链接都不能获取了
  
  Also, I have tested "perf top" in two VMs and host at the same time. It
  works well.
  > 我也在两个 VMs中同时测试了 "perf top". 他也运行的很好
  
  Thanks,
  Shannon
  ```

接下来我们来分析下patch code, 关于代码优化级别的patch不再分析.

## 数据结构引入 -- kvm_pmc, kvm_pmu

> FROM
>
> [\[PATCH v13 02/20\] KVM: ARM64: Define PMU data structure for each vcpu](
> https://lore.kernel.org/all/1456290520-10012-3-git-send-email-zhaoshenglong@huawei.com/
> )

我们先来看下commit message:
```
Here we plan to support virtual PMU for guest by full software
emulation, so define some basic structs and functions preparing for
futher steps. Define struct kvm_pmc for performance monitor counter and
struct kvm_pmu for performance monitor unit for each vcpu. According to
ARMv8 spec, the PMU contains at most 32(ARMV8_PMU_MAX_COUNTERS)
counters.

> 这里我们计划 通过 full software emulation 为 guest 支持 virtual PMU, 
> 所以定义了某些 basic structs 和 functions 来为后续的step 做准备.为
> performance counters 定义 kvm_pmc, 为 每个vcpu 的 performance monitor 
> unit 定义kvm_pmu. 根据 ARMv8 spec, PMU 包括至少 32(ARMV8_PMU_MAX_COUNTERS)
> 个 counters.

Since this only supports ARM64 (or PMUv3), add a separate config symbol
for it.

> 由于它只支持ARM64（或PMUv3），因此为它添加一个单独的 config symbol。
```

所以该patch有两个部分: 

* 增加配置项
  ```diff
  diff --git a/arch/arm64/kvm/Kconfig b/arch/arm64/kvm/Kconfig
  index a5272c0..de7450d 100644
  --- a/arch/arm64/kvm/Kconfig
  +++ b/arch/arm64/kvm/Kconfig
  @@ -36,6 +36,7 @@ config KVM
   	select HAVE_KVM_EVENTFD
   	select HAVE_KVM_IRQFD
   	select KVM_ARM_VGIC_V3
  +	select KVM_ARM_PMU if HW_PERF_EVENTS
   	---help---
   	  Support hosting virtualized guest machines.
   	  We don't support KVM with 16K page tables yet, due to the multiple
  @@ -48,6 +49,12 @@ config KVM_ARM_HOST
   	---help---
   	  Provides host support for ARM processors.
   
  +config KVM_ARM_PMU
  +	bool
  +	---help---
  +	  Adds support for a virtual Performance Monitoring Unit (PMU) in
  +	  virtual machines.
  +
  ```
* 引入 PMC, per vcpu PMU 数据结构
  ```cpp
  struct kvm_pmc {
        u8 idx; /* index into the pmu->pmc array */
        struct perf_event *perf_event;
        u64 bitmask;
  };
  ```
  + **idx**: 表示 pmc 的index
  + **perf_event** : 模拟pmc使用的是 full software  emulation, 所以
                 是完全借助原有的 perf 框架实现,将pmc 模拟成一个
                 perf event.
  + **bitmask**: ???
  ```cpp
  struct kvm_pmu {
          int irq_num;
          struct kvm_pmc pmc[ARMV8_PMU_MAX_COUNTERS];
          bool ready;
          bool irq_level;
  };
  ```
  + **irq_num**: 如果guest使能了PMI, 需要借助host注入, 所以这里记录
             的是, 注入guest的 irq
  + **pmc**: pmc 列表
  + **ready**: 表示 pmu已经初始化好了
  + **irq_level** : ????

## emulate PMU registers acccess

### PMCR -- part1 , 没有细分bits

我们主要看下handler 部分
```diff
+static void reset_pmcr(struct kvm_vcpu *vcpu, const struct sys_reg_desc *r)
+{
+	u64 pmcr, val;
+
+	asm volatile("mrs %0, pmcr_el0\n" : "=r" (pmcr));
+	/* Writable bits of PMCR_EL0 (ARMV8_PMU_PMCR_MASK) is reset to UNKNOWN
+	 * except PMCR.E resetting to zero.
+	 */
+	val = ((pmcr & ~ARMV8_PMU_PMCR_MASK)
+	       | (ARMV8_PMU_PMCR_MASK & 0xdecafbad)) & (~ARMV8_PMU_PMCR_E);
+	vcpu_sys_reg(vcpu, PMCR_EL0) = val;
+}
+
+static bool access_pmcr(struct kvm_vcpu *vcpu, struct sys_reg_params *p,
+			const struct sys_reg_desc *r)
+{
+	u64 val;
+
    //查看 pmu 是否是ready的, 不是ready 则忽略本次操作 -- read-as-zero write-ignore
    //#define kvm_arm_pmu_v3_ready(v)		((v)->arch.pmu.ready)
+	if (!kvm_arm_pmu_v3_ready(vcpu))
+		return trap_raz_wi(vcpu, p, r);
+
+	if (p->is_write) {
+		/* Only update writeable bits of PMCR */
+		val = vcpu_sys_reg(vcpu, PMCR_EL0);
+		val &= ~ARMV8_PMU_PMCR_MASK;
+		val |= p->regval & ARMV8_PMU_PMCR_MASK;
+		vcpu_sys_reg(vcpu, PMCR_EL0) = val;
+	} else {
+		/* PMCR.P & PMCR.C are RAZ */
+		val = vcpu_sys_reg(vcpu, PMCR_EL0)
+		      & ~(ARMV8_PMU_PMCR_P | ARMV8_PMU_PMCR_C);
+		p->regval = val;
+	}
+
+	return true;
+}
```

### PMSELR
```diff
+static bool access_pmselr(struct kvm_vcpu *vcpu, struct sys_reg_params *p,
+			  const struct sys_reg_desc *r)
+{
+	if (!kvm_arm_pmu_v3_ready(vcpu))
+		return trap_raz_wi(vcpu, p, r);
+
+	if (p->is_write)
+		vcpu_sys_reg(vcpu, PMSELR_EL0) = p->regval;
+	else
+		/* return PMSELR.SEL field */
+		p->regval = vcpu_sys_reg(vcpu, PMSELR_EL0)
+			    & ARMV8_PMU_COUNTER_MASK;
+
+	return true;
+}
```
### PMCEID -- PMCEID0_EL0 && PMCEID1_EL0
```diff
+static bool access_pmceid(struct kvm_vcpu *vcpu, struct sys_reg_params *p,
+			  const struct sys_reg_desc *r)
+{
+	u64 pmceid;
+
+	if (!kvm_arm_pmu_v3_ready(vcpu))
+		return trap_raz_wi(vcpu, p, r);
+
+	BUG_ON(p->is_write);
+
    //这两个寄存器用于表示支持哪些 Common architectual event.
    //PMCEID0 op2 == 0b110, PMCEID1_EL0 op2 == 0b111
    //由于是纯软件实现,所以host上支持哪些 guest就支持哪些.
+	if (!(p->Op2 & 1))
+		asm volatile("mrs %0, pmceid0_el0\n" : "=r" (pmceid));
+	else
+		asm volatile("mrs %0, pmceid1_el0\n" : "=r" (pmceid));
+
+	p->regval = pmceid;
+
+	return true;
+}
```

### EVENT COUNTER -- PMEVCNT0_EL0 ~ PMEVCNTR30_EL0 && PMCCNTR_EL0
```cpp
+static bool pmu_counter_idx_valid(struct kvm_vcpu *vcpu, u64 idx)
+{
+	u64 pmcr, val;
+
    /*
     * pmcr.n 定义了 counter的最大数量, 这里判断合法寄存器条件
     * 满足下面两条中的其中一条就行:
     * 1. idx ==  ARMV8_PMU_CYCLE_IDX
     * 2. idx < n
     */
+	pmcr = vcpu_sys_reg(vcpu, PMCR_EL0);
+	val = (pmcr >> ARMV8_PMU_PMCR_N_SHIFT) & ARMV8_PMU_PMCR_N_MASK;
+	if (idx >= val && idx != ARMV8_PMU_CYCLE_IDX)
+		return false;
+
+	return true;
+}
+
+static bool access_pmu_evcntr(struct kvm_vcpu *vcpu,
+			      struct sys_reg_params *p,
+			      const struct sys_reg_desc *r)
+{
+	u64 idx;
+
+	if (!kvm_arm_pmu_v3_ready(vcpu))
+		return trap_raz_wi(vcpu, p, r);
+
    //
+	if (r->CRn == 9 && r->CRm == 13) {
+		if (r->Op2 == 2) {
+			/* PMXEVCNTR_EL0 */
+			idx = vcpu_sys_reg(vcpu, PMSELR_EL0)
+			      & ARMV8_PMU_COUNTER_MASK;
+		} else if (r->Op2 == 0) {
+			/* PMCCNTR_EL0 */
+			idx = ARMV8_PMU_CYCLE_IDX;
+		} else {
+			BUG();
+		}
+	} else if (r->CRn == 14 && (r->CRm & 12) == 8) {
+		/* PMEVCNTRn_EL0 */
+		idx = ((r->CRm & 3) << 3) | (r->Op2 & 7);
+	} else {
+		BUG();
+	}
+
+	if (!pmu_counter_idx_valid(vcpu, idx))
+		return false;
+
+	if (p->is_write)
+		kvm_pmu_set_counter_value(vcpu, idx, p->regval);
+	else
+		p->regval = kvm_pmu_get_counter_value(vcpu, idx);
+
+	return true;
+}
```
