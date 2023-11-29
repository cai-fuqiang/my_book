# ORG PATCH

我们首先看下最初的patch, 但是我并没有找到最终的MAIL LIST,
只找到了一个中间版本:

[\[PATCH 23/32\] Generic dynamic per cpu refcounting](https://lore.kernel.org/all/1356573611-18590-26-git-send-email-koverstreet@google.com/)


我们还是先看下 COMMIT MESSAGE:
```
commit 215e262f2aeba378aa192da07c30770f9925a4bf
Author: Kent Overstreet <koverstreet@google.com>
Date:   Fri May 31 15:26:45 2013 -0700

    percpu: implement generic percpu refcounting

    This implements a refcount with similar semantics to
    atomic_get()/atomic_dec_and_test() - but percpu.

    这实现了一个具有类似 atomic_get()/atomic_dec_and_test()语义
    的 refcount -- 但是是precpu的

    It also implements two stage shutdown, as we need it to tear down the
    percpu counts.  Before dropping the initial refcount, you must call
    percpu_ref_kill(); this puts the refcount in "shutting down mode" and
    switches back to a single atomic refcount with the appropriate
    barriers (synchronize_rcu()).

    tear down : 拆除,拆毁
    as: 因为;作为;如同; 和...一样

    它也实现了 two stage shutdown, 因为我们需要它来销毁 percpu counts.
    在drop 到原始的 refcount之前,  你必须调用 percpu_ref_kill(); 这将
    refcount 置为 "shutting down mode" 并且 使用 适当的 barriers 将其转换
    到一个 single atomic refcount.

    It's also legal to call percpu_ref_kill() multiple times - it only
    returns true once, so callers don't have to reimplement shutdown
    synchronization.

    调用 percpu_ref_kill() 多次也是合法的 - 它只能返回一次true, 所以调用者
    不必重新实现 shutdown synchronization(关闭同步)
```


#



# TMP

`include/linux/percpu-refcount.h`注释:
```
/*
 * Percpu refcounts:
 * (C) 2012 Google, Inc.
 * Author: Kent Overstreet <koverstreet@google.com>
 *
 * This implements a refcount with similar semantics to atomic_t - atomic_inc(),
 * atomic_dec_and_test() - but percpu.
 *
 * There's one important difference between percpu refs and normal atomic_t
 * refcounts; you have to keep track of your initial refcount, and then when you
 * start shutting down you call percpu_ref_kill() _before_ dropping the initial
 * refcount.
 *
 * 在percpu refs和normal atomic_t refcount之间有一个重要的不同之处; 你需要跟踪
 * 你的初始的 refcount, 并且当你开始shutting down时, 你需要在drop initial refcount
 * 之前 调用 percpu_ref_kill()
 *
 * The refcount will have a range of 0 to ((1U << 31) - 1), i.e. one bit less
 * than an atomic_t - this is because of the way shutdown works, see
 * percpu_ref_kill()/PCPU_COUNT_BIAS.
 *
 * refcount 的range 在 [0, (1<<31) -1], 也就是说, 比 atomic_t 少了一个 bit --
 * 这是由于 shutdown 的工作方式, 请见 percpu_ref_kill() / PCPU_COUNT_BIAS
 *
 * Before you call percpu_ref_kill(), percpu_ref_put() does not check for the
 * refcount hitting 0 - it can't, if it was in percpu mode. percpu_ref_kill()
 * puts the ref back in single atomic_t mode, collecting the per cpu refs and
 * issuing the appropriate barriers, and then marks the ref as shutting down so
 * that percpu_ref_put() will check for the ref hitting 0.  After it returns,
 * it's safe to drop the initial ref.
 *
 * 在你调用 percpu_ref_kill()之前, percpu_ref_put() 不会检查refcount 是否 hit
 * 到了0 - 如果是在 percpu mode中, 他不能这样. percpu_ref_kill() 会将ref 转换
 * 到 single atomic_t mode, 收集 per cpu refs 并且 提交适当的e barriers, 并且
 * 标记 ref 作为 shutting down的状态, 以便 percpu_ref_put() 将检查 ref 是否hit
 * 到0. 当它返回是, 他是可以安全的 drop initial ref
 *
 * USAGE:
 *
 * See fs/aio.c for some example usage; it's used there for struct kioctx, which
 * is created when userspaces calls io_setup(), and destroyed when userspace
 * calls io_destroy() or the process exits.
 *
 * 请看 fs/aio.c 了解一些示例用法: 他被用于 struct kioctx, 这个被用户态通过调用
 * io_setup()创建,并且当用户态调用 io_destroy 或者程序退出时销毁.
 *
 * In the aio code, kill_ioctx() is called when we wish to destroy a kioctx; it
 * calls percpu_ref_kill(), then hlist_del_rcu() and sychronize_rcu() to remove
 * the kioctx from the proccess's list of kioctxs - after that, there can't be
 * any new users of the kioctx (from lookup_ioctx()) and it's then safe to drop
 * the initial ref with percpu_ref_put().
 *
 * 在 aio 的代码中, 当我们想要销毁一个 kioctx时, kill_ioctx() 被调用; 他调用
 * precpu_ref_kill(), 然后调用hlist_del_rcu() 和 sychronizert_rcu()  来 remove
 * 从进程的 kioctxs链中 移除kioctx (在 lookup_ioctx()) 并且他将用 percpu_ref_put()
 * 安全的 drop initial ref.
 *
 * Code that does a two stage shutdown like this often needs some kind of
 * explicit synchronization to ensure the initial refcount can only be dropped
 * once - percpu_ref_kill() does this for you, it returns true once and false if
 * someone else already called it. The aio code uses it this way, but it's not
 * necessary if the code has some other mechanism to synchronize teardown.
 * around.
 *
 * 像这样进行两个阶段的shutdown 的代码通常需要某种 显示的同步,来确保 initial 
 * refcount 只能被drop 一次 - percpu_ref_kill() 就为你做了这个事情, 它只return true
 * 一次, 其他人如果也调用它时会返回false. aio 也是这样的方式使用, 但是没有必要
 * 通过其他机制来同步 teardown
 */
```
