# struct
## xfs_cli
```cpp
/*
 * Committed Item List structure
 *
 * This structure is used to track log items that have been committed but not
 * yet written into the log. It is used only when the delayed logging mount
 * option is enabled.
 *
 * 该数据结构用来 track log items, 这些 log items 已经被提交了，但是还没有写入log.
 * 他只用于当 delayed logging mount option 被使能.
 *
 * This structure tracks the list of committing checkpoint contexts so
 * we can avoid the problem of having to hold out new transactions during a
 * flush until we have a the commit record LSN of the checkpoint. We can
 * traverse the list of committing contexts in xlog_cil_push_lsn() to find a
 * sequence match and extract the commit LSN directly from there. If the
 * checkpoint is still in the process of committing, we can block waiting for
 * the commit LSN to be determined as well. This should make synchronous
 * operations almost as efficient as the old logging methods.
 */
struct xfs_cil {
        struct xlog             *xc_log;
        struct list_head        xc_cil;
        spinlock_t              xc_cil_lock;

        struct rw_semaphore     xc_ctx_lock ____cacheline_aligned_in_smp;
        struct xfs_cil_ctx      *xc_ctx;

        spinlock_t              xc_push_lock ____cacheline_aligned_in_smp;
        xfs_lsn_t               xc_push_seq;
        struct list_head        xc_committing;
        wait_queue_head_t       xc_commit_wait;
        xfs_lsn_t               xc_current_sequence;
        struct work_struct      xc_push_work;
} ____cacheline_aligned_in_smp;
```

# test
## stack
```
[root@node-6 ~]# ps aux |grep dm-0
root      1794  0.0  0.0      0     0 ?        I<   Jul29   0:00 [xfs-buf/dm-0]
root      1795  0.0  0.0      0     0 ?        I<   Jul29   0:00 [xfs-data/dm-0]
root      1796  0.0  0.0      0     0 ?        I<   Jul29   0:00 [xfs-conv/dm-0]
root      1797  0.0  0.0      0     0 ?        I<   Jul29   0:00 [xfs-cil/dm-0]
root      1799  0.0  0.0      0     0 ?        I<   Jul29   0:00 [xfs-log/dm-0]
root      1801  0.0  0.0      0     0 ?        D    Jul29   0:02 [xfsaild/dm-0]
root     25991  0.0  0.0      0     0 ?        D    Jul29   0:00 [kworker/119:2+xfs-sync/dm-0]
root     28951  0.0  0.0      0     0 ?        D    Jul29   0:00 [kworker/64:0+xfs-cil/dm-0]
root     37619  0.0  0.0 216576  1600 pts/7    S+   12:28   0:00 grep --color=auto dm-0
root     61865  0.0  0.0      0     0 ?        D    Jul30   0:00 [kworker/2:0+xfs-eofblocks/dm-0]
[root@node-6 ~]# cat /proc/25991/stack
[<0>] __switch_to+0x6c/0x90
[<0>] flush_work+0x118/0x238
[<0>] xlog_cil_force_lsn+0x78/0x228 [xfs]
[<0>] xfs_log_force+0xb8/0x340 [xfs]
[<0>] xfs_log_worker+0x40/0x150 [xfs]
[<0>] process_one_work+0x1ac/0x3e8
[<0>] worker_thread+0x44/0x448
[<0>] kthread+0x130/0x138
[<0>] ret_from_fork+0x10/0x18
[<0>] 0xffffffffffffffff
[root@node-6 ~]# cat /proc/28951/stack
[<0>] __switch_to+0x6c/0x90
[<0>] xlog_state_get_iclog_space+0x124/0x310 [xfs]
[<0>] xlog_write+0x1c4/0x7a8 [xfs]
[<0>] xlog_cil_push+0x2e0/0x4d0 [xfs]
[<0>] xlog_cil_push_work+0x20/0x30 [xfs]
[<0>] process_one_work+0x1ac/0x3e8
[<0>] worker_thread+0x208/0x448
[<0>] kthread+0x130/0x138
[<0>] ret_from_fork+0x10/0x18
[<0>] 0xffffffffffffffff
[root@node-6 ~]# cat /proc/61865/stack
[<0>] __switch_to+0x6c/0x90
[<0>] xfs_ilock+0x7c/0x120 [xfs]
[<0>] xfs_free_eofblocks+0x150/0x1d8 [xfs]
[<0>] xfs_inode_free_eofblocks+0xfc/0x190 [xfs]
[<0>] xfs_inode_ag_walk.isra.5+0x1d0/0x3c8 [xfs]
[<0>] xfs_inode_ag_iterator_tag+0x84/0xc8 [xfs]
[<0>] xfs_eofblocks_worker+0x38/0x50 [xfs]
[<0>] process_one_work+0x1ac/0x3e8
[<0>] worker_thread+0x44/0x448
[<0>] kthread+0x130/0x138
[<0>] ret_from_fork+0x10/0x18
[<0>] 0xffffffffffffffff
```
