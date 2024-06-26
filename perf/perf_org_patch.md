# perf org patch

## [PATCH] performance counters: core code -- commit message

社区patch链接:

[performance counters: core code](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=0793a61d4df8daeac6492dbf8d2f3e5713caae5e)

并没有找到相关mail list, 所以我们这里先看下 COMMIT MESSAGE

<details>
<summary> COMMIT MESSAGE </summary>

```
Implement the core kernel bits of Performance Counters subsystem.

> bits of: 一点;少量的;小块碎片的
>
> 实现 Performance Counters subsystem 的一小部分kernel 代码

The Linux Performance Counter subsystem provides an abstraction of
performance counter hardware capabilities. It provides per task and per
CPU counters, and it provides event capabilities on top of those.

> Linux Performance Counter 子系统提供 performance counter hardware 
> capabilities 的抽象。 它提供per-task和per-CPU counters，并在此基础
> 上提供event capabilities。

Performance counters are accessed via special file descriptors.
There's one file descriptor per virtual counter used.

> Performance counters 可以 通过 特殊的 FD 来访问. 每一个 使用的virtual
> counters 都有一个 FD

The special file descriptor is opened via the perf_counter_open()
system call:

> 通过 perf_counter_open() syscall 可以打开该 特殊的fd

 int
 perf_counter_open(u32 hw_event_type,
                   u32 hw_event_period,
                   u32 record_type,
                   pid_t pid,
                   int cpu);

The syscall returns the new fd. The fd can be used via the normal
VFS system calls: read() can be used to read the counter, fcntl()
can be used to set the blocking mode, etc.

> 该系统调用返回new fd. 该fd 可以使用 常规的 VFS syscall: 
>   + read() : 用于读 该 counter
>   + fcntl: 用于设置 blocking modee
>   + etc

Multiple counters can be kept open at a time, and the counters
can be poll()ed.

> 多个 counters 可以同时打开, 这些counters 可以被 poll()

See more details in Documentation/perf-counters.txt.

> Documentation/perf-counters.txt 了解更多细节.
```

</details>

***

那我们就去读下 `Documention/perf-counters.txt`文档

# [PATCH] performance counters: documentation

上面的文档也是通过这一组patch引入.

社区patch链接:

[performance counters: documentation](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=e7bc62b6b3aeaa8849f8383e0cfb7ca6c003adc6)

<details>
<summary> Documentation/perf-counters.txt </summary>

```
Performance Counters for Linux
------------------------------

Performance counters are special hardware registers available on most modern
CPUs. These registers count the number of certain types of hw events: such
as instructions executed, cachemisses suffered, or branches mis-predicted -
without slowing down the kernel or applications. These registers can also
trigger interrupts when a threshold number of events have passed - and can
thus be used to profile the code that runs on that CPU.

> Performance counters 是在大多数 modern CPUs上可获取的 special hardware 
> registers. 这些 registers 计数 某些类型的hw events 的数量, 例如:
>   + instructions executed
>   + cachemisses suffered
>   + branches mis-predicted
> 并且不会让 kernel/apps 运行变慢. 
> 当 events 数量达到了 阈值时, 这些registers  也可以出发中断. 所以可以用来
> profile(分析) 运行在该CPU上的代码.

The Linux Performance Counter subsystem provides an abstraction of these
hardware capabilities. It provides per task and per CPU counters, and
it provides event capabilities on top of those.

Performance counters are accessed via special file descriptors.
There's one file descriptor per virtual counter used.

The special file descriptor is opened via the perf_counter_open()
system call:

 int
 perf_counter_open(u32 hw_event_type,
                   u32 hw_event_period,
                   u32 record_type,
                   pid_t pid,
                   int cpu);

The syscall returns the new fd. The fd can be used via the normal
VFS system calls: read() can be used to read the counter, fcntl()
can be used to set the blocking mode, etc.

Multiple counters can be kept open at a time, and the counters
can be poll()ed.

>> +++++++++++++++++++++++++++++++++
>> 上面和commit message 重复不再翻译
>> +++++++++++++++++++++++++++++++++

When creating a new counter fd, 'hw_event_type' is one of:

> 当 创建了一个新的 counter fd, 'hw_event_type' 是下面中的一个:

 enum hw_event_types {
	PERF_COUNT_CYCLES,
	PERF_COUNT_INSTRUCTIONS,
	PERF_COUNT_CACHE_REFERENCES,
	PERF_COUNT_CACHE_MISSES,
	PERF_COUNT_BRANCH_INSTRUCTIONS,
	PERF_COUNT_BRANCH_MISSES,
 };

These are standardized types of events that work uniformly on all CPUs
that implements Performance Counters support under Linux. If a CPU is
not able to count branch-misses, then the system call will return
-EINVAL.

> uniformly /ˈjuːnɪfɔːmli/ 均匀地；一致地；一律
>
> 这些是标准化的事件类型, 在Linux 实现 Performance Counter 实现的所有
> CPUs上统一工作. 如果CPU 无法 count branch-misses, 则syscall 将返回
> -EINVAL

[ Note: more hw_event_types are supported as well, but they are CPU
  specific and are enumerated via /sys on a per CPU basis. Raw hw event
  types can be passed in as negative numbers. For example, to count
  "External bus cycles while bus lock signal asserted" events on Intel
  Core CPUs, pass in a -0x4064 event type value. ]

> [ Note: 还支持更多的 hw_event_types, 但是他们是 CPU specific 并且通过
>   在per cpu基础上的/sys进行枚举. Raw hw event 类型可以作为负数传入. 例
>   如, 为在 Intel Core CPUs 上计数 "External bus cycles while bus lock 
>   signal asserted" 事件, 可以传入 -0x4064 event type 值.

The parameter 'hw_event_period' is the number of events before waking up
a read() that is blocked on a counter fd. Zero value means a non-blocking
counter.

> 参数 'hw_event_period' 是在唤醒 阻塞在 counter fd 的read() 之前的事件数.
> Zero value 意味着一个非阻塞的 counter

'record_type' is the type of data that a read() will provide for the
counter, and it can be one of:

> 'record_type' 是read() 将为计数器提供的 数据类型, 它可以是以下之一:

  enum perf_record_type {
	PERF_RECORD_SIMPLE,
	PERF_RECORD_IRQ,
  };

a "simple" counter is one that counts hardware events and allows
them to be read out into a u64 count value. (read() returns 8 on
a successful read of a simple counter.)

"simple" counter 是计数 hardware event, 并且允许将他们读入一个 
u64 count value.(read() 在成功读取 一个 simple counter时,返回8)

An "irq" counter is one that will also provide an IRQ context information:
the IP of the interrupted context. In this case read() will return
the 8-byte counter value, plus the Instruction Pointer address of the
interrupted context.

> "irq" counter 提供了 IRQ context information: interrupt context IP.
> 在 read() 时, 将会返回 8-byte counter value, 并且加上 interrupt context
> 的 IP.

The 'pid' parameter allows the counter to be specific to a task:

 pid == 0: if the pid parameter is zero, the counter is attached to the
 current task.

 pid > 0: the counter is attached to a specific task (if the current task
 has sufficient privilege to do so)

 pid < 0: all tasks are counted (per cpu counters)

> 'pid' 参数允许 counter 指定一个task
>
>   + pid == 0: attach current task
>   + pid > 0:  specific task ( 如果当前task 有足够的权限这样做)
>   + pid < 0 : all tasks (per cpu counters)(见下面Note)

The 'cpu' parameter allows a counter to be made specific to a full
CPU:

 cpu >= 0: the counter is restricted to a specific CPU
 cpu == -1: the counter counts on all CPUs

> 'cpu' 参允许计数器指定一个 full CPU.

Note: the combination of 'pid == -1' and 'cpu == -1' is not valid.

> Note: 'pid == -1' 和 'cpu == -1' 的组合不是合法的

A 'pid > 0' and 'cpu == -1' counter is a per task counter that counts
events of that task and 'follows' that task to whatever CPU the task
gets schedule to. Per task counters can be created by any user, for
their own tasks.

> 'pid > 0' 和 'cpu == -1' counter 是一个 per task counter, per task counter
> 来计数该task 的events ,并且跟踪该task, 无论tasks调度到了哪个 CPU. Per
> task counters 可以被任何用户创建, 对于他们自己的tasks (count own task)

A 'pid == -1' and 'cpu == x' counter is a per CPU counter that counts
all events on CPU-x. Per CPU counters need CAP_SYS_ADMIN privilege.

> 'pid == -1' 和 'cpu == x' counter 是一个 per CPU counter, 计数 在 
> CPU-x上的所有event. Per CPU counters需要 CAP_SYS_ADMIN 权限.
```
</details>

***

总结来说:
1. Performance Counter 是硬件功能,有一组特殊的硬件寄存器能干这个事情,
   这些寄存器能够计数某些事件, kernel 定义了一些通用事件`hw_event_type`, 
   对于一些cpu特定的事件,  可以通过传入负数指定.

2. hardware performance monitor unit 对这些事件技术不影响当前程序的效率.
   (只能说不太影响) 而kernel侧将这些counters进行了抽象, 抽象成:
   + per-cpu
   + per-task

   counters, 并且再次基础上,增加了一个 perf event的框架.

3. 该框架定义了一个 'perf_counter_open'系统调用.该系统调用返回一个fd, 用户态基于
   这个fd 可以调用一些vfs API, 例如:
   + read
   + poll
   + fcntl

   > 这些调用的细节不多说, 在上面翻译中有描述.

4. 'perf_counter_open' 可以指定一些参数, 这里我们只简单介绍'pid', 'cpu'. 因为他们
   设置不同的值, 可以创建不同类型的 "counter"
   + per task: 
     + 参数: pid > 0 && cpu == -1
     + 计数指定的task, 无论其调度到那个cpu
   + per cpu
     + 参数: pid == -1 && cpu == x
     + 计数指定的cpu上的所有task
   + 非法的
     + 参数: pid == -1 && cpu == -1

   当然,也可以设置 pid > 0 && cpu == x, 这些变体, 这个表示计数指定的task调度到
   指定的cpu上后, 所产生的事件数.


# 相关代码

## abstraction hw counter
从上面我们知道, kernel 抽象了 hw performance counter, 实际上kernel代码定义了
一个数据结构 `perf_counter`(后面被一个作者 see bye-bye to perf_event ^ ^).

### perf_counter
```cpp
/**
 * struct perf_counter - performance counter kernel representation:
 */
struct perf_counter {
        struct list_head                list;
        int                             active;
#if BITS_PER_LONG == 64
        atomic64_t                      count;
#else
        atomic_t                        count32[2];
#endif
        u64                             __irq_period;

        struct hw_perf_counter          hw;

        struct perf_counter_context     *ctx;
        struct task_struct              *task;

        /*
         * Protect attach/detach:
         */
        struct mutex                    mutex;

        int                             oncpu;
        int                             cpu;

        s32                             hw_event_type;
        enum perf_record_type           record_type;

        /* read() / irq related data */
        wait_queue_head_t               waitq;
        /* optional: for NMIs */
        int                             wakeup_pending;
        struct perf_data                *irqdata;
        struct perf_data                *usrdata;
        struct perf_data                data[2];
};
```
我们这里看一些比较重要的数据成员:
* **count**: 事件计数, 和 hw event counter不同 hardware event counter
         会在overflow后clear, 而这个counter会一直累加.
* **__irq_period**: 采样周期, 通过`perf_counter_open`系统调用的
                `hw_event_period` 参数传入
* **hw**: 和硬件counter 配置相关, 通过`perf_counter_open`的`hw_event_period`
       传入, 我们在下面展开将
* **ctx**: 下面展开
* **hw_event_type**: 事件类型, 通过`perf_counter_open`系统调用的`hw_event_type`
  传入, 从文档中得知, kernel定义了一些通用类型, 如下:

  <details>
  <summary> enum hw_event_type </summary>

  ```cpp
  /*
   * Generalized hardware event types, used by the hw_event_type parameter
   * of the sys_perf_counter_open() syscall:
   */
  enum hw_event_types {
         PERF_COUNT_CYCLES,
         PERF_COUNT_INSTRUCTIONS,
         PERF_COUNT_CACHE_REFERENCES,
         PERF_COUNT_CACHE_MISSES,
         PERF_COUNT_BRANCH_INSTRUCTIONS,
         PERF_COUNT_BRANCH_MISSES,
         /*
          * If this bit is set in the type, then trigger NMI sampling:
          */
         PERF_COUNT_NMI                  = (1 << 30),
  };
  ```
  </details>

* **record_type**: read() 返回的数据类型

  通过 `perf_counter_open`系统调用的`record_type`传入
  + PERF_RECORD_SIMPLE: counter number
  + PERF_RECORD_IRQ : counter number + IP of interrupt context
  + PERF_RECORD_GROUP: oh ???
* **waitq**: 和poll 有关, 下面介绍
* **irqdata**: ??
* **usrdata**: ??

### hw_perf_counter
```cpp
/**
 * struct hw_perf_counter - performance counter hardware details
 */
struct hw_perf_counter {
        u64                     config;
        unsigned long           config_base;
        unsigned long           counter_base;
        int                     nmi;
        unsigned int            idx;
        u64                     prev_count;
        s32                     next_count;
        u64                     irq_period;
};
```
* **config**:
* **config_base**
* **counter_base**
* **nmi**
* **idx**
* **prev_count**
* **next_count**
* **irq_period**
### perf_counter_context
```cpp
/**
 * struct perf_counter_context - counter context structure
 *
 * Used as a container for task counters and CPU counters as well:
 */
struct perf_counter_context {
#ifdef CONFIG_PERF_COUNTERS
        /*
         * Protect the list of counters:
         */
        spinlock_t              lock;
        struct list_head        counters;
        int                     nr_counters;
        int                     nr_active;
        struct task_struct      *task;
#endif
};
```

该数据结构可以描述两种类型的counter:
* task counter
  + **list**: 链接该task的所有 `perf_counter`
  + **task**: specific task
* CPU counter
  + **list**: 链接该cpu的所有 `perf_counter`
  + **task**:

### perf_cpu_context 
```cpp
/**
 * struct perf_counter_cpu_context - per cpu counter context structure
 */
struct perf_cpu_context {
        struct perf_counter_context     ctx;
        struct perf_counter_context     *task_ctx;
        int                             active_oncpu;
        int                             max_pertask;
};
```
该数据结构用来描述 当前cpu 的 counter context:
* **ctx**: cpu counter ctx
* **task_ctx**: task of cpu sched in 的 task context ctx
* **active_oncpu**:
* **max_pertask**:

### instance of  PER TASK COUNTER CTX --- CHANGE of task_struct
```diff
diff --git a/include/linux/sched.h b/include/linux/sched.h
index 55e30d114477..4c530278391b 100644
--- a/include/linux/sched.h
+++ b/include/linux/sched.h
@@ -71,6 +71,7 @@ struct sched_param {
 #include <linux/fs_struct.h>
 #include <linux/compiler.h>
 #include <linux/completion.h>
+#include <linux/perf_counter.h>
 #include <linux/pid.h>
 #include <linux/percpu.h>
 #include <linux/topology.h>
@@ -1326,6 +1327,7 @@ struct task_struct {
        struct list_head pi_state_list;
        struct futex_pi_state *pi_state_cache;
 #endif
+       struct perf_counter_context perf_counter_ctx;
 #ifdef CONFIG_NUMA
        struct mempolicy *mempolicy;
        short il_next;
@@ -2285,6 +2287,13 @@ static inline void inc_syscw(struct task_struct *tsk)
 #define TASK_SIZE_OF(tsk)      TASK_SIZE
 #endif
```
之前我们一直说 per task counter ctx, 这里新增的成员`perf_counter_ctx`
就是其实例.


### instance  of PER CPU COUNTERCTX
```cpp
DEFINE_PER_CPU(struct perf_cpu_context, perf_cpu_context);
```
定义了一个per cpu的全局变量,用于描述 per task counter.

## sys_perf_counter_open
由于参数我们上面都提到了, 下面我们直接看代码:
```cpp
/**
 * sys_perf_task_open - open a performance counter associate it to a task
 * @hw_event_type:      event type for monitoring/sampling...
 * @pid:                target pid
 */
asmlinkage int
sys_perf_counter_open(u32 hw_event_type,
                      u32 hw_event_period,
                      u32 record_type,
                      pid_t pid,
                      int cpu)
{
        struct perf_counter_context *ctx;
        struct perf_counter *counter;
        int ret;
        // 根据 pid, cpu 查找 context
        ctx = find_get_context(pid, cpu);
        if (IS_ERR(ctx))
                return PTR_ERR(ctx);

        ret = -ENOMEM;
        // 分配新的 perf counter
        counter = perf_counter_alloc(hw_event_period, cpu, record_type);
        if (!counter)
                goto err_put_context;
        // init hw counter
        ret = hw_perf_counter_init(counter, hw_event_type);
        if (ret)
                goto err_free_put_context;
        // 将新创建的 perf counter 链入
        perf_install_in_context(ctx, counter, cpu);

        // 为 perf counter 分配 匿名fd
        ret = anon_inode_getfd("[perf_counter]", &perf_fops, counter, 0);
        if (ret < 0)
                goto err_remove_free_put_context;

        return ret;

err_remove_free_put_context:
        mutex_lock(&counter->mutex);
        perf_remove_from_context(counter);
        mutex_unlock(&counter->mutex);

err_free_put_context:
        kfree(counter);

err_put_context:
        put_context(ctx);

        return ret;
}
```
我们分别来看
* find_get_context

  <details>
  <summary>find_get_context</summary>

  ```cpp
  static struct perf_counter_context *find_get_context(pid_t pid, int cpu)
  {
          struct perf_cpu_context *cpuctx;
          struct perf_counter_context *ctx;
          struct task_struct *task;
  
          /*
           * If cpu is not a wildcard then this is a percpu counter:
           */
          //如果 cpu!= -1, 说明是一个 percpu counter
          if (cpu != -1) {
                  /* Must be root to operate on a CPU counter: */
                  // doc中提到, 如果是 percpu counter, 该task 必须有 CAP_SYS_ADMIN
                  //权限
                  if (!capable(CAP_SYS_ADMIN))
                          return ERR_PTR(-EACCES);
  
                  if (cpu < 0 || cpu > num_possible_cpus())
                          return ERR_PTR(-EINVAL);
  
                  /*
                   * We could be clever and allow to attach a counter to an
                   * offline CPU and activate it when the CPU comes up, but
                   * that's for later.
                   */
                  if (!cpu_isset(cpu, cpu_online_map))
                          return ERR_PTR(-ENODEV);
                  //(a)处定义了 perf_cpu_context 类型的per-cpu变量
                  cpuctx = &per_cpu(perf_cpu_context, cpu);
                  //其ctx成员表示该cpu的 per-cpu context
                  ctx = &cpuctx->ctx;
                  /*
                   * 这里表明, 如果该 cpu上有 per-task context, 就不能有
                   * percpu context. 
                   *
                   * 这里什么意思呢 ?
                   *
                   * 目前这一版patch只有 perf_counter_open 系统调用会调用到,
                   * 执行到这里时, 该cpu一定处于该进程的上下文. 所以有两种情况
                   *   + cpuctx->ctx->task != NULL: 
                   *                 说明该进程之前申请过 per-task counter, 
                   *                 那么就不能再申请 per-cpu counter, 这是
                   *                 甲鱼的屁股---规定 (在前面的doc中提到过)
                   *   + cpuctx->ctx->task == NULL:
                   *                 说明该进程没有申请过 per-task counter
                   *
                   *   这个地方理解对么?????
                   *   这个地方理解对么?????
                   *   这个地方理解对么?????
                   *   这个地方理解对么?????
                   *   这个地方理解对么?????
                   */
                  WARN_ON_ONCE(ctx->task);
                  return ctx;
          }
  
          rcu_read_lock();
          if (!pid)
                  //doc中也提到, 如果 pid == 0, 说明是 current per-task counter
                  task = current;
          else
                  //通过pid 找到 specific task
                  task = find_task_by_vpid(pid);
          if (task)
                  get_task_struct(task);
          rcu_read_unlock();
  
          if (!task)
                  return ERR_PTR(-ESRCH);
          // 找到 per task counter ctx, 赋值其 task 成员
          ctx = &task->perf_counter_ctx;
          ctx->task = task;
  
          /* Reuse ptrace permission checks for now. */
          // 和 ptrace相关, 先不堪
          // !!!!!!!
          // 遗留问题
          // !!!!!!!
          if (!ptrace_may_access(task, PTRACE_MODE_READ)) {
                  put_context(ctx);
                  return ERR_PTR(-EACCES);
          }
  
          return ctx;
  }
  ```

  </details>

* perf_counter_alloc

  <details>
  <summary>perf_counter_alloc</summary>

  ```cpp
  /*
   * Allocate and initialize a counter structure
   */
  static struct perf_counter *
  perf_counter_alloc(u32 hw_event_period, int cpu, u32 record_type)
  {
          //调用kzalloc申请 counter
          struct perf_counter *counter = kzalloc(sizeof(*counter), GFP_KERNEL);
  
          if (!counter)
                  return NULL;
  
          mutex_init(&counter->mutex);
          INIT_LIST_HEAD(&counter->list);
          init_waitqueue_head(&counter->waitq);
  
          counter->irqdata        = &counter->data[0];
          counter->usrdata        = &counter->data[1];
          /*
           * NOTE: 这里的cpu 是从 sys_perf_counter_open 传递下来的,
           *       所以可能为-1
           */
          counter->cpu            = cpu;
          counter->record_type    = record_type;
          //这里 __irq_period 赋值就是 系统调用参数传递下来的
          counter->__irq_period   = hw_event_period;
          counter->wakeup_pending = 0;
  
          return counter;
  }
  ```
  </details>
* hw_perf_counter_init
  ```cpp
  /*
   * Architecture provided APIs - weak aliases:
   */
  
  int __weak hw_perf_counter_init(struct perf_counter *counter, u32 hw_event_type)
  {
          return -EINVAL;
  }
  ```
  该函数是架构定义的, 我们到讲解x86 perf时再看其处理流程.


* perf_install_in_context
  <details>
  <summary>perf_install_in_context</summary>

  ```cpp
  /*
   * Attach a performance counter to a context
   *
   * First we add the counter to the list with the hardware enable bit
   * in counter->hw_config cleared.
   *
   * 首先, 我们将counter 增加到 counter->hw_config 中hardware enable bit
   * cleard 的 list中.
   *
   * If the counter is attached to a task which is on a CPU we use a smp
   * call to enable it in the task context. The task might have been
   * scheduled away, but we check this in the smp call again.
   *
   * 如果 counter attach到一个在 其他(?) cpu上跑的task, 我们使用 
   * smp call 来其 task context 中enable 它. 该task 可能已经被调度走了,
   * 但是我们会在在此通过 smp call 检查它
   */
  static void
  perf_install_in_context(struct perf_counter_context *ctx,
                          struct perf_counter *counter,
                          int cpu)
  {
          struct task_struct *task = ctx->task;
  
          counter->ctx = ctx;
          //如果没有task, 说明肯定是 per cpu context
          if (!task) {
                  /*
                   * Per cpu counters are installed via an smp call and
                   * the install is always sucessful.
                   */
                  /*
                   * Q: 这里为什么不去判断是否是当前cpu呢?
                   * A: smp_call_function_single() 函数会判断, 并且如果
                   *    是当前cpu, 就不会在执行 remote call
                   *
                   * ==(1)==
                   */
                  smp_call_function_single(cpu, __perf_install_in_context,
                                           counter, 1);
                  return;
          }
  
          counter->task = task;
  retry:
          task_oncpu_function_call(task, __perf_install_in_context,
                                   counter);
  
          spin_lock_irq(&ctx->lock);
          /*
           * If the context is active and the counter has not been added
           * we need to retry the smp call.
           *
           * 这里提到如果 context 是 active, 并且 counter 还没有被add上,
           * 我们需要再次调用smp call, 在结合__perf_install_in_context
           * 函数后, 我们会详细介绍
           */
          if (ctx->nr_active && list_empty(&counter->list)) {
                  spin_unlock_irq(&ctx->lock);
                  goto retry;
          }
  
          /*
           * The lock prevents that this context is scheduled in so we
           * can add the counter safely, if it the call above did not
           * succeed.
           *
           * 走到这里说明 specific task没有在任何cpu上running 
           */
          if (list_empty(&counter->list)) {
                  list_add_tail(&counter->list, &ctx->counters);
                  ctx->nr_counters++;
          }
          spin_unlock_irq(&ctx->lock);
  }
  ```
  1. `__perf_install_in_context`
  
     <details>
     <summary>__perf_install_in_context</summary>
  
     ```cpp
     /*
      * Cross CPU call to install and enable a preformance counter
      */
     static void __perf_install_in_context(void *info)
     {
             struct perf_cpu_context *cpuctx = &__get_cpu_var(perf_cpu_context);
             struct perf_counter *counter = info;
             struct perf_counter_context *ctx = counter->ctx;
             int cpu = smp_processor_id();
     
             /*
              * If this is a task context, we need to check whether it is
              * the current task context of this cpu. If not it has been
              * scheduled out before the smp call arrived.
              *
              * 如果是一个 task context, 我们需要检查他是否是当前cpu的 current
              * task context. 如果不是, 说明他已经在 smp call 到达之前, schedule 
              * out 
              */
             if (ctx->task && cpuctx->task_ctx != ctx)
                     return;
     
             spin_lock(&ctx->lock);
     
             /*
              * Protect the list operation against NMI by disabling the
              * counters on a global level. NOP for non NMI based counters.
              *
              * 这里需要保护list 操作不受 NMI 的影响. 所以在 global level 上
              * disable了 counters.对于x86, PMI 是 NMI, 对于arm64不是, 所以
              * 对于arm64 而言, 该操作是NOP
              */
             hw_perf_disable_all();
             /*
              * counter list , 链入 ctx->counters, 当然这里有两种情况.
              *   + task ctx: this_task_struct->perf_counter_ctx
              *   + cpu ctx: cpuctx->ctx
              */
             list_add_tail(&counter->list, &ctx->counters);
             hw_perf_enable_all();
     
             ctx->nr_counters++;
             /*
              * 对于每个cpu 而言, 支持的 hw counter 是有限的, 所以这里需要
              * 判断这些counters是否用完了.
              */
             if (cpuctx->active_oncpu < perf_max_counters) {
                     hw_perf_counter_enable(counter);
                     counter->active = 1;
                     counter->oncpu = cpu;
                     ctx->nr_active++;
                     cpuctx->active_oncpu++;
             }
             /*
              * 如果是 per cpu counter, 这个counter会永远占据一个counter,
              * 所以每分配一个 per cpu counter, 就会给 per task counter 留的
              * counter就会少一个.
              */
             if (!ctx->task && cpuctx->max_pertask)
                     cpuctx->max_pertask--;
     
             spin_unlock(&ctx->lock);
     }
     ```
     </details> <!--__perf_install_in_context-->
  </details> <!--perf_install_in_context-->


2. 我们来看关于specific task counter(not own task)几种情况(这里可能需要了解 sche_in ,
   sche_out关于perf的处理流程.

   <details>
   <summary>perf_install_in_context</summary>

   + 在整个流程中, specific task is always RUNNING
     ```
     initiator                                   another cpu
                                                 specific task is sched in
     perf_install_in_context
     retry:
       task_oncpu_function_call {
         cpu = task_cpu(p)
         smp_call_function_single {
                                                 receive IPI
                                                 __perf_install_in_context {
                                                     list_add_tail(&counter->list, 
                                                        &ctx->counters)
                                                     MAY OR MAY NOT EXEC {
                                                       ctx->nr_active++
                                                     }
                                                 }
         }
       }
     
       if (ctx->nr_active && 
         list_empty(&counter->list)) {
         //因为 list_add 操作肯定会执行,所以
         //这里必然不会执行 goto retry.
         NOT goto retry
       }
       ```
   * 在执行到 smp_call func之前,已经sched out
     ```
     initiator                                   another cpu
     perf_install_in_context
     retry:
       task_oncpu_function_call {
         cpu = task_cpu(p)
                                                 specific task is sched out
         smp_call_function_single {
                                                 receive IPI
                                                 __perf_install_in_context {
                                                   //DO NOTHING 
                                                   if (ctx->task && cpuctx->task_ctx != ctx)
                                                     return;
                                                 }
         }
       }
       if (ctx->nr_active && 
          list_empty(&counter->list)) {
         //在 sched out 流程中, 会把 
         //ctx->nr_active减至0
         //(对于per task ctx 而言)
         NOT goto retry
       }
       if (list_empty(&counter->list)) {
         //走到这里, 一定是per task ctx,
         //并且 sched out 出去了
         //所以将其加到 ctx->counters 队列中.
         //在 sched in 的时候,会使能这些
         //counters
         list_add_tail(&counter->list, 
            &ctx->counters);
         ctx->nr_counters++;
       }
     ```

   * 在 task_cpu()执行时, 还在另一个cpu上RUNNING, 但是在收到IPI 中断时, 已经
     sched out, 并且在另一个cpu上RUNNING.
     ```
     initiator                             another cpu A                 another cpu B
     perf_install_in_context
     retry:
       task_oncpu_function_call {
         cpu = task_cpu(p)
                                           specific task is 
                                             sched out
                                                                         speific task is 
                                                                           sched in {
                                                                           //在sched in 的流程
                                                                           //中,会将ctx->nr_active
                                                                           //累加上, 
                                                                           //但是这里有一个问题,
                                                                           //如果是在本次发起之前,
                                                                           //没有添加过任何per task 
                                                                           //counter, ctx->nr_counters
                                                                           //仍然为0
     
                                                                         }
     
         smp_call_function_single {
                                           __perf_install_in_context {
                                             if (ctx->task && 
                                               //在这个场景下,
                                               //下面的条件满足
                                               cpuctx->task_ctx != ctx)
                                               return;
         }
       }
       if (ctx->nr_active && 
          list_empty(&counter->list)) {
         //==(1)==
         //在这种情况下, nr_active 是大于
         //0的, 所以这时, 要goto retry
     
         goto retry
       }
     ```
     > NOTE
     >
     > (1) 处, 实际上是假设, 在本次添加counters之前, 就已经
     > 有了其他的 per task counter, 如果没有, 这里其实还是判断
     > 不对, 会导致, 当前在本次sched in --- sched out 之间的
     > 事件统计不到, 所以,这里感觉处理的不太对.
     </details>

## file operation

### perf_fops
```cpp
static const struct file_operations perf_fops = {
        .release                = perf_release,
        .read                   = perf_read,
        .poll                   = perf_poll,
};
```
这里我们先看下`perf_release`回调

#### perf_release
```cpp
/*
 * Called when the last reference to the file is gone.
 */
static int perf_release(struct inode *inode, struct file *file)
{
        struct perf_counter *counter = file->private_data;
        struct perf_counter_context *ctx = counter->ctx;

        file->private_data = NULL;

        mutex_lock(&counter->mutex);

        perf_remove_from_context(counter);
        put_context(ctx);

        mutex_unlock(&counter->mutex);

        kfree(counter);

        return 0;
}
```

该函数流程比较简单, 我们下面主要分析下 `perf_remove_from_context`
* perf_remove_from_context

  <details>
  <summary>perf_remove_from_context</summary>

  ```cpp
  static void perf_remove_from_context(struct perf_counter *counter)
  {
          struct perf_counter_context *ctx = counter->ctx;
          struct task_struct *task = ctx->task;
          
          //如果是 per cpu counters
          if (!task) {
                  /*
                   * Per cpu counters are removed via an smp call and
                   * the removal is always sucessful.
                   */
                  smp_call_function_single(counter->cpu,
                                           __perf_remove_from_context,
                                           counter, 1);
                  return;
          }
  
  retry:
          //如果是 task counters
          //这里retry的目的, 仍然是为了解决当调用该函数时, 
          task_oncpu_function_call(task, __perf_remove_from_context,
                                   counter);
  
          spin_lock_irq(&ctx->lock);
          /*
           * If the context is active we need to retry the smp call.
           * 
           * 和 install的流程一样, 如果这次没有解绑成功,并且 nr_active > 0, 
           * 这里表示调度到了其他的cpu上. 需要 retry下
           */
          if (ctx->nr_active && !list_empty(&counter->list)) {
                  spin_unlock_irq(&ctx->lock);
                  goto retry;
          }
  
          /*
           * The lock prevents that this context is scheduled in so we
           * can remove the counter safely, if it the call above did not
           * succeed.
           */
          if (!list_empty(&counter->list)) {
                  ctx->nr_counters--;
                  list_del_init(&counter->list);
                  counter->task = NULL;
          }
          spin_unlock_irq(&ctx->lock);
  }
  ```
  * `__perf_remove_from_context`
    <details>
    <summary>__perf_remove_from_context</summary>

    ```cpp
    /*
     * Cross CPU call to remove a performance counter
     *
     * We disable the counter on the hardware level first. After that we
     * remove it from the context list.
     */
    static void __perf_remove_from_context(void *info)
    {
            struct perf_cpu_context *cpuctx = &__get_cpu_var(perf_cpu_context);
            struct perf_counter *counter = info;
            struct perf_counter_context *ctx = counter->ctx;
    
            /*
             * If this is a task context, we need to check whether it is
             * the current task context of this cpu. If not it has been
             * scheduled out before the smp call arrived.
             *
             * 同installed, 查看如果是 per task counter, 而该RUNNING 的task
             * 又不是specific task
             */
            if (ctx->task && cpuctx->task_ctx != ctx)
                    return;
    
            spin_lock(&ctx->lock);
    
            if (counter->active) {
                    hw_perf_counter_disable(counter);
                    counter->active = 0;
                    ctx->nr_active--;
                    cpuctx->active_oncpu--;
                    counter->task = NULL;
            }
            ctx->nr_counters--;
    
            /*
             * Protect the list operation against NMI by disabling the
             * counters on a global level. NOP for non NMI based counters.
             */
            hw_perf_disable_all();
            list_del_init(&counter->list);
            hw_perf_enable_all();
            /*
             * 同 installed流程 , 如果是 per-cpu task, 需要将max_pertask设置
             * 成 perf_max_counters, 另外需要注意的是, 这里为什么不
             * cpuctx->max_pertask-- 呢?
             *
             * 主要是因为ctx->nr_counters 变小后, 可能会ctx->nr_counters < 
             * perf_reserved_percpu, 所以需要重新比较下, 这两个大小.
             */
            if (!ctx->task) {
                    /*
                     * Allow more per task counters with respect to the
                     * reservation:
                     */
                    cpuctx->max_pertask =
                            min(perf_max_counters - ctx->nr_counters,
                                perf_max_counters - perf_reserved_percpu);
            }
    
            spin_unlock(&ctx->lock);
    }
    ```
    </details>
  </details>

#### perf_read
```cpp
static ssize_t
perf_read(struct file *file, char __user *buf, size_t count, loff_t *ppos)
{
        struct perf_counter *counter = file->private_data;

        switch (counter->record_type) {
        case PERF_RECORD_SIMPLE:
                return perf_read_hw(counter, buf, count);

        case PERF_RECORD_IRQ:
        case PERF_RECORD_GROUP:
                return perf_read_irq_data(counter, buf, count,
                                          file->f_flags & O_NONBLOCK);
        }
        return -EINVAL;
}
```

可以读取两种类型的数据:
* PERF_RECORD_SIMPLE : 仅读取 counter
  ```cpp
  /*
   * Read the performance counter - simple non blocking version for now
   */
  static ssize_t
  perf_read_hw(struct perf_counter *counter, char __user *buf, size_t count)
  {
          u64 cntval;
  
          if (count != sizeof(cntval))
                  return -EINVAL;
  
          mutex_lock(&counter->mutex);
          cntval = perf_read_counter(counter);
          mutex_unlock(&counter->mutex);
  
          return put_user(cntval, (u64 __user *) buf) ? -EFAULT : sizeof(cntval);
  }
  ```
* PERF_RECORD_GROUP/PERF_RECORD_IRQ:
  ```cpp
  static ssize_t
  perf_read_irq_data(struct perf_counter  *counter,
                     char __user          *buf,
                     size_t               count,
                     int                  nonblocking)
  {
          struct perf_data *irqdata, *usrdata;
          DECLARE_WAITQUEUE(wait, current);
          ssize_t res;
  
          irqdata = counter->irqdata;
          usrdata = counter->usrdata;
  
          if (usrdata->len + irqdata->len >= count)
                  goto read_pending;
  
          if (nonblocking)
                  return -EAGAIN;
  
          spin_lock_irq(&counter->waitq.lock);
          __add_wait_queue(&counter->waitq, &wait);
          for (;;) {
                  set_current_state(TASK_INTERRUPTIBLE);
                  /*
                   * count 是用户态传上来的, 这里一直会等到
                   * 数据的量达到count
                   */
                  if (usrdata->len + irqdata->len >= count)
                          break;
  
                  if (signal_pending(current))
                          break;
  
                  spin_unlock_irq(&counter->waitq.lock);
                  schedule();
                  spin_lock_irq(&counter->waitq.lock);
          }
          __remove_wait_queue(&counter->waitq, &wait);
          __set_current_state(TASK_RUNNING);
          spin_unlock_irq(&counter->waitq.lock);
          //这里表示被中断了 
          if (usrdata->len + irqdata->len < count)
                  return -ERESTARTSYS;
  read_pending:
          mutex_lock(&counter->mutex);
  
          /* Drain pending data first: */
          //==(1)==
          res = perf_copy_usrdata(usrdata, buf, count);
          //res == count 表示buf已经读取满了
          if (res < 0 || res == count)
                  goto out;
  
          /* Switch irq buffer: */
          //==(2)==
          //这里表示没有读满, 还需要switch一下,接着读
          usrdata = perf_switch_irq_data(counter);
          if (perf_copy_usrdata(usrdata, buf + res, count - res) < 0) {
                  if (!res)
                          res = -EFAULT;
          } else {
                  res = count;
          }
  out:
          mutex_unlock(&counter->mutex);
  
          return res;
  }
  ```
  1. perf_copy_usrdata
     ```cpp
     static ssize_t
     perf_copy_usrdata(struct perf_data *usrdata, char __user *buf, size_t count)
     {
             if (!usrdata->len)
                     return 0;
     
             count = min(count, (size_t)usrdata->len);
             //读取剩余的 usrdata
             if (copy_to_user(buf, usrdata->data + usrdata->rd_idx, count))
                     return -EFAULT;
     
             /* Adjust the counters */
             //调整rd_idx
             usrdata->len -= count;
             //这里表示读取完了, rd_idx归0
             if (!usrdata->len)
                     usrdata->rd_idx = 0;
             else
                     usrdata->rd_idx += count;
     
             return count;
     }
     ```
  2. perf_switch_irq_data
     ```cpp
     static struct perf_data *perf_switch_irq_data(struct perf_counter *counter)
     {
             struct perf_counter_context *ctx = counter->ctx;
             struct perf_data *oldirqdata = counter->irqdata;
             struct task_struct *task = ctx->task;
             //如果是 perf cpu counter, 直接切换. 
             if (!task) {
                     smp_call_function_single(counter->cpu,
                                              __perf_switch_irq_data,
                                              counter, 1);
                     return counter->usrdata;
             }
     
     retry:
             //per task counter
             spin_lock_irq(&ctx->lock);
             //如果不是active的.
             if (!counter->active) {
                     //在自旋锁的保护下,可以切换 irqdata, usrdata
                     counter->irqdata = counter->usrdata;
                     counter->usrdata = oldirqdata;
                     spin_unlock_irq(&ctx->lock);
                     return oldirqdata;
             }
             spin_unlock_irq(&ctx->lock);
             //如果是active的情况, 则需要让其他的cpu做切换动作
             task_oncpu_function_call(task, __perf_switch_irq_data, counter);
             /* Might have failed, because task was scheduled out */
             //这里表示没有切换,同上面一样, 可能是 task 已经被 schedule out出
             //去了. 有两种情况:
             //  + sched out , NOT RUNNING
             //  + sched out , RUNNING ON ANOTHER CPU 
             //两种情况都能从retry中处理.
             if (counter->irqdata == oldirqdata)
                     goto retry;
     
             return counter->usrdata;
     }
     ```
     `__perf_switch_irq_data`
     ```cpp
     /*
      * Cross CPU call to switch performance data pointers
      */
     static void __perf_switch_irq_data(void *info)
     {
             struct perf_cpu_context *cpuctx = &__get_cpu_var(perf_cpu_context);
             struct perf_counter *counter = info;
             struct perf_counter_context *ctx = counter->ctx;
             struct perf_data *oldirqdata = counter->irqdata;
     
             /*
              * If this is a task context, we need to check whether it is
              * the current task context of this cpu. If not it has been
              * scheduled out before the smp call arrived.
              *
              * 如果是 task context, 我们需要检查, 是否是当前的task context.
              * 如果不是, 在smp call调用之前, 该task 可能被sched out出去了.
              */
             if (ctx->task) {
                     if (cpuctx->task_ctx != ctx)
                             return;
                     spin_lock(&ctx->lock);
             }
             //直接切换. 
             /* Change the pointer NMI safe */
             atomic_long_set((atomic_long_t *)&counter->irqdata,
                             (unsigned long) counter->usrdata);
             counter->usrdata = oldirqdata;
     
             if (ctx->task)
                     spin_unlock(&ctx->lock);
     }
     ```
#### perf_poll
```cpp
static unsigned int perf_poll(struct file *file, poll_table *wait)
{
        struct perf_counter *counter = file->private_data;
        unsigned int events = 0;
        unsigned long flags;

        poll_wait(file, &counter->waitq, wait);

        spin_lock_irqsave(&counter->waitq.lock, flags);
        if (counter->usrdata->len || counter->irqdata->len)
                events |= POLLIN;
        spin_unlock_irqrestore(&counter->waitq.lock, flags);

        return events;
}
```

> 暂时不看.

## sched_in, sched_out
sched_in, sched_out 要去切入切出当前进程的 per task counter, 流程如下:
```diff
 /***
  * try_to_wake_up - wake up a thread
  * @p: the to-be-woken-up thread
@@ -2534,6 +2555,7 @@ prepare_task_switch(struct rq *rq, struct task_struct *prev,
                    struct task_struct *next)
 {
        fire_sched_out_preempt_notifiers(prev, next);
+       perf_counter_task_sched_out(prev, cpu_of(rq));
        prepare_lock_switch(rq, next);
        prepare_arch_switch(next);
 }
@@ -2574,6 +2596,7 @@ static void finish_task_switch(struct rq *rq, struct task_struct *prev)
         */
        prev_state = prev->state;
        finish_arch_switch(prev);
+       perf_counter_task_sched_in(current, cpu_of(rq));
        finish_lock_switch(rq, prev);
 #ifdef CONFIG_SMP
        if (current->sched_class->post_schedule)
@@ -4296,6 +4319,7 @@ void scheduler_tick(void)
        rq->idle_at_tick = idle_cpu(cpu);
        trigger_load_balance(rq, cpu);
 #endif
+       perf_counter_task_tick(curr, cpu);
 }
```
### sched in
```cpp
/*
 * Called from scheduler to add the counters of the current task
 * with interrupts disabled.
 *
 * We restore the counter value and then enable it.
 *
 * This does not protect us against NMI, but hw_perf_counter_enable()
 * sets the enabled bit in the control field of counter _before_
 * accessing the counter control register. If a NMI hits, then it will
 * keep the counter running.
 *
 * 该流程不会保护我们阻止NMI, 但是 hw_perf_counter_enable() 设置 counter
 * 中的 enabled bit, 在访问 counter control register 之前. 如果hits了一个
 * NMI, 他仍然会保持counter running.
 */
void perf_counter_task_sched_in(struct task_struct *task, int cpu)
{
        struct perf_cpu_context *cpuctx = &per_cpu(perf_cpu_context, cpu);
        struct perf_counter_context *ctx = &task->perf_counter_ctx;
        struct perf_counter *counter;
        //要调度进的task 没有perf task counter
        if (likely(!ctx->nr_counters))
                return;

        spin_lock(&ctx->lock);
        //遍历每一个 per task counter
        list_for_each_entry(counter, &ctx->counters, list) {
                //这里需要判断, 该task 的 per task counter 是否
                //太多了, 如果太多了, 达到了 max_pertask 的限制,
                //则break
                if (ctx->nr_active == cpuctx->max_pertask)
                        break;
                if (counter->cpu != -1 && counter->cpu != cpu)
                        continue;
                //使能这个counter
                hw_perf_counter_enable(counter);
                counter->active = 1;
                counter->oncpu = cpu;
                ctx->nr_active++;
                cpuctx->active_oncpu++;
        }
        spin_unlock(&ctx->lock);
        cpuctx->task_ctx = ctx;
}
```

### sched out
```cpp
/*
 * Called from scheduler to remove the counters of the current task,
 * with interrupts disabled.
 *
 * We stop each counter and update the counter value in counter->count.
 *
 * This does not protect us against NMI, but hw_perf_counter_disable()
 * sets the disabled bit in the control field of counter _before_
 * accessing the counter control register. If a NMI hits, then it will
 * not restart the counter.
 */
void perf_counter_task_sched_out(struct task_struct *task, int cpu)
{
        struct perf_cpu_context *cpuctx = &per_cpu(perf_cpu_context, cpu);
        struct perf_counter_context *ctx = &task->perf_counter_ctx;
        struct perf_counter *counter;
        //如果该cpuctx上原本没有 per task counter, 也就是调度出的task没有.
        if (likely(!cpuctx->task_ctx))
                return;

        spin_lock(&ctx->lock);
        //遍历每一个 per task counter
        list_for_each_entry(counter, &ctx->counters, list) {
                if (!ctx->nr_active)
                        break;
                //如果counter是active的
                if (counter->active) {
                        hw_perf_counter_disable(counter);
                        counter->active = 0;
                        counter->oncpu = -1;
                        ctx->nr_active--;
                        cpuctx->active_oncpu--;
                }
        }
        spin_unlock(&ctx->lock);
        cpuctx->task_ctx = NULL;
}
```

### tick
```cpp
void perf_counter_task_tick(struct task_struct *curr, int cpu)
{
        struct perf_counter_context *ctx = &curr->perf_counter_ctx;
        struct perf_counter *counter;

        if (likely(!ctx->nr_counters))
                return;

        perf_counter_task_sched_out(curr, cpu);

        spin_lock(&ctx->lock);

        /*
         * Rotate the first entry last:
         */
        hw_perf_disable_all();
        list_for_each_entry(counter, &ctx->counters, list) {
                list_del(&counter->list);
                list_add_tail(&counter->list, &ctx->counters);
                break;
        }
        hw_perf_enable_all();

        spin_unlock(&ctx->lock);

        perf_counter_task_sched_in(curr, cpu);
}
```

> 先不看

