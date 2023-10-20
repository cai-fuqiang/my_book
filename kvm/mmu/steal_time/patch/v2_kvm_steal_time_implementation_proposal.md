```
From: Glauber Costa <glommer@redhat.com>
To: kvm@vger.kernel.org
Cc: avi@redhat.com, zamsden@redhat.com, mtosatti@redhat.com,
	riel@redhat.com, peterz@infradead.org, mingo@elte.hu,
	jeremy@goop.org
Subject: [RFC v2 0/7] kvm steal time implementation proposal
Date: Mon, 30 Aug 2010 13:06:34 -0400	[thread overview]
Message-ID: <1283188001-7911-1-git-send-email-glommer@redhat.com> (raw)

Hi,

So, this is basically the same as v1, with three major
differences:
 1) I am posting to lkml for wider audience
 2) patch 2/7 fixes one problem I mentined would happen in
   smp systems, which is, we only update kvmclock when we
   changes pcup
 3) softlockup algorithm is changed. Again, as marcelo pointed
   out, this is open to discussion, and I am not dropping it
   so more people can step in.

I have some other patches under local test for a slightly modified
guest part accounting, and I do somehow support extending
the interface, and changing to nsecs (maybe not 100 %, but...). But
I am posting in this state so we can have lkml people to step
in earlier.

Reminder of the previous cover-letter:

There are two parts of it: the guest and host part.

The proposal for the guest part, is to just change the
common time accounting, and try to identify at that spot,
wether or not we should account any steal time. I considered
this idea less cumbersome that trying to cook a clockevents
implementation ourselves, since I see little value in it.
I am, however, pretty open to suggestions.

> proposal : 提议, 建议
>
>

For the host<->guest communications, I am using a shared
page, in the same way as pvclock. Because of that, I am just
hijacking pvclock structure anyway. There is a 32-bit field
floating by, that gives us enough room for 8 years of steal
time (we use msec resolution).

> hijacking : 劫持
>
>

The main idea is to timestamp our exit and entry through
sched notifiers, and export the value at pvclock updates.
This obviously have some disadvantages: by doing this we
are giving up futures ideas about only updating
this structure once, and even right now, won't work
on pinned-smp (since we don't update pvclock if we
haven't changed cpus.)

But again, it is just an RFC, and I'd like to feel the
reception of the idea as a whole.

Glauber Costa (7):
  change headers preparing for steal time
  always call kvm_write_guest
  measure time out of guest
  change kernel accounting to include steal time
  kvm steal time implementation
  touch softlockup watchdog
  tell guest about steal time feature

 arch/x86/include/asm/kvm_host.h    |    2 +
 arch/x86/include/asm/kvm_para.h    |    1 +
 arch/x86/include/asm/pvclock-abi.h |    4 ++-
 arch/x86/kernel/kvmclock.c         |   40 ++++++++++++++++++++++++++++++++++++
 arch/x86/kvm/x86.c                 |   26 ++++++++++++++++++----
 include/linux/sched.h              |    1 +
 kernel/sched.c                     |   29 ++++++++++++++++++++++++++
 7 files changed, 97 insertions(+), 6 deletions(-)
```
