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

# 参考链接
[三个案例轻松搞定 glib 事件循环](https://github.com/liyansong2018/glib_demo)

[Glib 主事件循环轻度分析与编程应用](https://blog.csdn.net/song_lee/article/details/116809089?spm=1001.2014.3001.5501)

[Poll 函数应用](https://zhuanlan.zhihu.com/p/195450596)
