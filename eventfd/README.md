# eventfd

## 简介
eventfd = 用fd 实现的事件通知。

有两个特点：
* 使用vfs实现
* 主要用于事件通知，不用于传输其他信息

## fops : eventfd_fops
```cpp
static const struct file_operations eventfd_fops = {
#ifdef CONFIG_PROC_FS
        .show_fdinfo    = eventfd_show_fdinfo,
#endif
        .release        = eventfd_release,
        .poll           = eventfd_poll,
        .read           = eventfd_read,
        .write          = eventfd_write,
        .llseek         = noop_llseek,
};
```

我们这里先看下 `read`, `write`, `poll`操作，看看其读取写入的行为。

这里先简单说下, 稍后，我们会详细看下其实现:
> NOTE
>
> eventfd 存储的信息 实际上是一个计数器。<br/>
> * \> 0: 表示 有事件到达，但是还未接收 <br/>
> * = 0: 表示 从上次接收该事件后，还未有事件。
* write: 表示有事件要通知到读侧, 写入的是一个64位的无符号整型。
   该值会累加该eventfd的计数中
* read : 读取事件，会将eventfd中的计数读取，并清零。(
  EFD_SEMAPHORE除外, 下面我们会看到)
* poll : 用于监听该事件，epoll 监听的时可读可写的事件。
 那么eventfd该监听什么信息呢 ? <br/>
 eventfd读写事件都可以监听，随后，我们会在kernel代码讲解中
 详细介绍。


## 用户态api
eventfd 是基于vfs实现的，对于vfs的一些api，eventfd也适用。但是
fd创建的api eventfd实现了两个系统调用.
```cpp
SYSCALL_DEFINE2(eventfd2, unsigned int, count, int, flags
{
        return do_eventfd(count, flags);
}

SYSCALL_DEFINE1(eventfd, unsigned int, count)
{
        return do_eventfd(count, 0);
}

```
* count : 计数的初始值
* flags : eventfd的一些属性，例如上面提到的`EFD_SEMAPHORE`

我们再看kernel 代码之前，先从用户态层面简单测试下api:
```cpp
#include <stdio.h>
#include <sys/eventfd.h>
#include <unistd.h>

int main()
{
        int fd;
        unsigned long u_wcnt;
        unsigned long u_rcnt;
        int i = 0;
        int flag = 0;
        for (i = 0; i < 2; i++) {
                fd = eventfd(0, flag);
                if (fd < 0) {
                        printf("create eventfd error\n");
                        goto err;
                }
                u_wcnt = 2;
                write(fd, &u_wcnt, sizeof(u_wcnt));
                read(fd, &u_rcnt, sizeof(u_rcnt));
                printf("u_rcnt is %u\n", u_rcnt);
                close(fd);
                flag |= EFD_SEMAPHORE;
        }

        return 0;
err:
        return -1;
}

```
程序输出:
```
u_rcnt is 2
u_rcnt is 1
```
可以看到, libc的接口`eventfd`, 对应的系统调用`eventfd2`。另外，使用了`EFD_SEMAPHORE`
标志位时，read操作会像信号量一样每次减少一个计数
> NOTE 
>
> 使用下面的命令可以调试, 是否调用了eventfd2系统调用(arm64平台)
>
> stap -e 'probe kernel.function("__arm64_sys_eventfd2") {printf("enter eventfd2\n") }'

# kernel 实现
## 主要的数据结构 -- eventfd_ctx
```cpp
struct eventfd_ctx {
        struct kref kref;
        wait_queue_head_t wqh;
        /*
         * Every time that a write(2) is performed on an eventfd, the
         * value of the __u64 being written is added to "count" and a
         * wakeup is performed on "wqh". A read(2) will return the "count"
         * value to userspace, and will reset "count" to zero. The kernel
         * side eventfd_signal() also, adds to the "count" counter and
         * issue a wakeup.
         */
        __u64 count;
        unsigned int flags;
};
```

* kref: 用于管理该对象。<br/>
 > NOTE:
 >
 > 这里可以想一个问题，什么时候会用到该计数 ? 用户态的行为
 > 不会用到, 因为用户态都是基于vfs的接口访问，vfs会维护这些东西，那么
 > 只有内核侧会用到, 这里我们先不展开来看，在 irqfd的章节中会讲到。
* wqh : 用于通知等待的进程。主要有以下几种情况:
    + 用于poll 监听 EPOLLIN 事件(write事件)
    + 用于poll 监听 EPOLLOUT 事件(read事件)
    + 在read操作时，如果count = 0, 然后文件没有设置`O_NONBLOCK`, 
     则会加入等待队列，以`TASK_INTERRUPTITBLE`睡眠，如果别的
     进程调用write, 则会唤醒该进程
    + 在write操作时，如果`count + write_count_this_time >= ULLONG_MAX`, 
     则会加入等待队列，以`TASK_INTERRUPTITBLE`睡眠，如果别的
     进程调用read, 则会唤醒该进程
* flags : 该对象的一些标志位, 目前标志位有:
```cpp
#define EFD_SEMAPHORE (1 << 0)                                     
#define EFD_CLOEXEC O_CLOEXEC                                      
#define EFD_NONBLOCK O_NONBLOCK                                    
                                                                   
#define EFD_SHARED_FCNTL_FLAGS (O_CLOEXEC | O_NONBLOCK)            
#define EFD_FLAGS_SET (EFD_SHARED_FCNTL_FLAGS | EFD_SEMAPHORE)     
```
* EFD_SEMAPHORE : eventfd 独有的，使其读取操作类似于信号量，每次
 只 减1
* EFD_CLOEXEC, EFD_NONBLOCK: 会在 eventfd系统调用中，创建vfs fd，设置
 `file->f_flags`

## fops
### fd create -- syscall eventfd
以 syscall.eventfd2为例:
```cpp
SYSCALL_DEFINE2(eventfd2, unsigned int, count, int, flags)
{
        return do_eventfd(count, flags);
}
static int do_eventfd(unsigned int count, int flags)
{
        struct eventfd_ctx *ctx;
        int fd;

        /* Check the EFD_* constants for consistency.  */
        //====================(1)=======================
        BUILD_BUG_ON(EFD_CLOEXEC != O_CLOEXEC);
        BUILD_BUG_ON(EFD_NONBLOCK != O_NONBLOCK);

        //====================(2)=======================
        if (flags & ~EFD_FLAGS_SET)
                return -EINVAL;

        //====================(3)=======================
        ctx = kmalloc(sizeof(*ctx), GFP_KERNEL);
        if (!ctx)
                return -ENOMEM;

        //====================(4)=======================
        kref_init(&ctx->kref);
        init_waitqueue_head(&ctx->wqh);
        ctx->count = count;
        ctx->flags = flags;

        //====================(5)=======================
        fd = anon_inode_getfd("[eventfd]", &eventfd_fops, ctx,
                              O_RDWR | (flags & EFD_SHARED_FCNTL_FLAGS));
        if (fd < 0)
                eventfd_free_ctx(ctx);

        return fd;
}
```
该流程非常简单清晰:
1. 因为 `EFD_CLOEXEC`, `EFD_NONBLOCK`, 最终要给vfs file->f_flags使用，所以必须
保证两者值相同
2. 检测是否出现了上面定义的3个标志位以外的标志位
3. 分配 eventfd_ctx 对象
4. 进行初始化，其中count 可以通过用户态传入
5. 通过`anon_inode_getfd`, 创建匿名的inode, 其中文件属性是`O_RDWR`

### write -- eventfd_write
```cpp
static ssize_t eventfd_write(struct file *file, const char __user *buf, size_t count,
                             loff_t *ppos)
{
        struct eventfd_ctx *ctx = file->private_data;
        ssize_t res;
        __u64 ucnt;
        DECLARE_WAITQUEUE(wait, current);
        
        //===================(1)======================
        if (count < sizeof(ucnt))
                return -EINVAL;
        if (copy_from_user(&ucnt, buf, sizeof(ucnt)))
                return -EFAULT;
        if (ucnt == ULLONG_MAX)
                return -EINVAL;
        //===================(2)======================
        spin_lock_irq(&ctx->wqh.lock);
        res = -EAGAIN;
        //===================(3)======================
        if (ULLONG_MAX - ctx->count > ucnt)
                res = sizeof(ucnt);
        else if (!(file->f_flags & O_NONBLOCK)) {
        //===================(4)======================
                __add_wait_queue(&ctx->wqh, &wait);
                for (res = 0;;) {
                        set_current_state(TASK_INTERRUPTIBLE);
                        if (ULLONG_MAX - ctx->count > ucnt) {
                                res = sizeof(ucnt);
                                break;
                        }
                        if (signal_pending(current)) {
                                res = -ERESTARTSYS;
                                break;
                        }
                        spin_unlock_irq(&ctx->wqh.lock);
                        schedule();
                        spin_lock_irq(&ctx->wqh.lock);
                }
                __remove_wait_queue(&ctx->wqh, &wait);
                __set_current_state(TASK_RUNNING);
        }
        //===================(5)======================
        if (likely(res > 0)) {
                ctx->count += ucnt;
                if (waitqueue_active(&ctx->wqh))
                        wake_up_locked_poll(&ctx->wqh, EPOLLIN);
        }
        spin_unlock_irq(&ctx->wqh.lock);

        return res;
}
```
1. 这里要求用户态传入的count < sizeof(u64)，但是从后面copy_from_user的参数来看，
copy的大小是 sizeof(u64), 并不是count
2. 加锁，这里不仅仅是锁住队列，还有eventfd_ctx->count
3. 如果 `count_from_user + ctx->count >= ULLONG_MAX`, 则需要等待读者读取事件，释放
计数资源, 这里会将该进程的`wait_queue_entry`加入等待队列，并退出调度，等待环境。
4. 如果3中的条件不满足，则会将ctx->count加上`count_from_user`, 并查看等待队列中是否
进程等待，如果有，则去唤醒。
5. 检测上面的流程是否有问题(res > 0), 如果没有问题，说明write操作完成(更新了ctx->count)
这时需要通知等待队列中的进程，以`EPOLLIN` 为key
> NOTE:
>
> 这里只想唤醒，EPOLL 等待的

### read -- event_read
```cpp
static ssize_t eventfd_read(struct file *file, char __user *buf, size_t count,
                        ¦   loff_t *ppos)
{
        struct eventfd_ctx *ctx = file->private_data;
        ssize_t res;
        __u64 ucnt = 0;
        DECLARE_WAITQUEUE(wait, current);

        if (count < sizeof(ucnt))
                return -EINVAL;

        spin_lock_irq(&ctx->wqh.lock);
        res = -EAGAIN;
        //===============(1)=======================
        if (ctx->count > 0)
                res = sizeof(ucnt);
        //===============(1.1)=======================
        else if (!(file->f_flags & O_NONBLOCK)) {
                __add_wait_queue(&ctx->wqh, &wait);
                for (;;) {
                        set_current_state(TASK_INTERRUPTIBLE);
                        if (ctx->count > 0) {
                                res = sizeof(ucnt);
                                break;
                        }
                        if (signal_pending(current)) {
                                res = -ERESTARTSYS;
                                break;
                        }
                        spin_unlock_irq(&ctx->wqh.lock);
                        schedule();
                        spin_lock_irq(&ctx->wqh.lock);
                }
                __remove_wait_queue(&ctx->wqh, &wait);
                __set_current_state(TASK_RUNNING);
        }
        //===============(2)=======================
        if (likely(res > 0)) {
                eventfd_ctx_do_read(ctx, &ucnt);
                if (waitqueue_active(&ctx->wqh))
                        wake_up_locked_poll(&ctx->wqh, EPOLLOUT);
        }
        spin_unlock_irq(&ctx->wqh.lock);

        if (res > 0 && put_user(ucnt, (__u64 __user *)buf))
                return -EFAULT;

        return res;
}
```
流程和`eventfd_write`很像.
1. 如果`ctx->count > 0`, 说明有事件，不然，在`file->f_flags`, 没有
设置`O_NONBLOCK`时, 会加入等待队列(`ctx->wqh`), 等待唤醒。
2. `eventfd_ctx_do_read`, 这个函数会去修改`ctx->count`, -1 或者清零。
具体流程我们下面在看，然后如果队列里面有等待的进程，以 `EPOLLOUT`,
为key唤醒。

`eventfd_ctx_do_read`: 
```cpp
void eventfd_ctx_do_read(struct eventfd_ctx *ctx, __u64 *cnt)
{
        lockdep_assert_held(&ctx->wqh.lock);
        /*
         * cnt会返回到用户态，作为本次读取的结果
         * 如果 ctx->flags 有 EFD_SEMAPHORE标志位，
         * 本次减1, 否则清零
         */
        *cnt = (ctx->flags & EFD_SEMAPHORE) ? 1 : ctx->count;
        ctx->count -= *cnt;
}
```

### poll -- eventfd_poll
了解`eventfd_poll`需要了解些poll框架的知识，我们将在其他的文档中解释，
这里我们只需要知道`fops->poll`有两个作用
1. 是为了 加入监听文件的`wait_queue_head`, 加入后，就可以触发事件回调了
2. 去检测下当前 file 是否有事件到达，如果有事件，则将事件类型作为返回值返回。

我们先来看下代码:
```cpp
static __poll_t eventfd_poll(struct file *file, poll_table *wait)
{
        struct eventfd_ctx *ctx = file->private_data;
        __poll_t events = 0;
        u64 count;

        poll_wait(file, &ctx->wqh, wait);
        /*
         * All writes to ctx->count occur within ctx->wqh.lock.  This read
         * can be done outside ctx->wqh.lock because we know that poll_wait
         * takes that lock (through add_wait_queue) if our caller will sleep.
         *
         * The read _can_ therefore seep into add_wait_queue's critical
         * section, but cannot move above it!  add_wait_queue's spin_lock acts
         * as an acquire barrier and ensures that the read be ordered properly
         * against the writes.  The following CAN happen and is safe:
         *
         *     poll                               write
         *     -----------------                  ------------
         *     lock ctx->wqh.lock (in poll_wait)
         *     count = ctx->count
         *     __add_wait_queue
         *     unlock ctx->wqh.lock
         *                                        lock ctx->qwh.lock
         *                                        ctx->count += n
         *                                        if (waitqueue_active)
         *                                          wake_up_locked_poll
         *                                        unlock ctx->qwh.lock
         *     eventfd_poll returns 0
         *
         * but the following, which would miss a wakeup, cannot happen:
         *
         *     poll                               write
         *     -----------------                  ------------
         *     count = ctx->count (INVALID!)
         *                                        lock ctx->qwh.lock
         *                                        ctx->count += n
         *                                        **waitqueue_active is false**
         *                                        **no wake_up_locked_poll!**
         *                                        unlock ctx->qwh.lock
         *     lock ctx->wqh.lock (in poll_wait)
         *     __add_wait_queue
         *     unlock ctx->wqh.lock
         *     eventfd_poll returns 0
         */
        count = READ_ONCE(ctx->count);
        
        if (count > 0)
                events |= EPOLLIN;
        if (count == ULLONG_MAX)
                events |= EPOLLERR;
        if (ULLONG_MAX - 1 > count)
                events |= EPOLLOUT;
        
        return events;
}
static inline void poll_wait(struct file * filp, wait_queue_head_t * wait_address, poll_table *p)
{
        if (p && p->_qproc && wait_address)
                p->_qproc(filp, wait_address, p);
}
```
这里 `poll_table`, 是调用者传过来的，里面有两个成员
```cpp
typedef struct poll_table_struct {
        poll_queue_proc _qproc;
        __poll_t _key;
} poll_table;
```

`_qproc`函数负责，将调用者的 `wait_queue_entry_t`加入 `wait_address`(wait_queue_head_t).
调用完成后，file 就可以进行事件通知了。`_key`则表示，该poll_table 是否需要事件过滤的类型。
(需不需要过滤由wakeup函数决定, 也就是调用方决定)

而在`poll_wait`调用完成后 (`eventfd_poll`, 可能会多次调用，去检测是否有事件到达，
而`p->_qproc`, 又是一个初始化函数, 所以一般在调用一次后，会将该指针置为NULL).
会检测是否有事件到达, 判断逻辑在上面read,write接口解释


#  参考资料
[Linux fd 系列 — eventfd 是什么？](https://blog.csdn.net/EDDYCJY/article/details/118980819)
