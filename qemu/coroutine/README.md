# struct
## struct Coroutine 
```cpp
struct Coroutine {
    CoroutineEntry *entry;
    void *entry_arg;
    Coroutine *caller;

    /* Only used when the coroutine has terminated.  */
    /*
     * 仅用于协程终止的时候。
     * 协程终止时，会将该成员链入协程池的链表中
     */
    QSLIST_ENTRY(Coroutine) pool_next;

    size_t locks_held;

    /* Only used when the coroutine has yielded.  */
    //仅用于协程调度出去, 在virtio submit_request中会讲解到
    AioContext *ctx;

    /* Used to catch and abort on illegal co-routine entry.
     * Will contain the name of the function that had first
     * scheduled the coroutine. */
    const char *scheduled;

    QSIMPLEQ_ENTRY(Coroutine) co_queue_next;

    /* Coroutines that should be woken up when we yield or terminate.
     * Only used when the coroutine is running.
     */
    QSIMPLEQ_HEAD(, Coroutine) co_queue_wakeup;

    QSLIST_ENTRY(Coroutine) co_scheduled_next;
};
```
## CoroutineUContext 
```cpp
typedef struct {
    Coroutine base;
    void *stack;        /* 协程栈空间 */
    size_t stack_size;  /* 栈空间大小 */
    sigjmp_buf env;

#ifdef CONFIG_VALGRIND_H
    unsigned int valgrind_stack_id;
#endif
} CoroutineUContext;
```

# global val
```cpp
//全局协程池
static QSLIST_HEAD(, Coroutine) release_pool = QSLIST_HEAD_INITIALIZER(pool);
//全局协程池大小
static unsigned int release_pool_size;
//当前线程的协程池
static __thread QSLIST_HEAD(, Coroutine) alloc_pool = QSLIST_HEAD_INITIALIZER(pool);
//线程的协城池大小
static __thread unsigned int alloc_pool_size;
static __thread Notifier coroutine_pool_cleanup_notifier;
```

# function
## create -- qemu_coroutine_create
```cpp
Coroutine *qemu_coroutine_create(CoroutineEntry *entry, void *opaque)
{
    Coroutine *co = NULL;

    if (CONFIG_COROUTINE_POOL) {
        //先在当前线程协程池中找
        co = QSLIST_FIRST(&alloc_pool);
        if (!co) {
            if (release_pool_size > POOL_BATCH_SIZE) {
                /* Slow path; a good place to register the destructor, too.  */
                /* 该notify 在线程退出的时候，会调用到, 用于清空该线程中的协程 */
                if (!coroutine_pool_cleanup_notifier.notify) {
                    coroutine_pool_cleanup_notifier.notify = coroutine_pool_cleanup;
                    qemu_thread_atexit_add(&coroutine_pool_cleanup_notifier);
                }

                /* This is not exact; there could be a little skew between
                 * release_pool_size and the actual size of release_pool.  But
                 * it is just a heuristic, it does not need to be perfect.
                 */
                /*
                 * 注释中提到，这里可能在 release_pool_size 和 release_pool 的真实
                 * 大小之间会有一点差异，但是这只是 heuristic(启发?), 并不需要完美
                 */
                /*
                 * NOTE:
                 * 这里的做法是release_pool_size > POOL_BATCH_SIZE时候，将全局release_pool
                 * 全部移动到 线程的 alloc_pool中。
                 *
                 * ????? 全部移动?????
                 */
                alloc_pool_size = atomic_xchg(&release_pool_size, 0);
                QSLIST_MOVE_ATOMIC(&alloc_pool, &release_pool);
                co = QSLIST_FIRST(&alloc_pool);
            }
        }
        //找到了，从线程协程池链表中移除
        if (co) {
            QSLIST_REMOVE_HEAD(&alloc_pool, pool_next);
            alloc_pool_size--;
        }
    }
    //没有找到，需要new
    if (!co) {
        co = qemu_coroutine_new();
    }

    co->entry = entry;
    co->entry_arg = opaque;
    QSIMPLEQ_INIT(&co->co_queue_wakeup);
    return co;
}
```

### qemu_coroutine_new
```cpp
Coroutine *qemu_coroutine_new(void)
{
    CoroutineUContext *co;
    ucontext_t old_uc, uc;
    sigjmp_buf old_env;
    union cc_arg arg = {0};
    void *fake_stack_save = NULL;

    /* The ucontext functions preserve signal masks which incurs a
     * system call overhead.  sigsetjmp(buf, 0)/siglongjmp() does not
     * preserve signal masks but only works on the current stack.
     * Since we need a way to create and switch to a new stack, use
     * the ucontext functions for that but sigsetjmp()/siglongjmp() for
     * everything else.
     */

    if (getcontext(&uc) == -1) {
        abort();
    }

    co = g_malloc0(sizeof(*co));
    //#define COROUTINE_STACK_SIZE (1 << 20)
    co->stack_size = COROUTINE_STACK_SIZE;
    //分配栈空间
    co->stack = qemu_alloc_stack(&co->stack_size);
    //jmp_buf
    co->base.entry_arg = &old_env; /* stash away our jmp_buf */

    uc.uc_link = &old_uc;
    uc.uc_stack.ss_sp = co->stack;
    uc.uc_stack.ss_size = co->stack_size;
    uc.uc_stack.ss_flags = 0;

#ifdef CONFIG_VALGRIND_H
    co->valgrind_stack_id =
        VALGRIND_STACK_REGISTER(co->stack, co->stack + co->stack_size);
#endif

    arg.p = co;
    //makecontext, 在下面的swapcontext 会跳转出去
    makecontext(&uc, (void (*)(void))coroutine_trampoline,
                2, arg.i[0], arg.i[1]);

    /* swapcontext() in, siglongjmp() back out */
    /*
     * 注释中也提到了，会在 swapcontext 换出上下文,
     * 在换出的上下文中(coroutine_trampoline), 在换回来, 我们接下来看下
     */
    if (!sigsetjmp(old_env, 0)) {
        start_switch_fiber(&fake_stack_save, co->stack, co->stack_size);
        //在这里切出
        swapcontext(&old_uc, &uc);
    }

    finish_switch_fiber(fake_stack_save);

    return &co->base;
}
```
### coroutine_trampoline
```cpp
static void coroutine_trampoline(int i0, int i1)
{
    union cc_arg arg;
    CoroutineUContext *self;
    Coroutine *co;
    void *fake_stack_save = NULL;

    finish_switch_fiber(NULL);

    arg.i[0] = i0;
    arg.i[1] = i1;
    self = arg.p;
    co = &self->base;

    /* Initialize longjmp environment and switch back the caller */
    //设置跳转点, 因为在 下面会跳出去
    if (!sigsetjmp(self->env, 0)) {
        start_switch_fiber(&fake_stack_save,
                           leader.stack, leader.stack_size);
        //在这里跳出
        //=============(1)==================
        siglongjmp(*(sigjmp_buf *)co->entry_arg, 1);
    }

    finish_switch_fiber(fake_stack_save);
    //下面的是第二次跳入的时候触发的
    while (true) {
        co->entry(co->entry_arg);
        //这里说明协程的处理函数已经执行完了，该协程需要销毁
        qemu_coroutine_switch(co, co->caller, COROUTINE_TERMINATE);
    }
}
```
在`coroutine_trampoline`(1)处跳出之后，会回到`qemu_coroutine_new`, 执行下面
的流程，一直到函数返回。那该协程什么时候，在跳转回来呢?

## aio_co_enter
```cpp
void aio_co_enter(AioContext *ctx, struct Coroutine *co)
{
    if (ctx != qemu_get_current_aio_context()) {
        aio_co_schedule(ctx, co);
        return;
    }
    //已经在协程中
    if (qemu_in_coroutine()) {
        Coroutine *self = qemu_coroutine_self();
        assert(self != co);
        QSIMPLEQ_INSERT_TAIL(&self->co_queue_wakeup, co, co_queue_next);
    } else {
        aio_context_acquire(ctx);
        qemu_aio_coroutine_enter(ctx, co);
        aio_context_release(ctx);
    }
}
```
### qemu_aio_coroutine_enter
```cpp
 void qemu_aio_coroutine_enter(AioContext *ctx, Coroutine *co)
 {
     QSIMPLEQ_HEAD(, Coroutine) pending = QSIMPLEQ_HEAD_INITIALIZER(pending);
     //获取当前的协程
     Coroutine *from = qemu_coroutine_self();

     QSIMPLEQ_INSERT_TAIL(&pending, co, co_queue_next);

     /* Run co and any queued coroutines */
     //如果不是空
     while (!QSIMPLEQ_EMPTY(&pending)) {
         Coroutine *to = QSIMPLEQ_FIRST(&pending);
         CoroutineAction ret;

         /* Cannot rely on the read barrier for to in aio_co_wake(), as there are
          * callers outside of aio_co_wake() */
         const char *scheduled = atomic_mb_read(&to->scheduled);
         //remove from list
         QSIMPLEQ_REMOVE_HEAD(&pending, co_queue_next);

         trace_qemu_aio_coroutine_enter(ctx, from, to, to->entry_arg);

         /* if the Coroutine has already been scheduled, entering it again will
          * cause us to enter it twice, potentially even after the coroutine has
          * been deleted */
         if (scheduled) {
             fprintf(stderr,
                     "%s: Co-routine was already scheduled in '%s'\n",
                     __func__, scheduled);
             abort();
         }

         if (to->caller) {
             fprintf(stderr, "Co-routine re-entered recursively\n");
             abort();
         }
         //设置caller
         to->caller = from;
         to->ctx = ctx;

         /* Store to->ctx before anything that stores to.  Matches
          * barrier in aio_co_wake and qemu_co_mutex_wake.
          */
         smp_wmb();
        //switch 到 to
         ret = qemu_coroutine_switch(from, to, COROUTINE_ENTER);

         /* Queued coroutines are run depth-first; previously pending coroutines
          * run after those queued more recently.
          */
         QSIMPLEQ_PREPEND(&pending, &to->co_queue_wakeup);

        switch (ret) {
        case COROUTINE_YIELD:
            //表示switch的协程主动退出调度，不用管
            break;
        case COROUTINE_TERMINATE:
            assert(!to->locks_held);
            trace_qemu_coroutine_terminate(to);
            //表示协程处理函数执行完了，需要销毁
            coroutine_delete(to);
            break;
        default:
            abort();
        }
    }
}
```
###  qemu_coroutine_switch
```cpp
/* This function is marked noinline to prevent GCC from inlining it
 * into coroutine_trampoline(). If we allow it to do that then it
 * hoists the code to get the address of the TLS variable "current"
 * out of the while() loop. This is an invalid transformation because
 * the sigsetjmp() call may be called when running thread A but
 * return in thread B, and so we might be in a different thread
 * context each time round the loop.
 */
CoroutineAction __attribute__((noinline))
qemu_coroutine_switch(Coroutine *from_, Coroutine *to_,
                      CoroutineAction action)
{
    CoroutineUContext *from = DO_UPCAST(CoroutineUContext, base, from_);
    CoroutineUContext *to = DO_UPCAST(CoroutineUContext, base, to_);
    int ret;
    void *fake_stack_save = NULL;
    //设置current
    current = to_;
    //这里设置了from的env, 下次调度到该协程, 跳转到这里
    //在调度回来流程，请看 qemu_coroutine_yield, 会switch 到 self->caller
    ret = sigsetjmp(from->env, 0);
    if (ret == 0) {
        start_switch_fiber(action == COROUTINE_TERMINATE ?
                           NULL : &fake_stack_save, to->stack, to->stack_size);
        //跳转到 to->env, 这里不用判断返回值，
        //协程跳转返回，ret != 0
        //这里注意，调度回去的时候，设置to 的 sigsetjmp 返回值为 action
        siglongjmp(to->env, action);
    }

    finish_switch_fiber(fake_stack_save);

    return ret;
}
```

## qemu_coroutine_yield
```cpp
void coroutine_fn qemu_coroutine_yield(void)
{
    Coroutine *self = qemu_coroutine_self();
    //这里会将self->caller
    Coroutine *to = self->caller;

    trace_qemu_coroutine_yield(self, to);

    if (!to) {
        fprintf(stderr, "Co-routine is yielding to no one\n");
        abort();
    }
    //这里将self->caller设置为空，表示to 协程，不会在
    //调用 qemu_coroutine_switch 调度回来
    self->caller = NULL;
    //将to sigsetjmp返回值设置为 COROUTINE_YIELD
    qemu_coroutine_switch(self, to, COROUTINE_YIELD);
}
```
##  coroutine_delete
```cpp
static void coroutine_delete(Coroutine *co)
{
    co->caller = NULL;
    //如果配置了协程池
    if (CONFIG_COROUTINE_POOL) {
        //当release_pool_size 大于 POOL_BATCH_SIZE 两倍的话，将其加入
        //全局的release_pool
        if (release_pool_size < POOL_BATCH_SIZE * 2) {
            QSLIST_INSERT_HEAD_ATOMIC(&release_pool, co, pool_next);
            atomic_inc(&release_pool_size);
            return;
        }
        //当alloc_pool_size <  POOL_BATCH_SIZE, 将其加入线程的
        //alloc_pool
        if (alloc_pool_size < POOL_BATCH_SIZE) {
            QSLIST_INSERT_HEAD(&alloc_pool, co, pool_next);
            alloc_pool_size++;
            return;
        }
    }
    /* 走到这里可能有以下几种情况
     *   1. 没有配置 CONFIG_COROUTINE_POOL
     *   2. release_pool_size > POOL_BATCH_SIZE * 2 &&
     *       alloc_pool_size > POOL_BATCH_SIZE
     *       这种情况表明现在分配的协程已经够多了。需要释放一些
     */
    //在该流程中彻底删除协程
    qemu_coroutine_delete(co);
}
```

### qemu_coroutine_delete
```cpp
void qemu_coroutine_delete(Coroutine *co_)
{
    CoroutineUContext *co = DO_UPCAST(CoroutineUContext, base, co_);

#ifdef CONFIG_VALGRIND_H
    valgrind_stack_deregister(co);
#endif

    qemu_free_stack(co->stack, co->stack_size);
    g_free(co);
}
```
# 参考链接
[sigsetjmp/siglongjmp简单例子](http://blog.chinaunix.net/uid-29073321-id-5557346.html)

[举例解释了sigsetjmp/setjmp不同](https://blog.csdn.net/matafeiyanll/article/details/110399010)

[sigsetjmp & siglongjmp 的小把戏 --- typedef 数组的好处](https://blog.csdn.net/FJDJFKDJFKDJFKD/article/details/127231995)

[makecontext MAN PAGE](https://man7.org/linux/man-pages/man3/swapcontext.3.html)
