## struct
### struct timekeeper

### struct tk_read_base
```cpp
/**
 * struct tk_read_base - base structure for timekeeping readout
 * @clock:  Current clocksource used for timekeeping.
 * @mask:   Bitmask for two's complement(补位) subtraction of non 64bit clocks
 *          非64bit clocks 的二进制 补位减法掩码（减高位?)
 * @cycle_last: @clock cycle value at last update
 * @mult:   (NTP adjusted) multiplier for scaled math conversion(转换)
 * @shift:  Shift value for scaled math conversion
 * @xtime_nsec: Shifted (fractional) nano seconds offset for readout
 * @base:   ktime_t (nanoseconds) base time for readout
 * @base_real:  Nanoseconds base value for clock REALTIME readout
 *
 * This struct has size 56 byte on 64 bit. Together with a seqcount it
 * occupies a single 64byte cache line.
 *
 * The struct is separate from struct timekeeper as it is also used
 * for a fast NMI safe accessors.
 *
 * @base_real is for the fast NMI safe accessor to allow reading clock
 * realtime from any context.
 */
struct tk_read_base {
    struct clocksource  *clock;
    u64         mask;
    u64         cycle_last;
    u32         mult;
    u32         shift;
    u64         xtime_nsec;
    ktime_t         base;
    u64         base_real;
};
```
