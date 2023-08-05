# aio_poll
## bt iothread
```
(gdb) bt
#0  virtio_queue_host_notifier_aio_poll_begin (n=0xffff84020088) at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/hw/virtio/virtio.c:3392
#1  0x0000aaaab63792fc in poll_set_started (ctx=ctx@entry=0xaaaaeda6ba80, started=started@entry=true) at util/aio-posix.c:368
#2  0x0000aaaab6379cb0 in poll_set_started (started=true, ctx=0xaaaaeda6ba80) at util/aio-posix.c:603
#3  try_poll_mode (timeout=<synthetic pointer>, ctx=0xaaaaeda6ba80) at util/aio-posix.c:603
#4  aio_poll (ctx=0xaaaaeda6ba80, blocking=blocking@entry=true) at util/aio-posix.c:658
#5  0x0000aaaab61ad57c in iothread_run (opaque=0xaaaaeda0bf60) at iothread.c:75
#6  0x0000aaaab637bec4 in qemu_thread_start (args=0xaaaaeda6bfd0) at util/qemu-thread-posix.c:519
#7  0x0000ffff97227800 in start_thread (arg=0xaaaab637be70 <qemu_thread_start>) at pthread_create.c:479
#8  0x0000ffff971717dc in thread_start () at ../sysdeps/unix/sysv/linux/aarch64/clone.S:78
```

## bt main_loop
```
#0  virtio_queue_host_notifier_aio_read (n=0xaaaaef251ae8) at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/hw/virtio/virtio.c:3382
#1  0x0000aaaab6379110 in aio_dispatch_handlers (ctx=ctx@entry=0xaaaaeda50a10) at util/aio-posix.c:437
#2  0x0000aaaab6379a74 in aio_dispatch (ctx=0xaaaaeda50a10) at util/aio-posix.c:468
#3  0x0000aaaab6376430 in aio_ctx_dispatch (source=<optimized out>, callback=<optimized out>, user_data=<optimized out>) at util/async.c:268
#4  0x0000ffff9792deb4 in g_main_context_dispatch () from /lib64/libglib-2.0.so.0
#5  0x0000aaaab6378bcc in glib_pollfds_poll () at util/main-loop.c:219
#6  os_host_main_loop_wait (timeout=<optimized out>) at util/main-loop.c:242
#7  main_loop_wait (nonblocking=<optimized out>) at util/main-loop.c:518
#8  0x0000aaaab61b2e60 in main_loop () at vl.c:1828
#9  0x0000aaaab5ffa568 in main (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at vl.c:4504
```

## bt 
```
(gdb) bt
#0  bdrv_set_aio_context_ignore (bs=bs@entry=0xaaaaf8238620, new_context=new_context@entry=0xaaaaf8207ec0, ignore=ignore@entry=0xffff6fbfdcf0)
    at block.c:6101
#1  0x0000aaaabc9ae400 in bdrv_child_try_set_aio_context (bs=bs@entry=0xaaaaf8238620, ctx=0xaaaaf8207ec0, ignore_child=<optimized out>, errp=<optimized out>)
    at block.c:6315
#2  0x0000aaaabc9e1b48 in blk_do_set_aio_context (blk=0xaaaaf82371d0, new_context=0xaaaaf8207ec0, update_root_node=update_root_node@entry=true,
    errp=errp@entry=0xffff6fbfdd90) at block/block-backend.c:1989
#3  0x0000aaaabc9e42b4 in blk_set_aio_context (blk=<optimized out>, new_context=<optimized out>, errp=errp@entry=0xffff6fbfdd90)
    at block/block-backend.c:2010
#4  0x0000aaaabc779f70 in virtio_blk_data_plane_start (vdev=<optimized out>)
    at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/hw/block/dataplane/virtio-blk.c:217
#5  0x0000aaaabc933388 in virtio_bus_start_ioeventfd (bus=bus@entry=0xaaaaf9b1f8f8) at hw/virtio/virtio-bus.c:222
#6  0x0000aaaabc935120 in virtio_pci_start_ioeventfd (proxy=0xaaaaf9b17800) at hw/virtio/virtio-pci.c:1244
#7  virtio_pci_common_write (opaque=0xaaaaf9b17800, addr=<optimized out>, val=<optimized out>, size=<optimized out>) at hw/virtio/virtio-pci.c:1244
#8  0x0000aaaabc749d9c in memory_region_write_accessor (mr=<optimized out>, addr=<optimized out>, value=<optimized out>, size=<optimized out>,
    shift=<optimized out>, mask=<optimized out>, attrs=...) at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/memory.c:484
#9  0x0000aaaabc747f34 in access_with_adjusted_size (addr=addr@entry=20, value=value@entry=0xffff6fbfdee8, size=size@entry=1,
    access_size_min=<optimized out>, access_size_max=<optimized out>, access_fn=access_fn@entry=0xaaaabc749ce8 <memory_region_write_accessor>,
    mr=mr@entry=0xaaaaf9b181d0, attrs=attrs@entry=...) at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/memory.c:545
#10 0x0000aaaabc74be30 in memory_region_dispatch_write (mr=0xaaaaf9b181d0, addr=20, data=<optimized out>, op=MO_8, attrs=...)
    at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/memory.c:1480
#11 0x0000aaaabc6fdee8 in flatview_write_continue (fv=0xffff68330d20, addr=549768396820, attrs=..., buf=0xffff90040028 "\017", len=1, addr1=<optimized out>,
    l=<optimized out>, mr=0xaaaaf9b181d0) at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/include/qemu/host-utils.h:164
#12 0x0000aaaabc6fe0e4 in flatview_write (fv=0xffff68330d20, addr=549768396820, attrs=..., buf=0xffff90040028 "\017", len=1)
    at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/exec.c:3169
#13 0x0000aaaabc702768 in address_space_write (as=<optimized out>, addr=<optimized out>, attrs=..., buf=<optimized out>, len=<optimized out>)
    at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/exec.c:3259
#14 0x0000aaaabc75b724 in kvm_cpu_exec (cpu=0xaaaaf84657c0) at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/accel/kvm/kvm-all.c:2386
#15 0x0000aaaabc73f920 in qemu_kvm_cpu_thread_fn (arg=<optimized out>) at /usr/src/debug/qemu-kvm-4.2.0-59.es8_6.aarch64/cpus.c:1318
#16 0x0000aaaabca7bec4 in qemu_thread_start (args=0xaaaaf84adbc0) at util/qemu-thread-posix.c:519
#17 0x0000ffff93cd7800 in start_thread (arg=0xaaaabca7be70 <qemu_thread_start>) at pthread_create.c:479
#18 0x0000ffff93c217dc in thread_start () at ../sysdeps/unix/sysv/linux/aarch64/clone.S:78
```
