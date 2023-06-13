# offset 取值

```cpp
u64 __init kaslr_early_init(u64 dt_phys)
{
        ...
        mask = ((1UL << (VA_BITS - 2)) - 1) & ~(SZ_2M - 1);
        offset = seed & mask;
        ...
}
```

# modules 位置
IS_NOT_ENABLE(CONFIG_RANDOMIZE_MODULE_REGION_FULL)
代码:
```cpp
u64 __init kaslr_early_init(u64 dt_phys)
{
        ...
        if (IS_ENABLED(CONFIG_RANDOMIZE_MODULE_REGION_FULL)) {
                ...
        } else {
                /*
                 * Randomize the module region by setting module_alloc_base to
                 * a PAGE_SIZE multiple in the range [_etext - MODULES_VSIZE,
                 * _stext) . This guarantees that the resulting region still
                 * covers [_stext, _etext], and that all relative branches can
                 * be resolved without veneers.
                 */
                module_range = MODULES_VSIZE - (u64)(_etext - _stext);
                module_alloc_base = (u64)_etext + offset - MODULES_VSIZE;
        }
        /* use the lower 21 bits to randomize the base of the module region */
        module_alloc_base += (module_range * (seed & ((1 << 21) - 1))) >> 21;
        module_alloc_base &= PAGE_MASK;
        
        return offset;
}
```

## offset取值分析
```
MODULES_VSIZE   alias   MS
_etext          alias   et
_stext          alias   st

module_range =  MS - (et - st)
modules_alloc_base = et + offset - MS
modules_alloc_base += (modules_range * (seed & ( (1<<21) - 1)) >> 21

这里seed是一个(0, (unsigned long) -1)的随机数, 而 x >> 21 相当于 x / (1 << 21)
那么 (seed & (1 << 21) - 1)) >> 21 的取值范围大概为
[0,  (1 << 21 - 1) / (1 << 21)] ~= 
[0, 1]

大概为[0, 1]的范围随机，但是随机分布不太清楚

modules_alloc_base += (modules_range * [0 ,1])
modules_alloc_base += [0, MS - et + st]
modules_alloc_base = [et + offset - MS, et + offset - MS + MS - et + st]
modules_alloc_base = [et + offset - MS, st + offset]

而这里et st 实际上值得编译的时候的_etext, 和 _stext值，
而经过kaslr位移后，位移后的两个值，我们记做 _etext' _stext', 值为:
_etext' = _etext + offset
_stext' = _stext + offset

所以modules_alloc_base的取值范围为:

modules_alloc_base = [_etext' - MS, _stext']
```

但是从前面的commit message中可以看到, modules位置，可取得的范围
为`[_etext' - 128M , _stext' + 128M]`, 但是该计算过程前面的注释中
又提到, 目前得到的随机范围为:`[_etext' - MODULES_VSIZE, _stext']`,
不知道为什么会有这样的改变，我们来看下，能不能获取到
`[etext' , _stext' + 128M]`, 这样的范围:
```
modules_alloc_base += [0, MS - et + st]
我们改变下 modules_alloc_base的初始值:
修改为 et + offset
得到

modules_alloc_base = [ et + offset, MS - et + st + et + offset]
modules_alloc_base = [et + offset, MS + st + offset]

modules_alloc_base = [etext', MS + stext']
```

这里可能需要随机确定下`modules_alloc_base`的初始值。
但是因为这是随机确定的，感觉影响不到什么，除非可以确定，
vmalloc_range中，究竟是`[etext', _stext' + 128M]`,占用的内存多，
还是`[etext' - 128M, stext']`占用的内存多，这样可以使modules
获取更多的虚拟内存空间。

这里还有一点，为什么要用 `1 << 21`,  这里21这个值有什么讲究么, 
我们来想下，上面的推导，是建立在数据不溢出的情况下，我们先来看下，
数据溢出。

moduels_alloc_base += (modules_range * (seed & ((1 << 21) - 1))) >> 21;
