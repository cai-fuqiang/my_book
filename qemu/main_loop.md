# main_loop 主流程
## main_loop_wait
```cpp
////gpollfds///////
static GArray *gpollfds;

void main_loop_wait(int nonblocking)
{
    MainLoopPoll mlpoll = {
        .state = MAIN_LOOP_POLL_FILL,
        .timeout = UINT32_MAX,
        .pollfds = gpollfds,
    };
    int ret;
    int64_t timeout_ns;

    if (nonblocking) {
        mlpoll.timeout = 0;
    }

    /* poll any events */
	//reset array
    g_array_set_size(gpollfds, 0); /* reset for new iteration */
    /* XXX: separate device handlers from system ones */
    notifier_list_notify(&main_loop_poll_notifiers, &mlpoll);

    if (mlpoll.timeout == UINT32_MAX) {
        timeout_ns = -1;
    } else {
        timeout_ns = (uint64_t)mlpoll.timeout * (int64_t)(SCALE_MS);
    }

    timeout_ns = qemu_soonest_timeout(timeout_ns,
                                      timerlistgroup_deadline_ns(
                                          &main_loop_tlg));
	//main loop wait
    ret = os_host_main_loop_wait(timeout_ns);
    mlpoll.state = ret < 0 ? MAIN_LOOP_POLL_ERR : MAIN_LOOP_POLL_OK;
    notifier_list_notify(&main_loop_poll_notifiers, &mlpoll);

    /* CPU thread can infinitely wait for event after
       missing the warp */
    qemu_start_warp_timer();
    qemu_clock_run_all_timers();
}
```

## os_host_main_loop_wait
```cpp
static int os_host_main_loop_wait(int64_t timeout)
{
    GMainContext *context = g_main_context_default();
    int ret;

    g_main_context_acquire(context);
	//这里会将 gpollfds的文件描述符，加入到context(g_main_context_query-> default context)
    glib_pollfds_fill(&timeout);

    qemu_mutex_unlock_iothread();
    replay_mutex_unlock();
	//执行poll
    ret = qemu_poll_ns((GPollFD *)gpollfds->data, gpollfds->len, timeout);

    replay_mutex_lock();
    qemu_mutex_lock_iothread();
	//在这里会执行 check , dispatch
    glib_pollfds_poll();

    g_main_context_release(context);

    return ret;
}
```
### glib_pollfds_fill
```cpp
static void glib_pollfds_fill(int64_t *cur_timeout)
{
    GMainContext *context = g_main_context_default();
    int timeout = 0;
    int64_t timeout_ns;
    int n;

    g_main_context_prepare(context, &max_priority);

    glib_pollfds_idx = gpollfds->len;
    n = glib_n_poll_fds;
    do {
        GPollFD *pfds;
        glib_n_poll_fds = n;
		//扩充 gpollfds
        g_array_set_size(gpollfds, glib_pollfds_idx + glib_n_poll_fds);
        pfds = &g_array_index(gpollfds, GPollFD, glib_pollfds_idx);
		/*
         * 返回值n, 实际上代表，保存 context->poll_recoreds 链表中的fds,
		 * 需要的数组大小, 这里 glib_n_poll_fds 可能大，也可能小。
		 *
         * 但是根据"概率论"，这次的数组大小有一定概率和上次相同。所以，这里
         * 先取上一次的大小，看看是否合适
         *
         * 另外，这里循环可能会进行多次，因为如果n < 实际的需求，那么就会
         * 在调用一次  g_main_context_query, 但是可能因为fd合并，导致上一次获取
         * 的实际的数组大小，并不一定是对的
		 */

        n = g_main_context_query(context, max_priority, &timeout, pfds,
                                 glib_n_poll_fds);
    } while (n != glib_n_poll_fds);

    if (timeout < 0) {
        timeout_ns = -1;
    } else {
        timeout_ns = (int64_t)timeout * (int64_t)SCALE_MS;
    }

    *cur_timeout = qemu_soonest_timeout(timeout_ns, *cur_timeout);
}
```

### glib_pollfds_poll
```cpp
static void glib_pollfds_poll(void)
{
    GMainContext *context = g_main_context_default();
    GPollFD *pfds = &g_array_index(gpollfds, GPollFD, glib_pollfds_idx);

    if (g_main_context_check(context, max_priority, pfds, glib_n_poll_fds)) {
        g_main_context_dispatch(context);
    }
}
```
* 调用 check 检查是否有事件
* 对check = true 的事件 dispatch

# GSource in main loop context
代码流程:
```
main
    qemu_init_main_loop
```
`qemu_init_main_loop`:
```cpp
/*
 * 我们这里先不展开AioContext的成员，
 * 只需要知道里面有一个GSource的成员(不是指针):
 * AioContext.GSource
 */
/////////qemu_aio_context//////////
static AioContext *qemu_aio_context;

/////////qemu_notify_bh////////////先不看
static QEMUBH *qemu_notify_bh;

/////////iohandler_ctx/////////////
static AioContext *iohandler_ctx;
int qemu_init_main_loop(Error **errp)
{
    int ret;
    GSource *src;
    Error *local_error = NULL;

    init_clocks(qemu_timer_notify_cb);
    //signal init , 和信号相关先不看
    ret = qemu_signal_init(errp);
    if (ret) {
        return ret;
    }

    //create qemu_aio_context g_source
    qemu_aio_context = aio_context_new(&local_error);
    if (!qemu_aio_context) {
        error_propagate(errp, local_error);
        return -EMFILE;
    }
    //init bh
    qemu_notify_bh = qemu_bh_new(notify_event_cb, NULL);
    //new gpollfds 数组
    gpollfds = g_array_new(FALSE, FALSE, sizeof(GPollFD));
    //在  aio_get_g_source() 中会调用 g_source_ref()增加引用

    src = aio_get_g_source(qemu_aio_context);
    g_source_set_name(src, "aio-context");
    //attach default context
    g_source_attach(src, NULL);
    //减少引用
    g_source_unref(src);
    //iohandler_ctx get
    src = iohandler_get_g_source();
    g_source_set_name(src, "io-handler");
    //也是attach到 default context
    g_source_attach(src, NULL);
    g_source_unref(src);
    return 0;
}

GSource *iohandler_get_g_source(void)
{
    iohandler_init();
    return aio_get_g_source(iohandler_ctx);
}
static void iohandler_init(void)
{
    if (!iohandler_ctx) {
        iohandler_ctx = aio_context_new(&error_abort);
    }
}
```
## aio_context_new
```cpp
AioContext *aio_context_new(Error **errp)
{
    int ret;
    AioContext *ctx;
    //创建g_source, 设置 aio_source_funcs
    ctx = (AioContext *) g_source_new(&aio_source_funcs, sizeof(AioContext)); aio_context_setup(ctx);
    //create ctx->epollfd, 这个文件描述符暂时不清楚作用
    aio_context_setup(ctx);
    //创建eventfd
    ret = event_notifier_init(&ctx->notifier, false);
    if (ret < 0) {
        error_setg_errno(errp, -ret, "Failed to initialize event notifier");
        goto fail;
    }
    //设置可递归
    g_source_set_can_recurse(&ctx->source, true);
    qemu_lockcnt_init(&ctx->list_lock);
    //new bh
    ctx->co_schedule_bh = aio_bh_new(ctx, co_schedule_bh_cb, ctx);
    QSLIST_INIT(&ctx->scheduled_coroutines);
    //设置event notifier
    //但是event_notifier_poll, 在主线程 main loop 中不会执行到
    aio_set_event_notifier(ctx, &ctx->notifier,
                           false,
                           event_notifier_dummy_cb,
                           event_notifier_poll);
#ifdef CONFIG_LINUX_AIO
    ctx->linux_aio = NULL;
#endif
    ctx->thread_pool = NULL;
    qemu_rec_mutex_init(&ctx->lock);
    timerlistgroup_init(&ctx->tlg, aio_timerlist_notify, ctx);

    ctx->poll_ns = 0;
    ctx->poll_max_ns = 0;
    ctx->poll_grow = 0;
    ctx->poll_shrink = 0;

    return ctx;
fail:
    g_source_destroy(&ctx->source);
    return NULL;
}
```

### event_notifier_init
```cpp
int event_notifier_init(EventNotifier *e, int active)
{
    int fds[2];
    int ret;

#ifdef CONFIG_EVENTFD
    //配置了eventfd就使用eventfd
    ret = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
#else
    ret = -1;
    errno = ENOSYS;
#endif
    if (ret >= 0) {
        e->rfd = e->wfd = ret;
    } else {
        //如果没有配置eventfd,或者返回失败了，使用pipe
        if (errno != ENOSYS) {
            return -errno;
        }
        if (qemu_pipe(fds) < 0) {
            return -errno;
        }
        ret = fcntl_setfl(fds[0], O_NONBLOCK);
        if (ret < 0) {
            ret = -errno;
            goto fail;
        }
        ret = fcntl_setfl(fds[1], O_NONBLOCK);
        if (ret < 0) {
            ret = -errno;
            goto fail;
        }
        e->rfd = fds[0];
        e->wfd = fds[1];
    }
    //如果是active, 需要在这里set下
    if (active) {
        event_notifier_set(e);
    }
    return 0;

fail:
    close(fds[0]);
    close(fds[1]);
    return ret;
}
```

### aio_set_event_notifier
```cpp
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
    //在ctx中 查找相同fd的 AioHnadler
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
        //创建一个新的 handler
        /* Alloc and insert if it's not already there */
        new_node = g_new0(AioHandler, 1);

        /* Update handler with latest information */
        new_node->io_read = io_read;
        new_node->io_write = io_write;
        new_node->io_poll = io_poll;
        new_node->opaque = opaque;
        new_node->is_external = is_external;

        if (is_new) {
            new_node->pfd.fd = fd;
        } else {
            new_node->pfd = node->pfd;
        }
        //将其加入 source->poll_fds中, 并且加入到context->poll_records中
        g_source_add_poll(&ctx->source, &new_node->pfd);
        /*
         * 根据其提供的 callback 选择监听事件类型，如果提供的是io_read, 说明
         * 监听事件为in
         */
        new_node->pfd.events = (io_read ? G_IO_IN | G_IO_HUP | G_IO_ERR : 0);
        new_node->pfd.events |= (io_write ? G_IO_OUT | G_IO_ERR : 0);
        //链入 ctx->aio_handlers
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
### aio_source_funcs
```cpp
static GSourceFuncs aio_source_funcs = {
    aio_ctx_prepare,
    aio_ctx_check,
    aio_ctx_dispatch,
    aio_ctx_finalize
};
```
#### aio_ctx_preare
这个函数在main loop 中貌似没有调用到
```cpp
static gboolean
aio_ctx_prepare(GSource *source, gint    *timeout)
{
    AioContext *ctx = (AioContext *) source;

    atomic_or(&ctx->notify_me, 1);

    /* We assume there is no timeout already supplied */
    //在这里计算下超时
    *timeout = qemu_timeout_ns_to_ms(aio_compute_timeout(ctx));
    //会调用atx->aio_handlers ->io_poll_end(如果有)
    if (aio_prepare(ctx)) {
        *timeout = 0;
    }

    return *timeout == 0;
}
bool aio_prepare(AioContext *ctx)
{
    /* Poll mode cannot be used with glib's event loop, disable it. */
    poll_set_started(ctx, false);

    return false;
}

static void poll_set_started(AioContext *ctx, bool started)
{
    AioHandler *node;

    if (started == ctx->poll_started) {
        return;
    }

    ctx->poll_started = started;

    qemu_lockcnt_inc(&ctx->list_lock);
    QLIST_FOREACH_RCU(node, &ctx->aio_handlers, node) {
        IOHandler *fn;

        if (node->deleted) {
            continue;
        }

        if (started) {
            fn = node->io_poll_begin;
        } else {
            fn = node->io_poll_end;
        }

        if (fn) {
            fn(node->opaque);
        }
    }
    qemu_lockcnt_dec(&ctx->list_lock);
}
```
#### aio_ctx_check
```cpp
static gboolean
aio_ctx_check(GSource *source)
{
    AioContext *ctx = (AioContext *) source;
    QEMUBH *bh;

    atomic_and(&ctx->notify_me, ~1);
    //accept notify (ctx->notfier 不太清楚做啥用的)
    aio_notify_accept(ctx);
    //和bh相关
    for (bh = ctx->first_bh; bh; bh = bh->next) {
        if (bh->scheduled) {
            return true;
        }
    }
    //主要是第一个条件，第二个条件可能和超时有关
    return aio_pending(ctx) || (timerlistgroup_deadline_ns(&ctx->tlg) == 0);
}

bool aio_pending(AioContext *ctx)
{
    AioHandler *node;
    bool result = false;

    /*
     * We have to walk very carefully in case aio_set_fd_handler is
     * called while we're walking.
     */
    qemu_lockcnt_inc(&ctx->list_lock);
    /*
     * 代码逻辑很简单，便利aio_handlers, 取 pdf.events 和 revents的交集，
     * 判断所监听事件有没有发生
     */
    QLIST_FOREACH_RCU(node, &ctx->aio_handlers, node) {
        int revents;

        revents = node->pfd.revents & node->pfd.events;
        //这里检测in事件，并判断有没有 node->io_read
        // aio_node_check没有看懂 ！！！
        if (revents & (G_IO_IN | G_IO_HUP | G_IO_ERR) && node->io_read &&
            aio_node_check(ctx, node->is_external)) {
            result = true;
            break;
        }
        //检测out事件
        if (revents & (G_IO_OUT | G_IO_ERR) && node->io_write &&
            aio_node_check(ctx, node->is_external)) {
            result = true;
            break;
        }
    }
    qemu_lockcnt_dec(&ctx->list_lock);

    return result;
}
```

#### aio_ctx_dispatch
```cpp
static gboolean
aio_ctx_dispatch(GSource     *source,
                 GSourceFunc  callback,
                 gpointer     user_data)
{
    AioContext *ctx = (AioContext *) source;

    assert(callback == NULL);
    aio_dispatch(ctx);
    return true;
}

void aio_dispatch(AioContext *ctx)
{
    qemu_lockcnt_inc(&ctx->list_lock);
    //和bh poll相关，先不看
    aio_bh_poll(ctx);
    aio_dispatch_handlers(ctx);
    qemu_lockcnt_dec(&ctx->list_lock);

    timerlistgroup_run_timers(&ctx->tlg);
}

static bool aio_dispatch_handlers(AioContext *ctx)
{
    AioHandler *node, *tmp;
    bool progress = false;

    //该逻辑和 check很像
    //获取各个node, 然后根据poll返回的事件，来判断是否需要
    //执行相应的 io_read/io_write 函数
    QLIST_FOREACH_SAFE_RCU(node, &ctx->aio_handlers, node, tmp) {
        int revents;

        revents = node->pfd.revents & node->pfd.events;
        node->pfd.revents = 0;

        if (!node->deleted &&
            (revents & (G_IO_IN | G_IO_HUP | G_IO_ERR)) &&
            aio_node_check(ctx, node->is_external) &&
            node->io_read) {
            node->io_read(node->opaque);

            /* aio_notify() does not count as progress */
            if (node->opaque != &ctx->notifier) {
                progress = true;
            }
        }
        if (!node->deleted &&
            (revents & (G_IO_OUT | G_IO_ERR)) &&
            aio_node_check(ctx, node->is_external) &&
            node->io_write) {
            node->io_write(node->opaque);
            progress = true;
        }

        if (node->deleted) {
            if (qemu_lockcnt_dec_if_lock(&ctx->list_lock)) {
                QLIST_REMOVE(node, node);
                g_free(node);
                qemu_lockcnt_inc_and_unlock(&ctx->list_lock);
            }
        }
    }

    return progress;
}
```

# 
