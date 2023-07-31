# bt -f 
```
PID: 34685  TASK: ffffa6d08c22ec00  CPU: 44  COMMAND: "find"
 #0 [ffff000060f2f970] __switch_to at ffff55d931ac74b8
    ffff000060f2f970: ffff000060f2f990 ffff55d9323960f8
    ffff000060f2f980: ffffa6f47fc4dd00 ffffa6f443186600
 #1 [ffff000060f2f990] __schedule at ffff55d9323960f4
    ffff000060f2f990: ffff000060f2fa20 ffff55d932396758
    ffff000060f2f9a0: 0000000000000002 ffffc6f421db0078
    ffff000060f2f9b0: ffff55d932e93708 ffff000060f2fa88
    ffff000060f2f9c0: ffffffffffffffff ffff00006742fa98
    ffff000060f2f9d0: ffff000060f2fa98 0000000000000000
    ffff000060f2f9e0: 0000000000000000 ffff000060f2fe54
    ffff000060f2f9f0: 0000000000000000 0000000000000000
    ffff000060f2fa00: ffff000060f2fa30 ffff55d932399458
    ffff000060f2fa10: 0000000000000004 b3e4fc7e9e15a700
 #2 [ffff000060f2fa20] schedule at ffff55d932396754
    ffff000060f2fa20: ffff000060f2fa30 ffff55d932399474
 #3 [ffff000060f2fa30] rwsem_down_read_failed at ffff55d932399470
    ffff000060f2fa30: ffff000060f2fac0 ffff55d932399234
    ffff000060f2fa40: ffffc6f421db0078 ffffc6f421db0000
    ffff000060f2fa50: ffffc6f421db0000 ffff55d91e15ba70
    ffff000060f2fa60: ffff55d91e14b260 0000000000000004
    ffff000060f2fa70: 0000000000000000 ffff55d931d60010
    ffff000060f2fa80: ffff000060f2faa0 0000000000000001
    ffff000060f2fa90: ffff000060f2fa88 ffff00006114fa98
    ffff000060f2faa0: ffff00006742fa98 ffffa6d08c22ec00
    ffff000060f2fab0: ffffc6f400000001 b3e4fc7e9e15a700
 #4 [ffff000060f2fac0] down_read at ffff55d932399230
    ffff000060f2fac0: ffff000060f2fae0 ffff55d91e15b960
    ffff000060f2fad0: 0000000000000008 0000000000000000
 #5 [ffff000060f2fae0] xfs_ilock at ffff55d91e15b95c [xfs]
    ffff000060f2fae0: ffff000060f2fb10 ffff55d91e15ba70
    ffff000060f2faf0: 0000000000000008[lock_flags] ffffc6f421db0000[xfs_inode_t *ip]
    ffff000060f2fb00: ffffc6f421db0000 ffffa6d3ffe13010
 #6 [ffff000060f2fb10] xfs_ilock_data_map_shared at ffff55d91e15ba6c [xfs]
    ffff000060f2fb10: ffff000060f2fb30 ffff55d91e14b2b0
    ffff000060f2fb20: 0000000000000000 ffffc6f421db0138
 #7 [ffff000060f2fb30] xfs_dir_open at ffff55d91e14b2ac [xfs]
    ffff000060f2fb30: ffff000060f2fb60 ffff55d931d4b974
    ffff000060f2fb40: ffffa6d3ffe13000 ffffc6f421db0138
    ffff000060f2fb50: 0000000000000000 ffffa6d3ffe13010
 #8 [ffff000060f2fb60] do_dentry_open at ffff55d931d4b970
    ffff000060f2fb60: ffff000060f2fba0 ffff55d931d4d2c0
    ffff000060f2fb70: ffff000060f2fd20 ffffa6d3ffe13000
    ffff000060f2fb80: 0000000000020000 ffff000060f2fcc4
    ffff000060f2fb90: ffffa6d3ffe13000 0000000000000004
 #9 [ffff000060f2fba0] vfs_open at ffff55d931d4d2bc
    ffff000060f2fba0: ffff000060f2fbc0 ffff55d931d60fa8
    ffff000060f2fbb0: ffff000060f2fd20 ffff55d932e93708
```
# dis xfs_ilock_data_map_shared
```
crash> dis xfs_ilock_data_map_shared
...
0xffff55d91e15ba64 <xfs_ilock_data_map_shared+60>:      mov     x0, x20  (ip)
0xffff55d91e15ba68 <xfs_ilock_data_map_shared+64>:      mov     w1, w19  (lock_flags)
0xffff55d91e15ba6c <xfs_ilock_data_map_shared+68>:      bl      0xffff55d91e15b908 <xfs_ilock>
...
```
# dis  xfs_ilock
```
0xffff55d91e15b908 <xfs_ilock>: stp     x29, x30, [sp,#-48]!
0xffff55d91e15b90c <xfs_ilock+4>:       mov     x29, sp
0xffff55d91e15b910 <xfs_ilock+8>:       stp     x19, x20, [sp,#16]
0xffff55d91e15b914 <xfs_ilock+12>:      stp     x21, x22, [sp,#32]
0xffff55d91e15b918 <xfs_ilock+16>:      mov     x21, x0
0xffff55d91e15b91c <xfs_ilock+20>:      mov     x22, x30
```
# struct xfs_inode ffffc6f421db0000
```
xfs_inode.i_vnode.i_rwsem.owner = 0xffffa6d3acfd4300
```


