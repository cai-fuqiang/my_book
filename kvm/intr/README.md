# struct

## kvm_irq_routing_table
```cpp
struct kvm_irq_routing_table {
        int chip[KVM_NR_IRQCHIPS][KVM_IRQCHIP_NUM_PINS];
        u32 nr_rt_entries;
        /*
        ¦* Array indexed by gsi. Each entry contains list of irq chips
        ¦* the gsi is connected to.
        ¦*/
        struct hlist_head map[];
};
```
`kvm_irq_routing_table`有一个什么样的作用呢 ? 从字面意思来看，该结
构是一个路由表. 实际上用于路由GSI-> interrupt pin. 



# 参考连接
https://zhuanlan.zhihu.com/p/26647697
