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
    //设置跳转点, 方便之后切入, self env始终指向这个地方
    if (!sigsetjmp(self->env, 0)) {
        start_switch_fiber(&fake_stack_save,
                           leader.stack, leader.stack_size);
        siglongjmp(*(sigjmp_buf *)co->entry_arg, 1);
    }

    finish_switch_fiber(fake_stack_save);

    while (true) {
        co->entry(co->entry_arg);
        qemu_coroutine_switch(co, co->caller, COROUTINE_TERMINATE);
    }
}
```
# 参考链接
[sigsetjmp/siglongjmp简单例子](http://blog.chinaunix.net/uid-29073321-id-5557346.html)

[举例解释了sigsetjmp/setjmp不同](https://blog.csdn.net/matafeiyanll/article/details/110399010)

[sigsetjmp & siglongjmp 的小把戏 --- typedef 数组的好处](https://blog.csdn.net/FJDJFKDJFKDJFKD/article/details/127231995)

[makecontext MAN PAGE](https://man7.org/linux/man-pages/man3/swapcontext.3.html)
