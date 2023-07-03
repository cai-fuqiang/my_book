# 代码流
## poll
```
poll
  do_sys_poll {
    struct poll_wqueues table;
    long stack_pps[POLL_STACK_ALLOC/sizeof(long)];
    struct poll_list *const head = (struct poll_list *)stack_pps;
    ...
    copy_from_user ufds {
       这里不过多描述，大概是首先用 stack_pps， 如果不够用，
       再去申请, 并链接上之前的 poll_list对象，形成链表,
       最终head变量指向poll_list链表的头部
    }
    poll_initwait(&table); {
      init_poll_funcptr(&pwq->pt, __pollwait); {
        pt->_qproc = qproc;
        //使能所有event
        pt->_key   = ~(__poll_t)0;
      } //init_poll_funcptr END
      //将polling_task设置为 current
      pwq->polling_task = current;
      pwd->table = NULL;
      pwq->inline_index = 0;
      ...
    } //poll_initwait END
    fdcount = do_poll(head, &table, end_time); {
    } //do_poll END
    poll_freewait(&table);
  } //do_sys_poll END
```

## struct
## struct poll_table_entry
```
struct poll_table_entry {
        struct file *filp;
        __poll_t key;
        wait_queue_entry_t wait;
        wait_queue_head_t *wait_address;
};

struct poll_wqueues {
        poll_table pt;
        struct poll_table_page *table;
        struct task_struct *polling_task;
        int triggered;
        int error;
        int inline_index;
        struct poll_table_entry inline_entries[N_INLINE_POLL_ENTRIES];
};
```
## do_pollfd
```cpp
static inline __poll_t do_pollfd(struct pollfd *pollfd, poll_table *pwait,
                                     bool *can_busy_poll,
                                     __poll_t busy_flag)
{
        int fd = pollfd->fd;
        __poll_t mask = 0, filter;
        struct fd f;

        if (fd < 0)
                goto out;
        mask = EPOLLNVAL;
        f = fdget(fd);
        if (!f.file)
                goto out;

        /* userland u16 ->events contains POLL... bitmap */
        filter = demangle_poll(pollfd->events) | EPOLLERR | EPOLLHUP;
        pwait->_key = filter | busy_flag;
        //调用vfs_poll
        mask = vfs_poll(f.file, pwait);
        if (mask & busy_flag)
                *can_busy_poll = true;
        mask &= filter;         /* Mask out unneeded events. */
        fdput(f);

out:
        /* ... and so does ->revents */
        pollfd->revents = mangle_poll(mask);
        return mask;
}

static inline __poll_t vfs_poll(struct file *file, struct poll_table_struct *pt)
{
        if (unlikely(!file->f_op->poll))
                return DEFAULT_POLLMASK;
        return file->f_op->poll(file, pt);
}
```


### 以eventfd为例
```cpp
static __poll_t eventfd_poll(struct file *file, poll_table *wait)
{
        struct eventfd_ctx *ctx = file->private_data;
        __poll_t events = 0;
        u64 count;
        //eventfd 中的等待队列
        poll_wait(file, &ctx->wqh, wait);
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
                //对于poll流程来说，是__pollwait
                p->_qproc(filp, wait_address, p);
}
```
## __pollwait
```cpp
/*
 * 我们思考下，poll操作需要关联哪些东西:
 *
 * poll 操作无非是监听多个文件描述符的事件, 所以需要关联:
 * 1. 文件 : filp
 * 2. 获取文件的通知 （等待队列) : wake_address( wait_queue_head)
 * 3. 对事件的过滤? : p->key !!!!(还需要看下)
 * 4. wakeup function : pollwake (该function 会去检查entry的key和本次事件
 * 的key能否对上，能对上的话，就唤醒关联进程
 *
 * 而 __pollwait函数，就是将上面提到的初始化好, 那我们猜测下pollwait什么时候，
 * 会被调用呢 ? 很简单, 只要想对 filp 进行监听，并且已经准备好 filp, wait_address
 * 就可以被调用了
 */
static void __pollwait(struct file *filp, wait_queue_head_t *wait_address,
                                poll_table *p)
{
        struct poll_wqueues *pwq = container_of(p, struct poll_wqueues, pt);
        //先获取一个 poll_table_entry
        struct poll_table_entry *entry = poll_get_entry(pwq);
        if (!entry)
                return;
        //=====需要监听的file=======
        entry->filp = get_file(filp);
        entry->wait_address = wait_address;
        entry->key = p->_key;
        //init wait_queue_entry:flags private, func = pollwake
        init_waitqueue_func_entry(&entry->wait, pollwake);
        entry->wait.private = pwq;
        //将wait_queue_entry 加入 wait_queue_head(wait_address)
        add_wait_queue(wait_address, &entry->wait);
}
```

## poll_get_entry
```cpp
/*
 * 这里 p->table是一个池子, poll_get_entry, 接口作用是从池
 * 子中获取一个entry, 从poll_initwait函数中可以看出, 最初p->table = NULL;
 * p->inline_index = 0 。
 *
 * 然而poll_wqueues内置的有inline entries, 所以先分配这里面的entry,
 * 如果分配空了，再去通过get_free_page动态申请, 如果动态申请的页生成
 * 的池子，也分配空了，那就再申请页，并且将这些页链起来
 */
static struct poll_table_entry *poll_get_entry(struct poll_wqueues *p)
{
        struct poll_table_page *table = p->table;

        if (p->inline_index < N_INLINE_POLL_ENTRIES)
                return p->inline_entries + p->inline_index++;

        if (!table || POLL_TABLE_FULL(table)) {
                struct poll_table_page *new_table;

                new_table = (struct poll_table_page *) __get_free_page(GFP_KERNEL);
                if (!new_table) {
                        p->error = -ENOMEM;
                        return NULL;
                }
                new_table->entry = new_table->entries;
                new_table->next = table;
                p->table = new_table;
                table = new_table;
        }

        return table->entry++;
}
```
