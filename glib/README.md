# struct

## GSource (and sub struct)
GSource 代表事件源。每个事件源绑定一个 GMainContext
```cpp
typedef struct _GSource                 GSource;

struct _GSource
{
  /*< private >*/
  gpointer callback_data;
  GSourceCallbackFuncs *callback_funcs;
  /*
   * 在主循环流程中，会遍历事件源，并且执行 GSourceFuncs
   * 的各个回调, 下面会讲
   */
  const GSourceFuncs *source_funcs;
  guint ref_count;

  GMainContext *context;

  gint priority;
  guint flags;
  guint source_id;
  /* 该事件源的 pollfd */
  GSList *poll_fds;
  /* 双向链表 */
  GSource *prev;
  GSource *next;

  char    *name;
  /* priv data */
  GSourcePrivate *priv;
};
```
### GSourceFuncs
```cpp
struct _GSourceFuncs
{
  gboolean (*prepare)  (GSource    *source,
                        gint       *timeout_);/* Can be NULL */
  gboolean (*check)    (GSource    *source);/* Can be NULL */
  gboolean (*dispatch) (GSource    *source,
                        GSourceFunc callback,
                        gpointer    user_data);
  void     (*finalize) (GSource    *source); /* Can be NULL */

  /*< private >*/
  /* For use by g_source_set_closure */
  GSourceFunc     closure_callback;
  GSourceDummyMarshal closure_marshal; /* Really is of type GClosureMarshal */
};
```
* prepare: 用来检查是否有事件发生. 事件分为两类
  + 不需要 poll（idle 事件源）, 返回值 TRUE，表示 idle 事件已经发生
  + 需要 poll（文件事件源），返回值 FALSE，因为只有轮询文件之后，才能知道文件事件是否发生。
* check: 检查事件源是否有事件发生
* dispatch: 如果检测到该事件发生，则调用 `dispatch()`, 如果dispatch返回值为True,则表示销毁GSource
* finalize: 这个还需要再看下代码!!!!

### GSourcePrivate
```cpp
struct _GSourcePrivate
{
  GSList *child_sources;
  GSource *parent_source;

  gint64 ready_time;

  /* This is currently only used on UNIX, but we always declare it (and
  ¦* let it remain empty on Windows) to avoid #ifdef all over the place.
  ¦*/
  GSList *fds;			//这里面也有一个fds
  GSourceDisposeFunc dispose;
  gboolean static_name;
};
```

## GMainContext (and sub struct)
### GMainContext
该数据结构可以认为是事件源(GSource)运行的上下文, 每个事件源绑定
一个GMainContext, 每个线程只能运行一个GMainContex。

结构体的定义如下:

```cpp
typedef struct _GMainContext            GMainContext;
struct _GMainContext
{
  /* The following lock is used for both the list of sources
  ¦* and the list of poll records
  ¦*/
  GMutex mutex;
  GCond cond;
  GThread *owner;
  guint owner_count;
  GMainContextFlags flags;
  GSList *waiters;

  gint ref_count;  /* (atomic) */

  GHashTable *sources;              /* guint -> GSource */	//GSource hash table

  GPtrArray *pending_dispatches;
  gint timeout;                 /* Timeout for current iteration */

  guint next_id;
  GList *source_lists;					//GList
  gint in_check_or_prepare;

  GPollRec *poll_records;				//poll 记录
  guint n_poll_records;					//GPollRec 个数
  GPollFD *cached_poll_array;
  guint cached_poll_array_size;

  GWakeup *wakeup;						//里面存放两个文件描述符, 如果使用eventfd, 则仅使用一个, 如果使用poll, 使用两个

  GPollFD wake_up_rec;					//wakeup的 GPollFD

/* Flag indicating whether the set of fd's changed during a poll */
  gboolean poll_changed;				//请看上面英文注释

  GPollFunc poll_func;					//poll function , Linux为 poll()

  gint64   time;
  gboolean time_is_fresh;
};
```

### GWakeup, GPollFD, GPollRec

#### GWakeup
```cpp
typedef struct _GWakeup GWakeup;
struct _GWakeup
{
  gint fds[2];
};
```
#### GPollRec
```cpp
typedef struct _GPollRec GPollRec;
struct _GPollRec
{
  GPollFD *fd;
  GPollRec *prev;
  GPollRec *next;
  gint priority;
};
```

#### GPollFD
```cpp
///////GPollFD///////
typedef struct _GPollFD GPollFD;
typedef enum /*< flags >*/
{
  G_IO_IN       GLIB_SYSDEF_POLLIN,
  G_IO_OUT      GLIB_SYSDEF_POLLOUT,
  G_IO_PRI      GLIB_SYSDEF_POLLPRI,
  G_IO_ERR      GLIB_SYSDEF_POLLERR,
  G_IO_HUP      GLIB_SYSDEF_POLLHUP,
  G_IO_NVAL     GLIB_SYSDEF_POLLNVAL
} GIOCondition;

/**
 * GPollFD:
 * @fd: the file descriptor to poll (or a HANDLE on Win32)
 * @events: a bitwise combination from #GIOCondition, specifying which
 *     events should be polled for. Typically for reading from a file
 *     descriptor you would use %G_IO_IN | %G_IO_HUP | %G_IO_ERR, and
 *     for writing you would use %G_IO_OUT | %G_IO_ERR.
 *     events:相当于需要被poll的事件
 * @revents: a bitwise combination of flags from #GIOCondition, returned
 *     from the poll() function to indicate which events occurred.
 * 		相当于出参，表示当前文件描述符发生的事件
 *
 * NOTE:
 * 该数据结构和glibc  struct pollfd, 结构相同
 * Represents a file descriptor, which events to poll for, and which events
 * occurred.
 */
struct _GPollFD
{
#if defined (G_OS_WIN32) && GLIB_SIZEOF_VOID_P == 8
#ifndef __GTK_DOC_IGNORE__
  gint64        fd;
#endif
#else
  gint          fd;
#endif
  gushort       events;
  gushort       revents;
};
```

## GMainLoop
```cpp
typedef struct _GMainLoop               GMainLoop;
struct _GMainLoop
{
  GMainContext *context;
  gboolean is_running; /* (atomic) */
  gint ref_count;  /* (atomic) */
};
```
`GMainLoop`是对`GMainContext`的简单封装，其代表一个主事件循环，
在主循环中，会检查每个事件源是否产生了新事件，并且分发他们。


# API
## g_source_new -- GSource alloc
```cpp
/**
 * g_source_new:
 * @source_funcs: structure containing functions that implement
 *                the sources behavior.
 * @struct_size: size of the #GSource structure to create.
 *
 * Creates a new #GSource structure. The size is specified to
 * allow creating structures derived from #GSource that contain
 * additional data. The size passed in must be at least
 * `sizeof (GSource)`.
 * 这里分配的内存大小不一定是sizeof(GSource)，可能包含一些额外数据，
 * 所以大小 >= sizeof(GSource)
 *
 * The source will not initially be associated with any #GMainContext
 * and must be added to one with g_source_attach() before it will be
 * executed.
 *
 * 该函数初始化时，并未关联 #GMainContext, 所以必须在执行之前通过
 * g_source_attach()函数关联一个 #GMainContext
 *
 * Returns: the newly-created #GSource.
 **/
GSource *
g_source_new
(GSourceFuncs *source_funcs,
              guint         struct_size)
{
  GSource *source;

  g_return_val_if_fail (source_funcs != NULL, NULL);
  g_return_val_if_fail (struct_size >= sizeof (GSource), NULL);

  source = (GSource*) g_malloc0 (struct_size);
  //g_slice_new0 类似于 kmalloc
  source->priv = g_slice_new0 (GSourcePrivate);
  source->source_funcs = source_funcs;
  //初始化ref_count
  source->ref_count = 1;

  source->priority = G_PRIORITY_DEFAULT;

  source->flags = G_HOOK_FLAG_ACTIVE;
  //不设置超时时间
  source->priv->ready_time = -1;

  /* NULL/0 initialization for all other fields */

  TRACE (GLIB_SOURCE_NEW (source, source_funcs->prepare, source_funcs->check,
                          source_funcs->dispatch, source_funcs->finalize,
                          struct_size));

  return source;
}
```
## g_source_attach -- attach GSource to GMainContext

### g_source_attach
```cpp
/**
 * g_source_attach:
 * @source: a #GSource
 * @context: (nullable): a #GMainContext (if %NULL, the global-default
 *   main context will be used)
 *
 * Adds a #GSource to a @context so that it will be executed within
 * that context. Remove it by calling g_source_destroy().
 *
 * This function is safe to call from any thread, regardless of which thread
 * the @context is running in.
 *
 * Returns: the ID (greater than 0) for the source within the
 *   #GMainContext.
 **/
guint
g_source_attach (GSource      *source,
                 GMainContext *context)
{
  guint result = 0;

  g_return_val_if_fail (source != NULL, 0);
  g_return_val_if_fail (g_atomic_int_get (&source->ref_count) > 0, 0);
  g_return_val_if_fail (source->context == NULL, 0);
  g_return_val_if_fail (!SOURCE_DESTROYED (source), 0);

  if (!context)
   //如果没有context,这里会去绑定 default_main_context, 下面我们再分析
    context = g_main_context_default ();

  LOCK_CONTEXT (context);

  result = g_source_attach_unlocked (source, context, TRUE);

  TRACE (GLIB_MAIN_SOURCE_ATTACH (g_source_get_name (source), source, context,
                                  result));

  UNLOCK_CONTEXT (context);

  return result;
}
```

### g_source_attach_unlocked
```cpp
static guint
g_source_attach_unlocked (GSource      *source,
                          GMainContext *context,
                          gboolean      do_wakeup)
{
  GSList *tmp_list;
  guint id;

  /* The counter may have wrapped, so we must ensure that we do not
   * reuse the source id of an existing source.
   */
  //找到一个空闲的id
  do
    id = context->next_id++;
  while (id == 0 || g_hash_table_contains (context->sources, GUINT_TO_POINTER (id)));
  //赋值 context 字段
  source->context = context;
  source->source_id = id;
  g_source_ref (source);
  //加入hash table
  g_hash_table_insert (context->sources, GUINT_TO_POINTER (id), source);

  //将source 加入 context->source_lists
  source_add_to_context (source, context);
  //如果没有 G_SOURCE_BLOCKED
  if (!SOURCE_BLOCKED (source))
    {
      tmp_list = source->poll_fds;
      //遍历source->poll_fds
      while (tmp_list)
        {
          g_main_context_add_poll_unlocked (context, source->priority, tmp_list->data);
          tmp_list = tmp_list->next;
        }
      //遍历source->priv->fds, 将其也加到poll_records中
      for (tmp_list = source->priv->fds; tmp_list; tmp_list = tmp_list->next)
        g_main_context_add_poll_unlocked (context, source->priority, tmp_list->data);
    }
  //child_sources不太了解这个, 但是这里会执行递归。
  tmp_list = source->priv->child_sources;
  //对每个child_sources都做递归
  while (tmp_list)
    {
      g_source_attach_unlocked (tmp_list->data, context, FALSE);
      tmp_list = tmp_list->next;
    }

  /* If another thread has acquired the context, wake it up since it
   * might be in poll() right now.
   */
  //这个地方不太清楚
  if (do_wakeup && (context->flags & G_MAIN_CONTEXT_FLAGS_OWNERLESS_POLLING ||
       (context->owner && context->owner != G_THREAD_SELF)))
    {
      g_wakeup_signal (context->wakeup);
    }
      g_trace_mark (G_TRACE_CURRENT_TIME, 0,
                "GLib", "g_source_attach",
                "%s to context %p",
                (g_source_get_name (source) != NULL) ? g_source_get_name (source) : "(unnamed)",
                context);

  return source->source_id;
}
```

### g_main_context_add_poll_unlocked
```cpp
static void
g_main_context_add_poll_unlocked (GMainContext *context,
                                 gint          priority,
                                 GPollFD      *fd)
{
  GPollRec *prevrec, *nextrec;
  //新申请 GPollRec
  GPollRec *newrec = g_slice_new (GPollRec);

  /* This file descriptor may be checked before we ever poll */
  //设置fd和 priority
  fd->revents = 0;
  newrec->fd = fd;
  newrec->priority = priority;

  /* Poll records are incrementally sorted by file descriptor identifier. */
  prevrec = NULL;
  nextrec = context->poll_records;
  while (nextrec)
    {
      //该链表根据fd数值排序，从小到达
      if (nextrec->fd->fd > fd->fd)
        break;
      prevrec = nextrec;
      nextrec = nextrec->next;
    }

  if (prevrec)
    prevrec->next = newrec;
  else
    context->poll_records = newrec;

  newrec->prev = prevrec;
  newrec->next = nextrec;

  if (nextrec)
    nextrec->prev = newrec;
  //自增n_poll_records
  context->n_poll_records++;
  //表示有poll_records改变
  context->poll_changed = TRUE;

  /* Now wake up the main loop if it is waiting in the poll() */
  //如果这次增加的fd 不是context->wake_up_rec的话，通知main_loop
  //NOTE : context->wake_up_rec就是用来通知main loop的
  if (fd != &context->wake_up_rec)
    g_wakeup_signal (context->wakeup);
}
/**
 * g_wakeup_signal:
 * @wakeup: a #GWakeup
 *
 * Signals @wakeup.
 *
 * Any future (or present) polling on the #GPollFD returned by
 * g_wakeup_get_pollfd() will immediately succeed until such a time as
 * g_wakeup_acknowledge() is called.
 *
 * This function is safe to call from a UNIX signal handler.
 *
 * Since: 2.30
 **/
void
g_wakeup_signal (GWakeup *wakeup)
{
  int res;
  //这个条件为使用eventfd, 下面是管道，我们只看这个分支
  if (wakeup->fds[1] == -1)
    {
      uint64_t one = 1;

      /* eventfd() case. It requires a 64-bit counter increment value to be
       * written. */
      do 
        //对eventfd写1
        res = write (wakeup->fds[0], &one, sizeof one);
      while (G_UNLIKELY (res == -1 && errno == EINTR));
    }
  else
    {
      uint8_t one = 1;

      /* Non-eventfd() case. Only a single byte needs to be written, and it can
       * have an arbitrary value. */
      do
        res = write (wakeup->fds[1], &one, sizeof one);
      while (G_UNLIKELY (res == -1 && errno == EINTR));
    }
}
```
## new main context -- g_main_context_new
在看这个之前，我们先看下上面说道的 `g_main_context_default`看下
### g_main_context_default 
```cpp
/**
 * g_main_context_default:
 *
 * Returns the global-default main context. This is the main context
 * used for main loop functions when a main loop is not explicitly
 * specified, and corresponds to the "main" main loop. See also
 * g_main_context_get_thread_default().
 *
 * 返回全局默认主上下文。当没有明确指定主循环时, 这是用于主循环函数的主
 * 上下文，并且对应于"main"主循环。另请参见
 * g_main_context_get_thread_default（）。 
 *
 * Returns: (transfer none): the global-default main context.
 **/
GMainContext *
g_main_context_default (void)
{
  static GMainContext *default_main_context = NULL;
  //这个宏定义有点复杂，没有分析，大概就是default_main_context为NULL
  if (g_once_init_enter (&default_main_context))
    {
      GMainContext *context;
      //新创建一个
      context = g_main_context_new ();

      TRACE (GLIB_MAIN_CONTEXT_DEFAULT (context));

#ifdef G_MAIN_POLL_DEBUG
      if (_g_main_poll_debug)
        g_print ("global-default main context=%p\n", context);
#endif
      //设置default_main_context
      g_once_init_leave (&default_main_context, context);
    }

  return default_main_context;
}
```

### g_main_context_new
```cpp
/**
 * g_main_context_new:
 *
 * Creates a new #GMainContext structure.
 *
 * Returns: the new #GMainContext
 **/
GMainContext *
g_main_context_new (void)
{
  return g_main_context_new_with_flags (G_MAIN_CONTEXT_FLAGS_NONE);
}
/**
 * g_main_context_new_with_flags:
 * @flags: a bitwise-OR combination of #GMainContextFlags flags that can only be
 *         set at creation time.
 *
 * Creates a new #GMainContext structure.
 *
 * Returns: (transfer full): the new #GMainContext
 *
 * Since: 2.72
 */
GMainContext *
g_main_context_new_with_flags (GMainContextFlags flags)
{
  static gsize initialised;
  GMainContext *context;
   //主要用于debug, 为什么不用debug全包上呢
  if (g_once_init_enter (&initialised))
    {
#ifdef G_MAIN_POLL_DEBUG
      if (g_getenv ("G_MAIN_POLL_DEBUG") != NULL)
        _g_main_poll_debug = TRUE;
#endif

      g_once_init_leave (&initialised, TRUE);
    }

  context = g_new0 (GMainContext, 1);

  TRACE (GLIB_MAIN_CONTEXT_NEW (context));

  g_mutex_init (&context->mutex);
  g_cond_init (&context->cond);
  //创建一个新的hash表
  context->sources = g_hash_table_new (NULL, NULL);
  context->owner = NULL;
  context->flags = flags;
  context->waiters = NULL;

  context->ref_count = 1;
  //next_id设置为1, 从1开始，而不是0
  context->next_id = 1;

  context->source_lists = NULL;
  //!!!这个比较关键，将poll_func设置为 g_poll, 最终会调用到glibc: poll()
  context->poll_func = g_poll;

  context->cached_poll_array = NULL;
  context->cached_poll_array_size = 0;

  context->pending_dispatches = g_ptr_array_new ();

  context->time_is_fresh = FALSE;
  //新创建一个wakeup
  context->wakeup = g_wakeup_new ();
  g_wakeup_get_pollfd (context->wakeup, &context->wake_up_rec);
  g_main_context_add_poll_unlocked (context, 0, &context->wake_up_rec);

  G_LOCK (main_context_list);
  main_context_list = g_slist_append (main_context_list, context);

#ifdef G_MAIN_POLL_DEBUG
  if (_g_main_poll_debug)
    g_print ("created context=%p\n", context);
#endif

  G_UNLOCK (main_context_list);

  return context;
}
```

### g_wakeup_new
```cpp

/**
 * g_wakeup_new:
 *
 * Creates a new #GWakeup.
 *
 * You should use g_wakeup_free() to free it when you are done.
 *
 * Returns: a new #GWakeup
 *
 * Since: 2.30
 **/
GWakeup *
g_wakeup_new (void)
{
  GError *error = NULL;
  GWakeup *wakeup;

  wakeup = g_slice_new (GWakeup);

  /* try eventfd first, if we think we can */
#if defined (HAVE_EVENTFD)
#ifndef TEST_EVENTFD_FALLBACK
  //如果定义了HAVE_EVENTFD，那么便用eventfd作为wakeup的方式,
  //并且是EFD_NONBLOCK, eventfd只使用一个文件描述符就够了
  wakeup->fds[0] = eventfd (0, EFD_CLOEXEC | EFD_NONBLOCK);
#else
  wakeup->fds[0] = -1;
#endif

  if (wakeup->fds[0] != -1)
    {
      wakeup->fds[1] = -1;
      return wakeup;
    }

  /* for any failure, try a pipe instead */
#endif
  //如果没有，则使用管道
  if (!g_unix_open_pipe (wakeup->fds, FD_CLOEXEC | O_NONBLOCK, &error))
    g_error ("Creating pipes for GWakeup: %s", error->message);
  //这里也设置为nonblock
  if (!g_unix_set_fd_nonblocking (wakeup->fds[0], TRUE, &error) ||
      !g_unix_set_fd_nonblocking (wakeup->fds[1], TRUE, &error))
    g_error ("Set pipes non-blocking for GWakeup: %s", error->message);

  return wakeup;
}
```

### g_wakeup_get_pollfd
```cpp
/**
 * g_wakeup_get_pollfd:
 * @wakeup: a #GWakeup
 * @poll_fd: a #GPollFD
 *
 * Prepares a @poll_fd such that polling on it will succeed when
 * g_wakeup_signal() has been called on @wakeup.
 *
 * @poll_fd is valid until @wakeup is freed.
 *
 * Since: 2.30
 **/
void
g_wakeup_get_pollfd (GWakeup *wakeup,
                     GPollFD *poll_fd)
{
  poll_fd->fd = wakeup->fds[0];
  poll_fd->events = G_IO_IN;
}
```
## new main loop -- g_main_loop_new
```cpp
/**
 * g_main_loop_new:
 * @context: (nullable): a #GMainContext  (if %NULL, the global-default
 *   main context will be used).
 *   该参数可以为空，如果是空，则使用 global-default main context
 * @is_running: set to %TRUE to indicate that the loop is running. This
 * is not very important since calling g_main_loop_run() will set this to
 * %TRUE anyway.
 *    如果为%TRUE指示在loop 中是 running的。这不是很重要，因为在g_main_loop_run()
 *    中会将其设置为%TRUE
 *
 * Creates a new #GMainLoop structure.
 *
 * Returns: a new #GMainLoop.
 **/
GMainLoop *
g_main_loop_new (GMainContext *context,
                 gboolean      is_running)
{
  GMainLoop *loop;

  if (!context)
    //使用默认的
    context = g_main_context_default();

  g_main_context_ref (context);

  loop = g_new0 (GMainLoop, 1);
  loop->context = context;
  loop->is_running = is_running != FALSE;
  loop->ref_count = 1;

  TRACE (GLIB_MAIN_LOOP_NEW (loop, context));

  return loop;
}
```

## g_main_loop_run
```cpp
/**
 * g_main_loop_run:
 * @loop: a #GMainLoop
 *
 * Runs a main loop until g_main_loop_quit() is called on the loop.
 * If this is called for the thread of the loop's #GMainContext,
 * it will process events from the loop, otherwise it will
 * simply wait.
 **/
void
g_main_loop_run (GMainLoop *loop)
{
  GThread *self = G_THREAD_SELF;

  g_return_if_fail (loop != NULL);
  g_return_if_fail (g_atomic_int_get (&loop->ref_count) > 0);

  /* Hold a reference in case the loop is unreffed from a callback function */
  //增长引用计数
  g_atomic_int_inc (&loop->ref_count);

  LOCK_CONTEXT (loop->context);
  //这个先不看
  if (!g_main_context_acquire_unlocked (loop->context))
    {
      gboolean got_ownership = FALSE;

      /* Another thread owns this context */
      g_atomic_int_set (&loop->is_running, TRUE);

      while (g_atomic_int_get (&loop->is_running) && !got_ownership)
        got_ownership = g_main_context_wait_internal (loop->context,
                                                      &loop->context->cond,
                                                      &loop->context->mutex);

      if (!g_atomic_int_get (&loop->is_running))
        {
          if (got_ownership)
            g_main_context_release_unlocked (loop->context);

          UNLOCK_CONTEXT (loop->context);
          g_main_loop_unref (loop);
          return;
        }

      g_assert (got_ownership);
    }
  //这个先不看
  if G_UNLIKELY (loop->context->in_check_or_prepare)
    {
      g_warning ("g_main_loop_run(): called recursively from within a source's "
                 "check() or prepare() member, iteration not possible.");
      g_main_context_release_unlocked (loop->context);
      UNLOCK_CONTEXT (loop->context);
      g_main_loop_unref (loop);
      return;
    }
  //将loop->is_running 设置为 %TRUE
  g_atomic_int_set (&loop->is_running, TRUE);
  while (g_atomic_int_get (&loop->is_running))
    //在该流程中，去检测事件
    g_main_context_iterate_unlocked (loop->context, TRUE, TRUE, self);

  g_main_context_release_unlocked (loop->context);

  UNLOCK_CONTEXT (loop->context);

  g_main_loop_unref (loop);
}
```
### g_main_context_iterate_unlocked 
```cpp
/* HOLDS context lock */
static gboolean
g_main_context_iterate_unlocked (GMainContext *context,
                                 gboolean      block,
                                 gboolean      dispatch,
                                 GThread      *self)
{
  gint max_priority = 0;
  gint timeout;
  gboolean some_ready;
  gint nfds, allocated_nfds;
  GPollFD *fds = NULL;
  gint64 begin_time_nsec G_GNUC_UNUSED;

  begin_time_nsec = G_TRACE_CURRENT_TIME;
  //先不看
  if (!g_main_context_acquire_unlocked (context))
    {
      gboolean got_ownership;

      if (!block)
        return FALSE;

      got_ownership = g_main_context_wait_internal (context,
                                                    &context->cond,
                                                    &context->mutex);

      if (!got_ownership)
        return FALSE;
    }
  /*
   * 如果没有 cache poll array, new一个
   * 之前提到过GPollFD的结构类似于pollfd, 
   * 该结构体会给glibc poll() 当作参数
   */
  if (!context->cached_poll_array)
    {
      context->cached_poll_array_size = context->n_poll_records;
      context->cached_poll_array = g_new (GPollFD, context->n_poll_records);
    }

  allocated_nfds = context->cached_poll_array_size;
  fds = context->cached_poll_array;
  //调用prepare, 传出一个max_priority
  g_main_context_prepare_unlocked (context, &max_priority);
  /*
   * 这里是入队的意思
   * 这里选择比 max_priority更高优先级的事件入队。
   * 执行后面的poll操作
   */
  while ((nfds = g_main_context_query_unlocked (
            context, max_priority, &timeout, fds,
            allocated_nfds)) > allocated_nfds)
    {
      g_free (fds);
      //这里空间不够了需要重新分配
      context->cached_poll_array_size = allocated_nfds = nfds;
      context->cached_poll_array = fds = g_new (GPollFD, nfds);
    }

  if (!block)
    timeout = 0;

  g_main_context_poll_unlocked (context, timeout, max_priority, fds, nfds);

  some_ready = g_main_context_check_unlocked (context, max_priority, fds, nfds);

  if (dispatch)
    g_main_context_dispatch_unlocked (context);

  g_main_context_release_unlocked (context);

  g_trace_mark (begin_time_nsec, G_TRACE_CURRENT_TIME - begin_time_nsec,
                "GLib", "g_main_context_iterate",
                "Context %p, %s ⇒ %s", context, block ? "blocking" : "non-blocking", some_ready ? "dispatched" : "nothing");

  return some_ready;
}
```

### g_main_context_prepare_unlocked 
```cpp
static gboolean
g_main_context_prepare_unlocked (GMainContext *context,
                                 gint         *priority)
{
  guint i;
  gint n_ready = 0;
  gint current_priority = G_MAXINT;
  GSource *source;
  GSourceIter iter;

  context->time_is_fresh = FALSE;

  if (context->in_check_or_prepare)
    {
      g_warning ("g_main_context_prepare() called recursively from within a source's check() or "
		 "prepare() member.");
      return FALSE;
    }

  TRACE (GLIB_MAIN_CONTEXT_BEFORE_PREPARE (context));

#if 0
  /* If recursing, finish up current dispatch, before starting over */
  if (context->pending_dispatches)
    {
      if (dispatch)
	g_main_dispatch (context, &current_time);
      
      return TRUE;
    }
#endif

  /* If recursing, clear list of pending dispatches */

  for (i = 0; i < context->pending_dispatches->len; i++)
    {
      if (context->pending_dispatches->pdata[i])
        g_source_unref_internal ((GSource *)context->pending_dispatches->pdata[i], context, TRUE);
    }
  g_ptr_array_set_size (context->pending_dispatches, 0);
  
  /* Prepare all sources */

  context->timeout = -1;
  
  g_source_iter_init (&iter, context, TRUE);
  while (g_source_iter_next (&iter, &source))
    {
      gint source_timeout = -1;

      if (SOURCE_DESTROYED (source) || SOURCE_BLOCKED (source))
	continue;
      //如果已经有ready的，并且该source->priority, 已经大于当前
      //的priority, 然后就跳出循环, 这个地方没看懂!!!
      //
      //个人感觉应该是去找所有ready source的最高的 priority, 但是
      //这里并没有这么做
      if ((n_ready > 0) && (source->priority > current_priority))
	break;
      //如果不是 G_SOURCE_READY, 执行下面的分支检测本轮是否ready了
      if (!(source->flags & G_SOURCE_READY))
	{
	  gboolean result;
	  gboolean (* prepare) (GSource  *source,
                                gint     *timeout);

          prepare = source->source_funcs->prepare;

          if (prepare)
            {
              gint64 begin_time_nsec G_GNUC_UNUSED;

              context->in_check_or_prepare++;
              UNLOCK_CONTEXT (context);

              begin_time_nsec = G_TRACE_CURRENT_TIME;

              result = (* prepare) (source, &source_timeout);
              TRACE (GLIB_MAIN_AFTER_PREPARE (source, prepare, source_timeout));

              g_trace_mark (begin_time_nsec, G_TRACE_CURRENT_TIME - begin_time_nsec,
                            "GLib", "GSource.prepare",
                            "%s ⇒ %s",
                            (g_source_get_name (source) != NULL) ? g_source_get_name (source) : "(unnamed)",
                            result ? "ready" : "unready");

              LOCK_CONTEXT (context);
              context->in_check_or_prepare--;
            }
          else
            result = FALSE;
          /* 
           * 如果result == FALSE, 也就是说没有在prepare中检测到事件，需要
           * 通过poll去检测事件, 但是这里有个事件到期的机制。
           *
           * source->priv->ready_time 记录的到期的时刻
           * 而 prepare(source, &source_timeout), 作为出参返回的 source_timeout
           * 的值，则表示poll()可以执行多长时间超时，也就是说ready_time是一个时间点。
           * 而 source_timeout则是时长。
           */
           /*
            * 如果ready_time != -1, 则说明指定了到期的时刻
            */
          if (result == FALSE && source->priv->ready_time != -1)
            {
              //time_is_fresh == False, 说明时间不新鲜了，需要重新获取时间
              if (!context->time_is_fresh)
                {
                  context->time = g_get_monotonic_time ();
                  context->time_is_fresh = TRUE;
                }
              /*
               * 如果到期时间 <= 现在的时间, 说明已经到期了
               * 这时候把source_timeout设置为0,并且result = TRUE, 
               * 表示到期事件已经触发，不再需要poll进行监听。
               */
              if (source->priv->ready_time <= context->time)
                {
                  source_timeout = 0;
                  result = TRUE;
                }
              else
                {
                  gint64 timeout;

                  /* rounding down will lead to spinning, so always round up */
                  /* 通过ready_time 计算timeout的时间点 */
                  timeout = (source->priv->ready_time - context->time + 999) / 1000;
                  //这里实际上是取 source_timeout 和 ready_time 哪个更早到期
                  if (source_timeout < 0 || timeout < source_timeout)
                    source_timeout = MIN (timeout, G_MAXINT);
                }
            }
          //如果result == TRUE, 说明事件发生，不需要poll
	  if (result)
	    {
	      GSource *ready_source = source;

	      while (ready_source)
		{
                  //将 本 source和 parent 等等source都置上 G_SOURCE_READY
		  ready_source->flags |= G_SOURCE_READY;
		  ready_source = ready_source->priv->parent_source;
		}
	    }
	}
      //如果是ready
      if (source->flags & G_SOURCE_READY)
	{
	  n_ready++;
	  current_priority = source->priority;
	  context->timeout = 0;
	}
      //设置context->timeout 
      if (source_timeout >= 0)
	{
	  if (context->timeout < 0)
	    context->timeout = source_timeout;
	  else
	    context->timeout = MIN (context->timeout, source_timeout);
	}
    }
  g_source_iter_clear (&iter);

  TRACE (GLIB_MAIN_CONTEXT_AFTER_PREPARE (context, current_priority, n_ready));
  
  if (priority)
    *priority = current_priority;
  
  return (n_ready > 0);
}
```
### g_main_context_query_unlocked
```cpp
static gint
g_main_context_query_unlocked (GMainContext *context,
                               gint          max_priority,
                               gint         *timeout,
                               GPollFD      *fds,
                               gint          n_fds)
{
  gint n_poll;
  GPollRec *pollrec, *lastpollrec;
  gushort events;

  TRACE (GLIB_MAIN_CONTEXT_BEFORE_QUERY (context, max_priority));

  /* fds is filled sequentially from poll_records. Since poll_records
   * are incrementally sorted by file descriptor identifier, fds will
   * also be incrementally sorted.
   */
  n_poll = 0;
  lastpollrec = NULL;
  //遍历 context->poll_records
  for (pollrec = context->poll_records; pollrec; pollrec = pollrec->next)
    {
      //过滤优先级，只有优先级比max_priority 大的时候，才监听
      if (pollrec->priority > max_priority)
        continue;

      /* In direct contradiction to the Unix98 spec, IRIX runs into
       * difficulty if you pass in POLLERR, POLLHUP or POLLNVAL
       * flags in the events field of the pollfd while it should
       * just ignoring them. So we mask them out here.
       */
       /* 获取 events */
      events = pollrec->fd->events & ~(G_IO_ERR|G_IO_HUP|G_IO_NVAL);

      /* This optimization --using the same GPollFD to poll for more
       * than one poll record-- relies on the poll records being
       * incrementally sorted.
       */
       /* 
        * 这种情况实际上是，同一个fd , 用了两个 pollrec,
        * 那这里会将事件合并。
        */
      if (lastpollrec && pollrec->fd->fd == lastpollrec->fd->fd)
        {
          if (n_poll - 1 < n_fds)
            fds[n_poll - 1].events |= events;
        }
      else
        {
          if (n_poll < n_fds)
            {
              fds[n_poll].fd = pollrec->fd->fd;
              fds[n_poll].events = events;
              fds[n_poll].revents = 0;
            }

          n_poll++;
        }

      lastpollrec = pollrec;
    }
  //接下来要走监听, 将poll_changed 置为FALSE
  context->poll_changed = FALSE;
  /*
   * 赋值timeout，并且将 time_is_fresh置 FALSE,
   * 下次再用时间，需要重新获取.
   *
   * 为什么要在这个地方重置 time_is_fresh, 因为
   * 接下来要走poll了，可能需要等待一段时间.
   */
  if (timeout)
    {
      *timeout = context->timeout;
      if (*timeout != 0)
        context->time_is_fresh = FALSE;
    }

  TRACE (GLIB_MAIN_CONTEXT_AFTER_QUERY (context, context->timeout,
                                        fds, n_poll));

  return n_poll;
}
```
### g_main_context_poll_unlocked
```cpp
static void
g_main_context_poll_unlocked (GMainContext *context,
                              int           timeout,
                              int           priority,
                              GPollFD      *fds,
                              int           n_fds)
{
#ifdef  G_MAIN_POLL_DEBUG
  GTimer *poll_timer;
  GPollRec *pollrec;
  gint i;
#endif

  GPollFunc poll_func;

  if (n_fds || timeout != 0)
    {
      int ret, errsv;

#ifdef  G_MAIN_POLL_DEBUG
      poll_timer = NULL;
      if (_g_main_poll_debug)
        {
          g_print ("polling context=%p n=%d timeout=%d\n",
                   context, n_fds, timeout);
          poll_timer = g_timer_new ();
        }
#endif
      poll_func = context->poll_func;

      UNLOCK_CONTEXT (context);
      ret = (*poll_func) (fds, n_fds, timeout);
      LOCK_CONTEXT (context);

      errsv = errno;
      if (ret < 0 && errsv != EINTR)
        {
#ifndef G_OS_WIN32
          g_warning ("poll(2) failed due to: %s.",
                     g_strerror (errsv));
#else
          /* If g_poll () returns -1, it has already called g_warning() */
#endif
        }
        //和debug相关，先不看
#ifdef  G_MAIN_POLL_DEBUG
      if (_g_main_poll_debug)
        {
          g_print ("g_main_poll(%d) timeout: %d - elapsed %12.10f seconds",
                   n_fds,
                   timeout,
                   g_timer_elapsed (poll_timer, NULL));
          g_timer_destroy (poll_timer);
          pollrec = context->poll_records;

          while (pollrec != NULL)
            {
              i = 0;
              while (i < n_fds)
                {
                  if (fds[i].fd == pollrec->fd->fd &&
                      pollrec->fd->events &&
                      fds[i].revents)
                    {
                      g_print (" [" G_POLLFD_FORMAT " :", fds[i].fd);
                      if (fds[i].revents & G_IO_IN)
                        g_print ("i");
                      if (fds[i].revents & G_IO_OUT)
                        g_print ("o");
                      if (fds[i].revents & G_IO_PRI)
                        g_print ("p");
                      if (fds[i].revents & G_IO_ERR)
                        g_print ("e");
                      if (fds[i].revents & G_IO_HUP)
                        g_print ("h");
                      if (fds[i].revents & G_IO_NVAL)
                        g_print ("n");
                      g_print ("]");
                    }
                  i++;
                }
              pollrec = pollrec->next;
            }
          g_print ("\n");
        }
#endif
    } /* if (n_fds || timeout != 0) */
}
```
### 
# 参考链接
[三个案例轻松搞定 glib 事件循环](https://github.com/liyansong2018/glib_demo)

[Glib 主事件循环轻度分析与编程应用](https://blog.csdn.net/song_lee/article/details/116809089?spm=1001.2014.3001.5501)

[Poll 函数应用](https://zhuanlan.zhihu.com/p/195450596)

[glib主事件循环](https://blog.csdn.net/woai110120130/article/details/99701442)
