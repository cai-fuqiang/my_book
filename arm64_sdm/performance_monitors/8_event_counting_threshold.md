When FEAT_PMUv3_TH is implemented, threshold condition controls are accessible
through each PMEVTYPER<n>_EL0 register. This gives software the ability to
count events described by PMEVTYPER<n> only when they meet a threshold
condition.

# D11.8.1 Enabling event counting threshold
When FEAT_PMUv3_TH is implemented, threshold counting for event counter n is
disabled if both of the following are true, and enabled otherwise:
* PMEVTYPER<n>_EL0.TC is 0b000.
* PMEVTYPER<n>_EL0.TH is zero.

# D11.8.2 Threshold conditions
The PMEVTYPER<n>_EL0.{TC, TH} fields define the threshold condition.

If FEAT_PMUv3_TH is not implemented, or threshold counting for event counter n
is disabled, V is the amount that the event defined by PMEVTYPER<n>.{MT,
evtCount} counts by in a given processor cycle.

Otherwise, on each processor cycle, V is compared with the value in
PMEVTYPER<n>_EL0.TH to determine whether it meets the threshold condition.
PMEVTYPER<n>_EL0.TC determines the threshold condition, and whether the counter
increments by V or 1 when the threshold condition is met.

PMMIR_EL1.THWIDTH describes the maximum value that can be written to
PMEVTYPER<n>_EL0.TH. The supported threshold conditions are:

* Less-than.
* Greater-than-or-equal-to.
* Not-equals.
* Equal-to.

> Example D11-4 Incrementing event counter n by V when V meets the threshold
> condition
>
> * When all of the following are true, the event counter n will increment by
>   four:
> * PMEVTYPER<n>_EL0.TC is 0b010, equals, meaning threshold counting for event
>   counter n is enabled.
> * PMEVTYPER<n>_EL0.TH is 4.
> * PMEVTYPER<n>.evtCount is 0x003F, STALL_SLOT.
> * There are exactly four operation Slots not occupied by an operation
>   Attributable to the PE on the cycle.

> Example D11-5 Incrementing event counter n by 1 when V meets the threshold
> condition
>
> When all of the following are true, the event counter n will increment by
> one:
> * PMEVTYPER<n>_EL0.TC is 0b101, greater-than-or-equal, count, meaning
>   threshold counting for event counter n is enabled.
> * PMEVTYPER<n>_EL0.TH is 2.
> * PMEVTYPER<n>.evtCount is 0x80C1, FP_FIXED_OPS_SPEC.
>
> * At least one floating-point multiply-add instruction is issued on the
>   cycle. 
>   > Note 
>   > 
>   > The event counter n also increments by 1 if, for example, two or more
>   > independent floatingtpoint add  operations are issued on the cycle.

# D11.8.3 Accessing event counting threshold functionality

The PMEVTYPER<n>_EL0.{TC, TH} fields are not accessible through the AArch32
PMEVTYPER<n> System register. However, the threshold condition still applies in
AArch32 state, and PMMIR_EL1.THWIDTH is readable in the AArch32 PMMIR System
register.

When FEAT_PMUv3_TH is implemented, the PMEVTYPER<n>_EL0.{TC, TH} fields are
accessible through the AArch64 PMEVTYPER<n>_EL0 System registers and the
external interface PMEVTYPER<n>_EL0 registers. See Chapter I3 Recommended
External Interface to the Performance Monitors.

PMMIR_EL1.THWIDTH is readable in the external PMMIR register.

# D11.8.4 Pseudocode description of event counting threshold

See PMUCountValue() in Chapter J1 Armv8 Pseudocode for a pseudocode description
of the operation of the threshold condition.
