# xfs_repair
执行`xfs_repair -n`命令
```
:/# xfs_repair -n /dev/vda1 
Phase 1 - find and verify superblock...
would write modified primary superblock
Primary superblock would have been modified.
Cannot proceed further in no_modify mode.
Exiting now.

:/# xfs_repair  /dev/vda1 
Phase 1 - find and verify superblock...
writing modified primary superblock
        - reporting progress in intervals of 15 minutes
Phase 2 - using internal log
        - zero log...
ERROR: The filesystem has valuable metadata changes in a log which needs to
be replayed.  Mount the filesystem to replay the log, and unmount it before
re-running xfs_repair.  If you are unable to mount the filesystem, then use
the -L option to destroy the log and attempt a repair.
Note that destroying the log may cause corruption -- please attempt a mount
of the filesystem before doing this.
```
从日志中可以看到，需要先执行下mount, 然后再执行xfs_repair
# mount and xfs_repair
```
:/# mount /dev/vda1 /root/                                                                                                              
[  232.517786] XFS (vda1): Mounting V5 Filesystem                                                                                       
[  232.562637] XFS (vda1): Starting recovery (logdev: internal)                                                                         
[  232.593023] XFS (vda1): Corruption warning: Metadata has LSN (14:10589) ahead of current LSN (14:10519). Please unmount and run xfs_repair (>= v4.3) to resolve.
[  232.596708] XFS (vda1): Metadata corruption detected at xfs_agf_verify+0x160/0x1c0 [xfs], xfs_agf block 0x1bff201 
[  232.611015] XFS (vda1): Unmount and run xfs_repair               
[  232.612469] XFS (vda1): First 128 bytes of corrupted metadata buffer:
[  232.613949] ffff8ca1f4505a00: 58 41 47 46 00 00 00 01 00 00 00 07 00 07 ff c0  XAGF............
[  232.616235] ffff8ca1f4505a10: 00 00 00 01 00 00 00 02 00 00 00 00 00 00 00 01  ................
[  232.618519] ffff8ca1f4505a20: 00 00 00 01 00 00 00 00 00 00 00 01 00 00 00 04  ................
[  232.620783] ffff8ca1f4505a30: 00 00 00 04 00 00 65 2d 00 00 4c c7 00 00 00 00  ......e-..L.....
[  232.623088] ffff8ca1f4505a40: 6c d5 0e 51 cf c6 40 b9 9e c5 f3 2f a2 e4 ff 02  l..Q..@..../....
[  232.625382] ffff8ca1f4505a50: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
[  232.627781] ffff8ca1f4505a60: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
[  232.630065] ffff8ca1f4505a70: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
[  232.632367] XFS (vda1): metadata I/O error in "xfs_trans_read_buf_map" at daddr 0x1bff201 len 1 error 117
mount: mount /dev/vda1 on /root failed: Structure needs cleaning    
:/# xfs_repair  /dev/vda1                                           
Phase 1 - find and verify superblock...                             
        - reporting progress in intervals of 15 minutes                                                                                 
Phase 2 - using internal log                                        
        - zero log...                                               
        - scan filesystem freespace and inode maps...                                                                                   
sb_icount 0, counted 59392                                          
sb_ifree 0, counted 1800                                                                                                                
sb_fdblocks 0, counted 10359809                                     
        - 02:46:58: scanning filesystem freespace - 31 of 31 allocation groups done
        - found root inode chunk                                    
Phase 3 - for each AG...                                            
        - scan and clear agi unlinked lists...
        - 02:46:58: scanning agi unlinked lists - 31 of 31 allocation groups done
        - process known inodes and perform inode discovery...
        - agno = 0                                                  
        - agno = 30                                                 
        - agno = 15                                                 
        - agno = 16                                                 
        - agno = 17                                                 
        - agno = 18                                                 
        - agno = 19                                                 
        - agno = 20                                                 
        - agno = 21                                                 
        - agno = 22                                                 
        - agno = 23                                                 
        - agno = 24                                                 
        - agno = 25                                                 
        - agno = 26                                                 
        - agno = 27                                                 
        - agno = 28                                                 
        - agno = 29                                                 
correcting imap                                                     
imap claims a free inode 640 is in use, correcting imap and clearing inode
cleared inode 640                                                   
imap claims a free inode 14491 is in use, correcting imap and clearing inode
cleared inode 14491                                                 
imap claims a free inode 478519 is in use, correcting imap and clearing inode
cleared inode 478519                                                
imap claims a free inode 478521 is in use, correcting imap and clearing inode
cleared inode 478521                                                
        - agno = 1                                                  
imap claims a free inode 4283008 is in use, correcting imap and clearing inode
cleared inode 4283009
        - agno = 2
        - agno = 3
data fork in ino 15092743 claims free block 1886667
correcting imap
imap claims a free inode 15092744 is in use, correcting imap and clearing inode
cleared inode 15092744
        - agno = 4
data fork in ino 18423934 claims free block 2303026
        - agno = 5
        - agno = 6
        - agno = 7
        - agno = 8
        - agno = 9
        - agno = 10
        - agno = 11
        - agno = 12
        - agno = 13
        - agno = 14
        - 02:46:58: process known inodes and inode discovery - 59392 of 0 inodes done
        - process newly discovered inodes...
        - 02:46:58: process newly discovered inodes - 31 of 31 allocation groups done
Phase 4 - check for duplicate blocks...
        - setting up duplicate extent list...
        - 02:46:58: setting up duplicate extent list - 31 of 31 allocation groups done
        - check for inodes claiming duplicate blocks...
        - agno = 0
        - agno = 1
        - agno = 2
        - agno = 3
        - agno = 4
        - agno = 5
        - agno = 6
        - agno = 7
        - agno = 8
        - agno = 9
        - agno = 10
        - agno = 11
        - agno = 12
        - agno = 13
        - agno = 14
        - agno = 15
        - agno = 16
        - agno = 17
        - agno = 18
        - agno = 19
        - agno = 20
        - agno = 21
        - agno = 22
        - agno = 23
        - agno = 24
        - agno = 25
        - agno = 26
        - agno = 27
        - agno = 28
        - agno = 29
        - agno = 30
        - 02:46:59: check for inodes claiming duplicate blocks - 59392 of 0 inodes done
Phase 5 - rebuild AG headers and trees...
        - 02:46:59: rebuild AG headers and trees - 31 of 31 allocation groups done
        - reset superblock...
Phase 6 - check inode connectivity...
        - resetting contents of realtime bitmap and summary inodes
        - traversing filesystem ...
fixing ftype mismatch (2/1) in directory/child inode 121634880/478520
        - traversal finished ...
        - moving disconnected inodes to lost+found ...
disconnected dir inode 8523747, moving to lost+found
disconnected dir inode 29372434, moving to lost+found
disconnected dir inode 41946242, moving to lost+found
disconnected dir inode 121634880, moving to lost+found
Phase 7 - verify and correct link counts...
resetting inode 640 nlinks from 2 to 6
resetting inode 478520 nlinks from 1 to 2
resetting inode 121634880 nlinks from 4 to 3
        - 02:46:59: verify and correct link counts - 31 of 31 allocation groups done
Maximum metadata LSN (14:10589) is ahead of log (14:10521).
Format log to cycle 17.
done
```

# 进一步调查
## 通过xfs_db获取出问题的agf信息
通过 sb 命令获取 agblocks
```
xfs_db> sb 1
xfs_db> p
blocksize = 4096
...
agblocks = 524224
...
sectsize = 512
...
```
从上面信息结上面的dmesg信息来计算下:
```
dmesg信息:
[  188.988570] XFS (vda1): Metadata corruption detected at xfs_agf_verify+0x160/0x1c0 [xfs], xfs_agf block 0x1bff201

agf为sb下的第一个block，所以其在ag 的第一个block 为 0x1bff200

0x1bff200 / agblocks(524224) / 8 = 7
```
所以为第7个ag
执行`agf 7`查看内容:
```
xfs_db> p
magicnum = 0x58414746
versionnum = 1
seqno = 7
length = 524224
bnoroot = 1
cntroot = 2
rmaproot =
refcntroot =
bnolevel = 1
cntlevel = 1
rmaplevel = 0
refcntlevel = 0
rmapblocks = 0
refcntblocks = 0
flfirst = 1
fllast = 4
flcount = 4
freeblks = 25901
longest = 19655
btreeblks = 0
uuid = 6cd50e51-cfc6-40b9-9ec5-f32fa2e4ff02
lsn = 0xe0000295d
crc = 0x415b3488 (correct)
```
可见lsn 为 `0xe0000295d` -> `14:10589`

## 通过`xfs_logprint`查看log信息
获取到的cycle 14 的最后的lsn为:
```
cycle: 14       version: 2              lsn: 14,10512   tail_lsn: 14,10174
length of Log Record: 3072      prev offset: 10496              num ops: 27
uuid: 6cd50e51-cfc6-40b9-9ec5-f32fa2e4ff02   format: little endian linux
h_size: 32768
```
14,10512

确实如日志中打印的那样，lsn小于agf中填写的lsn, 但是是不是说log中记录了一些值，
记录错了，导致logprint 没有相关输出呢, 我们需要看下 disk raw data

## 查看 disk raw data
通过hexdump 查找 xlog_rec_header magicnum `0xfeedbabe`
```
fff8a600  fe ed ba be 00 00 00 0e  00 00 00 02 00 00 7e 00  |..............~.|
fff8a610  00 00 00 0e 00 00 00 33  00 00 00 0d 00 00 48 92  |.......3......H.|
fff8a620  6d 50 75 68 00 00 4f f3  00 00 00 fc 67 2e 6b 19  |mPuh..O.....g.k.|
fff8a630  67 2e 6b 19 67 2e 6b 19  67 2e 6b 19 67 2e 6b 19  |g.k.g.k.g.k.g.k.|
*
```

结合`xlog_rec_header`来看:
```
typedef struct xlog_rec_header {
	__be32 h_magicno;
	__be32 h_cycle;
	__be32 h_version;
	__be32 h_len;
	__be64 h_lsn;
	...
}
```
那么`00 00 00 0e 00 00 00 33` 是lsn的值，代表的是`14, 51`
那么从`xfs_logprint`输出来看, log record header 的顺序为:
lsn: 13,20467
lsn: 14,51
lsn: 14,115

所以, 该地址为新一轮cycle 的第一个`xlog_rec_header`, 那么
结合`sb.log_start`(`1048580`), 我们来计算下:
```
1048580 * 4096 + 51 * 512 = 0x10000a600
```
这个值显然是不对的。

我们从`xfs_logprint`开头可以看出
```
xfs_logprint:
    data device: 0xfc01
    log device: 0xfc01 daddr: 8387616 length: 20480
```
从这里得到log的firsh daddr为`8387616`,计算可得:
```
(8387616 + 51) * 512 = fff8a600
```
> **不知道为什么会出现这种情况 !!!**

我们想看下last `xlog_rec_header`之后的block中，
还有没有 `xlog_rec_header`。

最后的`xlog_rec_header`
```
cycle: 14       version: 2              lsn: 14,10512   tail_lsn: 14,10174
length of Log Record: 3072      prev offset: 10496              num ops: 27
uuid: 6cd50e51-cfc6-40b9-9ec5-f32fa2e4ff02   format: little endian linux
h_size: 32768
```
计算所在的daddr:
```
10512 + 8387616 = 8398128
```
查看附近的存储数据，在`daddr 8398135`, 找到了`xlog_rec_header` magicnum
```
xfs_db> daddr 8398135
xfs_db> p
000: feedbabe 0000000d 00000002 00000000 0000000d 00002917 0000000e 000027be
020: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
...
```
但是该lsn为`13:10519`
和日志中的
```
 XFS (vda1): Corruption warning: Metadata has LSN (14:10589) ahead of current LSN (14:10519). Please unmount and run xfs_repair (>= v4.3) to resolve.
```
不太相符。

是不是LSN 10589, 有对该metadata记录log呢，只不过是 LSN计算的有问题。
我们来继续看下。

## 继续调查
在lsn (14, 10085) 中有对 daddr 0x1bff201 (agf 7)做记录: 
```
============================================================================
cycle: 14       version: 2              lsn: 14,10085   tail_lsn: 14,7667
length of Log Record: 9728      prev offset: 10079              num ops: 102
uuid: 6cd50e51-cfc6-40b9-9ec5-f32fa2e4ff02   format: little endian linux
h_size: 32768
...
----------------------------------------------------------------------------
Oper (74): tid: a63f4887  len: 24  clientid: TRANS  flags: none
BUF:  #regs: 2   start blkno: 29356545 (0x1bff201)  len: 1  bmap size: 1  flags: 0x2800
Oper (75): tid: a63f4887  len: 128  clientid: TRANS  flags: none
AGF Buffer: XAGF
ver: 1  seq#: 7  len: 524224
root BNO: 1  CNT: 2
level BNO: 1  CNT: 1
1st: 1  last: 4  cnt: 4  freeblks: 25917  longest: 19655
----------------------------------------------------------------------------
Oper (76): tid: a63f4887  len: 24  clientid: TRANS  flags: none
BUF:  #regs: 2   start blkno: 29356560 (0x1bff210)  len: 8  bmap size: 1  flags: 0x2000
Oper (77): tid: a63f4887  len: 256  clientid: TRANS  flags: none
BUF DATA
----------------------------------------------------------------------------
Oper (78): tid: a63f4887  len: 24  clientid: TRANS  flags: none
BUF:  #regs: 2   start blkno: 29356552 (0x1bff208)  len: 8  bmap size: 1  flags: 0x2000
Oper (79): tid: a63f4887  len: 128  clientid: TRANS  flags: none
BUF DATA
----------------------------------------------------------------------------
```
我们来看下相关数据:
```
(8387616 + 10085) = 8397701
```
查看该数据:
```
xfs_db> daddr 8397714
xfs_db> p
000: 0000000e 69000000 0100023d c57f0f00 60656373 2d6f6666 6c696e65 2d6f7461
020: 02040000 80000000 a63f4887 00000068 69000000 0067027b 07270473 656c696e
040: 75787379 7374656d 5f753a6f 626a6563 745f723a 636f6e74 61696e65 725f7368
060: 6172655f 743a7330 000e2102 6f766572 6c61792e 6f726967 696e00fb 2100816c
080: d50e51cf c640b99e c5f32fa2 e4ff02e5 00400200 00000033 5bb44b00 a63f4887
0a0: 00000038 69000000 3b120400 43000000 18000800 00000000 80000004 00000000
0c0: 00000000 00000000 00000000 00000000 80e0ff03 00000000 20000000 00000000
0e0: a63f4887 000000b0 69000000 4e49ed41 03010000 00000000 00000000 02000000
100: 00000000 00000000 00000000 cd252963 1c039c16 cd252963 1c039c16 cd252963
120: 1c039c16 06000000 00000000 00000000 00000000 00000000 00000000 00002501
140: 00000000 00000000 25f65d82 ffffffff 0e000000 01000000 00000000 00000000
160: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 cd252963
180: 1c039c16 80000004 00000000 6cd50e51 cfc640b9 9ec5f32f a2e4ff02 a63f4887
1a0: 00000008 69000000 000003c0 0080ffff a63f4887 00000018 69000000 0016017b
1c0: 0e01026f 7665726c 61792e6f 70617175 6579ffff a63f4887 00000018 69000000
1e0: 3c120200 00280100 01f2bf01 00000000 01000000 01000000 a63f4887 00000080
			 |
			 该数据

xfs_db> daddr 8397716
xfs_db> p
000: 0000000e 58414746 00000001 00000007 0007ffc0 00000001 00000002 00000000
020: 00000001 00000001 00000000 00000001 00000004 00000004 0000653d 00004cc7
040: 00000000 6cd50e51 cfc640b9 9ec5f32f a2e4ff02 00000000 00000000 00000000
060: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
080: 00000000 a63f4887 00000018 69000000 3c120200 00200800 10f2bf01 00000000
0a0: 01000000 03000000 a63f4887 00000100 69000000 41423343 0000000e ffffffff
0c0: ffffffff 00000000 01bff210 0000000e 00001b93 6cd50e51 cfc640b9 9ec5f32f
			|
			记录的下一个
0e0: a2e4ff02 00000007 fb439d3e 000019c2 00000001 0000241c 00000001 000024dd
100: 00000001 0000240e 00000002 00001425 00000003 00001a12 00000008 000024ce
120: 0000000b 000013ef 00000026 000019c9 00000045 000024e3 00000245 00007f15
140: 0000041c 00001430 00000591 000007d9 00000bfe 0004832d 00004cc7 0004832d
160: 00004cc7 0004832d 00004cc7 00000000 00000000 00000000 00000000 00000000
180: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
1a0: 00000000 00000000 00000000 00000000 00000000 a63f4887 00000018 69000000
1c0: 3c120200 00200800 08f2bf01 00000000 01000000 01000000 a63f4887 00000080
1e0: 69000000 41423342 0000000e ffffffff ffffffff 00000000 01bff208 0000000e
							     |
							   记录的下一个
...
```
找到了相关记录但是记录的blkno为`01f2bf01`, 不知道为什么
> NOTE
> 
> 所对应的数据结构有:
> * struct xfs_trans_header 
> * struct xfs_buf_log_format
> 这里不带着大家分析了

我们来看下:
LSN (14:10589) 相关数据:
```
(8387616 + 10589) = 8398205
```
查看该部分数据:
```
xfs_db> daddr 8398205
xfs_db> p
000: feedbabe 0000000d 00000002 00000000 0000000d 0000295d 0000000e 000027be
020: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
040: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
060: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
080: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
0a0: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
0c0: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
0e0: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
100: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
120: 00000000 00000000 00000000 00000001 6cd50e51 cfc640b9 9ec5f32f a2e4ff02
140: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
160: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
180: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
1a0: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
1c0: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
1e0: 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
xfs_db> daddr 8398206
xfs_db> p
000: feedbabe 0000000d 00000002 00000000 0000000d 0000295e 0000000e 000027be
...
```
可见并没有相关数据, 并且lsn 也为 13(d) 而不是 14(e) 所以可以暂时得出结论:

> 在 cycle 14 last lsn 14:10512 之后，并没有记录别的log。
> 而agf 中的lsn(14:10589) > cycle 14 last lsn
>
> 所以，也就是说明在没有记录log的情况下，更改了metadata,
> 这不符合xfs逻辑

> 目前有两点怀疑:
>
> 1. guest kernel 处理xfs文件系统相关操作有问题。
>
> 2. 存储端有问题，丢失了xfs log 的部分数据写入
