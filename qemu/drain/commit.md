# 1
```
commit 922453bca6a927bb527068ae8679d587cfa45dbc
Author: Stefan Hajnoczi <stefanha@linux.vnet.ibm.com>
Date:   Wed Nov 30 12:23:43 2011 +0000

    block: convert qemu_aio_flush() calls to bdrv_drain_all()

    可以看下早期qemu的 qemu_aio_flush()的流程, 如何等待 aio返回.
```

# 2
```
commit a77fd4bb2988c05953fdc9f1524085870ec1c939
Author: Fam Zheng <famz@redhat.com>
Date:   Tue Apr 5 19:20:52 2016 +0800

    block: Fix bdrv_drain in coroutine (引入 bdrv_co_drain_bh_cb)

```

# blockio limits
```
commit 0563e191516289c9d2f282a8c50f2eecef2fa773
Author: Zhi Yong Wu <wuzhy@linux.vnet.ibm.com>
Date:   Thu Nov 3 16:57:25 2011 +0800

    block: add the blockio limits command line support

commit 98f90dba5ee56f699b28509a6cc7a9a8a57636eb
Author: Zhi Yong Wu <wuzhy@linux.vnet.ibm.com>
Date:   Tue Nov 8 13:00:14 2011 +0800

    block: add I/O throttling algorithm
```

# new blockio limits
https://mail.gnu.org/archive/html/qemu-devel/2013-09/msg00052.html
