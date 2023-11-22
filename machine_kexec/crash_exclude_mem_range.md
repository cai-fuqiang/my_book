# 简述
在第一个内核执行`kexec_file_load()`的相关过程中, 会执行
`prepare_elf_headers()`, 该函数会初始化和elf headers
相关结构, 最终该结构的地址会通过fdt path `/chosen/linux,elfcorehdr`
传递给第二个kernel, 本文 我们不介绍和`elf header` 过多
内容,主要去对一个patch 进行分析
```
commit 4831be702b95047c89b3fa5728d07091e9e9f7c9
Author: Levi Yun <ppbuk5246@gmail.com>
Date:   Wed Aug 31 19:39:13 2022 +0900

    arm64/kexec: Fix missing extra range for crashkres_low.
```

# patch 内容
```diff
diff --git a/arch/arm64/kernel/machine_kexec_file.c b/arch/arm64/kernel/machine_kexec_file.c
index 889951291cc0..a11a6e14ba89 100644
--- a/arch/arm64/kernel/machine_kexec_file.c
+++ b/arch/arm64/kernel/machine_kexec_file.c
@@ -47,7 +47,7 @@ static int prepare_elf_headers(void **addr, unsigned long *sz)
        u64 i;
        phys_addr_t start, end;

-       nr_ranges = 1; /* for exclusion of crashkernel region */
+       nr_ranges = 2; /* for exclusion of crashkernel region */
        for_each_mem_range(i, &start, &end)
                nr_ranges++;
```

patch 也十分简单, 我们来看下改动后的代码.
# 代码分析
## prepare_elf_headers
```cpp
static int prepare_elf_headers(void **addr, unsigned long *sz)
{
        //=============(1)=================
        struct crash_mem *cmem;
        unsigned int nr_ranges;
        int ret;
        u64 i;
        phys_addr_t start, end;
        //=============(2)=================
        nr_ranges = 2; /* for exclusion of crashkernel region */
        //=============(3)=================
        for_each_mem_range(i, &memblock.memory, NULL, NUMA_NO_NODE,
                                        MEMBLOCK_NONE, &start, &end, NULL)
                nr_ranges++;

        //=============(4)=================
        cmem = kmalloc(sizeof(struct crash_mem) +
                        sizeof(struct crash_mem_range) * nr_ranges, GFP_KERNEL);
        if (!cmem)
                return -ENOMEM;

        //=============(5)=================
        cmem->max_nr_ranges = nr_ranges;
        cmem->nr_ranges = 0;
        //=============(6)=================
        for_each_mem_range(i, &memblock.memory, NULL, NUMA_NO_NODE,
                                        MEMBLOCK_NONE, &start, &end, NULL) {
                cmem->ranges[cmem->nr_ranges].start = start;
                cmem->ranges[cmem->nr_ranges].end = end - 1;
                cmem->nr_ranges++;
        }

        /* Exclude crashkernel region */
        //=============(7)=================
        ret = crash_exclude_mem_range(cmem, crashk_res.start, crashk_res.end);
        if (ret)
                goto out;

        //=============(8)=================
        if (crashk_low_res.end) {
                ret = crash_exclude_mem_range(cmem, crashk_low_res.start, crashk_low_res.end);
                if (ret)
                        goto out;
        }

        //=============(9)=================
        ret = crash_prepare_elf64_headers(cmem, true, addr, sz);
out:
        kfree(cmem);
        return ret;
}
```
1. `struct crash_mem` 相关定义如下:
   ```cpp
   struct crash_mem {
           unsigned int max_nr_ranges;
           unsigned int nr_ranges;
           struct crash_mem_range ranges[0];
   };
   ```
   + **crash_mem.max_nr_ranges**: 从`crash_mem.ranges[0]`来看, 该结构是一个数组
     头 + 一个数组, 该成员定义了数组的大小
   + **crash_mem.nr_ranges**: 定义了数组中的实际的成员数量(也就是说 `nr_ranges`
     可能小于`max_nr_ranges`
   + **crash_mem.ranges[0]**: `struct crash_mem_range`数组, 具体结构如下:

   `struct crash_mem_range` 定义如下
   ```cpp
   struct crash_mem_range {
           u64 start, end;
   };
   ```
   + **crash_mem_range.start**: memory region start
   + **crash_mem_range.end**: memory region end

   该数据结构主要用来获取第一个kernel的各个`memblock.memory[]`, 然后
   作为参数传递给`crash_prepare_elf64_headers`
2. 该处为改动的代码, 表示可能因为exclude crash mem range, 而splite出比 memblock.memory
   数量多出region数量(我们下面会详细解释)
3. 获取memblock.memory region数量, `nr_ranges = 2 + NUM(memblock.memory)`
4. 通过kmalloc()申请内存, 而申请的数组大小就是上面提到的`nr_ranges`
5. 将`cmem->max_nr_ranges` 赋值上面提到的 `nr_ranegs`, 并且将`cmem->nr_ranges = 0`, 
   表示此时该数组中还未有实际成员.
6. 遍历每一个 memblock.memory, 将其start end copy到 `crash_mem.ranges[]`中
7. 排除 `crashk_res` 的memory region(不将其报告给第二个kernel)
8. 排除 `crashk_res_low`的 memory region(下面会详细分析`crash_exclude_mem_range`
9. 调用`crash_prepare_elf64_headers()`初始化 `elfheaders`

## crash_exclude_mem_range
在分析代码之前, 我们来思考下, 可能遇到的一些情况
> 我们这里将需要exclude crash memory range, 简称为ex_mem,
> 将某一个memblock.memory[i] 简称为 memb[i]
>
> 并且我们这里假设, 只有一个需要exclude mem range, 也就是
> ```
> cmem->nr_ranges == cmem->max_nr_ranges - 1
> ```

### 可能遇到的情况

1. `ex_mem.start == memb[i].start && ex_mem.end == memb[i].end`
   ```
   memb[i]:     |<-memb[i-1]-->|<----memb[i]--->|<----memb[i+1]--->|
   ex_mem:                     |<----ex_mem---->|

   exclude 后:  |<-memb[i-1]-->|                |<----memb[i+1]--->|
   ```
   那么这种情况下, 不要splite, 需要将memb[i+1]以及之后的memb[x], 向前移动一格

   此时`cmem->nr_ranges--`
2. `ex_mem.start == memb[i].start && ex_mem.end < memb[i].end`
   ```
   memb[i]:     |<-memb[i-1]-->|<--------memb[i]----->|<--memb[i+1]-->|
   ex_mem:                     |<-ex_mem->|
   memb[i].end - ex_mem.end:              |<--------->|
   exclude后:   |<-memb[i-1]-->|          |<-memb[i]->|<--memb[i+1]-->|
   ```
   需要splite, 并将
   ```
   memb[i].start = memb[i].start + memb[i].end - ex_mem.end
   ```
   此时`cmem->nr_ranges`保持不变

3. `ex_mem.start > memb[i].start && ex_mem.end = memb[i].end`
   ```
   memb[i]:              |<-memb[i-1]-->|<-------memb[i]------>|<--memb[i+1]-->|
   ex_mem:                                          |<-ex_mem->|
   ex_mem.start - memb[i].start:        |<--------->|
   exclude后:            |<-memb[i-1]-->|<-memb[i]->|          |<--memb[i+1]-->|
   ```
   需要splite, 并将
   ```
   memb[i].end = memb[i].end - (ex_mem.start - memb[i].start)
   ```
   此时`cmem->nr_ranges`保持不变
4. `ex_mem.start > memb[i].start && ex_mem.end < memb[i]`
   ```
   memb[i]:              |<-memb[i-1]->|<------------memb[i]--------->|<-memb[i+1]->|
   ex_mem:                                         |<-ex_mem->|
   ex_mem.start - memb[i].start:       |<--------->|          |<----->|
   exclude后:            |<-memb[i-1]->|<-memb[i]->|          |<-NEW->|<-memb[i+1]->|
   ```
   需要splite,并将
   * `memb[i].end=memb[i].end - (ex_mem.start - memb[i].start)`
   * 将`memb[i+1]`以及后面的range, 向后移动一格
   * 将移动后的`memb[i+1]`的
     + `start = ex_mem.end`
     + `end = (old)memb[i].end`

   **需要注意的是, 最终cmem->nr_ranges++**
5. *OTHERS*

   还有一些其他情况是上面一些情况的组合, 我们来列举下
   ```
   /*================================================================
    *=(1)=
    *=====/
   memb[i]:              |<-memb[i-1]->|<--memb[i]-->|<-memb[i+1]->|
   ex_mem:                          |<-ex_mem->|

   情况为: 3+2
   cmem->nr_ranges不变
   /*================================================================
    *=(2)=
    *=====/
   memb[i]:              |<-memb[i-1]->|<--memb[i]-->|<-memb[i+1]->|
   ex_mem:                                   |<-ex_mem->|

   情况为: 3+2
   cmem->nr_ranges不变
   /*================================================================
    *=(3)=
    *=====/
   memb[i]:              |<-memb[i-1]->|<--memb[i]-->|<-memb[i+1]->|
   ex_mem:                        |<-----ex_mem----->|

   情况为: 3+1
   cmem->nr_ranges--
   /*================================================================
    *=(4)=
    *=====/
   memb[i]:              |<-memb[i-1]->|<--memb[i]-->|<-memb[i+1]->|
   ex_mem:                             |<-----ex_mem----->|

   情况为: 1+2
   cmem->nr_ranges--
   /*================================================================
    *=(5)=
    *=====/
   memb[i]:              |<-memb[i-1]->|<--memb[i]-->|<-memb[i+1]->|
   ex_mem:                         |<-------ex_mem------->|

   情况为: 3+1+2
   cmem->nr_ranges--
   ```
   可以看到这些其他的情况, 不会有`cmem->nr_ranges++`的情况, 也就是说,
   **每一次调用`crash_exclude_mem_range()`, cmem->nr_ranges可能会至多增加1**
### 代码分析
```cpp
int crash_exclude_mem_range(struct crash_mem *mem,
                            unsigned long long mstart, unsigned long long mend)
{
        int i, j;
        unsigned long long start, end, p_start, p_end;
        struct crash_mem_range temp_range = {0, 0};

        for (i = 0; i < mem->nr_ranges; i++) {
                start = mem->ranges[i].start;
                end = mem->ranges[i].end;
                p_start = mstart;
                p_end = mend;

                if (mstart > end || mend < start)
                        continue;
                //===============(1.1)================
                /* Truncate any area outside of range */
                if (mstart < start)
                        p_start = start;
                if (mend > end)
                        p_end = end;

                //===============(2)================
                /* Found completely overlapping range */
                if (p_start == start && p_end == end) {
                        mem->ranges[i].start = 0;
                        mem->ranges[i].end = 0;
                        if (i < mem->nr_ranges - 1) {
                                /* Shift rest of the ranges to left */
                                for (j = i; j < mem->nr_ranges - 1; j++) {
                                        mem->ranges[j].start =
                                                mem->ranges[j+1].start;
                                        mem->ranges[j].end =
                                                        mem->ranges[j+1].end;
                                }

                                /*
                                 * Continue to check if there are another overlapping ranges
                                 * from the current position because of shifting the above
                                 * mem ranges.
                                 */
                                i--;
                                //===============(1.2)================
                                mem->nr_ranges--;
                                continue;
                        }
                        mem->nr_ranges--;
                        return 0;
                }

                if (p_start > start && p_end < end) {
                        /* Split original range */
                        mem->ranges[i].end = p_start - 1;
                        temp_range.start = p_end + 1;
                        temp_range.end = end;
                } else if (p_start != start)
                        mem->ranges[i].end = p_start - 1;
                else
                        mem->ranges[i].start = p_end + 1;
                break;
        }

        /* If a split happened, add the split to array */
        if (!temp_range.end)
                return 0;

        /* Split happened */
        if (i == mem->max_nr_ranges - 1)
                return -ENOMEM;

        /* Location where new range should go */
        j = i + 1;
        if (j < mem->nr_ranges) {
                /* Move over all ranges one slot towards the end */
                for (i = mem->nr_ranges - 1; i >= j; i--)
                        mem->ranges[i + 1] = mem->ranges[i];
        }

        mem->ranges[j].start = temp_range.start;
        mem->ranges[j].end = temp_range.end;
        mem->nr_ranges++;
        return 0;
}
```
1. 这里主要是在处理 OTHER的情况
   1. (1.1)  这里做了一个循环去处理(跟我上面OTHERS分成了几种情况的组合一样,
      在循环中分别处理这几种情况)
   2. (1.2)  这里
