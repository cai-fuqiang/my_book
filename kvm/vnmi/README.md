# org patch

> FROM
>
> https://lore.kernel.org/all/200805151850.22339.sheng.yang@intel.com/
>
> https://lore.kernel.org/all/200805151850.27483.sheng.yang@intel.com/

## API 层面引入 NMI

COMMIT message :
```
From 3419ffc8e45a5344abc87684cbca6cdc5c9c8a01 Mon Sep 17 00:00:00 2001
From: Sheng Yang <sheng.yang@intel.com>
Date: Thu, 15 May 2008 09:52:48 +0800
Subject: [PATCH 1/2] KVM: IOAPIC/LAPIC: Enable NMI support
```
我们主要看下, 在引入patch前后, IOAPIC 和 LAPIC是如何处理NMI的.

我们先看数据结构的变动, 因为从早期的interrupt/nmi的处理, 用户侧先调用系统调用
注入中断/nmi, 然后, kvm在处理时, 标记下, 在vm entry 之前, 设置好 inject event.

所以为支持inject nmi, 在 `kvm_vcpu_arch`增加一个成员,表示有nmi pending
```diff
diff --git a/include/asm-x86/kvm_host.h b/include/asm-x86/kvm_host.h
index 4bcdc7de07b5..b66621935eb7 100644
--- a/include/asm-x86/kvm_host.h
+++ b/include/asm-x86/kvm_host.h
@@ -288,6 +288,8 @@ struct kvm_vcpu_arch {
        unsigned int hv_clock_tsc_khz;
        unsigned int time_offset;
        struct page *time_page;
+
+       bool nmi_pending;
 };
```

引入接口, 用来使能 nmi pending
```diff
+void kvm_inject_nmi(struct kvm_vcpu *vcpu)
+{
+       vcpu->arch.nmi_pending = 1;
+}
+EXPORT_SYMBOL_GPL(kvm_inject_nmi);

+static void ioapic_inj_nmi(struct kvm_vcpu *vcpu)
+{
+       kvm_inject_nmi(vcpu);
+}
```

我们接下来再看, IOAPIC, LAPIC的处理.
* LAPIC
  ```diff
  diff --git a/arch/x86/kvm/lapic.c b/arch/x86/kvm/lapic.c
  index f9201fbc61d1..e48d19394031 100644
  --- a/arch/x86/kvm/lapic.c
  +++ b/arch/x86/kvm/lapic.c
  @@ -356,8 +356,9 @@ static int __apic_accept_irq(struct kvm_lapic *apic, int delivery_mode,
          case APIC_DM_SMI:
                  printk(KERN_DEBUG "Ignoring guest SMI\n");
                  break;
  +
          case APIC_DM_NMI:
  -               printk(KERN_DEBUG "Ignoring guest NMI\n");
  +               kvm_inject_nmi(vcpu);
                  break;
  
          case APIC_DM_INIT:
  ```
  在该patch之前忽略 NMI. 而引入该patch 直接调用 `kvm_inject_nmi`

* IOAPIC
  ```diff
  @@ -239,8 +244,19 @@ static int ioapic_deliver(struct kvm_ioapic *ioapic, int irq)
                          }
                  }
                  break;
  -
  -               /* TODO: NMI */
  +       case IOAPIC_NMI:
  +               for (vcpu_id = 0; deliver_bitmask != 0; vcpu_id++) {
  +                       if (!(deliver_bitmask & (1 << vcpu_id)))
  +                               continue;
  +                       deliver_bitmask &= ~(1 << vcpu_id);
  +                       vcpu = ioapic->kvm->vcpus[vcpu_id];
  +                       if (vcpu)
  +                               ioapic_inj_nmi(vcpu);
  +                       else
  +                               ioapic_debug("NMI to vcpu %d failed\n",
  +                                               vcpu->vcpu_id);
  +               }
  +               break;
          default:
                  printk(KERN_WARNING "Unsupported delivery mode %d\n",
                         delivery_mode);
  ```
  和LAPIC处理类似.

该patch 就做了这些, 只是在IOAPIC/LAPIC 处理 irq时, 检测NMI 并使能 `vcpu->nmi_pending`

## KVM: VMX: Enable NMI with in-kernel irqchip
```
From f08864b42a45581a64558aa5b6b673c77b97ee5d Mon Sep 17 00:00:00 2001
From: Sheng Yang <sheng.yang@intel.com>
Date: Thu, 15 May 2008 18:23:25 +0800
Subject: [PATCH 2/2] KVM: VMX: Enable NMI with in-kernel irqchip
```

我们先思考下, 为了支持virtual-NMI, 我们需要关注哪些?
* vNMI feature detect
* vNMI inject
  + NMI-window exit
  + judge NMI-window is open or not 
* unblocked nmi by IRET

下面我们分别来看:

### vNMI feature detect
```diff
+static inline int cpu_has_virtual_nmis(void)
+{
+       return vmcs_config.pin_based_exec_ctrl & PIN_BASED_VIRTUAL_NMIS;
+}
+
 static int __find_msr_index(struct vcpu_vmx *vmx, u32 msr)
 {
        int i;
@@ -1088,7 +1093,7 @@ static __init int setup_vmcs_config(struct vmcs_config *vmcs_conf)
        u32 _vmentry_control = 0;

        min = PIN_BASED_EXT_INTR_MASK | PIN_BASED_NMI_EXITING;
-       opt = 0;
+       opt = PIN_BASED_VIRTUAL_NMIS;
        if (adjust_vmx_controls(min, opt, MSR_IA32_VMX_PINBASED_CTLS,
                                &_pin_based_exec_control) < 0)
                return -EIO;

```
代码较简单, 不过多解释

### vNMI inject

在看 vNMI inject 接口之前, 我们先看下该接口用到的
* 判断 NMI window 是否开启, enable NMI window exit
  ```cpp
  static void enable_nmi_window(struct kvm_vcpu *vcpu)
  {
         u32 cpu_based_vm_exec_control;
  
         if (!cpu_has_virtual_nmis())
                 return;
  
         cpu_based_vm_exec_control = vmcs_read32(CPU_BASED_VM_EXEC_CONTROL);
         cpu_based_vm_exec_control |= CPU_BASED_VIRTUAL_NMI_PENDING;
         vmcs_write32(CPU_BASED_VM_EXEC_CONTROL, cpu_based_vm_exec_control);
  }
  
  static int vmx_nmi_enabled(struct kvm_vcpu *vcpu)
  {
         u32 guest_intr = vmcs_read32(GUEST_INTERRUPTIBILITY_INFO);
         return !(guest_intr & (GUEST_INTR_STATE_NMI |
                                GUEST_INTR_STATE_MOV_SS |
                                GUEST_INTR_STATE_STI));
  }
  ```
  > NOTE
  >
  > 这里需要注意的是 `GUEST_INTR_STATE_STI`似乎也能影响 nmi是否能被注入,
  > 我们知道这个主要是看下在 VMX-root operation 下该指令的行为:
  >
  > 在 intel sdm 介绍STI 指令时, 会有下面一句话:
  >
  > ```
  > The IF flag and the STI and CLI instructions do not prohibit the generation
  > of exceptions and nonmaskable interrupts (NMIs). However, NMIs (and
  > system-management interrupts) may be inhibited on the instruction boundary
  > following an execution of STI that begins with IF = 0.
  > ```
  > 大意为:
  >
  > ```
  > prohibit [prəˈhɪbɪt] : 禁止,阻止,使不可能
  > inhibit: 阻止,抑制
  > ```
  >
  > IF flags和STI CLI 指令 并不能阻止 exception 和 NMIs的产生. 但是 NMI 和 SMI啃呢过会在
  > STI在IF=0的情况下执行时, 会在其指令之后的 boundary inhibited.

* 判断 intr window 是否开启, enable intr window exit
  ```cpp
  static int vmx_irq_enabled(struct kvm_vcpu *vcpu)
  {
         u32 guest_intr = vmcs_read32(GUEST_INTERRUPTIBILITY_INFO);
         return (!(guest_intr & (GUEST_INTR_STATE_MOV_SS |
                                GUEST_INTR_STATE_STI)) &&
                 (vmcs_readl(GUEST_RFLAGS) & X86_EFLAGS_IF));
  }
  
  static void enable_intr_window(struct kvm_vcpu *vcpu)
  {
         if (vcpu->arch.nmi_pending)
                 enable_nmi_window(vcpu);
         else if (kvm_cpu_has_interrupt(vcpu))
                 enable_irq_window(vcpu);
  }
  ```
* vmx_inject_nmi
  ```cpp
  static void vmx_inject_nmi(struct kvm_vcpu *vcpu)
  {
         vmcs_write32(VM_ENTRY_INTR_INFO_FIELD,
                         INTR_TYPE_NMI_INTR | INTR_INFO_VALID_MASK | NMI_VECTOR);
         vcpu->arch.nmi_pending = 0;
  }
  ```

  可以看到这里会将 nmi_pending 设置为0

***

vNMI inject 的接口主要在 `vmx_intr_assist`, 

> assist [əˈsɪst]: 帮助; 援助; 协助；促进

该函数是 `vmx_x86_ops` 的hook
```cpp
static struct kvm_x86_ops vmx_x86_ops = {
    ...
    .inject_pending_irq = vmx_intr_assist,
    ...
};
```

该函数变动如下:
```diff
 static void vmx_intr_assist(struct kvm_vcpu *vcpu)
 {
        struct vcpu_vmx *vmx = to_vmx(vcpu);
-       u32 idtv_info_field, intr_info_field;
-       int has_ext_irq, interrupt_window_open;
+       u32 idtv_info_field, intr_info_field, exit_intr_info_field;
        int vector;

        update_tpr_threshold(vcpu);

-       has_ext_irq = kvm_cpu_has_interrupt(vcpu);
        //VM-entry interruption-information field
        intr_info_field = vmcs_read32(VM_ENTRY_INTR_INFO_FIELD);
        //VM-exit interruption information
+       exit_intr_info_field = vmcs_read32(VM_EXIT_INTR_INFO);
        //在vm-exit 时, 从 IDT-vectoring information field 获取
        idtv_info_field = vmx->idt_vectoring_info;
        //已经有事件要注入
        if (intr_info_field & INTR_INFO_VALID_MASK) {
                if (idtv_info_field & INTR_INFO_VALID_MASK) {
                        /* TODO: fault when IDT_Vectoring */
                        if (printk_ratelimit())
                                printk(KERN_ERR "Fault when IDT_Vectoring\n");
                }
-               if (has_ext_irq)
-                       enable_irq_window(vcpu);
                //开启intr window exit, 让其在 interrupt/NMI window打开时, VM-exit,
                //以便接下来的 inject event.
+               enable_intr_window(vcpu);
                return;
        }
        //说明在event delivery 时, 出现了 VM exit
        if (unlikely(idtv_info_field & INTR_INFO_VALID_MASK)) {
                //如果是外部中断, 并且 rmode.active, 则将该触发vm exit中断注入,
                //并且开启interrupt window exit, 等待下次vm entry 时, 再注入中断
                if ((idtv_info_field & VECTORING_INFO_TYPE_MASK)
                    == INTR_TYPE_EXT_INTR
                    && vcpu->arch.rmode.active) {
                        u8 vect = idtv_info_field & VECTORING_INFO_VECTOR_MASK;

                        vmx_inject_irq(vcpu, vect);
-                       if (unlikely(has_ext_irq))
-                               enable_irq_window(vcpu);
+                       enable_intr_window(vcpu);
                        return;
                }

                KVMTRACE_1D(REDELIVER_EVT, vcpu, idtv_info_field, handler);

-               vmcs_write32(VM_ENTRY_INTR_INFO_FIELD, idtv_info_field);
+               /*
+                * SDM 3: 25.7.1.2
+                * Clear bit "block by NMI" before VM entry if a NMI delivery
+                * faulted.
+                */
                //如果VM exit是由于 NMI 注入, 则再次注入该NMI, 并且clear blocking by
                //NMI
+               if ((idtv_info_field & VECTORING_INFO_TYPE_MASK)
+                   == INTR_TYPE_NMI_INTR && cpu_has_virtual_nmis())
+                       vmcs_write32(GUEST_INTERRUPTIBILITY_INFO,
+                               vmcs_read32(GUEST_INTERRUPTIBILITY_INFO) &
+                               ~GUEST_INTR_STATE_NMI);
+
                //将 idtv_info_field, 写入 VM_ENTRY_INTR_INFO_FIELD, 为什么能直接写呢?
                //因为这两者格式完全一样.
+               vmcs_write32(VM_ENTRY_INTR_INFO_FIELD, idtv_info_field
+                               & ~INTR_INFO_RESVD_BITS_MASK);
                vmcs_write32(VM_ENTRY_INSTRUCTION_LEN,
                                vmcs_read32(VM_EXIT_INSTRUCTION_LEN));

                if (unlikely(idtv_info_field & INTR_INFO_DELIVER_CODE_MASK))
                        vmcs_write32(VM_ENTRY_EXCEPTION_ERROR_CODE,
                                vmcs_read32(IDT_VECTORING_ERROR_CODE));
-               if (unlikely(has_ext_irq))
-                       enable_irq_window(vcpu);
                //开启 interrrupt window exit
+               enable_intr_window(vcpu);
                return;
        }
-       if (!has_ext_irq)
-       if (!has_ext_irq)
        //这种情况是, 没有其他 vector 影响
+       if (cpu_has_virtual_nmis()) {
+               /*
+                * SDM 3: 25.7.1.2
+                * Re-set bit "block by NMI" before VM entry if vmexit caused by
+                * a guest IRET fault.
+                */
                //如果 unblock nmi mask && ! double fault && ! valid bit
                //8是double fault, 这里没有检测 valid bit.
+               if ((exit_intr_info_field & INTR_INFO_UNBLOCK_NMI) &&
+                   (exit_intr_info_field & INTR_INFO_VECTOR_MASK) != 8)
                        //由于unblock nmi, 则需要在下次vm entry 之前, 将 blocking by 
                        //NMI 设置上, 让其block
+                       vmcs_write32(GUEST_INTERRUPTIBILITY_INFO,
+                               vmcs_read32(GUEST_INTERRUPTIBILITY_INFO) |
+                               GUEST_INTR_STATE_NMI);
                //表示有nmi_pending
+               else if (vcpu->arch.nmi_pending) {
                        //将查看 nmi 是否可以注入(NMI window)
+                       if (vmx_nmi_enabled(vcpu))
                                //注入
+                               vmx_inject_nmi(vcpu);
                        //这里我们需要注意, 由于上面 vmx_inject_nmi 可能会clear nmi_pending,
                        //所以enable_intr_window()并不一定会enable nmi window exit,
                        //只有当上面发现 !vmx_nmi_enabled()时, 说明此时nmi window 并未开启,
                        //所以需要设置 nmi window exit, 等待其cpu到达 nmi window open时, vm
                        //exit , 然后再注入 nmi
+                       enable_intr_window(vcpu);
+                       return;
+               }
+
+       }
+       if (!kvm_cpu_has_interrupt(vcpu))
                return;
-       interrupt_window_open =
-               ((vmcs_readl(GUEST_RFLAGS) & X86_EFLAGS_IF) &&
-                (vmcs_read32(GUEST_INTERRUPTIBILITY_INFO) & 3) == 0);
-       if (interrupt_window_open) {
        //和上面比较类似, 只不过一个是中断, 一个是nmi, 不过这里感觉不太好的时,
        //如果有在这里pending了多个中断, 这里的逻辑并不会 enable interrupt window
        //exit , 而是等待其vcpu 因为别的原因vm exit后, 再inject next irq.
+       if (vmx_irq_enabled(vcpu)) {
                vector = kvm_cpu_get_interrupt(vcpu);
                vmx_inject_irq(vcpu, vector);
                kvm_timer_intr_post(vcpu, vector);
        } else
                enable_irq_window(vcpu);
}
```
