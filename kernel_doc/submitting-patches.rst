.. _submittingpatches:

Submitting patches: the essential guide to getting your code into the kernel
============================================================================

essential: 基本的;基础的

For a person or company who wishes to submit a change to the Linux
kernel, the process can sometimes be daunting if you're not familiar
with "the system."  This text is a collection of suggestions which
can greatly increase the chances of your change being accepted.::

  daunting ==> [dɔːntɪŋ] adj.令人畏惧的 动词daunt的现在分词.

This document contains a large number of suggestions in a relatively terse
format.  For detailed information on how the kernel development process
works, see Documentation/process/development-process.rst. Also, read
Documentation/process/submit-checklist.rst
for a list of items to check before submitting code.
For device tree binding patches, read
Documentation/devicetree/bindings/submitting-patches.rst.::

relatively ==> ['relətɪvli] adv.相对地；比较地
terse: 简洁

This documentation assumes that you're using ``git`` to prepare your patches.
If you're unfamiliar with ``git``, you would be well-advised to learn how to
use it, it will make your life as a kernel developer and in general much
easier.

well-advised: 细心的, 有思虑的
in general: 一般来说

Some subsystems and maintainer trees have additional information about
their workflow and expectations, see
:ref:`Documentation/process/maintainer-handbooks.rst <maintainer_handbooks_main>`.

workflow: 工作流
expectations: 期望

Obtain a current source tree
----------------------------

If you do not have a repository with the current kernel source handy, use
``git`` to obtain one.  You'll want to start with the mainline repository,
which can be grabbed with::

  git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

handy: 有用的, 方便的; 手边的,便于使用的; (现成的)
grab: 捕获, 匆忙去做, 强夺

Note, however, that you may not want to develop against the mainline tree
directly.  Most subsystem maintainers run their own trees and want to see
patches prepared against those trees.  See the **T:** entry for the subsystem
in the MAINTAINERS file to find that tree, or simply ask the maintainer if
the tree is not listed there.

.. _describe_changes:

Describe your changes
---------------------

Describe your problem.  Whether your patch is a one-line bug fix or
5000 lines of a new feature, there must be an underlying problem that
motivated you to do this work.  Convince the reviewer that there is a
problem worth fixing and that it makes sense for them to read past the
first paragraph.

underlying: 潜在的
motivated: 成为...的动机; 驱动
Convince: 使确认, 使信服
worth: 有价值的
make sense for: 对...有价值
past: 从一侧到另一侧

Describe user-visible impact.  Straight up crashes and lockups are
pretty convincing, but not all bugs are that blatant.  Even if the
problem was spotted during code review, describe the impact you think
it can have on users.  Keep in mind that the majority of Linux
installations run kernels from secondary stable trees or
vendor/product-specific trees that cherry-pick only specific patches
from upstream, so include anything that could help route your change
downstream: provoking circumstances, excerpts from dmesg, crash
descriptions, performance regressions, latency spikes, lockups, etc.

straight up: 直率的, 真实的
convincing: 令人信服的，有说服力的
blatant: 公然地, 明目张胆的; 直白的, 极明显的
spotted: 看见，注意到; 发现, 挖掘
Keep in mind: 记住
majority: 大多数
cherry-pick: 择优挑选;筛选
provoke: 诱发
circumstances: 环境，状况
excerpts: 摘由，节选
regressions: 后退，倒退
spikes: 峰值

Quantify optimizations and trade-offs.  If you claim improvements in
performance, memory consumption, stack footprint, or binary size,
include numbers that back them up.  But also describe non-obvious
costs.  Optimizations usually aren't free but trade-offs between CPU,
memory, and readability; or, when it comes to heuristics, between
different workloads.  Describe the expected downsides of your
optimization so that the reviewer can weigh costs against benefits.

quantify: 量化
trade-offs: 衡量
consumption: 消耗
footprint: 访问足迹, 是一个数值，表示程序最大访问地址和最小访问地址的差值
back ... up: 协防，补防 (支持, 支撑)

Once the problem is established, describe what you are actually doing
about it in technical detail.  It's important to describe the change
in plain English for the reviewer to verify that the code is behaving
as you intend it to.

establish: 建立, 确立; 确定, 证实
technical: 技术的
plain: 朴素的, 直白的

The maintainer will thank you if you write your patch description in a
form which can be easily pulled into Linux's source code management
system, ``git``, as a "commit log".  See :ref:`the_canonical_patch_format`.

canonical: 典型的

Solve only one problem per patch.  If your description starts to get
long, that's a sign that you probably need to split up your patch.
See :ref:`split_changes`.

sign: 迹象，征兆

When you submit or resubmit a patch or patch series, include the
complete patch description and justification for it.  Don't just
say that this is version N of the patch (series).  Don't expect the
subsystem maintainer to refer back to earlier patch versions or referenced
URLs to find the patch description and put that into the patch.
I.e., the patch (series) and its description should be self-contained.
This benefits both the maintainers and reviewers.  Some reviewers
probably didn't even receive earlier versions of the patch.

justification: 正当理由

Describe your changes in imperative mood, e.g. "make xyzzy do frotz"
instead of "[This patch] makes xyzzy do frotz" or "[I] changed xyzzy
to do frotz", as if you are giving orders to the codebase to change
its behaviour.

imperative: 极重要的;必要的;命令的
imperative mood: 祈使语气; 命令语气; 祁使式

If you want to refer to a specific commit, don't just refer to the
SHA-1 ID of the commit. Please also include the oneline summary of
the commit, to make it easier for reviewers to know what it is about.
Example::

	Commit e21d2170f36602ae2708 ("video: remove unnecessary
	platform_set_drvdata()") removed the unnecessary
	platform_set_drvdata(), but left the variable "dev" unused,
	delete it.

You should also be sure to use at least the first twelve characters of the
SHA-1 ID.  The kernel repository holds a *lot* of objects, making
collisions with shorter IDs a real possibility.  Bear in mind that, even if
there is no collision with your six-character ID now, that condition may
change five years from now.

collisions: 冲突,碰撞
bear in mind that：请记住

If related discussions or any other background information behind the change
can be found on the web, add 'Link:' tags pointing to it. In case your patch
fixes a bug, for example, add a tag with a URL referencing the report in the
mailing list archives or a bug tracker; if the patch is a result of some
earlier mailing list discussion or something documented on the web, point to
it.

archives : ['ɑːkaɪvz] n.档案；档案馆

When linking to mailing list archives, preferably use the lore.kernel.org
message archiver service. To create the link URL, use the contents of the
``Message-Id`` header of the message without the surrounding angle brackets.
For example::

    Link: https://lore.kernel.org/r/30th.anniversary.repost@klaava.Helsinki.FI/

preferably ==> ['prefrəbli] adv.更好地；宁可；宁愿
contents ==> ['kɒntents] n.内容；目录；内有的物品 名词content的复数形式.
surrounding ==> [sə'raʊndɪŋ] adj.周围的 n.环境；周围的事物
angle ==> ['æ ŋ ɡl] n.角度；角；观点 v.形成或转变角度；歪曲 v.钓鱼；谋取 Angle. n.盎格鲁人
brackets ==> [bræ kəts] n.括号 名词bracket的复数形式.

angle bracket ==> 尖角括号

Please check the link to make sure that it is actually working and points
to the relevant message.

relevant ==> ['reləvənt] adj.相关的；切题的；中肯的；有重大关系的；有意义的，目的明确的

However, try to make your explanation understandable without external
resources. In addition to giving a URL to a mailing list archive or bug,
summarize the relevant points of the discussion that led to the
patch as submitted.
"
explanation ==> [ˌeksplə'neɪʃn] n.解释；说明
understandable ==> [ˌʌndər'st æ ndəbl] adj.可理解的；能够懂的

If your patch fixes a bug in a specific commit, e.g. you found an issue using
``git bisect``, please use the 'Fixes:' tag with the first 12 characters of
the SHA-1 ID, and the one line summary.  Do not split the tag across multiple
lines, tags are exempt from the "wrap at 75 columns" rule in order to simplify
parsing scripts.  For example::

	Fixes: 54a4f0239f2e ("KVM: MMU: make kvm_mmu_zap_page() return the number of pages it actually freed")

exempt ==> [ɪɡ'zempt] adj.免除的 vt.免除 n.免税者；被免除义务者

The following ``git config`` settings can be used to add a pretty format for
outputting the above style in the ``git log`` or ``git show`` commands::

	[core]
		abbrev = 12
	[pretty]
		fixes = Fixes: %h (\"%s\")

An example call::

	$ git log -1 --pretty=fixes 54a4f0239f2e
	Fixes: 54a4f0239f2e ("KVM: MMU: make kvm_mmu_zap_page() return the number of pages it actually freed")

.. _split_changes:

Separate your changes
---------------------

Separate each **logical change** into a separate patch.

separate ==> ['sepərət] adj.分开的；不同的；单独的；各自的 v.分开；隔开；区分；分居；脱离 n.分开；抽印本

For example, if your changes include both bug fixes and performance
enhancements for a single driver, separate those changes into two
or more patches.  If your changes include an API update, and a new
driver which uses that new API, separate those into two patches.

enhancements ==> [ɪn'hɑːnsmənts] n.增强；提高 名词enhancement的复数形式.

On the other hand, if you make a single change to numerous files,
group those changes into a single patch.  Thus a single logical change
is contained within a single patch.

numerous ==> ['nuːmərəs] adj.为数众多的；许多

The point to remember is that each patch should make an easily understood
change that can be verified by reviewers.  Each patch should be justifiable
on its own merits.

justifiable ==> ['dʒʌstɪfaɪəbl] adj.可辩解的；可证明为正当的；有理的
merits ==> ['merɪts] n.功绩 名词merit的复数形式.

If one patch depends on another patch in order for a change to be
complete, that is OK.  Simply note **"this patch depends on patch X"**
in your patch description.

When dividing your change into a series of patches, take special care to
ensure that the kernel builds and runs properly after each patch in the
series.  Developers using ``git bisect`` to track down a problem can end up
splitting your patch series at any point; they will not thank you if you
introduce bugs in the middle.

track down : 追踪到
split ==> [splɪt] v.分裂；将…分成若干部分；分摊；分离；劈开；裂开；
splitting ==> ['splɪtɪŋ] adj.剧烈的 动词split的现在分词.

NOTE: 假如说一系列的patch，要做到每个patch kernel build 和 runs  properly。
否则可能影响到developer 使用 ``git bisect`` 来track down 问题

If you cannot condense your patch set into a smaller set of patches,
then only post say 15 or so at a time and wait for review and integration.

condense ==> [kən'dens] v.浓缩；凝结；缩短
integration ==> [ˌɪntɪ'ɡreɪʃn] n.集成；综合；同化

Style-check your changes
------------------------

Check your patch for basic style violations, details of which can be
found in Documentation/process/coding-style.rst.
Failure to do so simply wastes
the reviewers time and will get your patch rejected, probably
without even being read.

violations ==> [vaɪə'leɪʃnz] n.侵害，违反（名词violation的复数形式）
failure ==> ['feɪljər] n.失败；失败者；不及格；疏忽；失灵；未能；悲惨的事
wastes ==> ['weɪsts] n.废料 名词waste的复数形式.

One significant exception is when moving code from one file to
another -- in this case you should not modify the moved code at all in
the same patch which moves it.  This clearly delineates the act of
moving the code and your changes.  This greatly aids review of the
actual differences and allows tools to better track the history of
the code itself.

at all ==> 根本，完全
delineates ==> [dɪ'lɪnieɪt] vt.描绘；叙述；画出
aid ==> [eɪd] n.援助；帮助；救援；助手；辅助物 v.辅助；援助；接济

Check your patches with the patch style checker prior to submission
(scripts/checkpatch.pl).  Note, though, that the style checker should be
viewed as a guide, not as a replacement for human judgment.  If your code
looks better with a violation then its probably best left alone.

prior ==> ['praɪər] adj.优先的；在前的；更重要的 adv.居先；在前
judgment ==> ['dʒʌdʒmənt] n.裁判；判断；判断力；意见；判决书
violation ==> [ˌvaɪə'leɪʃn] n.违反；违背；妨碍
judgment ==> ['dʒʌdʒmənt] n.裁判；判断；判断力；意见；判决书

The checker reports at three levels:
 - ERROR: things that are very likely to be wrong
 - WARNING: things requiring careful review
 - CHECK: things requiring thought

You should be able to justify all violations that remain in your
patch.

justify ==> ['dʒʌstɪfaɪ] vt.替 ... 辩护；证明 ... 正当；调整版面

Select the recipients for your patch
------------------------------------

recipients ==> [rɪ'sɪpiənt] n.接受者；收信人
Linus Torvalds is the final arbiter of all changes accepted into the Linux kernel.
You should always copy the appropriate subsystem maintainer(s) on any patch
to code that they maintain; look through the MAINTAINERS file and the
source code revision history to see who those maintainers are.  The
script scripts/get_maintainer.pl can be very useful at this step (pass paths to
your patches as arguments to scripts/get_maintainer.pl).  If you cannot find a
maintainer for the subsystem you are working on, Andrew Morton
(akpm@linux-foundation.org) serves as a maintainer of last resort.

appropriate ==> [ə'proʊpriət] adj.适当的；相称的 vt.占用；拨出(款项)
resort ==> [rɪ'zɔːrt] n.(度假)胜地；手段；凭借 vi.诉诸；常去

You should also normally choose at least one mailing list to receive a copy
of your patch set.  linux-kernel@vger.kernel.org should be used by default
for all patches, but the volume on that list has caused a number of
developers to tune it out.  Look in the MAINTAINERS file for a
subsystem-specific list; your patch will probably get more attention there.
Please do not spam unrelated lists, though.

attention ==> [ə'tenʃn] n.注意；注意力；照料；留心；关怀；(口令)立正
though ==> 可是，不过, 然而
spam ==> [spæm] n.斯帕姆午餐肉（商标名） spam. n.垃圾电子邮件 v.兜售信息（邮件或广告等）
unrelated ==> [ˌʌnrɪ'leɪtɪd] adj.不相关的；无亲属关系的

Many kernel-related lists are hosted on vger.kernel.org; you can find a
list of them at http://vger.kernel.org/vger-lists.html.  There are
kernel-related lists hosted elsewhere as well, though.

hosted ==> [hoʊst] n.主人；主持人；主办方；大量；寄主；主机 v.主办；主持；做东;托管

Do not send more than 15 patches at once to the vger mailing lists!!!

Linus Torvalds is the final arbiter of all changes accepted into the
Linux kernel.  His e-mail address is <torvalds@linux-foundation.org>.
He gets a lot of e-mail, and, at this point, very few patches go through
Linus directly, so typically you should do your best to -avoid-
sending him e-mail.

arbiter ==> ['ɑːrbɪtər] n.仲裁人；主宰者
typically ==> ['tɪpɪkli] adv.典型地；代表性地；通常，一般；不出所料地

If you have a patch that fixes an exploitable security bug, send that patch
to security@kernel.org.  For severe bugs, a short embargo may be considered
to allow distributors to get the patch out to users; in such cases,
obviously, the patch should not be sent to any public lists. See also
Documentation/admin-guide/security-bugs.rst.

exploitable ==> [ɪks'plɔɪtəbəl] adj.可开发的；可利用的
severe ==> [sɪ'vɪr] adj.严厉的；严重的；剧烈的；严格的；严峻的
embargo ==> [ɪm'bɑːrɡoʊ] n.封港令；禁运；禁止（通商）
distributors ==> [dɪst'rɪbjuːtəz] n.分发器，承销商（distributor的复数形式）
obviously ==> ['ɑːbviəsli] adv.显然地

Patches that fix a severe bug in a released kernel should be directed
toward the stable maintainers by putting a line like this::

  Cc: stable@vger.kernel.org

into the sign-off area of your patch (note, NOT an email recipient).  You
should also read Documentation/process/stable-kernel-rules.rst
in addition to this document.

sign-off : 签收
recipient ==> [rɪ'sɪpiənt] n.接受者；收信人

If changes affect userland-kernel interfaces, please send the MAN-PAGES
maintainer (as listed in the MAINTAINERS file) a man-pages patch, or at
least a notification of the change, so that some information makes its way
into the manual pages.  User-space API changes should also be copied to
linux-api@vger.kernel.org.


No MIME, no links, no compression, no attachments.  Just plain text
-------------------------------------------------------------------

Linus and other kernel developers need to be able to read and comment
on the changes you are submitting.  It is important for a kernel
developer to be able to "quote" your changes, using standard e-mail
tools, so that they may comment on specific portions of your code.

mime ==> [maɪm] n.哑剧；丑角；模仿 vt.做哑剧表演；模仿 vi.演出哑剧角色
MIME ==> MIME邮件就是符合MIME规范的电子邮件，或者说根据MIME规范编码而成的电子邮件。
compression ==> [kəm'preʃn] n.压缩；浓缩；压紧
attachments ==> [ə'tæ tʃmənts] n.附属物；附属装置 名词attachment的复数形式.
quote ==> [kwoʊt] v.引述；报价；举证 n.引用

For this reason, all patches should be submitted by e-mail "inline". The
easiest way to do this is with ``git send-email``, which is strongly
recommended.  An interactive tutorial for ``git send-email`` is available at
https://git-send-email.io.

recommended ==> [rekə'mendɪd] adj.被推荐的 动词recommend的过去式和过去分词.
interactive ==> [ˌɪntər'æ ktɪv] adj.相互作用的；交互的
tutorial ==> [tuː'tɔːriəl] n.指南；教程；辅导班 adj.辅导的；个别指导的

If you choose not to use ``git send-email``:

.. warning::

  Be wary of your editor's word-wrap corrupting your patch,
  if you choose to cut-n-paste your patch.

wary ==> ['weri] adj.小心的；机警的
corrupting ==> [kə'rʌpt] adj.腐败的；堕落的；讹误的 vt.贿赂；使恶化；使腐烂 vi.腐败；腐烂
word-wrap ==> 自动换行 ?

Do not attach the patch as a MIME attachment, compressed or not.
Many popular e-mail applications will not always transmit a MIME
attachment as plain text, making it impossible to comment on your
code.  A MIME attachment also takes Linus a bit more time to process,
decreasing the likelihood of your MIME-attached change being accepted.

attachment ==> [ə'tætʃmənt] n.附件；附属物；忠诚；依恋；附著；依赖 n.[法律]扣押令
plain ==> [pleɪn] adj.清楚的；简单的；坦白的；平常的；朴素的；纯的 n.平原；广阔的区域 adv.完全地；纯粹地
decreasing ==> [diː'kriːsɪŋ] adj.递减的；减少的 动词decrease的现在分词.
likelihood ==> ['laɪklihʊd] n.可能性

Exception:  If your mailer is mangling patches then someone may ask
you to re-send them using MIME.

mangle ==> ['mæ ŋɡl] v.碾压；损坏；糟蹋；乱切 n.碾压机

See Documentation/process/email-clients.rst for hints about configuring
your e-mail client so that it sends your patches untouched.

hints ==> [hɪnt] n.暗示 v.暗示；示意

Respond to review comments
--------------------------

Your patch will almost certainly get comments from reviewers on ways in
which the patch can be improved, in the form of a reply to your email. You must
respond to those comments; ignoring reviewers is a good way to get ignored in
return. You can simply reply to their emails to answer their comments. Review
comments or questions that do not lead to a code change should almost certainly
bring about a comment or changelog entry so that the next reviewer better
understands what is going on.

in which ==> 表示定于从句，类似于where
ignoring reviewers is a good way to get ignored in return ==> 真幽默

Be sure to tell the reviewers what changes you are making and to thank them
for their time.  Code review is a tiring and time-consuming process, and
reviewers sometimes get grumpy.  Even in that case, though, respond
politely and address the problems they have pointed out.  When sending a next
version, add a ``patch changelog`` to the cover letter or to individual patches
explaining difference aganst previous submission (see
:ref:`the_canonical_patch_format`).

consuming ==> [kən'suːmɪŋ] adj.消费的；强烈的；引人入胜的 动词consume的现在分词.
time-consuming ==> 消耗时间的
grumpy ==> ['ɡrʌmpi] adj.性情乖戾的；脾气暴躁的
politely ==> [pə'laɪtli] adv.有礼貌地
point out ==> 指出
cover ==> ['kʌvər] n.封面；盖子；套子；表面 v.覆盖；涉及；包含；掩护；给…保险
letter ==> ['letər] n.信；字母 v.写下；印刷 n.租赁人
canonical == > [kə'nɑːnɪkl] adj.依教规的；圣典的；权威的；牧师的

See Documentation/process/email-clients.rst for recommendations on email
clients and mailing list etiquette.

recommendations ==> 建议
etiquette ==> ['etɪket] n.礼仪；礼节；规矩

.. _resend_reminders:

Don't get discouraged - or impatient
------------------------------------

discouraged ==> [dɪs'kʌrɪdʒd] adj.泄气的 动词discourage的过去式和过去分词形式.
impatient ==> [ɪm'peɪʃnt] adj.不耐烦的；急躁的

After you have submitted your change, be patient and wait.  Reviewers are
busy people and may not get to your patch right away.

patient ==> ['peɪʃnt] adj.有耐心的；能忍耐的 n.病人
get to sth ==> 也是获取, 获得的意思。(达到(某一阶段)/到达(某地)/口语中还有收买贿赂的意思)

Once upon a time, patches used to disappear into the void without comment,
but the development process works more smoothly than that now.  You should
receive comments within a week or so; if that does not happen, make sure
that you have sent your patches to the right place.  Wait for a minimum of
one week before resubmitting or pinging reviewers - possibly longer during
busy times like merge windows.

Once upon a time ==> 从前, 曾经
or so ==> 大约

It's also ok to resend the patch or the patch series after a couple of
weeks with the word "RESEND" added to the subject line::

   [PATCH Vx RESEND] sub/sys: Condensed patch summary

a couple of ==> 几个
condensed ==> [kən'denst] adj.浓缩的 动词condense的过去式和过去分词形式.

Don't add "RESEND" when you are submitting a modified version of your
patch or patch series - "RESEND" only applies to resubmission of a
patch or patch series which have not been modified in any way from the
previous submission.


Include PATCH in the subject
-----------------------------

Due to high e-mail traffic to Linus, and to linux-kernel, it is common
convention to prefix your subject line with [PATCH].  This lets Linus
and other kernel developers more easily distinguish patches from other
e-mail discussions.

traffic ==> ['træfɪk] n.（人或车等）交通流量；不正当生意（走私） v.做生意（多指违法的）；游览
convention ==> [kən'venʃn] n.大会；协定；惯例；公约
prefix ==> ['priːfɪks] n.前缀；(人名前的)称谓 vt.加 ... 作为前缀；置于前面
distinguish ==> [dɪ'stɪŋɡwɪʃ] vt.区别；辨认；使显著

``git send-email`` will do this for you automatically.

automatically ==> [ˌɔːtə'mætɪkli] adv.自动地；机械地

Sign your work - the Developer's Certificate of Origin
------------------------------------------------------

origin ==> ['ɔːrɪdʒɪn] n.起源；出身；[数]原点；起因
certificate ==> [sər'tɪfɪkət] n.执照；证(明)书 vt.认可；批准；发证书给 ...

To improve tracking of who did what, especially with patches that can
percolate to their final resting place in the kernel through several
layers of maintainers, we've introduced a "sign-off" procedure on
patches that are being emailed around.

percolate ==> ['pɜːrkəleɪt] v.过滤；渗透；浸透
resting ==> ['restɪŋ] adj.静止的；死的；休眠的 动词rest的现在分词形式.

The sign-off is a simple line at the end of the explanation for the
patch, which certifies that you wrote it or otherwise have the right to
pass it on as an open-source patch.  The rules are pretty simple: if you
can certify the below:

explanation ==> [ˌeksplə'neɪʃn] n.解释；说明
certifies ==> ['sɜːrtɪfaɪ] vt.证明；保证；证实；颁发证书

Developer's Certificate of Origin 1.1
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

certificate ==> [sər'tɪfɪkət] n.执照；证(明)书 vt.认可；批准；发证书给 ...

By making a contribution to this project, I certify that:

certify ==> ['sɜːrtɪfaɪ] vt.证明；保证；证实；颁发证书
contribution ==> [ˌkɑːntrɪ'bjuːʃn] n.贡献；捐款(赠)；投稿

        (a) The contribution was created in whole or in part by me and I
            have the right to submit it under the open source license
            indicated in the file; or

        (b) The contribution is based upon previous work that, to the best
            of my knowledge, is covered under an appropriate open source
            license and I have the right under that license to submit that
            work with modifications, whether created in whole or in part
            by me, under the same open source license (unless I am
            permitted to submit under a different license), as indicated
            in the file; or::

              to the best of my acknowledge ==> 据我所知
              covered ==> ['kʌvərd] adj.被覆盖的；有屋顶的 动词cover的过去式及过去分词.
              right ==> [raɪt] adj.正确的；对的；右边的；合适的；重要的；完全的 adv.正确地；
                直接地；向右；恰恰，就；立即；完全地 n.权利；道理；正确；右边；右派 v.扶直；
                纠正；公正对待；补偿；恢复平衡 （这里指权限，权力)

        (c) The contribution was provided directly to me by some other
            person who certified (a), (b) or (c) and I have not modified
            it.::

              certified ==> ['sɜːtɪˌfaɪd] adj.经证明的；经认证的；有保证的，保证合格的

        (d) I understand and agree that this project and the contribution
            are public and that a record of the contribution (including all
            personal information I submit with it, including my sign-off) is
            maintained indefinitely and may be redistributed consistent with
            this project or the open source license(s) involved.::

              indefinitely ==> [ɪn'defɪnətli] adv.无限地；不确定地；模糊地
              consistent ==> [kən'sɪstənt] adj.始终如一的；持续的；一致的

then you just add a line saying::

	Signed-off-by: Random J Developer <random@developer.example.org>

using your real name (sorry, no pseudonyms or anonymous contributions.)
This will be done for you automatically if you use ``git commit -s``.
Reverts should also include "Signed-off-by". ``git revert -s`` does that
for you.::

        pseudonyms ==> 假名

Some people also put extra tags at the end.  They'll just be ignored for
now, but you can do this to mark internal company procedures or just
point out some special detail about the sign-off.::

        procedures ==> [prə'si:dʒəz] 操作

Any further SoBs (Signed-off-by:'s) following the author's SoB are from
people handling and transporting the patch, but were not involved in its
development. SoB chains should reflect the **real** route a patch took
as it was propagated to the maintainers and ultimately to Linus, with
the first SoB entry signalling primary authorship of a single author.::

  reflect ==> [rɪ'flekt] v.反映；反射；反省；归咎；显示
  propagated ==> ['prɑːpəɡeɪt] v.繁殖；增殖；传播；传送
  ultimately ==> ['ʌltɪmətli] adv.最后；最终
  authorship ==> ['ɔːθərʃɪp] n.著述；来源；作家职业

When to use Acked-by:, Cc:, and Co-developed-by:
------------------------------------------------

The Signed-off-by: tag indicates that the signer was involved in the
development of the patch, or that he/she was in the patch's delivery path.

If a person was not directly involved in the preparation or handling of a
patch but wishes to signify and record their approval of it then they can
ask to have an Acked-by: line added to the patch's changelog.::

  approval ==> [ə'pruːvl] n.同意；批准；认可；赞同

Acked-by: is often used by the maintainer of the affected code when that
maintainer neither contributed to nor forwarded the patch.::

  forwarded ==> ['fɔːwədɪd] adj.转运的 动词forward的过去式和过去分词.

Acked-by: is not as formal as Signed-off-by:.  It is a record that the acker
has at least reviewed the patch and has indicated acceptance.  Hence patch
mergers will sometimes manually convert an acker's "yep, looks good to me"
into an Acked-by: (but note that it is usually better to ask for an
explicit ack).::

  formal ==> ['fɔːrml] adj.正式的；正规的；形式的；公开的；拘谨的；有条理的
  acceptance ==> [ək'septəns] n.认可；同意；承兑；接受（礼物、邀请、建议等）

Acked-by: does not necessarily indicate acknowledgement of the entire patch.
For example, if a patch affects multiple subsystems and has an Acked-by: from
one subsystem maintainer then this usually indicates acknowledgement of just
the part which affects that maintainer's code.  Judgement should be used here.
When in doubt people should refer to the original discussion in the mailing
list archives.

If a person has had the opportunity to comment on a patch, but has not
provided such comments, you may optionally add a ``Cc:`` tag to the patch.
This is the only tag which might be added without an explicit action by the
person it names - but it should indicate that this person was copied on the
patch.  This tag documents that potentially interested parties
have been included in the discussion.

Co-developed-by: states that the patch was co-created by multiple developers;
it is used to give attribution to co-authors (in addition to the author
attributed by the From: tag) when several people work on a single patch.  Since
Co-developed-by: denotes authorship, every Co-developed-by: must be immediately
followed by a Signed-off-by: of the associated co-author.  Standard sign-off
procedure applies, i.e. the ordering of Signed-off-by: tags should reflect the
chronological history of the patch insofar as possible, regardless of whether
the author is attributed via From: or Co-developed-by:.  Notably, the last
Signed-off-by: must always be that of the developer submitting the patch.

Note, the From: tag is optional when the From: author is also the person (and
email) listed in the From: line of the email header.

Example of a patch submitted by the From: author::

	<changelog>

	Co-developed-by: First Co-Author <first@coauthor.example.org>
	Signed-off-by: First Co-Author <first@coauthor.example.org>
	Co-developed-by: Second Co-Author <second@coauthor.example.org>
	Signed-off-by: Second Co-Author <second@coauthor.example.org>
	Signed-off-by: From Author <from@author.example.org>

Example of a patch submitted by a Co-developed-by: author::

	From: From Author <from@author.example.org>

	<changelog>

	Co-developed-by: Random Co-Author <random@coauthor.example.org>
	Signed-off-by: Random Co-Author <random@coauthor.example.org>
	Signed-off-by: From Author <from@author.example.org>
	Co-developed-by: Submitting Co-Author <sub@coauthor.example.org>
	Signed-off-by: Submitting Co-Author <sub@coauthor.example.org>


Using Reported-by:, Tested-by:, Reviewed-by:, Suggested-by: and Fixes:
----------------------------------------------------------------------

The Reported-by tag gives credit to people who find bugs and report them and it
hopefully inspires them to help us again in the future.  Please note that if
the bug was reported in private, then ask for permission first before using the
Reported-by tag. The tag is intended for bugs; please do not use it to credit
feature requests.

A Tested-by: tag indicates that the patch has been successfully tested (in
some environment) by the person named.  This tag informs maintainers that
some testing has been performed, provides a means to locate testers for
future patches, and ensures credit for the testers.

Reviewed-by:, instead, indicates that the patch has been reviewed and found
acceptable according to the Reviewer's Statement:

Reviewer's statement of oversight
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

By offering my Reviewed-by: tag, I state that:

	 (a) I have carried out a technical review of this patch to
	     evaluate its appropriateness and readiness for inclusion into
	     the mainline kernel.

	 (b) Any problems, concerns, or questions relating to the patch
	     have been communicated back to the submitter.  I am satisfied
	     with the submitter's response to my comments.

	 (c) While there may be things that could be improved with this
	     submission, I believe that it is, at this time, (1) a
	     worthwhile modification to the kernel, and (2) free of known
	     issues which would argue against its inclusion.

	 (d) While I have reviewed the patch and believe it to be sound, I
	     do not (unless explicitly stated elsewhere) make any
	     warranties or guarantees that it will achieve its stated
	     purpose or function properly in any given situation.

A Reviewed-by tag is a statement of opinion that the patch is an
appropriate modification of the kernel without any remaining serious
technical issues.  Any interested reviewer (who has done the work) can
offer a Reviewed-by tag for a patch.  This tag serves to give credit to
reviewers and to inform maintainers of the degree of review which has been
done on the patch.  Reviewed-by: tags, when supplied by reviewers known to
understand the subject area and to perform thorough reviews, will normally
increase the likelihood of your patch getting into the kernel.

Both Tested-by and Reviewed-by tags, once received on mailing list from tester
or reviewer, should be added by author to the applicable patches when sending
next versions.  However if the patch has changed substantially in following
version, these tags might not be applicable anymore and thus should be removed.
Usually removal of someone's Tested-by or Reviewed-by tags should be mentioned
in the patch changelog (after the '---' separator).

A Suggested-by: tag indicates that the patch idea is suggested by the person
named and ensures credit to the person for the idea. Please note that this
tag should not be added without the reporter's permission, especially if the
idea was not posted in a public forum. That said, if we diligently credit our
idea reporters, they will, hopefully, be inspired to help us again in the
future.

A Fixes: tag indicates that the patch fixes an issue in a previous commit. It
is used to make it easy to determine where a bug originated, which can help
review a bug fix. This tag also assists the stable kernel team in determining
which stable kernel versions should receive your fix. This is the preferred
method for indicating a bug fixed by the patch. See :ref:`describe_changes`
for more details.

Note: Attaching a Fixes: tag does not subvert the stable kernel rules
process nor the requirement to Cc: stable@vger.kernel.org on all stable
patch candidates. For more information, please read
Documentation/process/stable-kernel-rules.rst.

.. _the_canonical_patch_format:

The canonical patch format
--------------------------

This section describes how the patch itself should be formatted.  Note
that, if you have your patches stored in a ``git`` repository, proper patch
formatting can be had with ``git format-patch``.  The tools cannot create
the necessary text, though, so read the instructions below anyway.

The canonical patch subject line is::

    Subject: [PATCH 001/123] subsystem: summary phrase

The canonical patch message body contains the following:

  - A ``from`` line specifying the patch author, followed by an empty
    line (only needed if the person sending the patch is not the author).

  - The body of the explanation, line wrapped at 75 columns, which will
    be copied to the permanent changelog to describe this patch.

  - An empty line.

  - The ``Signed-off-by:`` lines, described above, which will
    also go in the changelog.

  - A marker line containing simply ``---``.

  - Any additional comments not suitable for the changelog.

  - The actual patch (``diff`` output).

The Subject line format makes it very easy to sort the emails
alphabetically by subject line - pretty much any email reader will
support that - since because the sequence number is zero-padded,
the numerical and alphabetic sort is the same.

The ``subsystem`` in the email's Subject should identify which
area or subsystem of the kernel is being patched.

The ``summary phrase`` in the email's Subject should concisely
describe the patch which that email contains.  The ``summary
phrase`` should not be a filename.  Do not use the same ``summary
phrase`` for every patch in a whole patch series (where a ``patch
series`` is an ordered sequence of multiple, related patches).

Bear in mind that the ``summary phrase`` of your email becomes a
globally-unique identifier for that patch.  It propagates all the way
into the ``git`` changelog.  The ``summary phrase`` may later be used in
developer discussions which refer to the patch.  People will want to
google for the ``summary phrase`` to read discussion regarding that
patch.  It will also be the only thing that people may quickly see
when, two or three months later, they are going through perhaps
thousands of patches using tools such as ``gitk`` or ``git log
--oneline``.

For these reasons, the ``summary`` must be no more than 70-75
characters, and it must describe both what the patch changes, as well
as why the patch might be necessary.  It is challenging to be both
succinct and descriptive, but that is what a well-written summary
should do.

The ``summary phrase`` may be prefixed by tags enclosed in square
brackets: "Subject: [PATCH <tag>...] <summary phrase>".  The tags are
not considered part of the summary phrase, but describe how the patch
should be treated.  Common tags might include a version descriptor if
the multiple versions of the patch have been sent out in response to
comments (i.e., "v1, v2, v3"), or "RFC" to indicate a request for
comments.

If there are four patches in a patch series the individual patches may
be numbered like this: 1/4, 2/4, 3/4, 4/4. This assures that developers
understand the order in which the patches should be applied and that
they have reviewed or applied all of the patches in the patch series.

Here are some good example Subjects::

    Subject: [PATCH 2/5] ext2: improve scalability of bitmap searching
    Subject: [PATCH v2 01/27] x86: fix eflags tracking
    Subject: [PATCH v2] sub/sys: Condensed patch summary
    Subject: [PATCH v2 M/N] sub/sys: Condensed patch summary

The ``from`` line must be the very first line in the message body,
and has the form:

        From: Patch Author <author@example.com>

The ``from`` line specifies who will be credited as the author of the
patch in the permanent changelog.  If the ``from`` line is missing,
then the ``From:`` line from the email header will be used to determine
the patch author in the changelog.

The explanation body will be committed to the permanent source
changelog, so should make sense to a competent reader who has long since
forgotten the immediate details of the discussion that might have led to
this patch. Including symptoms of the failure which the patch addresses
(kernel log messages, oops messages, etc.) are especially useful for
people who might be searching the commit logs looking for the applicable
patch. The text should be written in such detail so that when read
weeks, months or even years later, it can give the reader the needed
details to grasp the reasoning for **why** the patch was created.

If a patch fixes a compile failure, it may not be necessary to include
_all_ of the compile failures; just enough that it is likely that
someone searching for the patch can find it. As in the ``summary
phrase``, it is important to be both succinct as well as descriptive.

The ``---`` marker line serves the essential purpose of marking for
patch handling tools where the changelog message ends.

One good use for the additional comments after the ``---`` marker is
for a ``diffstat``, to show what files have changed, and the number of
inserted and deleted lines per file. A ``diffstat`` is especially useful
on bigger patches. If you are going to include a ``diffstat`` after the
``---`` marker, please use ``diffstat`` options ``-p 1 -w 70`` so that
filenames are listed from the top of the kernel source tree and don't
use too much horizontal space (easily fit in 80 columns, maybe with some
indentation). (``git`` generates appropriate diffstats by default.)

Other comments relevant only to the moment or the maintainer, not
suitable for the permanent changelog, should also go here. A good
example of such comments might be ``patch changelogs`` which describe
what has changed between the v1 and v2 version of the patch.

Please put this information **after** the ``---`` line which separates
the changelog from the rest of the patch. The version information is
not part of the changelog which gets committed to the git tree. It is
additional information for the reviewers. If it's placed above the
commit tags, it needs manual interaction to remove it. If it is below
the separator line, it gets automatically stripped off when applying the
patch::

  <commit message>
  ...
  Signed-off-by: Author <author@mail>
  ---
  V2 -> V3: Removed redundant helper function
  V1 -> V2: Cleaned up coding style and addressed review comments

  path/to/file | 5+++--
  ...

See more details on the proper patch format in the following
references.

.. _backtraces:

Backtraces in commit messages
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Backtraces help document the call chain leading to a problem. However,
not all backtraces are helpful. For example, early boot call chains are
unique and obvious. Copying the full dmesg output verbatim, however,
adds distracting information like timestamps, module lists, register and
stack dumps.

Therefore, the most useful backtraces should distill the relevant
information from the dump, which makes it easier to focus on the real
issue. Here is an example of a well-trimmed backtrace::

  unchecked MSR access error: WRMSR to 0xd51 (tried to write 0x0000000000000064)
  at rIP: 0xffffffffae059994 (native_write_msr+0x4/0x20)
  Call Trace:
  mba_wrmsr
  update_domains
  rdtgroup_mkdir

.. _explicit_in_reply_to:

Explicit In-Reply-To headers
----------------------------

It can be helpful to manually add In-Reply-To: headers to a patch
(e.g., when using ``git send-email``) to associate the patch with
previous relevant discussion, e.g. to link a bug fix to the email with
the bug report.  However, for a multi-patch series, it is generally
best to avoid using In-Reply-To: to link to older versions of the
series.  This way multiple versions of the patch don't become an
unmanageable forest of references in email clients.  If a link is
helpful, you can use the https://lore.kernel.org/ redirector (e.g., in
the cover email text) to link to an earlier version of the patch series.


Providing base tree information
-------------------------------

When other developers receive your patches and start the review process,
it is often useful for them to know where in the tree history they
should place your work. This is particularly useful for automated CI
processes that attempt to run a series of tests in order to establish
the quality of your submission before the maintainer starts the review.

If you are using ``git format-patch`` to generate your patches, you can
automatically include the base tree information in your submission by
using the ``--base`` flag. The easiest and most convenient way to use
this option is with topical branches::

    $ git checkout -t -b my-topical-branch master
    Branch 'my-topical-branch' set up to track local branch 'master'.
    Switched to a new branch 'my-topical-branch'

    [perform your edits and commits]

    $ git format-patch --base=auto --cover-letter -o outgoing/ master
    outgoing/0000-cover-letter.patch
    outgoing/0001-First-Commit.patch
    outgoing/...

When you open ``outgoing/0000-cover-letter.patch`` for editing, you will
notice that it will have the ``base-commit:`` trailer at the very
bottom, which provides the reviewer and the CI tools enough information
to properly perform ``git am`` without worrying about conflicts::

    $ git checkout -b patch-review [base-commit-id]
    Switched to a new branch 'patch-review'
    $ git am patches.mbox
    Applying: First Commit
    Applying: ...

Please see ``man git-format-patch`` for more information about this
option.

.. note::

    The ``--base`` feature was introduced in git version 2.9.0.

If you are not using git to format your patches, you can still include
the same ``base-commit`` trailer to indicate the commit hash of the tree
on which your work is based. You should add it either in the cover
letter or in the first patch of the series and it should be placed
either below the ``---`` line or at the very bottom of all other
content, right before your email signature.


References
----------

Andrew Morton, "The perfect patch" (tpp).
  <https://www.ozlabs.org/~akpm/stuff/tpp.txt>

Jeff Garzik, "Linux kernel patch submission format".
  <https://web.archive.org/web/20180829112450/http://linux.yyz.us/patch-format.html>

Greg Kroah-Hartman, "How to piss off a kernel subsystem maintainer".
  <http://www.kroah.com/log/linux/maintainer.html>

  <http://www.kroah.com/log/linux/maintainer-02.html>

  <http://www.kroah.com/log/linux/maintainer-03.html>

  <http://www.kroah.com/log/linux/maintainer-04.html>

  <http://www.kroah.com/log/linux/maintainer-05.html>

  <http://www.kroah.com/log/linux/maintainer-06.html>

NO!!!! No more huge patch bombs to linux-kernel@vger.kernel.org people!
  <https://lore.kernel.org/r/20050711.125305.08322243.davem@davemloft.net>

Kernel Documentation/process/coding-style.rst

Linus Torvalds's mail on the canonical patch format:
  <https://lore.kernel.org/r/Pine.LNX.4.58.0504071023190.28951@ppc970.osdl.org>

Andi Kleen, "On submitting kernel patches"
  Some strategies to get difficult or controversial changes in.

  http://halobates.de/on-submitting-patches.pdf
