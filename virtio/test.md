# qemu调试
## 脚本
```
global count = 0
probe process("/usr/libexec/qemu-kvm").mark("virtio_notify_irqfd") {
       if ($vdev == $1)
       {
               if (count > 120) {
                       printf("%s, %d, vdev = %lx\n", probefunc(), count, $vdev)
               }
               count = 0
       }
}

probe process("/usr/libexec/qemu-kvm").mark("virtio_blk_req_complete") {
       if($vdev == $1)    // $vdev是fio测试盘在qemu中的数据结构（struct VirtIODevice）
       {
               count = count + 1
       }
}

probe end {
       printf("count = %ld\n", count)
}
```
## 输出
[root@node-1 stap]# stap -v virtio.stap 0xaaaac88df530
Pass 1: parsed user script and 470 library scripts using 375296virt/136576res/17536shr/118400data kb, in 360usr/0sys/345real ms.
Pass 2: analyzed script: 3 probes, 7 functions, 0 embeds, 1 global using 413184virt/177856res/19008shr/156288data kb, in 150usr/10sys/157real ms.
Pass 3: translated to C into "/tmp/stapfPMdW2/stap_65b56a7d6eda4590098b400944b29b6e_2912_src.c" using 413184virt/178048res/19200shr/156288data kb, in 60usr/70sys/127real ms.



Pass 4: compiled C into "stap_65b56a7d6eda4590098b400944b29b6e_2912.ko" in 4410usr/150sys/3868real ms.
Pass 5: starting run.
virtio_notify_irqfd, 128, vdev = aaaac88df530
virtio_notify_irqfd, 127, vdev = aaaac88df530

## gdb 调试
```
2444    in /usr/src/debug/qemu-kvm-4.2.0-59.el8_6.wang2.aarch64/hw/virtio/virtio.c
1: *vq = {vring = {num = 128, num_default = 128, align = 4096, desc = 4641325056, avail = 4641327104, used = 4641327424, caches = 0xffff5c32faa0}, used_elems = 0xaaaaf42ff760, last_avail_idx = 31893, last_avail_wrap_counter = true, shadow_avail_idx = 31893,
  shadow_avail_wrap_counter = true, used_idx = 31893, used_wrap_counter = true, signalled_used = 31892, signalled_used_valid = true, notification = true, queue_index = 0, inuse = 0, vector = 1, handle_output = 0xaaaab8eea4c8 <virtio_blk_handle_output>,
  handle_aio_output = 0xaaaab8eea7f0 <virtio_blk_data_plane_handle_output>, vdev = 0xaaaaf42cd5f0, guest_notifier = {rfd = 109, wfd = 109}, host_notifier = {rfd = 110, wfd = 110}, host_notifier_enabled = true, node = {le_next = 0x0, le_prev = 0xaaaaf42d96b8}}
(gdb) c
Continuing.

...
Thread 1 "qemu-kvm" hit Breakpoint 1, virtio_notify_irqfd (vdev=0xaaaaf42cd5f0, vq=0xaaaaf42d96d0) at /usr/src/debug/qemu-kvm-4.2.0-59.el8_6.wang2.aarch64/hw/virtio/virtio.c:2444
2444    in /usr/src/debug/qemu-kvm-4.2.0-59.el8_6.wang2.aarch64/hw/virtio/virtio.c
1: *vq = {vring = {num = 128, num_default = 128, align = 4096, desc = 4641325056, avail = 4641327104, used = 4641327424, caches = 0xffff5c32faa0}, used_elems = 0xaaaaf42ff760, last_avail_idx = 32021, last_avail_wrap_counter = true, shadow_avail_idx = 32021,
  shadow_avail_wrap_counter = true, used_idx = 31894, used_wrap_counter = true, signalled_used = 31893, signalled_used_valid = true, notification = true, queue_index = 0, inuse = 127, vector = 1, handle_output = 0xaaaab8eea4c8 <virtio_blk_handle_output>,
  handle_aio_output = 0xaaaab8eea7f0 <virtio_blk_data_plane_handle_output>, vdev = 0xaaaaf42cd5f0, guest_notifier = {rfd = 109, wfd = 109}, host_notifier = {rfd = 110, wfd = 110}, host_notifier_enabled = true, node = {le_next = 0x0, le_prev = 0xaaaaf42d96b8}}
```
