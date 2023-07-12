# virtio qemu
## virtio_blk_data_plane_start
```
 0x55e653b2c349 : virtio_blk_data_plane_start+0x2b9/0x440 [/usr/bin/qemu-system-x86_64]
 0x55e653a008e2 : virtio_bus_start_ioeventfd+0x112/0x140 [/usr/bin/qemu-system-x86_64]
 0x55e653a02584 : virtio_pci_common_write+0x174/0x4c0 [/usr/bin/qemu-system-x86_64]
 0x55e653ba379b : memory_region_write_accessor+0x7b/0x120 [/usr/bin/qemu-system-x86_64]
 0x55e653b9fd5f : access_with_adjusted_size+0xaf/0x140 [/usr/bin/qemu-system-x86_64]
 0x55e653ba3250 : memory_region_dispatch_write+0x100/0x200 [/usr/bin/qemu-system-x86_64]
 0x55e653baa760 : flatview_write_continue+0x120/0x2d0 [/usr/bin/qemu-system-x86_64]
 0x55e653baa978 : flatview_write+0x68/0xd0 [/usr/bin/qemu-system-x86_64]
 0x55e653bae659 : address_space_rw+0x119/0x160 [/usr/bin/qemu-system-x86_64]
 0x55e653c3110b : kvm_cpu_exec+0x2db/0x520 [/usr/bin/qemu-system-x86_64]
 0x55e653c322b5 : kvm_vcpu_thread_fn+0xa5/0xf0 [/usr/bin/qemu-system-x86_64]
 0x55e653d86a15 : qemu_thread_start+0x55/0x90 [/usr/bin/qemu-system-x86_64]
```

## virtio_pci_modern_regions_init

# virtio guest kernel
## stack
```
#0  virtio_pci_modern_probe (vp_dev=0xffff8881076fc000) at drivers/virtio/virtio_pci_modern.c:421
#1  0xffffffff815a642f in virtio_pci_probe (pci_dev=0xffff8881013ab000, id=<optimized out>) at drivers/virtio/virtio_pci_common.c:546
#2  0xffffffff814fc952 in local_pci_probe (_ddi=_ddi@entry=0xffffc90000c63ce8) at drivers/pci/pci-driver.c:388
#3  0xffffffff814fe1c5 in pci_call_probe (id=<optimized out>, dev=0xffff8881013ab000, drv=<optimized out>) at drivers/pci/pci-driver.c:445
#4  __pci_device_probe (pci_dev=0xffff8881013ab000, drv=<optimized out>) at drivers/pci/pci-driver.c:470
#5  pci_device_probe (dev=0xffff8881013ab0b8) at drivers/pci/pci-driver.c:513
#6  0xffffffff81629142 in really_probe (dev=dev@entry=0xffff8881013ab0b8, drv=drv@entry=0xffffffff82ac8e70 <virtio_pci_driver+144>) at drivers/base/dd.c:604
#7  0xffffffff81629419 in driver_probe_device (drv=drv@entry=0xffffffff82ac8e70 <virtio_pci_driver+144>, dev=dev@entry=0xffff8881013ab0b8) at drivers/base/dd.c:768
#8  0xffffffff81629800 in device_driver_attach (drv=drv@entry=0xffffffff82ac8e70 <virtio_pci_driver+144>, dev=dev@entry=0xffff8881013ab0b8) at drivers/base/dd.c:1022
#9  0xffffffff81629871 in __driver_attach (dev=0xffff8881013ab0b8, data=0xffffffff82ac8e70 <virtio_pci_driver+144>) at drivers/base/dd.c:1099
#10 0xffffffff81626c87 in bus_for_each_dev (bus=<optimized out>, start=start@entry=0x0 <fixed_percpu_data>, data=data@entry=0xffffffff82ac8e70 <virtio_pci_driver+144>,
    fn=fn@entry=0xffffffff81629810 <__driver_attach>) at drivers/base/bus.c:304
#11 0xffffffff8162894a in driver_attach (drv=drv@entry=0xffffffff82ac8e70 <virtio_pci_driver+144>) at drivers/base/dd.c:1115
#12 0xffffffff816281dd in bus_add_driver (drv=drv@entry=0xffffffff82ac8e70 <virtio_pci_driver+144>) at drivers/base/bus.c:621
#13 0xffffffff8162a43b in driver_register (drv=0xffffffff82ac8e70 <virtio_pci_driver+144>) at drivers/base/driver.c:170
--Type <RET> for more, q to quit, c to continue without paging--
#14 0xffffffff810027f6 in do_one_initcall (fn=0xffffffff83002d54 <virtio_pci_driver_init>) at init/main.c:905
#15 0xffffffff82fac440 in do_initcall_level (level=6) at init/main.c:973
#16 do_initcalls () at init/main.c:981
#17 do_basic_setup () at init/main.c:998
#18 kernel_init_freeable () at init/main.c:1171
#19 0xffffffff81996b7f in kernel_init (unused=<optimized out>) at init/main.c:1081
#20 0xffffffff81a00255 in ret_from_fork () at arch/x86/entry/entry_64.S:319
#21 0x0000000000000000 in ?? ()
```
## virtio_pci_config_ops
```
static const struct virtio_config_ops virtio_pci_config_ops = {
        .get            = vp_get,
        .set            = vp_set,
        .generation     = vp_generation,
        .get_status     = vp_get_status,
        .set_status     = vp_set_status,
        .reset          = vp_reset,
        .find_vqs       = vp_modern_find_vqs,
        .del_vqs        = vp_del_vqs,
        .get_features   = vp_get_features,
        .finalize_features = vp_finalize_features,
        .bus_name       = vp_bus_name,
        .set_vq_affinity = vp_set_vq_affinity,
        .get_vq_affinity = vp_get_vq_affinity,
        .get_shm_region  = vp_get_shm_region,
};
```

## virtio_pci_probe
```cpp

```

## KVM_SET_GSI_ROUTING
```
the KVM_SET_GSI_ROUTING is enter
 0x55875b6239e0 : kvm_vm_ioctl+0x0/0x70 [/usr/bin/qemu-system-x86_64]
 0x55875b624306 : kvm_irqchip_commit_routes+0x46/0x70 [/usr/bin/qemu-system-x86_64]
 0x55875b4afb79 : pc_gsi_create+0x69/0x70 [/usr/bin/qemu-system-x86_64]
 0x55875b4a1abf : pc_q35_init+0x46f/0x9a0 [/usr/bin/qemu-system-x86_64]
 0x55875b2fc1d1 : machine_run_board_init+0x251/0x990 [/usr/bin/qemu-system-x86_64]
 0x55875b41faeb : qmp_x_exit_preconfig.part.0+0x3b/0x420 [/usr/bin/qemu-system-x86_64]
 0x55875b4237e1 : qemu_init+0x3571/0x42b0 [/usr/bin/qemu-system-x86_64]
 0x55875b284b9d : main+0xd/0x20 [/usr/bin/qemu-system-x86_64]
 0x7fbe2af0bb4a [/usr/lib64/libc.so.6+0x27b4a/0x1de000]
WARNING: Missing unwind data for a module, rerun with 'stap -d /usr/lib64/libc.so.6'



the KVM_SET_GSI_ROUTING is enter
 0x55875b6239e0 : kvm_vm_ioctl+0x0/0x70 [/usr/bin/qemu-system-x86_64]
 0x55875b624306 : kvm_irqchip_commit_routes+0x46/0x70 [/usr/bin/qemu-system-x86_64]
 0x55875b3fa587 : virtio_pci_set_guest_notifiers+0x487/0x5c0 [/usr/bin/qemu-system-x86_64]
 0x55875b5221e3 : virtio_blk_data_plane_start+0x153/0x440 [/usr/bin/qemu-system-x86_64]
 0x55875b3f68e2 : virtio_bus_start_ioeventfd+0x112/0x140 [/usr/bin/qemu-system-x86_64]
 0x55875b3f8584 : virtio_pci_common_write+0x174/0x4c0 [/usr/bin/qemu-system-x86_64]
 0x55875b59979b : memory_region_write_accessor+0x7b/0x120 [/usr/bin/qemu-system-x86_64]
 0x55875b595d5f : access_with_adjusted_size+0xaf/0x140 [/usr/bin/qemu-system-x86_64]
 0x55875b599250 : memory_region_dispatch_write+0x100/0x200 [/usr/bin/qemu-system-x86_64]
 0x55875b5a0760 : flatview_write_continue+0x120/0x2d0 [/usr/bin/qemu-system-x86_64]
 0x55875b5a0978 : flatview_write+0x68/0xd0 [/usr/bin/qemu-system-x86_64]
 0x55875b5a4659 : address_space_rw+0x119/0x160 [/usr/bin/qemu-system-x86_64]
 0x55875b62710b : kvm_cpu_exec+0x2db/0x520 [/usr/bin/qemu-system-x86_64]
 0x55875b6282b5 : kvm_vcpu_thread_fn+0xa5/0xf0 [/usr/bin/qemu-system-x86_64]
 0x55875b77ca15 : qemu_thread_start+0x55/0x90 [/usr/bin/qemu-system-x86_64]
 0x7fbe2af70907 [/usr/lib64/libc.so.6+0x8c907/0x1de000]
```

## virtio_blk_device_realize
```
 0x5572e7a6a2d0 : virtio_blk_device_realize+0x0/0x4a0 [/usr/bin/qemu-system-x86_64]
 0x5572e7aaa840 : virtio_device_realize+0xb0/0x1b0 [/usr/bin/qemu-system-x86_64]
 0x5572e7b7a875 : device_set_realized+0x1e5/0x720 [/usr/bin/qemu-system-x86_64]
 0x5572e7b7d9fd : property_set_bool+0x4d/0x70 [/usr/bin/qemu-system-x86_64]
 0x5572e7b80a5e : object_property_set+0x7e/0x110 [/usr/bin/qemu-system-x86_64]
 0x5572e7b840e4 : object_property_set_qobject+0x34/0x50 [/usr/bin/qemu-system-x86_64]
 0x5572e7b810cd : object_property_set_bool+0x3d/0xb0 [/usr/bin/qemu-system-x86_64]
 0x5572e78e0db8 : pci_qdev_realize+0x7c8/0x1160 [/usr/bin/qemu-system-x86_64]
 0x5572e7b7a875 : device_set_realized+0x1e5/0x720 [/usr/bin/qemu-system-x86_64]
 0x5572e7b7d9fd : property_set_bool+0x4d/0x70 [/usr/bin/qemu-system-x86_64]
 0x5572e7b80a5e : object_property_set+0x7e/0x110 [/usr/bin/qemu-system-x86_64]
 0x5572e7b840e4 : object_property_set_qobject+0x34/0x50 [/usr/bin/qemu-system-x86_64]
 0x5572e7b810cd : object_property_set_bool+0x3d/0xb0 [/usr/bin/qemu-system-x86_64]
 0x5572e796650e : qdev_device_add_from_qdict+0xace/0xd30 [/usr/bin/qemu-system-x86_64]
 0x5572e796679e : qdev_device_add+0x2e/0xa0 [/usr/bin/qemu-system-x86_64]
 0x5572e79683ab : device_init_func+0x1b/0x50 [/usr/bin/qemu-system-x86_64]
 0x5572e7ccfe99 : qemu_opts_foreach+0x69/0xe0 [/usr/bin/qemu-system-x86_64]
 0x5572e796abea : qmp_x_exit_preconfig.part.0+0x13a/0x420 [/usr/bin/qemu-system-x86_64]
 0x5572e796e7e1 : qemu_init+0x3571/0x42b0 [/usr/bin/qemu-system-x86_64]
 0x5572e77cfb9d : main+0xd/0x20 [/usr/bin/qemu-system-x86_64]
```

## msix_init

## msix_prepare_message
```
pci_get_msi_message
kvm_irqchip_add_msi_route
kvm_virtio_pci_vq_vector_use
kvm_virtio_pci_vector_use
```
# VIRTIO SPEC
## 4.1.4.3 Common configuration structure layout
```cpp
struct virtio_pci_common_cfg {
        /* About the whole device. */
        __le32 device_feature_select;   /* read-write */
        __le32 device_feature;          /* read-only */
        __le32 guest_feature_select;    /* read-write */
        __le32 guest_feature;           /* read-write */
        __le16 msix_config;             /* read-write */
        __le16 num_queues;              /* read-only */
        __u8 device_status;             /* read-write */
        __u8 config_generation;         /* read-only */

        /* About a specific virtqueue. */
        __le16 queue_select;            /* read-write */
        __le16 queue_size;              /* read-write, power of 2. */
        __le16 queue_msix_vector;       /* read-write */
        __le16 queue_enable;            /* read-write */
        __le16 queue_notify_off;        /* read-only */
        __le32 queue_desc_lo;           /* read-write */
        __le32 queue_desc_hi;           /* read-write */
        __le32 queue_avail_lo;          /* read-write */
        __le32 queue_avail_hi;          /* read-write */
        __le32 queue_used_lo;           /* read-write */
        __le32 queue_used_hi;           /* read-write */
};
```

* **device_feature_select** The driver uses this to select which feature bits device_feature shows. Value 0x0
selects Feature Bits 0 to 31, 0x1 selects Feature Bits 32 to 63, etc.
* **device_feature** The device uses this to report which feature bits it is offering to the driver: the driver writes
to device_feature_select to select which feature bits are presented.
* **driver_feature_select** The driver uses this to select which feature bits driver_feature shows. Value 0x0
selects Feature Bits 0 to 31, 0x1 selects Feature Bits 32 to 63, etc.
* **driver_feature** The driver writes this to accept feature bits offered by the device. Driver Feature Bits se-
lected by driver_feature_select.


# 参考连接
https://blog.csdn.net/huang987246510/article/details/103379926
