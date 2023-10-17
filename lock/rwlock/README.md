# 简介
spinclock是互斥锁
```cpp
```

# 思考一个问题
1. kernel 中的spinlock通过mcs队列来控制线程获取锁的顺序，
rwclock需不需要保证顺序呢 ?
