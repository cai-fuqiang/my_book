Events that count cycles are not counted in Debug state.

Events Attributable to the operations issued by the debugger through the
external debug interface are not counted in Debug state.

In an implementation that supports multithreading, when the Effective value of
PMEVTYPER<n>_EL0.MT is 1, if an event is Attributable to an operation issued by
the debugger through the external debug interface to another thread that is in
Debug state, then the event is not counted, and it is IMPLEMENTATION DEFINED
whether the event is counted when the counting thread is in Debug state.

For each Unattributable event, it is IMPLEMENTATION DEFINED whether it is
counted when the counting PE is in Debug state. If the event might be counted,
then the rules in Filtering by Exception level and Security state on page
D11-5260 apply for the current Security state in Debug state.
