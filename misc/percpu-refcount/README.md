# 简介
我们简单想一下,为什么需要`percpu-ref`, `refcount`原本的目的
是计数, 需要在销毁的时候, 判断其是否还有其他人在使用,
如果有人在使用, 那么销毁动作会在其他使用者执行put时, 
直到 `refcount -> 0`时, 才会发生.

那么, 这里其实有一个出发点, 就是`refcount`主要是用于object
的销毁. 那么销毁动作大多也是有一个出发点, 例如删除file, 
只有当我们在用户态执行类似于`rm -f`命令时,才会发生, 那么
在该命令执行之前, 我们实际上不会去关心该值. 

但是, 在我们正常引用object时, 需要去操作count, 首先,可能
多个cpu都会操作refcount, 这就会引起cacheline 抖动, 另外,
该refcount是atomic的, 会锁数据总线, 性能也会降低.

google一位工程师`koverstreet`, 通过下面我们讲到的patch 解决了
这一问题, 方法也很简单.

就是我们一般情况下, 操作refcount, 都是操作`percpu refcount`, 
但是当销毁动作触发时(这时需要调用一个 `kill` 的接口), 这时
将`percpu refcount` 转换到 `atomic refcount`. 这样做, 在销毁
之前去操作refcount 由于是 percpu的, 就避免了上面提到的那些
问题. 


我们先看看下最初的patch
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


我们先来看下数据结构
## 数据结构
```cpp
struct percpu_ref;
typedef void (percpu_ref_release)(struct percpu_ref *);

struct percpu_ref {
       atomic_t                count;
       /*
        * The low bit of the pointer indicates whether the ref is in percpu
        * mode; if set, then get/put will manipulate the atomic_t (this is a
        * hack because we need to keep the pointer around for
        * percpu_ref_kill_rcu())
        */

       /*
        * manipulate [məˈnɪpjuleɪt]: 操作, 操纵
        * 
        * 该指针的 low bit 表示 ref是否在 percpu mode中; 如果设置了, get/put 将会
        * 操作 atomic_t( 这是一个hack, 因为我们需要为percpu_ref_kill_rcu()保持
        * 该指针 )
        *
        * NOTE
        *
        * 这里的 hack是啥意思 ???
        */
       unsigned __percpu       *pcpu_count;
       percpu_ref_release      *release;
       struct rcu_head         rcu;
};
```
* **count** : 为atomic类型, single atomic refcount
* **pcpu_count**: percpu refcount, 但是low bit表示是否在 percpu mode中, 我们来看下相关定义
  ```
  #define PCPU_STATUS_BITS       2
  #define PCPU_STATUS_MASK       ((1 << PCPU_STATUS_BITS) - 1)
  #define PCPU_REF_PTR           0
  #define PCPU_REF_DEAD          1
  
  #define REF_STATUS(count)      (((unsigned long) count) & PCPU_STATUS_MASK)
  ```

  可以看到虽然预留了两位,但是实际上就使用了一位(bit0)
  + PCPU_REF_PTR  (0) : 在使用percpu mode
  + PCPU_REF_DEAD (1) : 在使用atomic mode

* **release**: 销毁函数
* **rcu**: 使用rcu机制来完成, percpu mode -> atomic mode 的转换,下面会详细介绍

接下来, 我们来看类似于`atomic_get()`, `atomic_dec_and_test()` 这样的percpu 版本
## PERCPU get/set
```cpp
//============FILE : include/linux/percpu-refcount.h =========
/**
 * percpu_ref_get - increment a percpu refcount
 *
 * Analagous to atomic_inc().
  */
static inline void percpu_ref_get(struct percpu_ref *ref)
{
       unsigned __percpu *pcpu_count;

       //=========(1?)==========
       preempt_disable();

       //=========(2?)==========
       pcpu_count = ACCESS_ONCE(ref->pcpu_count);
       //=========(1)==========
       if (likely(REF_STATUS(pcpu_count) == PCPU_REF_PTR))
               __this_cpu_inc(*pcpu_count);
       else
               atomic_inc(&ref->count);

       preempt_enable();
}

/**
 * percpu_ref_put - decrement a percpu refcount
 *
 * Decrement the refcount, and if 0, call the release function (which was passed
 * to percpu_ref_init())
 */
static inline void percpu_ref_put(struct percpu_ref *ref)
{
       unsigned __percpu *pcpu_count;

       preempt_disable();

       pcpu_count = ACCESS_ONCE(ref->pcpu_count);

       if (likely(REF_STATUS(pcpu_count) == PCPU_REF_PTR))
               __this_cpu_dec(*pcpu_count);
       //=========(2)==========
       else if (unlikely(atomic_dec_and_test(&ref->count)))
               ref->release(ref);

       preempt_enable();
}
```
1. 无论是get/set, 对于是否操作percpu 还是atomic 成员, 都有一样
   的判断逻辑: 

   判断 `PCPU_STATUS_BITS` 是否是 `PCPU_REF_PTR`

   如果为真, 则操作 percpu ref, 如果是假, 操作atomic ref
2. 在执行put操作时, 如果操作的是 atomic ref, 当refcount降低为0 时, 
   会执行 `ref->release()`

???<br/>
???<br/>
???<br/>
这里有两点疑问: 
1. 为什么关闭抢占?
2. ACCESS_ONCE() 的作用

头文件中除了这两个接口, 还有两个:
```cpp
int percpu_ref_init(struct percpu_ref *, percpu_ref_release *);
void percpu_ref_kill(struct percpu_ref *ref);
```

在`lib/percpu-refcount.c`中定义, 我们来看下

## percpu_ref_init
```cpp
//========(1.1)========
#define PCPU_COUNT_BIAS                (1U << 31)
/**
 * percpu_ref_init - initialize a percpu refcount
 * @ref:       ref to initialize
 * @release:   function which will be called when refcount hits 0
 *
 * Initializes the refcount in single atomic counter mode with a refcount of 1;
 * analagous to atomic_set(ref, 1).
 *
 * Note that @release must not sleep - it may potentially be called from RCU
 * callback context by percpu_ref_kill().
 */
int percpu_ref_init(struct percpu_ref *ref, percpu_ref_release *release)
{
       //========(1)========
       atomic_set(&ref->count, 1 + PCPU_COUNT_BIAS);

       //========(2)========
       ref->pcpu_count = alloc_percpu(unsigned);
       if (!ref->pcpu_count)
               return -ENOMEM;

       //========(3)========
       ref->release = release;
       return 0;
}
```
1. 这里在初始化, atomic ref, 注意,这里给的初值不是1, 而是 `1 + PCPU_COUNT_BIAS`, 是为了
   防止在kill之后, 在rcu callback之前, 会让 atomic ref hitting 0, 从而错误的释放object, 
   我们在 介绍完`percpu_ref_kill_rcu()`之后, 再详细举例说明
2. 这里需要注意的是alloc_percpu()申请到的percpu variable, 会被初始化为0
3. 设置 object release callbak `ref->release`.

## percpu_ref_kill
```cpp
/**
 * percpu_ref_kill - safely drop initial ref
 *
 * Must be used to drop the initial ref on a percpu refcount; must be called
 * precisely once before shutdown.
 *
 * Puts @ref in non percpu mode, then does a call_rcu() before gathering up the
 * percpu counters and dropping the initial ref.
 */
void percpu_ref_kill(struct percpu_ref *ref)
{
        unsigned __percpu *pcpu_count, *old, *new;

        pcpu_count = ACCESS_ONCE(ref->pcpu_count);
        //=========(1)==========
        do {
                if (REF_STATUS(pcpu_count) == PCPU_REF_DEAD) {
                        WARN(1, "percpu_ref_kill() called more than once!\n"); 
                        return;
                }

                old = pcpu_count;
                new = (unsigned __percpu *)
                        (((unsigned long) pcpu_count)|PCPU_REF_DEAD);

                pcpu_count = cmpxchg(&ref->pcpu_count, old, new);
        } while (pcpu_count != old);

        //=========(2)==========
        call_rcu(&ref->rcu, percpu_ref_kill_rcu);
}
```
1. 这里的循环就是在执行`cmpxchg()`, 为什么这里有race呢, 在一般情况下,
   大家都是只读`ref->pcpu_count`(这里并不是说只读 percpu变量,而是
   只读该指针,而这里就是要操作这个指针), 但是在多个cpu 都执行`percpu_ref_kill()`
   时,就会有race, 这里就是为了保证只有一个人, 能够执行`call_rcu`, 
   其他的cpu 直接打一个警告,然后返回.
   > NOTE
   >
   > 这里打印警告的意思是, 不应该有多个流程都会执行到kill, 理论上来说只有
   > 一个发起者去drop initial ref
2. 调用call_rcu 去释放指针中的percpu 变量

   这里就是使用了rcu的机制, 先将`pcpu_count`设置为`PCPU_REF_DEAD`, 这样就不会
   有后续的cpu再去操作 percpu refcount, 也就不会在访问`ref->pcpu_count`
   指针, 而是去操作atomic refcount -- `ref->count`

   然后, 在宽限期中将 `ref->pcpu_count` 引用的percpu object释放.

接下来, 我们分析下 `percpu_ref_kill_rcu()`这个rcu callbak

## percpu_ref_kill_rcu
```cpp
/**
 * percpu_ref_kill - safely drop initial ref
 *
 * Must be used to drop the initial ref on a percpu refcount; must be called
 * precisely once before shutdown.
 *
 * Puts @ref in non percpu mode, then does a call_rcu() before gathering up the
 * percpu counters and dropping the initial ref.
 */
static void percpu_ref_kill_rcu(struct rcu_head *rcu)
{
        struct percpu_ref *ref = container_of(rcu, struct percpu_ref, rcu);
        unsigned __percpu *pcpu_count;
        unsigned count = 0;
        int cpu;

        pcpu_count = ACCESS_ONCE(ref->pcpu_count);

        //=========(1)==========
        /* Mask out PCPU_REF_DEAD */
        pcpu_count = (unsigned __percpu *)
                (((unsigned long) pcpu_count) & ~PCPU_STATUS_MASK);

        //=========(2)==========
        for_each_possible_cpu(cpu)
                count += *per_cpu_ptr(pcpu_count, cpu);

        //=========(3)==========
        free_percpu(pcpu_count);

        pr_debug("global %i pcpu %i", atomic_read(&ref->count), (int) count);

        /*
         * It's crucial that we sum the percpu counters _before_ adding the sum
         * to &ref->count; since gets could be happening on one cpu while puts
         * happen on another, adding a single cpu's count could cause
         * @ref->count to hit 0 before we've got a consistent value - but the
         * sum of all the counts will be consistent and correct.
         *
         * 我们先将percpu counters相加,然后在加到 &ref->count中是十分重要的;
         * 因为可能在一个cpu上会执行get, 在另外一个cpu 上会执行put, 如果将单独的一个
         * cpu的count 加到 @ref->count上, 可能会导致该变量hit到0 (在我们得到一个
         * consistent value之前 - 但是将所有count的相加, 将会是 consistent和正确的
         *
         * Subtracting the bias value then has to happen _after_ adding count to
         * &ref->count; we need the bias value to prevent &ref->count from
         * reaching 0 before we add the percpu counts. But doing it at the same
         * time is equivalent and saves us atomic operations:
         *
         * 减去 bias value 这个动作必须在 adding count to &ref->count之后; 我们需要
         * 这个bias 来防止 在我们加上 percpu count之前, &ref->count 到达0. 但是, 
         * 同时做这个是等价的(等价于先加percpu count在减 bias value???), 并且节省
         * 我们的原子操作. 
         */

        //=========(4)==========
        atomic_add((int) count - PCPU_COUNT_BIAS, &ref->count);

        /*
         * Now we're in single atomic_t mode with a consistent refcount, so it's
         * safe to drop our initial ref:
         */
        //=========(5)==========
        percpu_ref_put(ref);
}
```
> NOTE
>
> 这时候已经在宽限期中, 所以所有的操作都不会和读者竞争

1. 获取 percpu 指针
2. 将所有cpu 的 `pcpu_count`相加(这里注释中有说明为什么这么做)
3. free percpu object
4. 将count 加到 ref->count上, 但是要减去`PCPU_COUNT_BIAS`. (注释中已经讲的很清楚了, 
   我们下面会举个例子)

我们这里来举两个反例,对应注释中的两段:

1. 我们举个例子, 不一次加,一个个的加, 这里简单的将refcount假设初始为1
   <font size = 1>
   ```
   初始状态: ref = 1, pcpu0 = 0, pcpu1 = 0, pcpu2 = 0

   cpu 0                    cpu1                    cpu2                    cpu - kill
   put_pcpu: pcpu0=-1
                            get_pcpu: pcpu1 = 1
                                                    get_pcpu:pcpu =1
                                                    
                                                                            触发kill, 并且触发了rcu kill
                                                                            一个个加先加 pcpu0, ref = 0
                                                                                    再加 pcpu1, ref = 1
                                                                            (kill未完成,还有initial refcount未put)
   put_atomic: ref = 0, release
   ```
   </font>

   可以看到, 这时get两次,put两次,但是还有一个initial refcount未put 结果却释放了节点
2. 我们再来看看如果init时候, atomic refcount 初始为1
   ```
   初始状态: ref = 1, pcpu0 = 0, pcpu_1 = 0

   cpu0                                 cpu1
   get_pcpu: pcpu0=1                    
                                        kill:(这时还未执行rcu kill)
   put_atomic: ref = 0, release
                                        kill_rcu
   ```

   可以看到, 在这种情况下, kill_rcu还未执行 put initial refcount时, 该object已经被
   释放了

   所以, 作者相当于牺牲了 refcount的一位(`PCPU_COUNT_BIAS`) 第31位, 来让 atomic
   ref在kill之前很大, 这样就不会put到0了.


# confirm kill

COMMIT MESSAGE
```
commit dbece3a0f1ef0b19aff1cc6ed0942fec9ab98de1
Author: Tejun Heo <tj@kernel.org>
Date:   Thu Jun 13 19:23:53 2013 -0700

    percpu-refcount: implement percpu_tryget() along with percpu_ref_kill_and_confirm()

    Implement percpu_tryget() which stops giving out references once the
    percpu_ref is visible as killed.  Because the refcnt is per-cpu,
    different CPUs will start to see a refcnt as killed at different
    points in time and tryget() may continue to succeed on subset of cpus
    for a while after percpu_ref_kill() returns.

    subset: 子集

    实现 percpu_tryget(), 一旦 percpu_ref 已经被观测到 killed , 它将停止
    再次发生 references(引用). 因为 refcnt 是 per-cpu的, 不同的 CPUs 将会
    在不同的时间点看到 refcnt 被终止 并且 tryget() 可能在 percpu_ref_kill()
    后在某些cpu上仍然能返回成功.

    For use cases where it's necessary to know when all CPUs start to see
    the refcnt as dead, percpu_ref_kill_and_confirm() is added.  The new
    function takes an extra argument @confirm_kill which is invoked when
    the refcnt is guaranteed to be viewed as killed on all CPUs.

    invoke: 调用,使产生,唤起,引起,提及, 提出

    为了支持那些需要知道在何时 所有的CPPUs已经看到 refcnt 已经dead 来说, 
    增加了 percpu_ref_kill_and_confirm(). 这个心函数带有一个额外的参数
    @confirm_kill , 该参数在 refcnt 已经保证被所有的cpus已经可以被看到
    是killed 状态时, 会被调用.

    While this isn't the prettiest interface, it doesn't force synchronous
    wait and is much safer than requiring the caller to do its own
    call_rcu().
    
    现在,这不是最漂亮的 interface, 他不强制同步等待 并且比要求调用者自己
    调用call_rcu()要更安全.

    v2: Patch description rephrased to emphasize that tryget() may
        continue to succeed on some CPUs after kill() returns as suggested
        by Kent.

    v3: Function comment in percpu_ref_kill_and_confirm() updated warning
        people to not depend on the implied RCU grace period from the
        confirm callback as it's an implementation detail.
```


数据结构变动

```diff

diff --git a/include/linux/percpu-refcount.h b/include/linux/percpu-refcount.h
index 6d843d60690d..dd2a08600453 100644
--- a/include/linux/percpu-refcount.h
+++ b/include/linux/percpu-refcount.h
@@ -63,13 +63,30 @@ struct percpu_ref {
         */
        unsigned __percpu       *pcpu_count;
        percpu_ref_func_t       *release;
+       percpu_ref_func_t       *confirm_kill;
        struct rcu_head         rcu;
 };
```

接口变动:
* 增加`percpu_ref_tryget()` 接口
  ```cpp
  /**
   * percpu_ref_tryget - try to increment a percpu refcount
   * @ref: percpu_ref to try-get
   *
   * Increment a percpu refcount unless it has already been killed.  Returns
   * %true on success; %false on failure.
   *
   * 除非 它已经被kill了, 否则增加 percpu refcount.
   *
   * Completion of percpu_ref_kill() in itself doesn't guarantee that tryget
   * will fail.  For such guarantee, percpu_ref_kill_and_confirm() should be
   * used.  After the confirm_kill callback is invoked, it's guaranteed that
   * no new reference will be given out by percpu_ref_tryget().
   *
   * percpu_ref_kill() 他自己执行完成, 不能保证 tryget() 将会失败. 如果想要
   * 这个保证,应该使用 percpu_ref_kill_and_confirm(). 当 confirm_kill() callback
   * 被调用, 他保证 percpu_ref_tryget() 不会产生新的引用.
   */
  static inline bool percpu_ref_tryget(struct percpu_ref *ref)
  {
         unsigned __percpu *pcpu_count;
         int ret = false;
  
         rcu_read_lock();
  
         pcpu_count = ACCESS_ONCE(ref->pcpu_count);
  
         if (likely(REF_STATUS(pcpu_count) == PCPU_REF_PTR)) {
                 __this_cpu_inc(*pcpu_count);
                 ret = true;
         }
  
         rcu_read_unlock();
  
         return ret;
  }
  ```
* 增加 `percpu_ref_kill_and_confirm`接口
  ```diff
  /*
   * percpu_ref_kill_and_confirm - drop the initial ref and schedule confirmation
   * @ref: percpu_ref to kill
   * @confirm_kill: optional confirmation callback
   *
   * Equivalent to percpu_ref_kill() but also schedules kill confirmation if
   * @confirm_kill is not NULL.  @confirm_kill, which may not block, will be
   * called after @ref is seen as dead from all CPUs - all further
   * invocations of percpu_ref_tryget() will fail.  See percpu_ref_tryget()
   * for more details.
   *
   * Equivalent: 相同的,等价的
   *
   * 和percpu_ref_kill()相同, 但是在 会调用 kill confirmation 如果 @ confirm_kill
   * 不是空. @confirm_kill, 不能阻塞, 将会在@ref被所有cpu看为dead的情况下调用 -- 
   * 所有未来 percpu_ref_tryget()调用都会失败. 请看 percpu_ref_tryget()
   * 了解更多细节
   *
   * Due to the way percpu_ref is implemented, @confirm_kill will be called
   * after at least one full RCU grace period has passed but this is an
   * implementation detail and callers must not depend on it.
   *
   * 由于 percpu_ref 实现的方式, @confirm_kill 将被在至少在一个完整的RCU 宽限期
   * 过去后在调用, 但是调用者不能依赖它.
   */
  -void percpu_ref_kill(struct percpu_ref *ref)
  +void percpu_ref_kill_and_confirm(struct percpu_ref *ref,
  +                                percpu_ref_func_t *confirm_kill)
   {
          WARN_ONCE(REF_STATUS(ref->pcpu_count) == PCPU_REF_DEAD,
                    "percpu_ref_kill() called more than once!\n");
  
          ref->pcpu_count = (unsigned __percpu *)
                  (((unsigned long) ref->pcpu_count)|PCPU_REF_DEAD);
  +       ref->confirm_kill = confirm_kill;
  
          call_rcu(&ref->rcu, percpu_ref_kill_rcu);
   }

  ```
* 修改原本`percpu_ref_kill()`流程
  ```cpp
  /**
   * percpu_ref_kill - drop the initial ref
   * @ref: percpu_ref to kill
   *
   * Must be used to drop the initial ref on a percpu refcount; must be called
   * precisely once before shutdown.
   *
   * Puts @ref in non percpu mode, then does a call_rcu() before gathering up the
   * percpu counters and dropping the initial ref.
   */
  static inline void percpu_ref_kill(struct percpu_ref *ref)
  {
         return percpu_ref_kill_and_confirm(ref, NULL);
  }
  ```
* 修改`percpu_ref_kill_rcu()`流程, 增加对`@confirm_kill`的调用
  ```diff
   /**
    * percpu_ref_put - decrement a percpu refcount
    * @ref: percpu_ref to put
  diff --git a/lib/percpu-refcount.c b/lib/percpu-refcount.c
  index ebeaac274cb9..8bf9e719cca0 100644
  --- a/lib/percpu-refcount.c
  +++ b/lib/percpu-refcount.c
  @@ -118,6 +118,10 @@ static void percpu_ref_kill_rcu(struct rcu_head *rcu)
  
          atomic_add((int) count - PCPU_COUNT_BIAS, &ref->count);
  
  +       /* @ref is viewed as dead on all CPUs, send out kill confirmation */
  +       if (ref->confirm_kill)
  +               ref->confirm_kill(ref);
  +
          /*
           * Now we're in single atomic_t mode with a consistent refcount, so it's
           * safe to drop our initial ref:
  @@ -126,22 +130,29 @@ static void percpu_ref_kill_rcu(struct rcu_head *rcu)
   }
  ```

这些变动,注释里面写的十分清楚, 在这里就不再赘述.
# OTHERS

## org patch `include/linux/percpu-refcount.h`注释:
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

## org patch `lib/percpu-refcount.c`注释
```
#define pr_fmt(fmt) "%s: " fmt "\n", __func__

#include <linux/kernel.h>
#include <linux/percpu-refcount.h>

/*
 * Initially, a percpu refcount is just a set of percpu counters. Initially, we
 * don't try to detect the ref hitting 0 - which means that get/put can just
 * increment or decrement the local counter. Note that the counter on a
 * particular cpu can (and will) wrap - this is fine, when we go to shutdown the
 * percpu counters will all sum to the correct value
 *
 * 最初的, percpu refcount 仅仅是一组percpu counter. 最初, 我们并不会去检测ref
 * 是否 已经 hit 到0 - 这将意味这 get/put 仅仅是 inc 或者 dec local counter.
 * 请注意, 特定cpu上的 counter 也可以(也将) wrap (封装) ???? - 这很好, 当我们
 * 关闭 percpu counters时, 所有counters 会 加到一个正确的值
 * 
 * (More precisely: because moduler arithmatic is commutative the sum of all the
 * pcpu_count vars will be equal to what it would have been if all the gets and
 * puts were done to a single integer, even if some of the percpu integers
 * overflow or underflow).
 *
 * precisely [prɪˈsaɪsli]: 准确的,精确的
 * moduler: 模块
 * arithmatic :算数
 * commutative: 交换
 *
 * ( 更准确的说: 因为 模算数运算是可交换的, 所以所有pcpu_count 值相加等于如果
 * 使用signle integer执行的 gets/puts 之后的值, 即使有些 percpu integers 向上,
 * 或者向下溢出.
 *
 * The real trick to implementing percpu refcounts is shutdown. We can't detect
 * the ref hitting 0 on every put - this would require global synchronization
 * and defeat the whole purpose of using percpu refs.
 *
 * trick [trɪk] :技巧;把戏;花招;诡计; 骗局
 * defeat: 击败 [LOL?]
 * 实现 percpu refcount 真正的 trick(这里感觉可以翻译成核心)是 shutdown. 我们不能
 * 在每次put时检测 ref 是否已经hit到 0 - 这需要全局同步, 并且这违背了使用 percpu 
 * ref的初衷.
 *
 * What we do is require the user to keep track of the initial refcount; we know
 * the ref can't hit 0 before the user drops the initial ref, so as long as we
 * convert to non percpu mode before the initial ref is dropped everything
 * works.
 * 
 * everything work: 一切正常
 *
 * 我们需要使用者去跟踪 initial refcount; 我们知道在 user drop initial ref 之前,
 * ref 不能 hit 0, 所以只要在drop initial ref之前, 转换到 non percpu mode, 那么
 * 一切将正常运行
 *
 * Converting to non percpu mode is done with some RCUish stuff in
 * percpu_ref_kill. Additionally, we need a bias value so that the atomic_t
 * can't hit 0 before we've added up all the percpu refs.
 *
 * stuff: 东西, 物品, 玩意
 * bias [ˈbaɪəs]: 偏差值
 *
 * 在 percpu_ref_kill 中使用 某些 RCUish 的某些机制 可以完成 转换到 non percpu mode.
 * 另外, 我们需要一个 bias value(偏差值) 这样我们吧所有percpu ref加起来之前, atomic_t
 * 不会hit 到 0.
 */
```
