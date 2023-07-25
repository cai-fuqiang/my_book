# 简介
本文主要描述，qemu 在实现virtio-blk时， 对于guest notify,
host notify 的相关处理

主要的代码文件
```
hw/block/dataplane/virtio-blk.c
```

> NOTE
>
> 这里还有一个点没有搞懂, qemu 的bh机制，本文
> 暂时不对bh机制做介绍

# struct
## VirtIOBlock
```cpp
typedef struct VirtIOBlock {
    VirtIODevice parent_obj;    //包含 VirtIODevice
    BlockBackend *blk;
    void *rq;
    QEMUBH *bh;
    VirtIOBlkConf conf;
    unsigned short sector_mask;
    bool original_wce;
    VMChangeStateEntry *change;
    bool dataplane_disabled;    //dataplane状态
    bool dataplane_started;
    struct VirtIOBlockDataPlane *dataplane;
    uint64_t host_features;
    size_t config_size;
} VirtIOBlock;
```
## VirtIOBlockDataPlane
```cpp
struct VirtIOBlockDataPlane {
    bool starting;
    bool stopping;

    VirtIOBlkConf *conf;
    VirtIODevice *vdev;
    QEMUBH *bh;                     /* bh for guest notification */
    unsigned long *batch_notify_vqs;
    bool batch_notifications;       //表示是否能batch notify(几个请求，发一个notify)

    /* Note that these EventNotifiers are assigned by value.  This is
     * fine as long as you do not call event_notifier_cleanup on them
     * (because you don't own the file descriptor or handle; you just
     * use it).
     */
    IOThread *iothread;
    AioContext *ctx;                 //指向所在的AioContext
};
```
##  VirtIOBlkConf
```cpp
struct VirtIOBlkConf
{
    BlockConf conf;
    IOThread *iothread;              //iothread， 可以为空
    char *serial;
    uint32_t request_merging;
    uint16_t num_queues;             //队列数量
    uint16_t queue_size;             //队列大小
    uint32_t max_discard_sectors;
    uint32_t max_write_zeroes_sectors;
};
```

# 代码路径
##  virtio_blk_data_plane_create
```cpp
bool virtio_blk_data_plane_create(VirtIODevice *vdev, VirtIOBlkConf *conf,
                                  VirtIOBlockDataPlane **dataplane,
                                  Error **errp)
{
    VirtIOBlockDataPlane *s;
    BusState *qbus = BUS(qdev_get_parent_bus(DEVICE(vdev)));
    VirtioBusClass *k = VIRTIO_BUS_GET_CLASS(qbus);

    *dataplane = NULL;
    /* 
     * 指定了io thread, 这样，就不是用主线程的 main loop
     * 在测试时，发现conf->iothread为空，下面的流程，只看
     * conf->iothread == NULL 的情况
     */
    if (conf->iothread) {
        if (!k->set_guest_notifiers || !k->ioeventfd_assign) {
            error_setg(errp,
                       "device is incompatible with iothread "
                       "(transport does not support notifiers)");
            return false;
        }
        if (!virtio_device_ioeventfd_enabled(vdev)) {
            error_setg(errp, "ioeventfd is required for iothread");
            return false;
        }

        /* If dataplane is (re-)enabled while the guest is running there could
         * be block jobs that can conflict.
         */
        if (blk_op_is_blocked(conf->conf.blk, BLOCK_OP_TYPE_DATAPLANE, errp)) {
            error_prepend(errp, "cannot start virtio-blk dataplane: ");
            return false;
        }
    }
    /* Don't try if transport does not support notifiers. */
    if (!virtio_device_ioeventfd_enabled(vdev)) {
        return false;
    }

    s = g_new0(VirtIOBlockDataPlane, 1);
    s->vdev = vdev;
    s->conf = conf;

    if (conf->iothread) {
        s->iothread = conf->iothread;
        object_ref(OBJECT(s->iothread));
        s->ctx = iothread_get_aio_context(s->iothread);
    } else {
        //使用qemu_aio_context(主线程 main loop)
        s->ctx = qemu_get_aio_context();
    }
    s->bh = aio_bh_new(s->ctx, notify_guest_bh, s);
    s->batch_notify_vqs = bitmap_new(conf->num_queues);

    *dataplane = s;

    return true;
}
```

## virtio_blk_data_plane_start
该流程由guest driver write PCIe STATUS field 为 DRIVER_OK
时触发，这里不再列出调用逻辑。
```cpp
int virtio_blk_data_plane_start(VirtIODevice *vdev)
{
    VirtIOBlock *vblk = VIRTIO_BLK(vdev);
    VirtIOBlockDataPlane *s = vblk->dataplane;
    BusState *qbus = BUS(qdev_get_parent_bus(DEVICE(vblk)));
    VirtioBusClass *k = VIRTIO_BUS_GET_CLASS(qbus);
    unsigned i;
    unsigned nvqs = s->conf->num_queues;
    Error *local_err = NULL;
    int r;

    if (vblk->dataplane_started || s->starting) {
        return 0;
    }

    s->starting = true;
    /*
     * 查看vdev是否有 VIRTIO_RING_F_EVENT_IDX, 如果没有
     * batch_notifications  为真。
     *
     * VIRTIO_RING_F_EVENT_IDX为 virtio event idx机制，该机值
     * 可以让guest/driver 调整 期望在何种条件下对方才能发送notify。
     *
     * 而，没有该feature的话，需要每个req都要发送notify给对方，但是
     * 这样又比较慢, 所以qemu搞了个bh机制。通知bh，让其发送，如果notify
     * 过于频繁，可能会出现 batch notification
     */
    if (!virtio_vdev_has_feature(vdev, VIRTIO_RING_F_EVENT_IDX)) {
        s->batch_notifications = true;
    } else {
        s->batch_notifications = false;
    }

    /* Set up guest notifier (irq) */
    /* 设置guest notification, guest notification 比较简单，我们在 最后看 */
    r = k->set_guest_notifiers(qbus->parent, nvqs, true);
    if (r != 0) {
        error_report("virtio-blk failed to set guest notifier (%d), "
                     "ensure -accel kvm is set.", r);
        goto fail_guest_notifiers;
    }

    /* Set up virtqueue notify */
    for (i = 0; i < nvqs; i++) {
        //申请 eventfd, 将bus 上的地址和 eventfd 绑定
        r = virtio_bus_set_host_notifier(VIRTIO_BUS(qbus), i, true);
        if (r != 0) {
            fprintf(stderr, "virtio-blk failed to set host notifier (%d)\n", r);
            while (i--) {
                virtio_bus_set_host_notifier(VIRTIO_BUS(qbus), i, false);
                virtio_bus_cleanup_host_notifier(VIRTIO_BUS(qbus), i);
            }
            goto fail_guest_notifiers;
        }
    }

    s->starting = false;
    vblk->dataplane_started = true;
    trace_virtio_blk_data_plane_start(s);
    r = blk_set_aio_context(s->conf->conf.blk, s->ctx, &local_err);
    if (r < 0) {
        error_report_err(local_err);
        goto fail_guest_notifiers;
    }

    /* Kick right away to begin processing requests already in vring */
    for (i = 0; i < nvqs; i++) {
        VirtQueue *vq = virtio_get_queue(s->vdev, i);
        //在 dataplane start 时，avail vring 可能有一些请求，这里
        //set host notify
        event_notifier_set(virtio_queue_get_host_notifier(vq));
    }

    /* Get this show started by hooking up our callbacks */
    aio_context_acquire(s->ctx);
    for (i = 0; i < nvqs; i++) {
        VirtQueue *vq = virtio_get_queue(s->vdev, i);
        //将eventfd 纳入 aio_ctx 框架中，用于监听该描述符，并且
        //调用相关的handler
        virtio_queue_aio_set_host_notifier_handler(vq, s->ctx,
                virtio_blk_data_plane_handle_output);
    }
    aio_context_release(s->ctx);
    return 0;

  fail_guest_notifiers:
    vblk->dataplane_disabled = true;
    s->starting = false;
    vblk->dataplane_started = true;
    return -ENOSYS;
}
```

我们思考下，为什么要这么做？

主要是因为, 处理io的线程(main) 和 driver notification trap QEMU 的线程
(VCPU) 是不同的线程，所以流程大概如下:
* guest driver write pci NOTIFICATION address trap EL2
* kvm return qemu thread (QEMU VCPU)
* VCPU write eventfd, notify main_loop thread
* main_loop thread poll this event, call handler

我们这里分两个流程看下
* virtio_bus_set_host_notifier (pci NOTIFICATION address callback)
* virtio_queue_aio_set_host_notifier_handler (eventfd callback)

### virtio_bus_set_host_notifier  
```cpp

/*
 * This function switches ioeventfd on/off in the device.
 * The caller must set or clear the handlers for the EventNotifier.
 */
int virtio_bus_set_host_notifier(VirtioBusState *bus, int n, bool assign)
{
    VirtIODevice *vdev = virtio_bus_get_device(bus);
    VirtioBusClass *k = VIRTIO_BUS_GET_CLASS(bus);
    DeviceState *proxy = DEVICE(BUS(bus)->parent);
    VirtQueue *vq = virtio_get_queue(vdev, n);
    EventNotifier *notifier = virtio_queue_get_host_notifier(vq);
    int r = 0;

    if (!k->ioeventfd_assign) {
        return -ENOSYS;
    }
    //如果assign为true，则绑定，如果为false则取消绑定
    if (assign) {
        //init event notifier, 千面分析过，这里不再展开
        //大概流程是，能用eventfd就用eventfd， 不能用的话，
        //则使用 pipe
        r = event_notifier_init(notifier, 1);
        if (r < 0) {
            error_report("%s: unable to init event notifier: %s (%d)",
                         __func__, strerror(-r), r);
            return r;
        }
        /*
         * 将该eventfd绑定 pci address
         *
         * NOTE： 这里我们只看 virtio pci device代码（还有
         * 另外一种类型的device : mmio, 这种device type 专门为
         * 虚拟化设计)
         *
         * 函数指针为: virtio_pci_ioeventfd_assign
         */
        r = k->ioeventfd_assign(proxy, notifier, n, true);
        if (r < 0) {
            error_report("%s: unable to assign ioeventfd: %d", __func__, r);
            virtio_bus_cleanup_host_notifier(bus, n);
        }
    } else {
        k->ioeventfd_assign(proxy, notifier, n, false);
    }

    if (r == 0) {
        virtio_queue_set_host_notifier_enabled(vq, assign);
    }

    return r;
}
```
#### virtio_pci_ioeventfd_assign
```cpp
static int virtio_pci_ioeventfd_assign(DeviceState *d, EventNotifier *notifier,
                                       int n, bool assign)
{
    VirtIOPCIProxy *proxy = to_virtio_pci_proxy(d);
    VirtIODevice *vdev = virtio_bus_get_device(&proxy->bus);
    VirtQueue *vq = virtio_get_queue(vdev, n);
    bool legacy = virtio_pci_legacy(proxy);
    bool modern = virtio_pci_modern(proxy);
    bool fast_mmio = kvm_ioeventfd_any_length_enabled();
    bool modern_pio = proxy->flags & VIRTIO_PCI_FLAG_MODERN_PIO_NOTIFY;
    // notify cap的memory region
    MemoryRegion *modern_mr = &proxy->notify.mr;
    //这个不太清楚
    MemoryRegion *modern_notify_mr = &proxy->notify_pio.mr;
    MemoryRegion *legacy_mr = &proxy->bar;
    /*
     * 在virtio spec中有描述，该部分和 PCI NOTIFACTION  cap
     * 相关。
     *
     * 计算某个队列的notifcation address公式为:
     * cap.offset + queue_notify_off * notify_off_multiplier
     *
     * 其中:
     * queue_notify_off 表示 virtqueue_idx
     * notify_off_multiplier 是一个乘积，两者均在 cap中有字段描述，
     * 这里不再赘述
     */
    hwaddr modern_addr = virtio_pci_queue_mem_mult(proxy) *
                         virtio_get_queue_index(vq);
    hwaddr legacy_addr = VIRTIO_PCI_QUEUE_NOTIFY;

    if (assign) {
        if (modern) {
            //这两个分支只是 size参数不同，这里先不了解其差异
            if (fast_mmio) {
                memory_region_add_eventfd(modern_mr, modern_addr, 0,
                                          false, n, notifier);
            } else {
                memory_region_add_eventfd(modern_mr, modern_addr, 2,
                                          false, n, notifier);
            }
            if (modern_pio) {
                memory_region_add_eventfd(modern_notify_mr, 0, 2,
                                              true, n, notifier);
            }
        }
        if (legacy) {
            memory_region_add_eventfd(legacy_mr, legacy_addr, 2,
                                      true, n, notifier);
        }
    } else {
        if (modern) {
            if (fast_mmio) {
                memory_region_del_eventfd(modern_mr, modern_addr, 0,
                                          false, n, notifier);
            } else {
                memory_region_del_eventfd(modern_mr, modern_addr, 2,
                                          false, n, notifier);
            }
            if (modern_pio) {
                memory_region_del_eventfd(modern_notify_mr, 0, 2,
                                          true, n, notifier);
            }
        }
        if (legacy) {
            memory_region_del_eventfd(legacy_mr, legacy_addr, 2,
                                      true, n, notifier);
        }
    }
    return 0;
}
```

####  memory_region_add_eventfd
```cpp
void memory_region_add_eventfd(MemoryRegion *mr,
                               hwaddr addr,
                               unsigned size,
                               bool match_data,
                               uint64_t data,
                               EventNotifier *e)
{
    //将memory region 中的某个地址和 eventfd绑定
    MemoryRegionIoeventfd mrfd = {
        .addr.start = int128_make64(addr),
        .addr.size = int128_make64(size),
        .match_data = match_data,
        .data = data,
        .e = e,
    };
    unsigned i;

    if (kvm_enabled() && (!(kvm_eventfds_enabled() ||
                            userspace_eventfd_warning))) {
        userspace_eventfd_warning = true;
        error_report("Using eventfd without MMIO binding in KVM. "
                     "Suboptimal performance expected");
    }

    if (size) {
        adjust_endianness(mr, &mrfd.data, size_memop(size) | MO_TE);
    }
    memory_region_transaction_begin();
    /* 
     * MemoryRegionIoeventfd  compare, 类似于java的object compare
     * 会对比 ->addr.start, ->addr.size, a->match_data , a->data, a->e
     * 等成员这里不再展开
     */
    for (i = 0; i < mr->ioeventfd_nb; ++i) {
        if (memory_region_ioeventfd_before(&mrfd, &mr->ioeventfds[i])) {
            break;
        }
    }
    /*
     * 一个memory region 可能有多个eventfd
     * mr->eventfds是一个数组，扩充，
     * 因为刚刚有个比较的操作，所以需要将该成员插入到何时的位置，即
     * idx = i 的位置（可以看上面退出的条件)
     */
    ++mr->ioeventfd_nb;
    mr->ioeventfds = g_realloc(mr->ioeventfds,
                                  sizeof(*mr->ioeventfds) * mr->ioeventfd_nb);
    //将i位置之后的fds移走
    memmove(&mr->ioeventfds[i+1], &mr->ioeventfds[i],
            sizeof(*mr->ioeventfds) * (mr->ioeventfd_nb-1 - i));
    mr->ioeventfds[i] = mrfd;
    ioeventfd_update_pending |= mr->enabled;
    memory_region_transaction_commit();
}
```

> NOTE
>
> 关于 pci mmio write 的部分流程，这里暂不展开。

### virtio_queue_aio_set_host_notifier_handler
```cpp
void virtio_queue_aio_set_host_notifier_handler(VirtQueue *vq, AioContext *ctx,
                                                VirtIOHandleAIOOutput handle_output)
{
    //virtio_blk_data_plane_handle_output
    if (handle_output) {
        vq->handle_aio_output = handle_output;
        aio_set_event_notifier(ctx, &vq->host_notifier, true,
                               virtio_queue_host_notifier_aio_read,
                               virtio_queue_host_notifier_aio_poll);
        aio_set_event_notifier_poll(ctx, &vq->host_notifier,
                                    virtio_queue_host_notifier_aio_poll_begin,
                                    virtio_queue_host_notifier_aio_poll_end);
    } else {
        aio_set_event_notifier(ctx, &vq->host_notifier, true, NULL, NULL);
        /* Test and clear notifier before after disabling event,
         * in case poll callback didn't have time to run. */
        virtio_queue_host_notifier_aio_read(&vq->host_notifier);
        vq->handle_aio_output = NULL;
    }
}
void aio_set_event_notifier(AioContext *ctx,
                            EventNotifier *notifier,
                            bool is_external,
                            EventNotifierHandler *io_read,
                            AioPollFn *io_poll)
{
    aio_set_fd_handler(ctx, event_notifier_get_fd(notifier), is_external,
                       (IOHandler *)io_read, NULL, io_poll, notifier);
}
```
####  aio_set_fd_handler
```cpp
void aio_set_fd_handler(AioContext *ctx,
                        int fd,
                        bool is_external,
                        IOHandler *io_read,
                        IOHandler *io_write,
                        AioPollFn *io_poll,
                        void *opaque)
{
    AioHandler *node;
    AioHandler *new_node = NULL;
    bool is_new = false;
    bool deleted = false;
    int poll_disable_change;

    qemu_lockcnt_lock(&ctx->list_lock);
    //找到 AioHandler（看看ctx->aio_handlers 链表中
    //是否有相同fd的AioHandler)
    node = find_aio_handler(ctx, fd);

    /* Are we deleting the fd handler? */
    if (!io_read && !io_write && !io_poll) {
        if (node == NULL) {
            qemu_lockcnt_unlock(&ctx->list_lock);
            return;
        }
        /* Clean events in order to unregister fd from the ctx epoll. */
        node->pfd.events = 0;

        poll_disable_change = -!node->io_poll;
    } else {
        poll_disable_change = !io_poll - (node && !node->io_poll);
        if (node == NULL) {
            is_new = true;
        }
        /* Alloc and insert if it's not already there */
        new_node = g_new0(AioHandler, 1);

        /* Update handler with latest information */
        //设置各个回调
        new_node->io_read = io_read;
        new_node->io_write = io_write;
        new_node->io_poll = io_poll;
        new_node->opaque = opaque;
        new_node->is_external = is_external;
        /*
         * 这个地方个人感觉没有什么必要, 这里会把
         * node->pdf.events copy到new_node中，但是
         * g_main_context_query 中会做相同fd的事件
         * 合并
         */
        if (is_new) {
            new_node->pfd.fd = fd;
        } else {
            new_node->pfd = node->pfd;
        }
        //将 new_node->pfd 假如ctx 的 gsource中
        g_source_add_poll(&ctx->source, &new_node->pfd);

        new_node->pfd.events = (io_read ? G_IO_IN | G_IO_HUP | G_IO_ERR : 0);
        new_node->pfd.events |= (io_write ? G_IO_OUT | G_IO_ERR : 0);
        //将node 链入 aio_handlers
        QLIST_INSERT_HEAD_RCU(&ctx->aio_handlers, new_node, node);
    }
    if (node) {
        deleted = aio_remove_fd_handler(ctx, node);
    }

    /* No need to order poll_disable_cnt writes against other updates;
     * the counter is only used to avoid wasting time and latency on
     * iterated polling when the system call will be ultimately necessary.
     * Changing handlers is a rare event, and a little wasted polling until
     * the aio_notify below is not an issue.
     */
    //这里没看懂，先略过
    atomic_set(&ctx->poll_disable_cnt,
               atomic_read(&ctx->poll_disable_cnt) + poll_disable_change);

    if (new_node) {
        aio_epoll_update(ctx, new_node, is_new);
    } else if (node) {
        /* Unregister deleted fd_handler */
        aio_epoll_update(ctx, node, false);
    }
    qemu_lockcnt_unlock(&ctx->list_lock);
    aio_notify(ctx);

    if (deleted) {
        g_free(node);
    }
}
```

将fd加入gsource后，在aio_ctx_dispatch中回调用到node中的回调

#### virtio_queue_host_notifier_aio_read
```cpp
static void virtio_queue_host_notifier_aio_read(EventNotifier *n)
{
    VirtQueue *vq = container_of(n, VirtQueue, host_notifier);
    //先去read eventfd
    if (event_notifier_test_and_clear(n)) {
        virtio_queue_notify_aio_vq(vq);
    }
}

static bool virtio_queue_notify_aio_vq(VirtQueue *vq)
{
    bool ret = false;

    if (vq->vring.desc && vq->handle_aio_output) {
        VirtIODevice *vdev = vq->vdev;

        trace_virtio_queue_notify(vdev, vq - vdev->vq, vq);
        //调用handle_aio_output, 该流程为virtio_blk_data_plane_handle_output
        ret = vq->handle_aio_output(vdev, vq);

        if (unlikely(vdev->start_on_kick)) {
            virtio_set_started(vdev, true);
        }
    }

    return ret;
}
```
#### virtio_blk_data_plane_handle_output
```cpp
static bool virtio_blk_data_plane_handle_output(VirtIODevice *vdev,
                                                VirtQueue *vq)
{
    VirtIOBlock *s = (VirtIOBlock *)vdev;

    assert(s->dataplane);
    assert(s->dataplane_started);

    return virtio_blk_handle_vq(s, vq);
}
```
下面的流程不再展开，实际上在处理 vq avail vring 中的请求
