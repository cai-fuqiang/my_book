I'm very sorry for taking so long to reply to your comment.

# release_lock: XCHG vs MOV
I have written a script here where the user retrieves the average value 
of all perf stat outputs. And test using it.

* the test based on Aug 21 version
> NOTE
>
> This code is recorded in the spin_lock_test_8_18 branch.

```
Performance counter stats for 'spinlock_pause':
           4,624,476    machine_clears.memory_ordering:u
       3,410,737,040    inst_retired.any:u
     209,748,022,626    cycles:u
              65,847    task-clock:u
           66.740276    seconds time elapsed
           65.627257    seconds user
            0.011180    seconds sys
Performance counter stats for 'spinlock_nopause':
          80,937,101    machine_clears.memory_ordering:u
      24,912,493,022    inst_retired.any:u
     204,791,415,270    cycles:u
              64,285    task-clock:u
           65.064343    seconds time elapsed
           64.076759    seconds user
            0.007806    seconds sys
```

* modify the code as follows
```
 int release_lock()
 {
        int unlock_val = 0;
-       __asm("xchg %[unlock_val], (%[global_lock_addr])"::
-                       [global_lock_addr] "r" (global_lock),
-                       [unlock_val] "r" (unlock_val)
-                       :);
+       //__asm("xchg %[unlock_val], (%[global_lock_addr])"::
+       //              [global_lock_addr] "r" (global_lock),
+       //              [unlock_val] "r" (unlock_val)
+       //              :);
+       __asm__("movq $0, %[global_lock]":
+                [global_lock] "+m" (*global_lock)
+                :
+                :);
 }
```
The result perf stat data is as follows:
```
Performance counter stats for 'spinlock_pause':
           2,538,595    machine_clears.memory_ordering:u
       1,059,975,768    inst_retired.any:u
      63,680,330,835    cycles:u
              19,993    task-clock:u
           20.191900    seconds time elapsed
           19.929954    seconds user
            0.003206    seconds sys
Performance counter stats for 'spinlock_nopause':
          20,891,231    machine_clears.memory_ordering:u
       7,482,792,637    inst_retired.any:u
      61,691,562,988    cycles:u
              19,370    task-clock:u
           19.567399    seconds time elapsed
           19.307589    seconds user
            0.003171    seconds sys

```

* the test based on Aug 23 version 
> NOTE
>
> This code is recorded in the master branch
> commit : 981feeaa2a78c7ade12b690ee0c750296f6cc03a
```
Performance counter stats for 'spinlock_pause':
           2,668,950    machine_clears.memory_ordering:u
       1,001,791,880    inst_retired.any:u
      60,560,465,430    cycles:u
              19,018    task-clock:u
           19.255554    seconds time elapsed
           18.954110    seconds user
            0.004128    seconds sys
Performance counter stats for 'spinlock_nopause':
          21,209,982    machine_clears.memory_ordering:u
       7,516,987,863    inst_retired.any:u
      59,556,471,561    cycles:u
              18,700    task-clock:u
           18.906565    seconds time elapsed
           18.637049    seconds user
            0.005327    seconds sys

```
* modify rax to eax
> NOTE
>
> This code is recorded in the master branch
> commit : 208ce2a6057a4b97263ab218590b026a1f2e9192
```
Performance counter stats for 'spinlock_pause':
           2,376,406    machine_clears.memory_ordering:u
         959,953,295    inst_retired.any:u
      54,003,323,734    cycles:u
              16,964    task-clock:u
           17.232234    seconds time elapsed
           16.902346    seconds user
            0.006810    seconds sys
Performance counter stats for 'spinlock_nopause':
          19,962,974    machine_clears.memory_ordering:u
       7,034,392,892    inst_retired.any:u
      56,486,680,780    cycles:u
              17,735    task-clock:u
           17.940551    seconds time elapsed
           17.675627    seconds user
            0.004624    seconds sys
```


It can be found that modifying xchg to mov can significantly improve 
performance.

# The pause instruction promotes Hyper-Threading
On a machine with 20 cores and 40 threads, run 20 spin wait loop programs 
and an additional 20 other processes that only run dead loops.

the dead loop code:
```
//FILE======only loop
int main()
{
        for (;;)
        {
        }
}
```

the result of this test:
```
Performance counter stats for 'spinlock_pause':
           2,196,923    machine_clears.memory_ordering:u
         553,103,942    inst_retired.any:u
      35,262,014,237    cycles:u
              11,075    task-clock:u
           11.220299    seconds time elapsed
           11.038079    seconds user
            0.002871    seconds sys
Performance counter stats for 'spinlock_nopause':
          12,917,030    machine_clears.memory_ordering:u
       3,510,805,805    inst_retired.any:u
      33,626,983,054    cycles:u
              10,553    task-clock:u
           10.642098    seconds time elapsed
           10.518182    seconds user
            0.002419    seconds sys
Performance counter stats for 'only_loop_spinlock_pause':
                   0    machine_clears.memory_ordering:u
      32,862,792,348    inst_retired.any:u
      42,268,579,050    cycles:u
              13,271    task-clock:u
           13.372920    seconds time elapsed
           13.227297    seconds user
            0.002964    seconds sys
Performance counter stats for 'only_loop_spinlock_nopause':
                   0    machine_clears.memory_ordering:u
      30,620,332,985    inst_retired.any:u
      40,411,022,277    cycles:u
              12,682    task-clock:u
           12.812660    seconds time elapsed
           12.639875    seconds user
            0.002321    seconds sys
```
It can be observed that there is no significant difference in the test results
of the dead loop process between the nopause and pause versions.

> NOTE OTHER
>
> I need time to learn about CPU pipeline and cache related topics.
> Thank you very much : )
