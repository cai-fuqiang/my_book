# func
## submit_requests
```cpp
static inline void submit_requests(BlockBackend *blk, MultiReqBuffer *mrb,
                                   int start, int num_reqs, int niov)
{
    QEMUIOVector *qiov = &mrb->reqs[start]->qiov;
    int64_t sector_num = mrb->reqs[start]->sector_num;
    bool is_write = mrb->is_write;

    if (num_reqs > 1) {
        int i;
        struct iovec *tmp_iov = qiov->iov;
        int tmp_niov = qiov->niov;

        /* mrb->reqs[start]->qiov was initialized from external so we can't
         * modify it here. We need to initialize it locally and then add the
         * external iovecs. */
        qemu_iovec_init(qiov, niov);

        for (i = 0; i < tmp_niov; i++) {
            qemu_iovec_add(qiov, tmp_iov[i].iov_base, tmp_iov[i].iov_len);
        }

        for (i = start + 1; i < start + num_reqs; i++) {
            qemu_iovec_concat(qiov, &mrb->reqs[i]->qiov, 0,
                              mrb->reqs[i]->qiov.size);
            mrb->reqs[i - 1]->mr_next = mrb->reqs[i];
        }

        trace_virtio_blk_submit_multireq(VIRTIO_DEVICE(mrb->reqs[start]->dev),
                                         mrb, start, num_reqs,
                                         sector_num << BDRV_SECTOR_BITS,
                                         qiov->size, is_write);
        block_acct_merge_done(blk_get_stats(blk),
                              is_write ? BLOCK_ACCT_WRITE : BLOCK_ACCT_READ,
                              num_reqs - 1);
    }
    //如果是写走第一个流程，我们只分析这个
    //virtio_blk_rw_complete 在 io已经完成时候，执行
    if (is_write) {
        blk_aio_pwritev(blk, sector_num << BDRV_SECTOR_BITS, qiov, 0,
                        virtio_blk_rw_complete, mrb->reqs[start]);
    } else {
        blk_aio_preadv(blk, sector_num << BDRV_SECTOR_BITS, qiov, 0,
                       virtio_blk_rw_complete, mrb->reqs[start]);
    }
}
```
### blk_aio_pwritev
```cpp
BlockAIOCB *blk_aio_pwritev(BlockBackend *blk, int64_t offset,
                            QEMUIOVector *qiov, BdrvRequestFlags flags,
                            BlockCompletionFunc *cb, void *opaque)
{
    return blk_aio_prwv(blk, offset, qiov->size, qiov,
                        blk_aio_write_entry, flags, cb, opaque);
}
```
### blk_aio_prwv
```cpp
static BlockAIOCB *blk_aio_prwv(BlockBackend *blk, int64_t offset, int bytes,
                                void *iobuf, CoroutineEntry co_entry,
                                BdrvRequestFlags flags,
                                BlockCompletionFunc *cb, void *opaque)
{
    BlkAioEmAIOCB *acb;
    Coroutine *co;

    blk_inc_in_flight(blk);
    acb = blk_aio_get(&blk_aio_em_aiocb_info, blk, cb, opaque);
    acb->rwco = (BlkRwCo) {
        .blk    = blk,
        .offset = offset,
        .iobuf  = iobuf,
        .flags  = flags,
        .ret    = NOT_DONE,
    };
    acb->bytes = bytes;
    acb->has_returned = false;
    //创建协程 co entry为: blk_aio_write_entry
    co = qemu_coroutine_create(co_entry, acb);
    //进入协程
    bdrv_coroutine_enter(blk_bs(blk), co);

    acb->has_returned = true;
    if (acb->rwco.ret != NOT_DONE) {
        replay_bh_schedule_oneshot_event(blk_get_aio_context(blk),
                                         blk_aio_complete_bh, acb);
    }

    return &acb->common;
}

void bdrv_coroutine_enter(BlockDriverState *bs, Coroutine *co)
{
    aio_co_enter(bdrv_get_aio_context(bs), co);
}

AioContext *bdrv_get_aio_context(BlockDriverState *bs)
{
    return bs ? bs->aio_context : qemu_get_aio_context();
}
```

##  blk_aio_write_entry
```cpp
static void blk_aio_write_entry(void *opaque)
{
    BlkAioEmAIOCB *acb = opaque;
    BlkRwCo *rwco = &acb->rwco;
    QEMUIOVector *qiov = rwco->iobuf;

    if (rwco->blk->quiesce_counter) {
        blk_dec_in_flight(rwco->blk);
        blk_wait_while_drained(rwco->blk);
        blk_inc_in_flight(rwco->blk);
    }

    assert(!qiov || qiov->size == acb->bytes);
    rwco->ret = blk_co_pwritev(rwco->blk, rwco->offset, acb->bytes,
                               qiov, rwco->flags);
    //表明io已经完成
    blk_aio_complete(acb);
}

static void blk_aio_complete(BlkAioEmAIOCB *acb)
{
    if (acb->has_returned) {
        //调用callbak, virtio_blk_rw_complete
        acb->common.cb(acb->common.opaque, acb->rwco.ret);
        blk_dec_in_flight(acb->rwco.blk);
        qemu_aio_unref(acb);
    }
}
```

## blk_co_pwritev
代码较多，不过多展开，大概堆栈为:
```
blk_co_pwritev
  blk_co_pwritev_part
    bdrv_co_pwritev_part
      bdrv_aligned_pwritev
        bdrv_driver_pwritev
          drv->bdrv_co_pwritev
```

## BlockDriver
```cpp
static BlockDriver bdrv_host_device = {
    .format_name        = "host_device",
    .protocol_name        = "host_device",
    ...
    .bdrv_co_pwritev        = raw_co_pwritev,
    ...
};

BlockDriver bdrv_file = {
    .format_name = "file",
    .protocol_name = "file",
    ...
    .bdrv_co_pwritev        = raw_co_pwritev,
    ...
};
```
无论是 host_device driver, 还是file driver，`bdrv_co_pwritev`
回调都是`raw_co_pwritev`.我们来看下其实现:

## raw_co_pwritev
```cpp
static int coroutine_fn raw_co_pwritev(BlockDriverState *bs, uint64_t offset,
                                       uint64_t bytes, QEMUIOVector *qiov,
                                       int flags)
{
    assert(flags == 0);
    return raw_co_prw(bs, offset, bytes, qiov, QEMU_AIO_WRITE);
}
```
### raw_co_prw
```cpp
static int coroutine_fn raw_co_prw(BlockDriverState *bs, uint64_t offset,
                                   uint64_t bytes, QEMUIOVector *qiov, int type)
{
    BDRVRawState *s = bs->opaque;
    RawPosixAIOData acb;

    if (fd_open(bs) < 0)
        return -EIO;

    /*
     * Check if the underlying device requires requests to be aligned,
     * and if the request we are trying to submit is aligned or not.
     * If this is the case tell the low-level driver that it needs
     * to copy the buffer.
     */
    /* 这里有两个分支:
     * 1. 使用 libaio 提交aio请求。使用 eventfd
     * 监听, 然后该协程退出调度。等IO完成后，在主事件
     * 循环中唤醒协程
     * 2. 不使用 libaio，那这样只能使用同步io了，
     * 同步io 的系统调用可能会造成协程阻塞，所以
     * 需要启一个线程，来完成同步io，io完成后，
     * 唤醒协程
     *
     * 所以这里需要保证的是： IO请求的下发，不能
     * 阻塞协程，因为协程是在某个线程中运行，如果
     * 协程不主动退出调度，其他协程不会运行。
     */
    if (s->needs_alignment) {
        if (!bdrv_qiov_is_aligned(bs, qiov)) {
            type |= QEMU_AIO_MISALIGNED;
#ifdef CONFIG_LINUX_AIO
        } else if (s->use_linux_aio) {
            LinuxAioState *aio = aio_get_linux_aio(bdrv_get_aio_context(bs));
            assert(qiov->size == bytes);
            return laio_co_submit(bs, aio, s->fd, offset, qiov, type);
#endif
        }
    }

    acb = (RawPosixAIOData) {
        .bs             = bs,
        .aio_fildes     = s->fd,
        .aio_type       = type,
        .aio_offset     = offset,
        .aio_nbytes     = bytes,
        .io             = {
            .iov            = qiov->iov,
            .niov           = qiov->niov,
        },
    };

    assert(qiov->size == bytes);
    return raw_thread_pool_submit(bs, handle_aiocb_rw, &acb);
}
```

## AIO
在了解aio之前，我们需要了解一些libaio的api:

### laio_co_submit
```cpp

int coroutine_fn laio_co_submit(BlockDriverState *bs, LinuxAioState *s, int fd,
                                uint64_t offset, QEMUIOVector *qiov, int type)
{
    int ret;
    struct qemu_laiocb laiocb = {
        .co         = qemu_coroutine_self(),
        .nbytes     = qiov->size,
        .ctx        = s,
        .ret        = -EINPROGRESS,
        .is_read    = (type == QEMU_AIO_READ),
        .qiov       = qiov,
    };

    ret = laio_do_submit(fd, &laiocb, offset, type);
    if (ret < 0) {
        return ret;
    }
    /* 一般情况下，这里不会改, 还是 上面静态定义中的值，表示
     * 该io已经入队，等待异步处理。
     * 
     * 在kernel 中, 一般各个文件系统的处理函数会在异步io中返回
     * 该值，但是io_submit返回值表示已经处理了多少个io请求, 所以
     * 这里可以认为，如果没有任何io返回，则返回值为-EINPROGRESS
     *
     * 这时该协程会退出调度，等待wakeup
     */
    if (laiocb.ret == -EINPROGRESS) {
        qemu_coroutine_yield();
    }
    return laiocb.ret;
}
```
### laio_do_submit
```cpp
static int laio_do_submit(int fd, struct qemu_laiocb *laiocb, off_t offset,
                          int type)
{
    LinuxAioState *s = laiocb->ctx;
    struct iocb *iocbs = &laiocb->iocb;
    QEMUIOVector *qiov = laiocb->qiov;

    switch (type) {
    case QEMU_AIO_WRITE:
        io_prep_pwritev(iocbs, fd, qiov->iov, qiov->niov, offset);
        break;
    case QEMU_AIO_READ:
        io_prep_preadv(iocbs, fd, qiov->iov, qiov->niov, offset);
        break;
    /* Currently Linux kernel does not support other operations */
    default:
        fprintf(stderr, "%s: invalid AIO request type 0x%x.\n",
                        __func__, type);
        return -EIO;
    }
    //该接口为libaio接口，将 s->e (eventfd)和aio请求进行绑定
    io_set_eventfd(&laiocb->iocb, event_notifier_get_fd(&s->e));
    //加入到pending 队列
    QSIMPLEQ_INSERT_TAIL(&s->io_q.pending, laiocb, next);
    //这里 in_queue 表示的队列就是 s->io_q.pending
    s->io_q.in_queue++;
    /*
     * s->io_q.plugged: 表示该队列有io在处理
     * s->io_q.in_queue: 已经加入到pending队列但是没有io_submit
     * s->io_q.in_flight: 已经io_submit, 但是io还没有complete
     *
     * 在 laio_io_plug()会自增 s->io_q.plugged
     * 在 laio_io_unplug() 会自减，并且如果有pending,则调用 ioq_submit
     */
    /*
     * MAX_EVENTS为io_setup是传入的参数，kernel注释中描述为可以接受的
     * 最低的events 数量，但是这里将其作为event数量的上限
     */
    /* commit 5e1b34a3fa0a0fbf46628aab10cc49f6f855520e
     * Author: Roman Pen <roman.penyaev@profitbricks.com>
     * Date:   Wed Jul 13 15:03:24 2016 +0200
     *
     *    linux-aio: prevent submitting more than MAX_EVENTS
     *
     * commit 43f2376e096382df44d9322ae0cbdca89612d464
     * Author: Paolo Bonzini <pbonzini@redhat.com>
     * Date:   Thu Dec 11 14:52:27 2014 +0100
     * 
     *     linux-aio: track whether the queue is blocked
     */

    if (!s->io_q.blocked &&
        (!s->io_q.plugged ||
         s->io_q.in_flight + s->io_q.in_queue >= MAX_EVENTS)) {
        ioq_submit(s);
    }

    return 0;
}
```
# TMP
## laio_io_unplug
```cpp
void laio_io_unplug(BlockDriverState *bs, LinuxAioState *s)
{
    assert(s->io_q.plugged);
    //plugged减少为0
    //并且 io_q.blocked 为0, io_q.pending 不是空
    if (--s->io_q.plugged == 0 &&
        !s->io_q.blocked && !QSIMPLEQ_EMPTY(&s->io_q.pending)) {
        ioq_submit(s);
    }
}
```

# commit
```
commit 28b240877bbcdc8add61be227f429b536edd4653
Author: Paolo Bonzini <pbonzini@redhat.com>
Date:   Thu Dec 11 14:52:26 2014 +0100

    linux-aio: queue requests that cannot be submitted


commit 1b3abdcccf18d98c3952b41be0bc1db3ef6009dd
Author: Ming Lei <ming.lei@canonical.com>
Date:   Fri Jul 4 18:04:34 2014 +0800

    linux-aio: implement io plug, unplug and flush io queue

```
