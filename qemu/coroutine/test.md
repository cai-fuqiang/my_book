# thread_pool_co_cb 
```
(gdb) bt
#0  thread_pool_co_cb (opaque=0xfffb415af728, ret=0) at util/thread-pool.c:277
#1  0x0000aaaae84b736c in thread_pool_completion_bh (opaque=0xaaaaede4bd10) at util/thread-pool.c:188
#2  thread_pool_completion_bh (opaque=0xaaaaede4bd10) at util/thread-pool.c:162
#3  0x0000aaaae84b6548 in aio_bh_call (bh=0xaaaaede86850) at util/async.c:117
#4  aio_bh_poll (ctx=ctx@entry=0xaaaaede4b940) at util/async.c:117
#5  0x0000aaaae84b9a6c in aio_dispatch (ctx=0xaaaaede4b940) at util/aio-posix.c:467
#6  0x0000aaaae84b6430 in aio_ctx_dispatch (source=<optimized out>, callback=<optimized out>,
    user_data=<optimized out>) at util/async.c:268
#7  0x0000ffff8bb1deb4 in g_main_context_dispatch () from /lib64/libglib-2.0.so.0
#8  0x0000aaaae84b8bcc in glib_pollfds_poll () at util/main-loop.c:219
#9  os_host_main_loop_wait (timeout=<optimized out>) at util/main-loop.c:242
#10 main_loop_wait (nonblocking=<optimized out>) at util/main-loop.c:518
#11 0x0000aaaae82f2e60 in main_loop () at vl.c:1828
#12 0x0000aaaae813a568 in main (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>)
    at vl.c:4504
```

# raw_thread_pool_submit 
```
#0  raw_thread_pool_submit (bs=bs@entry=0xaaaaedeb0220, func=func@entry=0xaaaae8428f78 <handle_aiocb_rw>,
    arg=arg@entry=0xfffb4028f6c8) at block/file-posix.c:1908
#1  0x0000aaaae8428e88 in raw_co_prw (bs=0xaaaaedeb0220, offset=1635233792, bytes=4096, qiov=0xaaaaef1a3f08,
    type=2) at block/file-posix.c:1952
#2  0x0000aaaae8433f14 in bdrv_driver_pwritev (bs=bs@entry=0xaaaaedeb0220, offset=offset@entry=1635233792,
    bytes=bytes@entry=4096, qiov=qiov@entry=0xaaaaef1a3f08, qiov_offset=qiov_offset@entry=0,
    flags=flags@entry=0) at block/io.c:1183
#3  0x0000aaaae843608c in bdrv_aligned_pwritev (child=child@entry=0xaaaaede696c0,
    req=req@entry=0xfffb4028f918, offset=offset@entry=1635233792, bytes=bytes@entry=4096,
    align=align@entry=1, qiov=qiov@entry=0xaaaaef1a3f08, qiov_offset=qiov_offset@entry=0,
    flags=flags@entry=0) at block/io.c:1980
#4  0x0000aaaae8436714 in bdrv_co_pwritev_part (child=0xaaaaede696c0, offset=offset@entry=1635233792,
    bytes=<optimized out>, bytes@entry=4096, qiov=<optimized out>, qiov@entry=0xaaaaef1a3f08,
    qiov_offset=<optimized out>, qiov_offset@entry=0, flags=flags@entry=0) at block/io.c:2137
#5  0x0000aaaae8404304 in qcow2_co_pwritev_task (l2meta=0x0, qiov_offset=<optimized out>,
    qiov=0xaaaaef1a3f08, bytes=<optimized out>, offset=<optimized out>, file_cluster_offset=1635188736,
    bs=0xaaaaede973f0) at block/qcow2.c:2448
#6  qcow2_co_pwritev_task_entry (task=<optimized out>) at block/qcow2.c:2479
#7  0x0000aaaae8402f88 in qcow2_add_task (bs=bs@entry=0xaaaaede973f0, pool=pool@entry=0x0,
    func=func@entry=0xaaaae8403f98 <qcow2_co_pwritev_task_entry>,
    cluster_type=cluster_type@entry=QCOW2_CLUSTER_UNALLOCATED, file_cluster_offset=1635188736,
    offset=offset@entry=6461173760, bytes=4096, qiov=qiov@entry=0xaaaaef1a3f08,
    qiov_offset=qiov_offset@entry=0, l2meta=0x0) at block/qcow2.c:2144
#8  0x0000aaaae840304c in qcow2_co_pwritev_part (bs=0xaaaaede973f0, offset=6461173760, bytes=4096,
    qiov=0xaaaaef1a3f08, qiov_offset=0, flags=<optimized out>) at block/qcow2.c:2533
#9  0x0000aaaae8433e70 in bdrv_driver_pwritev (bs=bs@entry=0xaaaaede973f0, offset=offset@entry=6461173760,
    bytes=bytes@entry=4096, qiov=qiov@entry=0xaaaaef1a3f08, qiov_offset=qiov_offset@entry=0,
    flags=flags@entry=0) at block/io.c:1171
#10 0x0000aaaae843608c in bdrv_aligned_pwritev (child=child@entry=0xaaaaedda0490,
    req=req@entry=0xfffb4028fe68, offset=offset@entry=6461173760, bytes=bytes@entry=4096,
    align=align@entry=1, qiov=qiov@entry=0xaaaaef1a3f08, qiov_offset=qiov_offset@entry=0,
    flags=flags@entry=0) at block/io.c:1980
#11 0x0000aaaae8436714 in bdrv_co_pwritev_part (child=0xaaaaedda0490, offset=offset@entry=6461173760,
    bytes=<optimized out>, bytes@entry=4096, qiov=<optimized out>, qiov@entry=0xaaaaef1a3f08,
    qiov_offset=<optimized out>, qiov_offset@entry=0, flags=0) at block/io.c:2137
#12 0x0000aaaae842369c in blk_do_pwritev_part (blk=0xaaaaede68900, offset=6461173760, bytes=4096,
    qiov=0xaaaaef1a3f08, qiov_offset=qiov_offset@entry=0, flags=<optimized out>)
    at block/block-backend.c:1231
#13 0x0000aaaae84237a0 in blk_aio_write_entry (opaque=0xaaaaef9378a0) at block/block-backend.c:1439
#14 0x0000aaaae84cfe80 in coroutine_trampoline (i0=<optimized out>, i1=<optimized out>)
    at util/coroutine-ucontext.c:115
#15 0x0000ffff8b2d1f90 in ?? () from /lib64/libc.so.6
```
