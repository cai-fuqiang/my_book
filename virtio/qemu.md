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

# virtio pop 
```
virtio_blk_data_plane_start {
    ...
    for (i = 0; i < nvqs; i++) {
    VirtQueue *vq = virtio_get_queue(s->vdev, i);
   
    //set host notifier
    virtio_queue_aio_set_host_notifier_handler(vq, s->ctx,
          virtio_blk_data_plane_handle_output);
    ...
}
virtio_blk_data_plane_handle_output {
    virtio_blk_handle_vq {
        ...
		do {
		    virtio_queue_set_notification(vq, 0);
		
		    while ((req = virtio_blk_get_request(s, vq))) { 
		        progress = true;
		        if (virtio_blk_handle_request(req, &mrb)) {
		            virtqueue_detach_element(req->vq, &req->elem, 0);
		            virtio_blk_free_request(req);
		            break;
		        }
		    }
		
		    virtio_queue_set_notification(vq, 1);
		} while (!virtio_queue_empty(vq));
		...
    }
}
```

`virtio_queue_empty`:
```cpp
int virtio_queue_empty(VirtQueue *vq)
{
    if (virtio_vdev_has_feature(vq->vdev, VIRTIO_F_RING_PACKED)) {
    ¦   return virtio_queue_packed_empty(vq);
    } else {
    ¦   return virtio_queue_split_empty(vq);
    }
}

static int virtio_queue_split_empty(VirtQueue *vq)
{
    bool empty;

    if (unlikely(vq->vdev->broken)) {
        return 1;
    }

    if (unlikely(!vq->vring.avail)) {
        return 1;
    }

    if (vq->shadow_avail_idx != vq->last_avail_idx) {
        return 0;
    }

    RCU_READ_LOCK_GUARD();
	//当last_avail_idx == avail_idx 时，认为avail ring request全部处理完
    empty = vring_avail_idx(vq) == vq->last_avail_idx;
    return empty;
}
```

`virtio_blk_get_request`
```
{
    virtqueue_pop
        virtqueue_split_pop {
            ...
            if (!virtqueue_get_head(vq, vq->last_avail_idx++, &head)) {
                goto done;
            }

            vq->inuse++;
            ...
        }
}
```

# push
```
void virtqueue_push(VirtQueue *vq, const VirtQueueElement *elem,
    ¦   ¦   ¦   ¦   unsigned int len)
{
    RCU_READ_LOCK_GUARD();
    virtqueue_fill(vq, elem, len, 0);   //这个是更新used vring
    virtqueue_flush(vq, 1);
}

virtqueue_flush {
    virtqueue_split_flush
}

static void virtqueue_split_flush(VirtQueue *vq, unsigned int count)
{
    uint16_t old, new;

    if (unlikely(!vq->vring.used)) {
       return;
    }

    /* Make sure buffer is written before we update index. */
    smp_wmb();
    trace_virtqueue_flush(vq, count);
    old = vq->used_idx;
    new = old + count;
    vring_used_idx_set(vq, new);
    vq->inuse -= count;
    if (unlikely((int16_t)(new - vq->signalled_used) < (uint16_t)(new - old)))
        vq->signalled_used_valid = false;
}
static inline void vring_used_idx_set(VirtQueue *vq, uint16_t val)
{
    VRingMemoryRegionCaches *caches = vring_get_region_caches(vq);
    hwaddr pa = offsetof(VRingUsed, idx);
    virtio_stw_phys_cached(vq->vdev, &caches->used, pa, val);
    address_space_cache_invalidate(&caches->used, pa, sizeof(val));
    vq->used_idx = val;
}
```
