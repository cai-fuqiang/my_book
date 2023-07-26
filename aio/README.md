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
SYSCALL_DEFINE1(io_destroy, aio_context_t, ctx)
```
