# qemu docs
```
Timers are used to execute callbacks from different subsystems of QEMU
at the specified moments of time. There are several kinds of timers:
 * Real time clock. Based on host time and used only for callbacks that
   do not change the virtual machine state. For this reason real time
   clock and timers does not affect deterministic replay at all.
 * Virtual clock. These timers run only during the emulation. In icount
   mode virtual clock value is calculated using executed instructions counter.
   That is why it is completely deterministic and does not have to be recorded.
 * Host clock. This clock is used by device models that simulate real time
   sources (e.g. real time clock chip). Host clock is the one of the sources
   of non-determinism. Host clock read operations should be logged to
   make the execution deterministic.
 * Virtual real time clock. This clock is similar to real time clock but
   it is used only for increasing virtual clock while virtual machine is
   sleeping. Due to its nature it is also non-deterministic as the host clock
   and has to be logged too.
```

