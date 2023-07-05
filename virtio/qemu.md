# vring_need_event
```cpp
/* The following is used with USED_EVENT_IDX and AVAIL_EVENT_IDX */
/* Assuming a given event_idx value from the other side, if
 * we have just incremented index from old to new_idx,
 * should we trigger an event? */
static inline int vring_need_event(uint16_t event_idx, uint16_t new_idx, uint16_t old)
{
    /* Note: Xen has similar logic for notification hold-off
    ¦* in include/xen/interface/io/ring.h with req_event and req_prod
    ¦* corresponding to event_idx + 1 and new_idx respectively.
    ¦* Note also that req_event and req_prod in Xen start at 1,
    ¦* event indexes in virtio start at 0. */
    return (uint16_t)(new_idx - event_idx - 1) < (uint16_t)(new_idx - old);
}
```

* `if (new < event_idx + 1 )` <br/>
`new_idx - event_idx -1 < 0`, 由于这里是uint16_t, 则是一个非常大的值(最高位是一), 
而 `new_idx - old` 肯定是个正数，该条件不成立, 不会notify

* if (new >= event_idx + 1) && (old < event_idx + 1) <br/>

此时 `new_idx - event_idx - 1` 和`new_idx - old` 都是 > 0 , 所以可以推下
```
return (uint16_t)(new_idx - event_idx - 1) < (uint16_t)(new_idx - old);

new_idx - event_idx - 1 - (new_idx - old)   //看看这个是否真的是 < 0
= old - event_idx - 1
= old - (event_idx + 1)
< 0
```
所以该条件成立。

* if (new >= event_idx - 1) && (old >= event_idx  + 1)
此时 `new_idx - event_idx - 1` 和`new_idx - old` 也都是 > 0 , 所以可以推下
```
new_idx - event_idx - 1 - (new_idx - old)   //看看这个是否真的是 < 0
= old - event_idx - 1
= old - (event_idx + 1)
>= 0
```
所以该条件不成立。

分析了上面几种情况后，我们来想下为什么这么做, 首先根据virtio spec,
avail_event_idx + 1 == used_idx 时，是需要发送notify， 这里需要注意，
device 一次可能会写入多个buffer,也就是used_idx在本次增长中 > 1, 这个
时候也要发送notify。那么还有一种情况，就是上次发送了，那本次还要在发送么？
这里的逻辑是，不发送, 为什么?<br/>

很简单，virtio spec中规定，只有`avail_event_idx + 1 == used_idx`, 才会发送。
假设本次发送了，说明`used_idx >= avail_event_idx + 1`, 那么，在driver 没有
更新 `avail_event_idx`的情况下，`used_idx > avail_event_idx + 1`,
那么就不能发送。

怎么去避免这种问题呢? qemu这边的逻辑是记录old, 如果old > event_idx + 1, 说明
上次已经发送过了，那么这次就不需要在发送了。
