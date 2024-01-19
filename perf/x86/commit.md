```
commit ee06094f8279e1312fc0a31591320cc7b6f0ab1e
Author: Ingo Molnar <mingo@elte.hu>
Date:   Sat Dec 13 09:00:03 2008 +0100

    perfcounters: restructure x86 counter math

    Impact: restructure code

commit 241771ef016b5c0c83cd7a4372a74321c973c1e6
Author: Ingo Molnar <mingo@elte.hu>
Date:   Wed Dec 3 10:39:53 2008 +0100

    performance counters: x86 support

    Implement performance counters for x86 Intel CPUs.

    It's simplified right now: the PERFMON CPU feature is assumed,
    which is available in Core2 and later Intel CPUs.

    The design is flexible to be extended to more CPU types as well.

    Signed-off-by: Ingo Molnar <mingo@elte.hu>

commit e7bc62b6b3aeaa8849f8383e0cfb7ca6c003adc6
Author: Ingo Molnar <mingo@elte.hu>
Date:   Thu Dec 4 20:13:45 2008 +0100

    performance counters: documentation

    Add more documentation about performance counters.

    Signed-off-by: Ingo Molnar <mingo@elte.hu>

commit 0793a61d4df8daeac6492dbf8d2f3e5713caae5e
Author: Thomas Gleixner <tglx@linutronix.de>
Date:   Thu Dec 4 20:12:29 2008 +0100

    performance counters: core code

    Implement the core kernel bits of Performance Counters subsystem.

    The Linux Performance Counter subsystem provides an abstraction of
    performance counter hardware capabilities. It provides per task and per
    CPU counters, and it provides event capabilities on top of those.

    Performance counters are accessed via special file descriptors.
    There's one file descriptor per virtual counter used.

    The special file descriptor is opened via the perf_counter_open()
    system call:

     int
     perf_counter_open(u32 hw_event_type,
                       u32 hw_event_period,
                       u32 record_type,
                       pid_t pid,
                       int cpu);

    The syscall returns the new fd. The fd can be used via the normal
    VFS system calls: read() can be used to read the counter, fcntl()
    can be used to set the blocking mode, etc.

    Multiple counters can be kept open at a time, and the counters
    can be poll()ed.

    See more details in Documentation/perf-counters.txt.

    Signed-off-by: Thomas Gleixner <tglx@linutronix.de>
    Signed-off-by: Ingo Molnar <mingo@elte.hu>

commit b5aa97e83bcc31a96374d18f5452d53909a16c90
Merge: 218d11a8b071 4217458dafaa 5b3eec0c8003
Author: Ingo Molnar <mingo@elte.hu>
Date:   Mon Dec 8 15:46:30 2008 +0100

    Merge branches 'x86/signal' and 'x86/irq' into perfcounters/core

    Merge these pending x86 tree changes into the perfcounters tree
    to avoid conflicts.
```


[performance counters: x86 support](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=241771ef016b5c0c83cd7a4372a74321c973c1e6)
[performance counters: documentation](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=e7bc62b6b3aeaa8849f8383e0cfb7ca6c003adc6)
[performance counters: core code](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=0793a61d4df8daeac6492dbf8d2f3e5713caae5e)
