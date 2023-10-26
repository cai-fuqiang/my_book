```
Subject: [PATCH v4 00/10] PCID and improved laziness
Date: Thu, 29 Jun 2017 08:53:12 -0700	[thread overview]
Message-ID: <cover.1498751203.git.luto@kernel.org> (raw)

*** Ingo, even if this misses 4.13, please apply the first patch before
*** the merge window.

There are three performance benefits here:

1. TLB flushing is slow.  (I.e. the flush itself takes a while.)
   This avoids many of them when switching tasks by using PCID.  In
   a stupid little benchmark I did, it saves about 100ns on my laptop
   per context switch.  I'll try to improve that benchmark.

2. Mms that have been used recently on a given CPU might get to keep
   their TLB entries alive across process switches with this patch
   set.  TLB fills are pretty fast on modern CPUs, but they're even
   faster when they don't happen.

3. Lazy TLB is way better.  We used to do two stupid things when we
   ran kernel threads: we'd send IPIs to flush user contexts on their
   CPUs and then we'd write to CR3 for no particular reason as an excuse
   to stop further IPIs.  With this patch, we do neither.

This will, in general, perform suboptimally if paravirt TLB flushing
is in use (currently just Xen, I think, but Hyper-V is in the works).
The code is structured so we could fix it in one of two ways: we
could take a spinlock when touching the percpu state so we can update
it remotely after a paravirt flush, or we could be more careful about
our exactly how we access the state and use cmpxchg16b to do atomic
remote updates.  (On SMP systems without cmpxchg16b, we'd just skip
the optimization entirely.)

This is still missing a final comment-only patch to add overall
documentation for the whole thing, but I didn't want to block sending
the maybe-hopefully-final code on that.

This is based on tip:x86/mm.  The branch is here if you want to play:
https://git.kernel.org/pub/scm/linux/kernel/git/luto/linux.git/log/?h=x86/pcid

In general, performance seems to exceed my expectations.  Here are
some performance numbers copy-and-pasted from the changelogs for
"Rework lazy TLB mode and TLB freshness" and "Try to preserve old
TLB entries using PCID":

MADV_DONTNEED; touch the page; switch CPUs using sched_setaffinity.  In
an unpatched kernel, MADV_DONTNEED will send an IPI to the previous CPU.
This is intended to be a nearly worst-case test.
patched:         13.4µs
unpatched:       21.6µs

Vitaly's pthread_mmap microbenchmark with 8 threads (on four cores),
nrounds = 100, 256M data
patched:         1.1 seconds or so
unpatched:       1.9 seconds or so

ping-pong between two mms on the same CPU using eventfd:
  patched:         1.22µs
  patched, nopcid: 1.33µs
  unpatched:       1.34µs

Same ping-pong, but now touch 512 pages (all zero-page to minimize
cache misses) each iteration.  dTLB misses are measured by
dtlb_load_misses.miss_causes_a_walk:
  patched:         1.8µs  11M  dTLB misses
  patched, nopcid: 6.2µs, 207M dTLB misses
  unpatched:       6.1µs, 190M dTLB misses

MADV_DONTNEED; touch the page; switch CPUs using sched_setaffinity.  In
an unpatched kernel, MADV_DONTNEED will send an IPI to the previous CPU.
This is intended to be a nearly worst-case test.
  patched:         13.4µs
  unpatched:       21.6µs

Changes from v3:
 - Lots more acks.
 - Move comment deletion to the beginning.
 - Misc cleanups from lots of reviewers.

Changes from v2:
 - Add some Acks
 - Move the reentrancy issue to the beginning.
   (I also sent the same patch as a standalone fix -- it's just in here
    so that this series applies to x86/mm.)
 - Fix some comments.

Changes from RFC:
 - flush_tlb_func_common() no longer gets reentered (Nadav)
 - Fix ASID corruption on unlazying (kbuild bot)
 - Move Xen init to the right place
 - Misc cleanups
```
