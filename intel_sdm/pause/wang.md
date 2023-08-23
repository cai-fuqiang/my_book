# part1
The PAUSE instruction may not work in my test.

## the detail of test program
I tested it in user mode using examples from Intel SDM,
The details of this test are as follows:

* Provide an global lock using SystemV shared memory
  for multiple processes use it
* Use the assembly example in Intel SDM as the main code for lock grabbing:
```cpp
int get_lock()
{
        int locked_val = 1;
        __asm__(
        "Spin_Lock: \n"
        "cmpq $0, (%[global_lock_addr]) \n"
        "je  Get_Lock \n"
        FILL_INST "\n" //FILL_INST is "nop" or "pause"
        "jmp Spin_Lock \n"
        "Get_Lock: \n"
        "mov $1, %[locked_val] \n"
        "xchg %[locked_val], (%[global_lock_addr]) \n"
        "cmp $0, %[locked_val]\n"
        "jne Spin_Lock \n"
        "Get_Lock_Success:"
        ::
        [global_lock_addr] "r" (global_lock),
        [locked_val] "r" (locked_val)
        :
        );
        return 0;
}
```
* The implementation of release lock is as follows:
```
int release_lock()
{
        int unlock_val = 0;
        __asm("xchg %[unlock_val], (%[global_lock_addr])"::
                        [global_lock_addr] "r" (global_lock),
                        [unlock_val] "r" (unlock_val)
                        :);
}
```
* The process will exit after obtaining and releasing the 
 lock a certain number of times
```
int main()
{
    ...
    printf("exec lock \n");
    for (i = 0; i < LOOP_TIME; i++) {
        get_lock();
        release_lock();
    }
    ... 
}
```
* Two executable programs can be compiled using this Makefile
  + `spinlock_pause` : `FILL_INST` macro is defined as "pause" string
  + `spinlock_nopause` : `FILL_INST` macro is defined as "nop" string
* By using the `exec.sh` script, compilation and running can be completed, 
 provided that the `CUR_EXEC_NUM` environment variable needs to be defined
 > This variable indicate how many processes will be started
* Using the perf command to collect `machine_clears.memory_ordering` and
 `inst_retired.any` events for executing a program
* Save the test results in the ./log directory

[The URL of this test](https://github.com/cai-fuqiang/kernel_test/tree/master/spin_lock_test)

## test result
### Test environment
* x86 E5-2666 v3
* core number: 20 , Thread per core : 2
* export CUR_EXEC_NUM 40 (one program work on per thread)
### result
* spinlock_pause
```
 Performance counter stats for '././spinlock_pause':

         5,228,707      machine_clears.memory_ordering:u
     5,018,001,922      inst_retired.any:u

      78.053822086 seconds time elapsed

      76.887470000 seconds user
       0.022657000 seconds sys
```
* spinlock_nopause
```
 Performance counter stats for '././spinlock_nopause':

        74,524,989      machine_clears.memory_ordering:u
    21,212,346,839      inst_retired.any:u

      73.076739387 seconds time elapsed

      72.129267000 seconds user
       0.010899000 seconds sys
```
From the above results, it can be seen that the pause instruction 
can reduce `machine_clears.memory_ordering` event count. 
(I don't know if this event is equal to `memory order violation`),
but due to the cycle of `pause` instruction is larger to decrease in the 
number of instructions executed (inst-reired), I don't think 
this test can indicate that pause can avoid `machines_clears.memory_ordering`

On the other hand, the total execution time of programs using 
the `pause` instruction is **NOT LESS** than that of programs using 
the `nop` instruction.

Based on the above test results, I would like to consult everyone if 
there are any defects in my testing or how to explain the above 
test results.


# part2
Thank you for your comment. In your comment, I learned a lot about the
details of inline assembly (but there are still some that I haven't 
understood and will continue to learn later), and made modifications
to the previous code as follows:
* get_lock()
  + modify `"r"(global_lock)` input operand to `"+m" (* global_lock)`
  + delete locked_val spare register, and let `%rax` to do this, 
   and indicate it in `Clobbers`
```cpp
 int get_lock()
 {
-       int locked_val = 1;
        __asm__(
        "Spin_Lock: \n"
-       "cmpq $0, (%[global_lock_addr]) \n"
+       "cmpq $0, %[global_lock] \n"
        "je  Get_Lock \n"
        FILL_INST "\n"
        "jmp Spin_Lock \n"
        "Get_Lock: \n"
-       "mov $1, %[locked_val] \n"
-       "xchg %[locked_val], (%[global_lock_addr]) \n" //, %[locked_val] \n"
-       "cmp $0, %[locked_val]\n"
+       "mov $1, %%rax \n"
+       "xchg %%rax, %[global_lock] \n" //, %[locked_val] \n"
+       "cmp $0, %%rax\n"
        "jne Spin_Lock \n"
        "Get_Lock_Success:"
-       ::
-       [global_lock_addr] "r" (global_lock),
-       [locked_val] "r" (locked_val)
        :
+       [global_lock] "+m" (*global_lock)
+       :
+       :
+       "%rax"
        );
        return 0;
-}
+}
```
* release_lock()
You are right. Because after obtaining the lock, only 
the process has exclusive write operations. In fact, The 
release lock code is not provided in Intel SDM,

> NOTE 
> But I don't know if the Lock prefix instruction will cause other CPUs 
> to observe memory changes earlier when performing load 
> operations and there seems to be no pure-load instruction 
> with lock prefix in the x86 instruction set.In other words, 
> after executing the store instruction with the lock prefix, 
> the memory (cache) must contain the modified values, rather
> than just changing the store buffer
>
> I lack knowledge in this area too much and need to take a 
> look at the introduction in Intel SDM regarding this aspect
```cpp
Modify the release lock as follows:
 int release_lock()
 {
-       int unlock_val = 0;
-       __asm("xchg %[unlock_val], (%[global_lock_addr])"::
-                       [global_lock_addr] "r" (global_lock),
-                       [unlock_val] "r" (unlock_val)
+       __asm__("movq $0, %[global_lock]":
+                       [global_lock] "+m" (*global_lock)
+                       :
                        :);
 }
```

***
***
***

> The remaining machine-clears in the version with pause might 
> be mostly from the initial read on the first attempt to take 
> the lock; I'd be curious to see how it goes starting with an 
> xchg attempt, with pure-load only after pause.

Sorry, I didn't understand the meaning of this part. Is 
it necessary to first execute the xchg instruction before executing
the pure load instruction such as mov? For example:
```cpp
 "Spin_Lock: \n"
 "mov $1, %%rax \n"
 "xchg %%rax, %[global_lock] \n" 
 "cmpq $0, %%rax \n"
 "je  Get_Lock \n"
 "pause \n"
 "jmp Spin_Lock \n"
 "Get_Lock: \n"
 "mov %[global_lock], %%rax \n" //pure-load after xchg
 "Get_Lock_Success:"
```
But this seems meaningless. I am not sure if atomic RMW instructions 
like xchg can cause memory order violation, but subsequent pure-load 
instructions (mov) will no longer cause memory order violation, because 
store operations on that memory do not occur on any other CPU before release 
lock

I have tested the following methods for obtaining locks:
```
0000000000400741 <Spin_Lock>:
        __asm__(
  400741:       48 c7 c0 01 00 00 00    mov    $0x1,%rax
  400748:       48 87 02                xchg   %rax,(%rdx)
  40074b:       48 83 f8 00             cmp    $0x0,%rax
  40074f:       90                      nop         //nop or pause
  400750:       75 ef                   jne    400741 <Spin_Lock>

0000000000400752 <Get_Lock_Success>:
```

The test results are as follows:
* pause version
```
 Performance counter stats for './spinlock_pause':

             12348      machine_clears.memory_ordering
         523754760      inst_retired.any

      15.155263345 seconds time elapsed

      14.476663000 seconds user
       0.001972000 seconds sys
```
* nop version
```
 Performance counter stats for './spinlock_nopause':

             14277      machine_clears.memory_ordering
         594787887      inst_retired.any

      16.325078817 seconds time elapsed

      15.421201000 seconds user
       0.001984000 seconds sys
```
The difference in `machine_clears.memory_ordering` is not significant 
in the different versions above, `inst_retired.any`, too. Can it be 
explained here that the cycle of `pause` varies in different scenarios.

***

> Part of the idea of Skylake's change to pause (making it block 100 
> cycles instead of 5) is to let the other hyperthread get more useful 
> work done while we're waiting for a lock, even if that slightly 
> delays us from noticing the lock is available. But here there is no 
> useful work; all threads spend most of their time spin-waiting. 
> This is not the case Intel optimized for. 

I also think so. Later, I will do some tests for this. But I still want 
to know how much improvement can be achieved by using the pause instruction 
to avoid memory order Violation (without considering CPU hyper threading 
optimization), or what kind of code can be written to obtain beautiful data.

***
***
***

Thank you again for Peter's answer.
