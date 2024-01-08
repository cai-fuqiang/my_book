# 计算偏移

## 获取PC值
```
virsh # qemu-monitor-command --domain instance-00004c81 --hmp 'info registers' -a

CPU#0
 PC=ffffd4f1fa6818c4 X00=00000000000c0000 X01=0000000000000000

CPU#1
 PC=ffffd4f1fa7f0a1c X00=ffff11c81552fc50 X01=00000000000004c1
...
```
这里, 我们只用 PC `ffffd4f1fa7f0a1c` 测试, 查看相关反汇编,发现其不在
`arch_cpu_idle`内.

## 通过search 指令值找到相关符号

获取指令值
```
virsh # qemu-monitor-command --domain instance-00004c81 --hmp 'x/10i 0xffffd4f1fa7f0a1c'
0xffffd4f1fa7f0a1c:  f9401000  ldr      x0, [x0, #0x20]
0xffffd4f1fa7f0a20:  92400001  and      x1, x0, #1
0xffffd4f1fa7f0a24:  f9003be1  str      x1, [sp, #0x70]
0xffffd4f1fa7f0a28:  3607fd20  tbz      w0, #0, #0xffffd4f5fa7f09cc
0xffffd4f1fa7f0a2c:  1400001e  b        #0xffffd4f1fa7f0aa4
0xffffd4f1fa7f0a30:  aa0303e1  mov      x1, x3
0xffffd4f1fa7f0a34:  2a1903e2  mov      w2, w25
0xffffd4f1fa7f0a38:  910203e0  add      x0, sp, #0x80
0xffffd4f1fa7f0a3c:  92400001  and      x1, x0, #1
0xffffd4f1fa7f0a40:  f9003be1  str      x1, [sp, #0x70]
```

> NOTE
>
> 这里我们有要找, 8-byte 对其的地址, 以`0xffffd4f1fa7f0a20`
> 为例
```
virsh # qemu-monitor-command --domain instance-00004c81 --hmp 'x/1xg 0xffffd4f1fa7f0a20'
ffffd4f1fa7f0a20: 0xf9003be192400001
```

在另一个装有同版本kernel的代码中search该值, 首先我们确认下`text`段范围
```
[root@node-2 ~]# cat /proc/kallsyms |grep -E ' _text| _end'
ffff800010080000 T _text
ffff800013430000 B _end
```
search 该值: 
```
crash> search -s ffff800010080000 -e ffff800013430000  0xf9003be192400001
ffff8000102d0a20: f9003be192400001
```

查看该地址所在的符号
```
crash> dis ffff8000102d0a20
0xffff8000102d0a20 <shrink_slab+512>:   and     x1, x0, #0x1
```
对比 两个环境内存相关值:
* 虚拟机
  ```
  virsh # qemu-monitor-command --domain instance-00004c81 --hmp 'x/5xg 0xffffd4f1fa7f0a20'
  ffffd4f1fa7f0a20: 0xf9003be192400001 0x1400001e3607fd20
  ffffd4f1fa7f0a30: 0x2a1903e2aa0303e1 0xf90033e3910203e0
  ffffd4f1fa7f0a40: 0xb100081f97fffa88
  ```
* 该环境(和虚拟机同kernel版本环境)
  ```
  crash> x/5xg 0xffff8000102d0a20
  0xffff8000102d0a20 <shrink_slab+512>:   0xf9003be192400001      0x1400001e3607fd20
  0xffff8000102d0a30 <shrink_slab+528>:   0x2a1903e2aa0303e1      0xf90033e3910203e0
  0xffff8000102d0a40 <shrink_slab+544>:   0xb100081f97fffa88
  ```

可以发现, 是一样的.所以,两者的偏移为:
```
crash> p (char *)(0xffffd4f1fa7f0a20-0xffff8000102d0a20)
$1 = 0x54f1ea520000 <Address 0x54f1ea520000 out of bounds>
```

# 获取kimage_voffset值
获取虚拟机的`kimage_voffset`实际地址,以及地址中的值:
* 获取地址
  ```
  crash> p (char *)&kimage_voffset
  $16 = 0xffff800010e8c6f0 <kimage_voffset> ""
  ```
* 加上偏移
  ```

  crash> p (char *)(0xffff800010e8c6f0+0x54f1ea520000)
  $7 = 0xffffd4f1fb3ac6f0 p: invalid kernel virtual address: ffffd4f1fb3ac6f0  type: "gdb_readmem_callback"
  p: invalid kernel virtual address: ffffd4f1fb3ac6f0  type: "gdb_readmem_callback"
  <Address 0xffffd4f1fb3ac6f0 out of bounds>

  ```
* 在虚拟机中获取值
  ```
  virsh # qemu-monitor-command --domain instance-00004c81 --hmp 'x/1xg 0xffffd4f1fb3ac6f0'
  ffffd4f1fb3ac6f0: 0xffffd4e44c800000
  ```

得出`kimage_voffset`的值为`0xffffd4e44c800000`


# 计算phys_offset
通过`memstart_offset`, 获取该值
* 获取`memstart_offset`地址
  ```
  crash> p &memstart_addr
  $9 = (s64 *) 0xffff800010e8c6d8 <memstart_addr>
  crash> p (char *)(0xffff800010e8c6d8+0x54f1ea520000)
  $10 = 0xffffd4f1fb3ac6d8 p: invalid kernel virtual address: ffffd4f1fb3ac6d8  type: "gdb_readmem_callback"
  p: invalid kernel virtual address: ffffd4f1fb3ac6d8  type: "gdb_readmem_callback"
  <Address 0xffffd4f1fb3ac6d8 out of bounds>
  ```
* 读取值
  ```
  virsh # qemu-monitor-command --domain instance-00004c81 --hmp 'x/1xg 0xffffd4f1fb3ac6d8'
  ffffd4f1fb3ac6d8: 0xffffee4500000000
     ```
# KASLR
由于另一个环境没有使能`KASLR`, 所以offset实际上就是`kaslr`的值--`0x54f1ea520000`


# 执行crash命令
```
[root@node-1 wangfuqiang]# crash usr/lib/debug/lib/modules/4.18.0-372.19.1.es8_8.aarch64/vmlinux /root/yc/instance-00004c81.coredump  -m vabits_actual=48 -m kimage_voffset=0xffffd4e44c800000 --kaslr 0x54f1ea520000 -m phys_offset=0xffffee4500000000

crash 7.2.9-2.es8
Copyright (C) 2002-2020  Red Hat, Inc.
Copyright (C) 2004, 2005, 2006, 2010  IBM Corporation
Copyright (C) 1999-2006  Hewlett-Packard Co
Copyright (C) 2005, 2006, 2011, 2012  Fujitsu Limited
Copyright (C) 2006, 2007  VA Linux Systems Japan K.K.
Copyright (C) 2005, 2011  NEC Corporation
Copyright (C) 1999, 2002, 2007  Silicon Graphics, Inc.
Copyright (C) 1999, 2000, 2001, 2002  Mission Critical Linux, Inc.
This program is free software, covered by the GNU General Public License,
and you are welcome to change it and/or distribute copies of it under
certain conditions.  Enter "help copying" to see the conditions.
This program has absolutely no warranty.  Enter "help warranty" for details.

WARNING: ignoring --machdep option: vabits_actual=48
NOTE: setting kimage_voffset to: 0xffffd4e44c800000

NOTE: setting phys_offset to: 0xffffee4500000000

GNU gdb (GDB) 7.6
Copyright (C) 2013 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.  Type "show copying"
and "show warranty" for details.
This GDB was configured as "aarch64-unknown-linux-gnu"...

WARNING: kernel relocated [89071269MB]: patching 94279 gdb minimal_symbol values

crash: invalid kernel virtual address: ffff11cb3a5e0058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3a680058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3a720058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3a7c0058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3a860058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3a900058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3a9a0058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3aa40058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3aae0058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3ab80058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3ac20058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3acc0058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3ad60058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3ae00058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3aea0058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3af40058  type: "IRQ stack pointer"
crash: invalid kernel virtual address: ffff11cb3f7ca380  type: "memory section root table"
```
