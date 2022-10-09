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
