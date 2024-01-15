If an implementation is multithreaded and the Effective value of
PMEVTYPER<n>.MT ==1, events on other PEs with the same level 1 Affinity are
also counted. A pair of PEs have the same level 1 Affinity if they have the
same values for all fields in MPIDR_EL1 or MPIDR except the Aff0 field.
> 如果实现是多线程的并且 PMEVTYPER.MT 的有效值 ==1，则具有相同级别 1 
> 亲和力的其他 PE 上的事件也会被计数。 如果一对 PE 对 MPIDR_EL1 或 M
> PIDR 中除 Aff0 字段之外的所有字段具有相同的值，则它们具有相同的级别 
> 1 亲和性。

Events on other PEs are not counted when the Effective value of PMEVTYPER<n>.MT
is 0.
> 当 PMEVTYPER.MT 的有效值为 0 时，不统计其他 PE 上的事件。

If the CPU implements multithreading, and FEAT_MTPMU is not implemented, for
Armv8.5 and earlier, it is IMPLEMENTATION DEFINED whether PMEVTYPER<n>.MT is
implemented as RW or RES0. From Armv8.6, if the OPTIONAL FEAT_MTPMU feature is
not implemented, the Effective value of PMEVTYPER<n>.MT is RES0.
> 如果CPU实现了超线程，并且未实现FEAT_MTPMU，则对于Armv8.5及更早版本，
> PMEVTYPER.MT是否实现为RW或RES0 是 IMPLEMENTATION DEFINED。 从 Armv8.6 开始，
> 如果未实现 OPTIONAL FEAT_MTPMU 功能，则 PMEVTYPER.MT 的有效值为 RES0。

If FEAT_MTPMU is implemented, EL3 is implemented, and MDCR_EL3.MTPME is 0 or
SDCR.MTPME is 0, FEAT_MTPMU is disabled and the Effective value of
PMEVTYPER<n>.MT is 0.
> 如果实现了 FEAT_MTPMU，实现了 EL3，并且 MDCR_EL3.MTPME 为 0 或 SDCR.MTPME 为 
> 0，则 FEAT_MTPMU 被禁用，并且 PMEVTYPER.MT 的有效值为 0。

If FEAT_MTPMU is implemented, EL3 is not implemented, EL2 is implemented, and
MDCR_EL2.MTPME is 0 or HDCR.MTPME is 0, FEAT_MTPMU is disabled and the
Effective value of PMEVTYPER<n>.MT is 0.
> 如果实现了 FEAT_MTPMU，未实现 EL3，实现了 EL2，并且 MDCR_EL2.MTPME 为 0 或 
> HDCR.MTPME 为 0，则 FEAT_MTPMU 被禁用，PMEVTYPER.MT 的有效值为 0。

If FEAT_MTPMU is disabled on a Processing Element PEA, it is IMPLEMENTATION
DEFINED whether FEAT_MTPMU is disabled on another Processing Element PEB, if
all the following are true:
> 如果在 Processing Element(PE) PEA 上禁用 FEAT_MTPMU，如果满足以下所有条件，
> 是否在另一个 Processing Element PEB 上禁用 FEAT_MTPMU 由实现定义：

* FEAT_MTPMU is implemented on PEA and PEB.
* PEA and PEB have the same values for Affinity level 1 and higher.
* PEA and PEB both have MPIDR_EL1.MT or MPIDR.MT set to 1.

However, even when the Effective value of PMEVTYPER<n>.MT is 1, PEA does not
count an event that is Attributable to Secure state on PEB if counting events
Attributable to Secure state is prohibited on PEA. Similarly, PEA does not
count an event that is Attributable to EL2 on PEB if counting events
Attributable to EL2 is prohibited on PEA.
> 但是，即使在 PMEVTYPER.MT 的有效值为 1 时，如果在 PEA 上禁止对可归因于安全状
> 态的事件进行计数，PEA 也不会对 PEB 上可归因于安全状态的事件进行计数。同样，
> 如果在PEA 上禁止对可归因于 EL2 的事件进行计数，则 PEA 不会对 PEB 上可归因于 
> EL2 的事件进行计数。

> Example D11-1 The effect of having PMEVTYPER<n>.MT == 1
> 
> If the value of MDCR_EL3.SPME is 0, and n is less than PMCR.N on PEA, then
> event counter n on PEA does not count events Attributable to Secure state on
> PEB, even if one or both of the following applies:
> > 如果 MDCR_EL3.SPME 的值为 0，并且 PEA 上的 n 小于 PMCR.N，则 PEA 上的事件计数
> > 器 n 不会对 PEB 上可归因于安全状态的事件进行计数，即使以下一项或两项适用：
>
> * PEA is in Non-secure state.
> * MDCR_EL3.SPME==1 on PEB.


> Example D11-2 The effect of having PMEVTYPER<n>.MT == 1
>
> When MDCR_EL2.HPMN is not 0, if the value of MDCR_EL2.HPMD is 1 and n is less
> than MDCR_EL2.HPMN on PEA, then event counter n on PEA does not count events
> Attributable to EL2 on PEB, even if one of the following applies:
> > 当 MDCR_EL2.HPMN 不为 0 时，如果 MDCR_EL2.HPMD 的值为 1 并且 n 小于 PEA 上的
> > MDCR_EL2.HPMN，则 PEA 上的事件计数器 n 不会对 PEB 上归因于 EL2 的事件进行计数，
> > 即使出现以下情况之一 适用：
> >> 这让我想起之前在超线程x86环境调试 pause..., x86 的 bus cycle event 是不是也
> >> 这样.
> * MDCR_EL2.HPMD==0 on PEB.
> * PEA is not executing at EL2.
>
>> 当 MDCR_EL2.HPMN 不是0, 如果

When the current configuration is not multithreaded, and PEA prohibits
counting of events Attributable to Secure state when PEA is in Secure state,
it is IMPLEMENTATION DEFINED whether:
> 当前配置不是多线程，并且 PEA 禁止对可归因于安全状态的事件进行计数 当 PEA 
> 处于安全状态时，由 IMPLEMENTATION DEFINED 是否：
* Counting events Attributable to Secure state when PEA is in Non-secure
  state is permitted.
  > 当 PEA 处于非安全状态时，允许对可归因于安全状态的事件进行计数。
* Counting Unattributable events related to other Secure operations in the
  system when PEA is in Non-secure state is permitted.
  > 当 PEA 处于非安全状态时，允许对与系统中其他安全操作相关的不可归因事件进
  > 行计数。

Otherwise, counting events in Non-secure state is permitted. 

> 否则，允许对非安全状态下的事件进行计数。 

When the current configuration is not multithreaded, and PEA prohibits counting
of events Attributable to EL2 when PEA is at EL2, it is IMPLEMENTATION DEFINED
whether:

> 当当前配置不是多线程，并且 PEA 禁止对可归因于 EL2 的事件进行计数时，当 PEA 
> 处于 EL2 时，由实现定义是否：

* Counting events Attributable to EL2 when PEA is using another
  Exception level is permitted.
  > 当 PEA 使用另一个异常级别时，允许对归因于 EL2 的事件进行计数。

* Counting Unattributable events related to EL2 when PEA is using another
  Exception level is permitted.
  > 当 PEA 使用另一个异常级别时，允许对与 EL2 相关的不可归因事件进行计数。

Otherwise, counting events at another Exception level is permitted.
> 否则，允许对另一个异常级别的事件进行计数。
