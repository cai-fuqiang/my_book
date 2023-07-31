# API -- syscall
```cpp
/* sys_io_setup:
 *      Create an aio_context capable of receiving at least nr_events.
 *      ctxp must not point to an aio_context that already exists, and
 *      must be initialized to 0 prior to the call.  On successful
 *      creation of the aio_context, *ctxp is filled in with the resulting
 *      handle.  May fail with -EINVAL if *ctxp is not initialized,
 *      if the specified nr_events exceeds internal limits.  May fail
 *      with -EAGAIN if the specified nr_events exceeds the user's limit
 *      of available events.  May fail with -ENOMEM if insufficient kernel
 *      resources are available.  May fail with -EFAULT if an invalid
 *      pointer is passed for ctxp.  Will fail with -ENOSYS if not
 *      implemented.
 */
/*
 * 创建一个具有能够接收至少 `nr_events`能力的 aio_context。 ctxp 必须不能
 * 指向一个已经存在的 aio_context，并且必须在调用之前初始化为0. 在创建aio_context
 * 成功后，使用生成的句柄填充 *ctxp。可能有以下几种失败的情况:
 *   -EINVAL: 指定的 nr_events 超过了 internal limits
 *   -EAGAIN: nr_events 超过了 user's limit 或者 available events
 *   -ENOMEM: 内核资源不足
 *   -EFAULT: ctxp的指针是非法的
 *   -ENOSYS: 该功能没有实现
 *
 * NOTE: 查看原来的patch, 感觉nr_events 应该是规定了一个上限，events的数量
 * 不能够超过 nr_events - 1, 包括现在的代码逻辑中还存在着 nr_events - 1 的代码
 * 逻辑.
 */
SYSCALL_DEFINE2(io_setup, unsigned, nr_events, aio_context_t __user *, ctxp)
/* sys_io_submit:
 *      Queue the nr iocbs pointed to by iocbpp for processing.  Returns
 *      the number of iocbs queued.  May return -EINVAL if the aio_context
 *      specified by ctx_id is invalid, if nr is < 0, if the iocb at
 *      *iocbpp[0] is not properly initialized, if the operation specified
 *      is invalid for the file descriptor in the iocb.  May fail with
 *      -EFAULT if any of the data structures point to invalid data.  May
 *      fail with -EBADF if the file descriptor specified in the first
 *      iocb is invalid.  May fail with -EAGAIN if insufficient resources
 *      are available to queue any iocbs.  Will return 0 if nr is 0.  Will
 *      fail with -ENOSYS if not implemented.
 */
 /* 将由 iocbpp 指向的 nr个 iocbs进行排队处理。可能有以下几种失败的情况:
  *  -EINVAL: 
  *    1. 由 ctx_id 指定的 aio_context 是非法的
  *    2. nr < 0
  *    3. iocbpp[0] 处的 iocb 没有被正确的初始化
  *    4. iocb中指定的文件描述符是非法的
  *  -EFAULT: 任何的数据结构指针指向了非法的数据
  *  -EBADF: 第一个iocb中的文件描述符是非法的
  *  -EAGAIN: queue 任意的iocbs时，资源不足
  *  -ENOSYS: 没有实现
  *  0: nr = 0
  */
SYSCALL_DEFINE3(io_submit, aio_context_t, ctx_id, long, nr,
                struct iocb __user * __user *, iocbpp)
/* sys_io_cancel:
 *      Attempts to cancel an iocb previously passed to io_submit.  If
 *      the operation is successfully cancelled, the resulting event is
 *      copied into the memory pointed to by result without being placed
 *      into the completion queue and 0 is returned.  May fail with
 *      -EFAULT if any of the data structures pointed to are invalid.
 *      May fail with -EINVAL if aio_context specified by ctx_id is
 *      invalid.  May fail with -EAGAIN if the iocb specified was not
 *      cancelled.  Will fail with -ENOSYS if not implemented.
 */
/*
 * 尝试取消之前 io_submit 提交的 iocb。如果操作已经成功取消, 则生成的事件将被复制到
 * 结果所指向的内存中，而不会被放入完成队列中，并返回0。
 */
SYSCALL_DEFINE3(io_cancel, aio_context_t, ctx_id, struct iocb __user *, iocb,
                struct io_event __user *, result)
/* io_getevents:
 *      Attempts to read at least min_nr events and up to nr events from
 *      the completion queue for the aio_context specified by ctx_id. If
 *      it succeeds, the number of read events is returned. May fail with
 *      -EINVAL if ctx_id is invalid, if min_nr is out of range, if nr is
 *      out of range, if timeout is out of range.  May fail with -EFAULT
 *      if any of the memory specified is invalid.  May return 0 or
 *      < min_nr if the timeout specified by timeout has elapsed
 *      before sufficient events are available, where timeout == NULL
 *      specifies an infinite timeout. Note that the timeout pointed to by
 *      timeout is relative.  Will fail with -ENOSYS if not implemented.
 */
/*
 * 尝试从 ctx_id 指定的 aio_context 的完成队列中 读取 至少 min_nr个事件, 
 * 最多 nr 个event, 如果成功，返回 读取事件的数量
 */
SYSCALL_DEFINE5(io_getevents, aio_context_t, ctx_id,
                long, min_nr,
                long, nr,
                struct io_event __user *, events,
                struct timespec __user *, timeout)
SYSCALL_DEFINE6(io_pgetevents,
                aio_context_t, ctx_id,
                long, min_nr,
                long, nr,
                struct io_event __user *, events,
                struct timespec __user *, timeout,
                const struct __aio_sigset __user *, usig)
/* sys_io_destroy:
 *      Destroy the aio_context specified.  May cancel any outstanding
 *      AIOs and block on completion.  Will fail with -ENOSYS if not
 *      implemented.  May fail with -EINVAL if the context pointed to
 *      is invalid.
 */
/* 销毁指定的 aio_context。会取消任何 outstanding AIOs 并且 block completion(?)
 *
 */
SYSCALL_DEFINE1(io_destroy, aio_context_t, ctx)
```

# struct
## uapi
### struct iocb
```cpp
/*
 * we always use a 64bit off_t when communicating
 * with userland.  its up to libraries to do the
 * proper padding and aio_error abstraction
 */

struct iocb {
        /* these are internal to the kernel/libc. */
        __u64   aio_data;       /* data to be returned in event's data */

#if defined(__BYTE_ORDER) ? __BYTE_ORDER == __LITTLE_ENDIAN : defined(__LITTLE_ENDIAN)
        __u32   aio_key;        /* the kernel sets aio_key to the req # */
        __kernel_rwf_t aio_rw_flags;    /* RWF_* flags */
#elif defined(__BYTE_ORDER) ? __BYTE_ORDER == __BIG_ENDIAN : defined(__BIG_ENDIAN)
        __kernel_rwf_t aio_rw_flags;    /* RWF_* flags */
        __u32   aio_key;        /* the kernel sets aio_key to the req # */
#else
#error edit for your odd byteorder.
#endif

        /* common fields */
        __u16   aio_lio_opcode; /* see IOCB_CMD_ above */
        __s16   aio_reqprio;
        __u32   aio_fildes;

        __u64   aio_buf;
        __u64   aio_nbytes;
        __s64   aio_offset;

        /* extra parameters */
        __u64   aio_reserved2;  /* TODO: use this for a (struct sigevent *) */

        /* flags for the "struct iocb" */
        __u32   aio_flags;

        /*
        ¦* if the IOCB_FLAG_RESFD flag of "aio_flags" is set, this is an
        ¦* eventfd to signal AIO readiness to
        ¦*/
        /*
         * 当设置 (aio_flags & IOCB_FLAG_RESFD) = true, 
         * 该字段表示 该aio 关联的eventfd, 详见 `libaio: io_set_eventfd()`
         * 会在aio__complete流程中，eventfd_signal() 该 eventfd
         */
        __u32   aio_resfd;
}; /* 64 bytes */
```
## kernel struct
### struct kioctx
```cpp
struct kioctx {
        struct percpu_ref       users;
        atomic_t                dead;

        struct percpu_ref       reqs;

        unsigned long           user_id;
        /*
         * per cpu变量可以 减少catch line 的冲突
         */
        struct __percpu kioctx_cpu *cpu;

        /*
        ¦* For percpu reqs_available, number of slots we move to/from global
        ¦* counter at a time:
        ¦*/
        /*
         * 对于percpu reqs_available, 我们一次从 global counter 中 move to/from
         * 的slot 数量
         *
         * 这里是配合上面使用的, 可以控制修改全局 reqs_available 频率
         */
        unsigned                req_batch;
        /*
        ¦* This is what userspace passed to io_setup(), it's not used for
        ¦* anything but counting against the global max_reqs quota.
        ¦*
        ¦* The real limit is nr_events - 1, which will be larger (see
        ¦* aio_setup_ring())
        ¦*/
        //
        unsigned                max_reqs;

        /* Size of ringbuffer, in units of struct io_event */
        unsigned                nr_events;

        unsigned long           mmap_base;
        unsigned long           mmap_size;
        //指向 ring array
        struct page             **ring_pages;
        long                    nr_pages;

        struct rcu_work         free_rwork;     /* see free_ioctx() */

        /*
        ¦* signals when all in-flight requests are done
        ¦*/
        struct ctx_rq_wait      *rq_wait;

        struct {
                /*
                ¦* This counts the number of available slots in the ringbuffer,
                ¦* so we avoid overflowing it: it's decremented (if positive)
                ¦* when allocating a kiocb and incremented when the resulting
                ¦* io_event is pulled off the ringbuffer.
                ¦*
                ¦* We batch accesses to it with a percpu version.
                 */
                 /*
                  * 该counts 记录了 ringbuffer中可用的 slots的数量，所以我们应该
                  * 避免 溢出:
                  * 当分配 kiocb时会递减，当从ringbuffer中提取到 io_event时，会递增
                  */
                atomic_t        reqs_available;
        } ____cacheline_aligned_in_smp;

        struct {
                spinlock_t      ctx_lock;
                struct list_head active_reqs;   /* used for cancellation */
        } ____cacheline_aligned_in_smp;

        struct {
                struct mutex    ring_lock;
                wait_queue_head_t wait;
        } ____cacheline_aligned_in_smp;

        struct {
                unsigned        tail;
                unsigned        completed_events;
                spinlock_t      completion_lock;
        } ____cacheline_aligned_in_smp;
        //内置的page pointer array
        struct page             *internal_pages[AIO_RING_PAGES];
        /*
         * ring file
         * anon inode file
         * 方便将 ring page mmap 到用户态
         */
        struct file             *aio_ring_file;

        unsigned                id;
};
```
# API details
## io_setup
```cpp
SYSCALL_DEFINE2(io_setup, unsigned, nr_events, aio_context_t __user *, ctxp)
{
        struct kioctx *ioctx = NULL;
        unsigned long ctx;
        long ret;
        //读取该指针
        ret = get_user(ctx, ctxp);
        if (unlikely(ret))
                goto out;

        ret = -EINVAL;
        if (unlikely(ctx || nr_events == 0)) {
                pr_debug("EINVAL: ctx %lu nr_events %u\n",
                         ctx, nr_events);
                goto out;
        }
        // 创建 kioctx
        ioctx = ioctx_alloc(nr_events);
        ret = PTR_ERR(ioctx);
        if (!IS_ERR(ioctx)) {
                //将 ioctx->user_id , 赋值给 ctxp 指针
                ret = put_user(ioctx->user_id, ctxp);
                if (ret)
                        kill_ioctx(current->mm, ioctx, NULL);
                percpu_ref_put(&ioctx->users);
        }

out:
        return ret;
}
```
### ioctx_alloc
```cpp
/* ioctx_alloc
 *      Allocates and initializes an ioctx.  Returns an ERR_PTR if it failed.
 */
static struct kioctx *ioctx_alloc(unsigned nr_events)
{
        struct mm_struct *mm = current->mm;
        struct kioctx *ctx;
        int err = -ENOMEM;

        /*
        ¦* Store the original nr_events -- what userspace passed to io_setup(),
        ¦* for counting against the global limit -- before it changes.
        ¦*/
        //注释中提到，这个保存着原始的 nr_events -- 由用户态传递给 iosetup的
        unsigned int max_reqs = nr_events;

        /*
        ¦* We keep track of the number of available ringbuffer slots, to prevent
        ¦* overflow (reqs_available), and we also use percpu counters for this.
        ¦*
        ¦* So since up to half the slots might be on other cpu's percpu counters
        ¦* and unavailable, double nr_events so userspace sees what they
        ¦* expected: additionally, we move req_batch slots to/from percpu
        ¦* counters at a time, so make sure that isn't 0:
        ¦*/
        /* 我这里我个人感觉可能实现的有问题:
         * 最差的情况是每个cpu拿一个:一共拿了多少个到 per cpu呢:  num_possible_cpus()
         * ctx->nr_events 为补偿后的nr_events数量
         *
         * ctx->req_batch * (num_possible_cpus)
         *   = ((ctx->nr_events - 1) / ((num_possible_cpus() * 4))  * num_possible_cpus()
         *   = (ctx->nr_events -1 ) / 4
         *
         * 用户这边期望看到剩余的io_events数量为:
         * nr_events  - num_possible_cpus()
         *
         * 那现在剩余的:
         * ctx->nr_events - (ctx->nr_event - 1) / 4
         *
         * 在 nr_events 远大于 num_possible_cpus()，应该怎么补偿呢?
         * 期望剩余 = 现在剩余:
         * 那么可以得出:
         *  nr_events - num_possible_cpus() = ctx->nr_events - (ctx->nr_events - 1) /4
         *  nr_events = ctx->nr_events - ctx->nr_events / 4
         *  nr_events = 3/4(ctx->nr_events)
         *
         * 当 nr_events 最小的时候呢? = num_possible_cpus() * 4
         *
         * nr_events - num_possible_cpus() = ctx->nr_events - (ctx->nr_event - 1) /4
         * nr_events - nr_events / 4 = ctx->nr_events - ctx->nr_events / 4
         * nr_events = ctx->nr_events
         *
         * 所以在最差的情况下:
         * 将ctx->nr_events = 4/3 * nr_events 即可
         */
        nr_events = max(nr_events, num_possible_cpus() * 4);
        nr_events *= 2;

        /* Prevent overflows */
        if (nr_events > (0x10000000U / sizeof(struct io_event))) {
                pr_debug("ENOMEM: nr_events too high\n");
                return ERR_PTR(-EINVAL);
        }

        if (!nr_events || (unsigned long)max_reqs > aio_max_nr)
                return ERR_PTR(-EAGAIN);

        ctx = kmem_cache_zalloc(kioctx_cachep, GFP_KERNEL);
        if (!ctx)
                return ERR_PTR(-ENOMEM);
        //用户态传递下来的
        ctx->max_reqs = max_reqs;

        spin_lock_init(&ctx->ctx_lock);
        spin_lock_init(&ctx->completion_lock);
        mutex_init(&ctx->ring_lock);
        /* Protect against page migration throughout kiotx setup by keeping
        ¦* the ring_lock mutex held until setup is complete. */
        mutex_lock(&ctx->ring_lock);
        init_waitqueue_head(&ctx->wait);

        INIT_LIST_HEAD(&ctx->active_reqs);
        if (percpu_ref_init(&ctx->users, free_ioctx_users, 0, GFP_KERNEL))
                goto err;

        if (percpu_ref_init(&ctx->reqs, free_ioctx_reqs, 0, GFP_KERNEL))
                goto err;
        //alloc per cpu var
        ctx->cpu = alloc_percpu(struct kioctx_cpu);
        if (!ctx->cpu)
                goto err;
        /* 初始化ring */
        err = aio_setup_ring(ctx, nr_events);
        if (err < 0)
                goto err;
        /*
         * 这个地方设置为 ctx->nr_egvents - 1
         * 最早引入 reqs_available 的patch
         * commit 34e83fc618085e00dc9803286c581f51966673bd
         * Author: Kent Overstreet <koverstreet@google.com>
         * Date:   Fri Apr 26 10:58:39 2013 +1000
         * 
         *     aio: reqs_active -> reqs_available
         *     [Patch 21/26]
         * 这个地方沿用了上面patch的逻辑，感觉像是设置了 能够处理
         * 的events 数量上限, 不能超过 nr_events, 这个和 io_setup
         * 接口参数意义冲突，需要在查阅些资料，不过，现在的实现，
         * 应该满足了这个需求（至少能够处理 nr_events 个请求，是
         * 因为上面的代码逻辑 采用了 nr_events * 2 )
         */
        atomic_set(&ctx->reqs_available, ctx->nr_events - 1);

        //设置req_batch
        ctx->req_batch = (ctx->nr_events - 1) / (num_possible_cpus() * 4);
        //如果 < 1 ,设置为 1
        if (ctx->req_batch < 1)
                ctx->req_batch = 1;

        /* limit the number of system wide aios */
        spin_lock(&aio_nr_lock);
        //全局的 reqs
        if (aio_nr + ctx->max_reqs > aio_max_nr ||
            //这个表示溢出了
            aio_nr + ctx->max_reqs < aio_nr) {
                spin_unlock(&aio_nr_lock);
                err = -EAGAIN;
                goto err_ctx;
        }
        aio_nr += ctx->max_reqs;
        spin_unlock(&aio_nr_lock);

        percpu_ref_get(&ctx->users);    /* io_setup() will drop this ref */
        percpu_ref_get(&ctx->reqs);     /* free_ioctx_users() will drop this */

        err = ioctx_add_table(ctx, mm);
        if (err)
                goto err_cleanup;

        /* Release the ring_lock mutex now that all setup is complete. */
        mutex_unlock(&ctx->ring_lock);

        pr_debug("allocated ioctx %p[%ld]: mm=%p mask=0x%x\n",
                ¦ctx, ctx->user_id, mm, ctx->nr_events);
        return ctx;

err_cleanup:
        aio_nr_sub(ctx->max_reqs);
err_ctx:
        atomic_set(&ctx->dead, 1);
        if (ctx->mmap_size)
                vm_munmap(ctx->mmap_base, ctx->mmap_size);
        aio_free_ring(ctx);
err:
        mutex_unlock(&ctx->ring_lock);
        free_percpu(ctx->cpu);
        percpu_ref_exit(&ctx->reqs);
        percpu_ref_exit(&ctx->users);
        kmem_cache_free(kioctx_cachep, ctx);
        pr_debug("error allocating ioctx %d\n", err);
        return ERR_PTR(err);
}
```
### aio_setup_ring
```cpp
static int aio_setup_ring(struct kioctx *ctx, unsigned int nr_events)
{
        struct aio_ring *ring;
        struct mm_struct *mm = current->mm;
        unsigned long size, unused;
        int nr_pages;
        int i;
        struct file *file;

        /* Compensate for the ring buffer's head/tail overlap entry */
        nr_events += 2; /* 1 is required, 2 for good luck */

        size = sizeof(struct aio_ring);
        size += sizeof(struct io_event) * nr_events;

        nr_pages = PFN_UP(size);
        if (nr_pages < 0)
                return -EINVAL;
        //创建private file
        file = aio_private_file(ctx, nr_pages);
        if (IS_ERR(file)) {
                ctx->aio_ring_file = NULL;
                return -ENOMEM;
        }

        ctx->aio_ring_file = file;
        nr_events = (PAGE_SIZE * nr_pages - sizeof(struct aio_ring))
                        / sizeof(struct io_event);
        //如果 internal_pages够用，就用 internal_pages
        ctx->ring_pages = ctx->internal_pages;
        if (nr_pages > AIO_RING_PAGES) {
                ctx->ring_pages = kcalloc(nr_pages, sizeof(struct page *),
                                        ¦ GFP_KERNEL);
                if (!ctx->ring_pages) {
                        put_aio_ring_file(ctx);
                        return -ENOMEM;
                }
        }
        //填充page pointer array
        for (i = 0; i < nr_pages; i++) {
                struct page *page;
                //find page
                page = find_or_create_page(file->f_mapping,
                                        ¦  i, GFP_HIGHUSER | __GFP_ZERO);
                if (!page)
                        break;
                pr_debug("pid(%d) page[%d]->count=%d\n",
                        ¦current->pid, i, page_count(page));
                SetPageUptodate(page);
                unlock_page(page);

                ctx->ring_pages[i] = page;
        }
        ctx->nr_pages = i;

        if (unlikely(i != nr_pages)) {
                if (unlikely(i != nr_pages)) {
                aio_free_ring(ctx);
                return -ENOMEM;
        }

        ctx->mmap_size = nr_pages * PAGE_SIZE;
        pr_debug("attempting mmap of %lu bytes\n", ctx->mmap_size);

        if (down_write_killable(&mm->mmap_sem)) {
                ctx->mmap_size = 0;
                aio_free_ring(ctx);
                return -EINTR;
        }
        //memory map
        ctx->mmap_base = do_mmap_pgoff(ctx->aio_ring_file, 0, ctx->mmap_size,
                                ¦      PROT_READ | PROT_WRITE,
                                ¦      MAP_SHARED, 0, &unused, NULL);
        up_write(&mm->mmap_sem);
        if (IS_ERR((void *)ctx->mmap_base)) {
                ctx->mmap_size = 0;
                aio_free_ring(ctx);
                return -ENOMEM;
        }

        pr_debug("mmap address: 0x%08lx\n", ctx->mmap_base);

        ctx->user_id = ctx->mmap_base;
        ctx->nr_events = nr_events; /* trusted copy */
        //kmap，初始化 aio_ring
        ring = kmap_atomic(ctx->ring_pages[0]);
        ring->nr = nr_events;   /* user copy */
        ring->id = ~0U;
        ring->head = ring->tail = 0;
        ring->magic = AIO_RING_MAGIC;
        ring->compat_features = AIO_RING_COMPAT_FEATURES;
        ring->incompat_features = AIO_RING_INCOMPAT_FEATURES;
        ring->header_length = sizeof(struct aio_ring);
        kunmap_atomic(ring);
        //????这里为什么要flush dcache呢
        flush_dcache_page(ctx->ring_pages[0]);

        return 0;
}
```

## io_submit
```cpp
SYSCALL_DEFINE3(io_submit, aio_context_t, ctx_id, long, nr,
                struct iocb __user * __user *, iocbpp)
{
        struct kioctx *ctx;
        long ret = 0;
        int i = 0;
        struct blk_plug plug;

        if (unlikely(nr < 0))
                return -EINVAL;

        ctx = lookup_ioctx(ctx_id);
        if (unlikely(!ctx)) {
                pr_debug("EINVAL: invalid context id\n");
                return -EINVAL;
        }

        if (nr > ctx->nr_events)
                nr = ctx->nr_events;

        blk_start_plug(&plug);
        for (i = 0; i < nr; i++) {
                struct iocb __user *user_iocb;

                if (unlikely(get_user(user_iocb, iocbpp + i))) {
                        ret = -EFAULT;
                        break;
                }

                ret = io_submit_one(ctx, user_iocb, false);
                if (ret)
                        break;
        }
        blk_finish_plug(&plug);

        percpu_ref_put(&ctx->users);
        return i ? i : ret;
}
```

### io_submit_one
```cpp
static int io_submit_one(struct kioctx *ctx, struct iocb __user *user_iocb,
                        ¦bool compat)
{
        struct aio_kiocb *req;
        struct iocb iocb;
        ssize_t ret;

        if (unlikely(copy_from_user(&iocb, user_iocb, sizeof(iocb))))
                return -EFAULT;

        /* enforce forwards compatibility on users */
        if (unlikely(iocb.aio_reserved2)) {
                pr_debug("EINVAL: reserve field set\n");
                return -EINVAL;
        }

        /* prevent overflows */
        if (unlikely(
            (iocb.aio_buf != (unsigned long)iocb.aio_buf) ||
            (iocb.aio_nbytes != (size_t)iocb.aio_nbytes) ||
            ((ssize_t)iocb.aio_nbytes < 0)
           )) {
                pr_debug("EINVAL: overflow check\n");
                return -EINVAL;
        }
        //获取req
        req = aio_get_req(ctx);
        if (unlikely(!req))
                return -EAGAIN;

        if (iocb.aio_flags & IOCB_FLAG_RESFD) {
                /*
                ¦* If the IOCB_FLAG_RESFD flag of aio_flags is set, get an
                ¦* instance of the file* now. The file descriptor must be
                ¦* an eventfd() fd, and will be signaled for each completed
                ¦* event using the eventfd_signal() function.
                ¦*/
                req->ki_eventfd = eventfd_ctx_fdget((int) iocb.aio_resfd);
                if (IS_ERR(req->ki_eventfd)) {
                        ret = PTR_ERR(req->ki_eventfd);
                        req->ki_eventfd = NULL;
                        goto out_put_req;
                }
        }

        ret = put_user(KIOCB_KEY, &user_iocb->aio_key);
        if (unlikely(ret)) {
                pr_debug("EFAULT: aio_key\n");
                goto out_put_req;
        }

        req->ki_user_iocb = user_iocb;
        req->ki_user_data = iocb.aio_data;

        switch (iocb.aio_lio_opcode) {
        case IOCB_CMD_PREAD:
                ret = aio_read(&req->rw, &iocb, false, compat);
                break;
        case IOCB_CMD_PWRITE:
                ret = aio_write(&req->rw, &iocb, false, compat);
                break;
        case IOCB_CMD_PREADV:
                ret = aio_read(&req->rw, &iocb, true, compat);
                break;
        case IOCB_CMD_PWRITEV:
                ret = aio_write(&req->rw, &iocb, true, compat);
                break;
        case IOCB_CMD_FSYNC:
                ret = aio_fsync(&req->fsync, &iocb, false);
                break;
        case IOCB_CMD_FDSYNC:
                ret = aio_fsync(&req->fsync, &iocb, true);
                break;
        default:
                pr_debug("invalid aio operation %d\n", iocb.aio_lio_opcode);
                ret = -EINVAL;
                break;
        }

        /*
         * If ret is 0, we'd either done aio_complete() ourselves or have
         * arranged for that to be done asynchronously.  Anything non-zero
         * means that we need to destroy req ourselves.
         */
        if (ret)
                goto out_put_req;
        return 0;
out_put_req:
        put_reqs_available(ctx, 1);
        percpu_ref_put(&ctx->reqs);
        if (req->ki_eventfd)
                eventfd_ctx_put(req->ki_eventfd);
        kmem_cache_free(kiocb_cachep, req);
        return ret;
}
```
### aio_get_req
```cpp
/* aio_get_req
 *      Allocate a slot for an aio request.
 * Returns NULL if no requests are free.
 */
static inline struct aio_kiocb *aio_get_req(struct kioctx *ctx)
{
        struct aio_kiocb *req;

        if (!get_reqs_available(ctx)) {
                //没有获取到req, 说明per cpu没有了，
                //全局的也不够了
                user_refill_reqs_available(ctx);
                if (!get_reqs_available(ctx))
                        return NULL;
        }

        req = kmem_cache_alloc(kiocb_cachep, GFP_KERNEL|__GFP_ZERO);
        if (unlikely(!req))
                goto out_put;

        percpu_ref_get(&ctx->reqs);
        INIT_LIST_HEAD(&req->ki_list);
        req->ki_ctx = ctx;
        return req;
out_put:
        put_reqs_available(ctx, 1);
        return NULL;
}
```

#### get_reqs_available
```cpp
static bool get_reqs_available(struct kioctx *ctx)
{
        struct kioctx_cpu *kcpu;
        bool ret = false;
        unsigned long flags;

        local_irq_save(flags);
        kcpu = this_cpu_ptr(ctx->cpu);
        //读取per cpu 的 reqs_available
        if (!kcpu->reqs_available) {
                //获取全局的
                int old, avail = atomic_read(&ctx->reqs_available);

                do {
                        //ctx->req_batch 表示一次移动的量
                        if (avail < ctx->req_batch)
                                goto out;

                        old = avail;
                        avail = atomic_cmpxchg(&ctx->reqs_available,
                                        ¦      avail, avail - ctx->req_batch);
                } while (avail != old);

                kcpu->reqs_available += ctx->req_batch;
        }

        ret = true;
        //get 一个
        kcpu->reqs_available--;
out:
        local_irq_restore(flags);
        return ret;
}
```

#### user_refill_reqs_available
```cpp
/* user_refill_reqs_available
 *      Called to refill reqs_available when aio_get_req() encounters an
 *      out of space in the completion ring.
 */
static void user_refill_reqs_available(struct kioctx *ctx)
{
        spin_lock_irq(&ctx->completion_lock);
        //在aio complete的流程中 ctx->complete_events 会自增
        //表示事件完成
        if (ctx->completed_events) {
                struct aio_ring *ring;
                unsigned head;

                /* Access of ring->head may race with aio_read_events_ring()
                ¦* here, but that's okay since whether we read the old version
                ¦* or the new version, and either will be valid.  The important
                ¦* part is that head cannot pass tail since we prevent
                ¦* aio_complete() from updating tail by holding
                ¦* ctx->completion_lock.  Even if head is invalid, the check
                ¦* against ctx->completed_events below will make sure we do the
                ¦* safe/right thing.
                ¦*/
                /*
                 * 获取head
                 *
                 * NOTE: 这里为什么要获取head呢，而不是从ctx->head 中获取呢？
                 * 那为什么tail就可以直接从ctx中获取
                 *
                 * 因为用户态可以直接修改head, 但是不能修改tail,tail只能内核侧修改
                 */
                ring = kmap_atomic(ctx->ring_pages[0]);
                head = ring->head;
                kunmap_atomic(ring);

                refill_reqs_available(ctx, head, ctx->tail);
        }

        spin_unlock_irq(&ctx->completion_lock);
}
```

#### refill_reqs_available
```cpp
/* refill_reqs_available
 *      Updates the reqs_available reference counts used for tracking the
 *      number of free slots in the completion ring.  This can be called
 *      from aio_complete() (to optimistically update reqs_available) or
 *      from aio_get_req() (the we're out of events case).  It must be
 *      called holding ctx->completion_lock.
 */
/* 该函数实际上将 ctx->completed_events 回收
 */
static void refill_reqs_available(struct kioctx *ctx, unsigned head,
                                  unsigned tail)
{
        unsigned events_in_ring, completed;

        /* Clamp head since userland can write to it. */
        head %= ctx->nr_events;
        if (head <= tail)
                events_in_ring = tail - head;
        else
                events_in_ring = ctx->nr_events - (head - tail);

        completed = ctx->completed_events;
        /*
         * 这里怎么理解呢 ?
         *
         * ctx->completed_events 会在aio_complete 中自增, 会在
         * refill_reqs_available减少
         *
         * 而tail 会在 aio_complete中自增
         * head会在 aio_read_events_ring 增加
         *
         * 绝对的 tail - head 为aio_complete了，但是还没有 read events
         * 的event, 但是这部分还占有着资源。
         *
         * 所以需要将这部分减去
         */
        if (events_in_ring < completed)
                completed -= events_in_ring;
        else
                completed = 0;

        if (!completed)
                return;

        ctx->completed_events -= completed;
        put_reqs_available(ctx, completed);
}
```

### aio_write
这里只看下aio_write, 其他的也差不多。主要了解aio的处理流程
```cpp
static ssize_t aio_write(struct kiocb *req, struct iocb *iocb, bool vectored,
                bool compat)
{
        struct iovec inline_vecs[UIO_FASTIOV], *iovec = inline_vecs;
        struct iov_iter iter;
        struct file *file;
        ssize_t ret;

        ret = aio_prep_rw(req, iocb);
        if (ret)
                return ret;
        file = req->ki_filp;

        ret = -EBADF;
        if (unlikely(!(file->f_mode & FMODE_WRITE)))
                goto out_fput;
        ret = -EINVAL;
        if (unlikely(!file->f_op->write_iter))
                goto out_fput;

        ret = aio_setup_rw(WRITE, iocb, &iovec, vectored, compat, &iter);
        if (ret)
                goto out_fput;
        ret = rw_verify_area(WRITE, file, &req->ki_pos, iov_iter_count(&iter));
        if (!ret) {
                /*
                ¦* Open-code file_start_write here to grab freeze protection,
                ¦* which will be released by another thread in
                ¦* aio_complete_rw().  Fool lockdep by telling it the lock got
                ¦* released so that it doesn't complain about the held lock when
                ¦* we return to userspace.
                ¦*/
                if (S_ISREG(file_inode(file)->i_mode)) {
                        __sb_start_write(file_inode(file)->i_sb, SB_FREEZE_WRITE, true);
                        __sb_writers_release(file_inode(file)->i_sb, SB_FREEZE_WRITE);
                }
                req->ki_flags |= IOCB_WRITE;
                aio_rw_done(req, call_write_iter(file, req, &iter));
        }
        kfree(iovec);
out_fput:
        if (unlikely(ret))
                fput(file);
        return ret;
}
```
#### aio_prep_rw
```cpp
static int aio_prep_rw(struct kiocb *req, struct iocb *iocb)
{
        int ret;

        req->ki_filp = fget(iocb->aio_fildes);
        if (unlikely(!req->ki_filp))
                return -EBADF;
        req->ki_complete = aio_complete_rw;
        req->ki_pos = iocb->aio_offset;
        req->ki_flags = iocb_flags(req->ki_filp);
        if (iocb->aio_flags & IOCB_FLAG_RESFD)
                req->ki_flags |= IOCB_EVENTFD;
        req->ki_hint = ki_hint_validate(file_write_hint(req->ki_filp));
        if (iocb->aio_flags & IOCB_FLAG_IOPRIO) {
                /*
                ¦* If the IOCB_FLAG_IOPRIO flag of aio_flags is set, then
                ¦* aio_reqprio is interpreted as an I/O scheduling
                ¦* class and priority.
                ¦*/
                ret = ioprio_check_cap(iocb->aio_reqprio);
                if (ret) {
                        pr_debug("aio ioprio check cap error: %d\n", ret);
                        goto out_fput;
                }

                req->ki_ioprio = iocb->aio_reqprio;
        } else
                req->ki_ioprio = get_current_ioprio();

        ret = kiocb_set_rw_flags(req, iocb->aio_rw_flags);
        if (unlikely(ret))
                goto out_fput;

        req->ki_flags &= ~IOCB_HIPRI; /* no one is going to poll for this I/O */
        return 0;

out_fput:
        fput(req->ki_filp);
        return ret;
}
```
#### aio_setup_rw
```cpp
static int aio_setup_rw(int rw, struct iocb *iocb, struct iovec **iovec,
                bool vectored, bool compat, struct iov_iter *iter)
{
        void __user *buf = (void __user *)(uintptr_t)iocb->aio_buf;
        size_t len = iocb->aio_nbytes;

        if (!vectored) {
                ssize_t ret = import_single_range(rw, buf, len, *iovec, iter);
                *iovec = NULL;
                return ret;
        }
#ifdef CONFIG_COMPAT
        if (compat)
                return compat_import_iovec(rw, buf, len, UIO_FASTIOV, iovec,
                                iter);
#endif
        return import_iovec(rw, buf, len, UIO_FASTIOV, iovec, iter);
}
```
#### aio_rw_done
```cpp
static inline void aio_rw_done(struct kiocb *req, ssize_t ret)
{
        switch (ret) {
        case -EIOCBQUEUED:
                //这个表示入队，但是还没有处理
                break;
        case -ERESTARTSYS:
        case -ERESTARTNOINTR:
        case -ERESTARTNOHAND:
        case -ERESTART_RESTARTBLOCK:
                /*
                ¦* There's no easy way to restart the syscall since other AIO's
                ¦* may be already running. Just fail this IO with EINTR.
                ¦*/
                ret = -EINTR;
                /*FALLTHRU*/
        default:
                aio_complete_rw(req, ret, 0);
        }
}
```
#### aio_complete_rw
```cpp
static void aio_complete_rw(struct kiocb *kiocb, long res, long res2)
{                                                                               
        struct aio_kiocb *iocb = container_of(kiocb, struct aio_kiocb, rw);
                                                                                
        if (!list_empty_careful(&iocb->ki_list))
                aio_remove_iocb(iocb);                                          

        if (kiocb->ki_flags & IOCB_WRITE) {                                     
                struct inode *inode = file_inode(kiocb->ki_filp);
                                                                                
                /*
                 * Tell lockdep we inherited freeze protection from submission  
                 * thread.
                 */                                                             
                if (S_ISREG(inode->i_mode))
                        __sb_writers_acquired(inode->i_sb, SB_FREEZE_WRITE);    
                file_end_write(kiocb->ki_filp);
        }                                                                       

        fput(kiocb->ki_filp);                                                   
        aio_complete(iocb, res, res2);
}                                                                               
```
## aio_complete
```cpp
static void aio_complete(struct aio_kiocb *iocb, long res, long res2)
{
        struct kioctx   *ctx = iocb->ki_ctx;
        struct aio_ring *ring;
        struct io_event *ev_page, *event;
        unsigned tail, pos, head;
        unsigned long   flags;

        /*
         * Add a completion event to the ring buffer. Must be done holding
         * ctx->completion_lock to prevent other code from messing with the tail
         * pointer since we might be called from irq context.
         */
        spin_lock_irqsave(&ctx->completion_lock, flags);

        tail = ctx->tail;
        pos = tail + AIO_EVENTS_OFFSET;

        if (++tail >= ctx->nr_events)
                tail = 0;
        //找到所在的page
        ev_page = kmap_atomic(ctx->ring_pages[pos / AIO_EVENTS_PER_PAGE]);
        event = ev_page + pos % AIO_EVENTS_PER_PAGE;

        event->obj = (u64)(unsigned long)iocb->ki_user_iocb;
        event->data = iocb->ki_user_data;
        event->res = res;
        event->res2 = res2;

        kunmap_atomic(ev_page);
        flush_dcache_page(ctx->ring_pages[pos / AIO_EVENTS_PER_PAGE]);

        pr_debug("%p[%u]: %p: %p %Lx %lx %lx\n",
                ¦ctx, tail, iocb, iocb->ki_user_iocb, iocb->ki_user_data,
                ¦res, res2);

        /* after flagging the request as done, we
        ¦* must never even look at it again
        ¦*/
        smp_wmb();      /* make event visible before updating tail */

        ctx->tail = tail;

        ring = kmap_atomic(ctx->ring_pages[0]);
        head = ring->head;
        ring->tail = tail;
        kunmap_atomic(ring);
        flush_dcache_page(ctx->ring_pages[0]);

        ctx->completed_events++;
        if (ctx->completed_events > 1)
                refill_reqs_available(ctx, head, tail);
        spin_unlock_irqrestore(&ctx->completion_lock, flags);                                                                                  
        pr_debug("added to ring %p at [%u]\n", iocb, tail);

        /*
        ¦* Check if the user asked us to deliver the result through an
        ¦* eventfd. The eventfd_signal() function is safe to be called
        ¦* from IRQ context.
        ¦*/
        //signal eventfd
        if (iocb->ki_eventfd) {
                eventfd_signal(iocb->ki_eventfd, 1);
                eventfd_ctx_put(iocb->ki_eventfd);
        }

        kmem_cache_free(kiocb_cachep, iocb);

        /*
        ¦* We have to order our ring_info tail store above and test
        ¦* of the wait list below outside the wait lock.  This is
        ¦* like in wake_up_bit() where clearing a bit has to be
        ¦* ordered with the unlocked test.
        ¦*/
        smp_mb();
        //wakeup io_getevents 等待的进程
        if (waitqueue_active(&ctx->wait))
                wake_up(&ctx->wait);

        percpu_ref_put(&ctx->reqs);
}
```

### req->ki_complete 调用路径
```
dio_complete
  dio->iocb->ki_complete
```

## io_getevents
```
SYSCALL_DEFINE5(io_getevents, aio_context_t, ctx_id,
                long, min_nr,
                long, nr,
                struct io_event __user *, events,
                struct timespec __user *, timeout)
{
        struct timespec64       ts;
        int                     ret;

        if (timeout && unlikely(get_timespec64(&ts, timeout)))
                return -EFAULT;

        ret = do_io_getevents(ctx_id, min_nr, nr, events, timeout ? &ts : NULL);
        if (!ret && signal_pending(current))
                ret = -EINTR;
        return ret;
}
```

####  do_io_getevents
```cpp
static long do_io_getevents(aio_context_t ctx_id,
                long min_nr,
                long nr,
                struct io_event __user *events,
                struct timespec64 *ts)
{
        ktime_t until = ts ? timespec64_to_ktime(*ts) : KTIME_MAX;
        struct kioctx *ioctx = lookup_ioctx(ctx_id);
        long ret = -EINVAL;

        if (likely(ioctx)) {
                if (likely(min_nr <= nr && min_nr >= 0))
                        ret = read_events(ioctx, min_nr, nr, events, until);
                percpu_ref_put(&ioctx->users);
        }

        return ret;
}
```
####  read_events
```cpp
static long read_events(struct kioctx *ctx, long min_nr, long nr,
                        struct io_event __user *event,
                        ktime_t until)
{
        long ret = 0;

        /*
         * Note that aio_read_events() is being called as the conditional - i.e.
         * we're calling it after prepare_to_wait() has set task state to
         * TASK_INTERRUPTIBLE.
         *
         * But aio_read_events() can block, and if it blocks it's going to flip
         * the task state back to TASK_RUNNING.
         *
         * This should be ok, provided it doesn't flip the state back to
         * TASK_RUNNING and return 0 too much - that causes us to spin. That
         * will only happen if the mutex_lock() call blocks, and we then find
         * the ringbuffer empty. So in practice we should be ok, but it's
         * something to be aware of when touching this code.
         *
         * aio_read_events, 这个里面可能会阻塞。会造成什么现象呢? filp state
         * back to TASK_RUNNING, but return 0(没有read到 events)。这里相当于空转了
         * 一次，但是作者认为这种现象是可以接受的，但是还需要注意一下，在什么情况下，会
         * 出发这个代码
         */
        if (until == 0)
                aio_read_events(ctx, min_nr, nr, event, &ret);
        else
                wait_event_interruptible_hrtimeout(ctx->wait,
                                aio_read_events(ctx, min_nr, nr, event, &ret),
                                until);
        return ret;
}
```

#### aio_read_events
```cpp
static long aio_read_events_ring(struct kioctx *ctx,
                                ¦struct io_event __user *event, long nr)
{
        struct aio_ring *ring;
        unsigned head, tail, pos;
        long ret = 0;
        int copy_ret;

        /*
         * The mutex can block and wake us up and that will cause
         * wait_event_interruptible_hrtimeout() to schedule without sleeping
         * and repeat. This should be rare enough that it doesn't cause
         * peformance issues. See the comment in read_events() for more detail.
         */
        /*
         * 在不是running的状态下, 去sleep, 这里可能会报warnning, 所以需要将
         * current->task_state_change 置为空
         *
         * MY_NOTE:
         *   这里 annotate的意思是: 批注;注解
         *   我的理解是，虽然在running 状态下sleep大部分情况下不正常，但是在这
         *   种情况下正常，那么这里就标注下这种特殊情况。
         */
        sched_annotate_sleep();
        mutex_lock(&ctx->ring_lock);

        /* Access to ->ring_pages here is protected by ctx->ring_lock. */
        ring = kmap_atomic(ctx->ring_pages[0]);
        head = ring->head;
        tail = ring->tail;
        kunmap_atomic(ring);

        /*
        ¦* Ensure that once we've read the current tail pointer, that
        ¦* we also see the events that were stored up to the tail.
        ¦*/
        smp_rmb();

        pr_debug("h%u t%u m%u\n", head, tail, ctx->nr_events);

        if (head == tail)
                goto out;

        head %= ctx->nr_events;
        tail %= ctx->nr_events;

        while (ret < nr) {
                long avail;
                struct io_event *ev;
                struct page *page;
                //队列中可以获得的
                avail = (head <= tail ?  tail : ctx->nr_events) - head;
                if (head == tail)
                        break;

                pos = head + AIO_EVENTS_OFFSET;
                page = ctx->ring_pages[pos / AIO_EVENTS_PER_PAGE];
                pos %= AIO_EVENTS_PER_PAGE;
                //因为有nr的限制，这里取最小值
                avail = min(avail, nr - ret);
                //只能一个page一个page的去获取，所以这里还需要考虑下page
                //的限制
                avail = min_t(long, avail, AIO_EVENTS_PER_PAGE - pos);

                ev = kmap(page);
                copy_ret = copy_to_user(event + ret, ev + pos,
                                                    sizeof(*ev) * avail);
                kunmap(page);

                if (unlikely(copy_ret)) {
                        ret = -EFAULT;
                        goto out;
                }

                ret += avail;
                //将head
                head += avail;
                head %= ctx->nr_events;
        }

        ring = kmap_atomic(ctx->ring_pages[0]);
        ring->head = head;
        kunmap_atomic(ring);
        flush_dcache_page(ctx->ring_pages[0]);

        pr_debug("%li  h%u t%u\n", ret, head, tail);
out:
        mutex_unlock(&ctx->ring_lock);

        return ret;
}
```

# TMP
## AIO_EVENTS_PER_PAGE
```cpp
#define AIO_EVENTS_PER_PAGE     (PAGE_SIZE / sizeof(struct io_event))
#define AIO_EVENTS_FIRST_PAGE   ((PAGE_SIZE - sizeof(struct aio_ring)) / sizeof(struct io_event))
#define AIO_EVENTS_OFFSET       (AIO_EVENTS_PER_PAGE - AIO_EVENTS_FIRST_PAGE)


AIO_EVENTS_OFFSET:
        PAGE_SIZE / sizeof(struct io_event) - 
        PAGE_SIZE / sizeof(struct io_event) + sizeof(struct aio_ring) / sizeof(io_event) \
~=      sizeof(aio_ring) / sizeof(io_event)

那为什么不能直接空 sizeof(aio_ring) / sizeof(io_event) 作为 pos的偏移呢?

其实这样计算不合适，因为必须确认取整的方式， 举个例子:

PAGE_SIZE = 4096, sizeof(aio_ring) = 96, sizeof(io_event) = 200

其实这样来, first page aio event number 和 second page aio event number 一样。

而刚刚说的计算方式就需要向下取整， 那我们再看一个

PAGE_SIZE = 4000, sizeof(aio_ring) = 100, sizeof(io_event) = 200
我们来看下 first page aio event number 为 20
second page aio event number 19
所以有需要向上取整。

而向上面计算，首先计算出first page aio event number, 在计算出second page aio event number
一相减，就可以知道first page 和 second page 差距多少个 io_events number。

这样就可以使用:
pos = tail + AIO_EVENTS_OFFSET (加上第一个page缺少的 io event number，这样就等于 second page io event number)
pos / AIO_EVENTS_PER_PAGE 得到 page index
```
