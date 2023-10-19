```
From: Wanpeng Li <kernellwp@gmail.com>
To: linux-kernel@vger.kernel.org, kvm@vger.kernel.org
Cc: "Paolo Bonzini" <pbonzini@redhat.com>,
	"Radim Krčmář" <rkrcmar@redhat.com>,
	"Peter Zijlstra" <peterz@infradead.org>,
	"Wanpeng Li" <wanpeng.li@hotmail.com>
Subject: [PATCH v8 0/4] KVM: X86: Add Paravirt TLB Shootdown
Date: Tue, 12 Dec 2017 17:33:00 -0800	[thread overview]
Message-ID: <1513128784-5924-1-git-send-email-wanpeng.li@hotmail.com> (raw)

Remote flushing api's does a busy wait which is fine in bare-metal
scenario. But with-in the guest, the vcpus might have been pre-empted
or blocked. In this scenario, the initator vcpu would end up
busy-waiting for a long amount of time.

> scenario : 场景 
>
> Remote flushing api's 是一个忙等机制, 他在裸金属场景里面运行的可以，
> 但是在guest中，vcpu 可能被抢占或者blocked. 在这个场景下，发起的vcpu
> 最终会忙等 很长一段时间.

This patch set implements para-virt flush tlbs making sure that it
does not wait for vcpus that are sleeping. And all the sleeping vcpus
flush the tlb on guest enter. Idea was discussed here:
https://lkml.org/lkml/2012/2/20/157

> 该patch 组 实现了 para-virt flush tlb 来保证 他（发起的vcpu) 不会等待
> 正在 sleeping 的vcpu。并且所有的sleeping vcpu 会在 guest enter 时候
> flush the tlb

The best result is achieved when we're overcommiting the host by running 
multiple vCPUs on each pCPU. In this case PV tlb flush avoids touching 
vCPUs which are not scheduled and avoid the wait on the main CPU.

> 当我噩梦呢通过每个pCPU 上运行多个 vCPUs以过度使用host(增加负载)。在这个
> 情况下，PV tlb flush 避免了touch 那些 没有 scheduled VCPUs 也就避免了
> 在 main CPU 上等待(initator)

In addition, thanks for commit 9e52fc2b50d ("x86/mm: Enable RCU based 
page table freeing (CONFIG_HAVE_RCU_TABLE_FREE=y)")

Testing on a Xeon Gold 6142 2.6GHz 2 sockets, 32 cores, 64 threads,
so 64 pCPUs, and each VM is 64 vCPUs.

ebizzy -M 
              vanilla    optimized     boost
1VM            46799       48670         4%
2VM            23962       42691        78%
3VM            16152       37539       132%

Note: The patchset is not rebased against "locking/qspinlock/x86: Avoid
   test-and-set when PV_DEDICATED is set" v3 since I can still observe a 
   little improvement for 64 vCPUs on 64 pCPUs, it is due to the system 
   is not completely isolated, there are many housekeeping tasks work
   sporadically, and vCPUs are preemted some times, I also confirm this 
   when adding some print to the kvm_flush_tlb_others. After PV_DEDICATED
   is merged, we can disable pv tlb flush when not overcommiting if it 
   is needed. 

v7 -> v8:
 * rebase against latest kvm/queue

v6 -> v7:
 * don't check !flushmask 
 * use arch_initcall() to achieve late allocate percpu mask

v5 -> v6:
 * fix the percpu mask 
 * rebase against latest kvm/queue

v4 -> v5:
 * flushmask instead of cpumask

v3 -> v4:
 * use READ_ONCE()
 * use try_cmpxchg instead of cmpxchg
 * add {} to if
 * no FLUSH flags to preserve during set_preempted
 * "KVM: X86" prefix to patch subject

v2 -> v3: 
 * percpu cpumask

v1 -> v2:
 * a new CPUID feature bit
 * fix cmpxchg check
 * use kvm_vcpu_flush_tlb() to get the statistics right
 * just OR the KVM_VCPU_PREEMPTED in kvm_steal_time_set_preempted
 * add a new bool argument to kvm_x86_ops->tlb_flush
 * __cpumask_clear_cpu() instead of cpumask_clear_cpu()
 * not put cpumask_t on stack
 * rebase the patchset against "locking/qspinlock/x86: Avoid
   test-and-set when PV_DEDICATED is set" v3
```
