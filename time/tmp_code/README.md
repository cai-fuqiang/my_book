#  native_calibrate_tsc
```cpp
/**
 * native_calibrate_tsc
 * Determine TSC frequency via CPUID, else return 0.
 */
u
unsigned long native_calibrate_tsc(void)
{
        unsigned int eax_denominator, ebx_numerator, ecx_hz, edx;
        unsigned int crystal_khz;

        if (boot_cpu_data.x86_vendor != X86_VENDOR_INTEL)
                return 0;

        if (boot_cpu_data.cpuid_level < 0x15)
                return 0;

        eax_denominator = ebx_numerator = ecx_hz = edx = 0;

        /* CPUID 15H TSC/Crystal ratio, plus optionally Crystal Hz */
        cpuid(0x15, &eax_denominator, &ebx_numerator, &ecx_hz, &edx);
        //=================(1)==========================
        if (ebx_numerator == 0 || eax_denominator == 0)
                return 0;
        //=================(2)==========================
        crystal_khz = ecx_hz / 1000;

        //=================(2)==========================
        if (crystal_khz == 0) {
                switch (boot_cpu_data.x86_model) {
                case INTEL_FAM6_SKYLAKE_MOBILE:
                case INTEL_FAM6_SKYLAKE_DESKTOP:
                case INTEL_FAM6_KABYLAKE_MOBILE:
                case INTEL_FAM6_KABYLAKE_DESKTOP:
                        crystal_khz = 24000;    /* 24.0 MHz */
                        break;
                case INTEL_FAM6_ATOM_GOLDMONT_X:
                        crystal_khz = 25000;    /* 25.0 MHz */
                        break;
                case INTEL_FAM6_ATOM_GOLDMONT:
                        crystal_khz = 19200;    /* 19.2 MHz */
                        break;
                }
        }

        //=================(2)==========================
        if (crystal_khz == 0)
                return 0;
        /*
         * TSC frequency determined by CPUID is a "hardware reported"
         * frequency and is the most accurate one so far we have. This
         * is considered a known frequency.
         */
        setup_force_cpu_cap(X86_FEATURE_TSC_KNOWN_FREQ);

        /*
         * For Atom SoCs TSC is the only reliable clocksource.
         * Mark TSC reliable so no watchdog on it.
         */
        if (boot_cpu_data.x86_model == INTEL_FAM6_ATOM_GOLDMONT)
                setup_force_cpu_cap(X86_FEATURE_TSC_RELIABLE);

        return crystal_khz * ebx_numerator / eax_denominator;
}
```
