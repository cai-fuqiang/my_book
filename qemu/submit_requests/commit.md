# aio poll polling mode
## commit
```
commit 4a1cba3802554a3b077d436002519ff1fb0c18bf
Author: Stefan Hajnoczi <stefanha@redhat.com>
Date:   Thu Dec 1 19:26:42 2016 +0000

    aio: add polling mode to AioContext

    add:
    	struct AioContext->poll_disable_cnt, poll_max_ns


commit 684e508c23d28af8d6ed2c62738a0f60447c8274
Author: Stefan Hajnoczi <stefanha@redhat.com>
Date:   Thu Dec 1 19:26:49 2016 +0000

    aio: add .io_poll_begin/end() callbacks

    The begin and end callbacks can be used to prepare for the polling loop
    and clean up when polling stops.  Note that they may only be called once
    for multiple aio_poll() calls if polling continues to succeed.  Once
    polling fails the end callback is invoked before aio_poll() resumes file
    descriptor monitoring.


commit e4346192f1c2e1683a807b46efac47ef0cf9b545
Author: Stefan Hajnoczi <stefanha@redhat.com>
Date:   Thu Mar 5 17:08:00 2020 +0000

    aio-posix: completely stop polling when disabled
```
## maillist
https://marc.info/?l=qemu-devel&m=148062066405481&w=2

# commit 2
```
commit e30cffa04d52e35996569f1cfac111be19576bde
Author: Paolo Bonzini <pbonzini@redhat.com>
Date:   Wed Sep 12 19:10:39 2018 +0200

    aio-posix: compute timeout before polling
```
