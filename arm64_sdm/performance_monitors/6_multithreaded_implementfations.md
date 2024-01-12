If an implementation is multithreaded and the Effective value of
PMEVTYPER<n>.MT ==1, events on other PEs with the same level 1 Affinity are
also counted. A pair of PEs have the same level 1 Affinity if they have the
same values for all fields in MPIDR_EL1or MPIDR except the Aff0 field.

Events on other PEs are not counted when the Effective value of PMEVTYPER<n>.MT
is 0.

If the CPU implements multithreading, and FEAT_MTPMU is not implemented, for
Armv8.5 and earlier, it is IMPLEMENTATION DEFINED whether PMEVTYPER<n>.MT is
implemented as RW or RES0. From Armv8.6, if the OPTIONAL FEAT_MTPMU feature is
not implemented, the Effective value of PMEVTYPER<n>.MT is RES0.

If FEAT_MTPMU is implemented, EL3 is implemented, and MDCR_EL3.MTPME is 0 or
SDCR.MTPME is 0, FEAT_MTPMU is disabled and the Effective value of
PMEVTYPER<n>.MT is 0.

If FEAT_MTPMU is implemented, EL3 is not implemented, EL2 is implemented, and
MDCR_EL2.MTPME is 0 or HDCR.MTPME is 0, FEAT_MTPMU is disabled and the
Effective value of PMEVTYPER<n>.MT is 0.

If FEAT_MTPMU is disabled on a Processing Element PEA, it is IMPLEMENTATION
DEFINED whether FEAT_MTPMU is disabled on another Processing Element PEB, if
all the following are true:

* FEAT_MTPMUis implemented on PEA and PEB.
* PEA and PEB have the same values for Affinity level 1 and higher.
* PEA and PEB both have MPIDR_EL1.MT or MPIDR.MT set to 1.

However, even when the Effective value of PMEVTYPER<n>.MT is 1, PEA does not
count an event that is Attributable to Secure state on PEB if counting events
Attributable to Secure state is prohibited on PEA. Similarly, PEA does not
count an event that is Attributable to EL2 on PEB if counting events
Attributable to EL2 is prohibited on PEA.

> Example D11-1 The effect of having PMEVTYPER<n>.MT == 1
> 
> If the value of MDCR_EL3.SPME is 0, and n is less than PMCR.N on PEA, then
> event counter n on PEA does not count events Attributable to Secure state on
> PEB, even if one or both of the following applies:
> * PEA is in Non-secure state.
> * MDCR_EL3.SPME==1 on PEB.

> Example D11-2 The effect of having PMEVTYPER<n>.MT == 1
>
> When MDCR_EL2.HPMN is not 0, if the value of MDCR_EL2.HPMD is 1 and n is less
> than MDCR_EL2.HPMN on PEA, then event counter n on PEA does not count events
> Attributable to EL2 on PEB, even if one of the following applies:
> * MDCR_EL2.HPMD==0 on PEB.
> * PEA is not executing at EL2.

When the current configuration is not multithreaded, and PEA prohibits
counting of events Attributable to Secure state when PEA is in Secure state,
it is IMPLEMENTATION DEFINED whether:
* Counting events Attributable to Secure state when PEA is in Non-secure
  state is permitted.
* Counting Unattributable events related to other Secure operations in the
  system when PEA is in Non-secure state is permitted.

Otherwise, counting events in Non-secure state is permitted. When the current
configuration is not multithreaded, and PEA prohibits counting of events
Attributable to EL2 when PEA is at EL2, it is IMPLEMENTATION DEFINED whether:
* D11-5258 Counting events Attributable to EL2 when PEA is using another
  Exception level is permitted.
* Counting Unattributable events related to EL2 when PEA is using another
  Exception level is permitted.

Otherwise, counting events at another Exception level is permitted.
