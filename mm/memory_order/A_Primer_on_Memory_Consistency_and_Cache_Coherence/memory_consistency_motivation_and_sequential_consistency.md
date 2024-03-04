## 3.8 OPTIMIZED SC IMPLEMENTATIONS WITH CACHE COHERENCE

Most real core implementations are more complicated than our basic SC
implementation with cache coherence. Cores employ features like prefetching,
speculative execution, and multithreading in order to improve performance and
tolerate memory access latencies. These features interact with the memory
interface, and we now discuss how these features impact the implementation of
SC. It is worth bearing in mind that any feature or optimization is legal as
long as it does not produce an end result (values returned by loads) that
violates SC.

> it's worth bearing in mind: 值得牢记的是
>
> 大多数真正的核心实现比我们具有缓存一致性的基本 SC 实现更复杂。 内核采用预
> 取、推测执行和多线程等功能来提高性能并容忍内存访问延迟。这些功能与内存接口交互，
> 我们现在讨论这些功能如何影响 SC 的实现。 值得记住的是，任何功能或优化都是合
> 法的，只要它不产生违反 SC 的最终结果（load返回的值）。

**Non-Binding Prefetching**

A non-binding prefetch for block B is a request to the coherent memory system
to change B’s coherence state in one or more caches. Most commonly, prefetches
are requested by software, core hardware, or the cache hardware to change B’s
state in the level-one cache to permit loads (e.g., B’s state is M or S) or
loads and stores (B’s state is M) by issuing coherence requests such as GetS
and GetM. Importantly, in no case does a non-binding prefetch change the state
of a register or data in block B. The eﬀect of the non-binding prefetch is
limited to within the “cache- coherent memory system” block of Figure 3.5a,
making the eﬀect of non-binding prefetches on the memory consistency model to
be the functional equivalent of a no-op. So long as the loads and stores are
performed in program order, it does not matter in what order coherence
permissions are obtained.

Implementations may do non-binding prefetches without aﬀecting the memory
consis- tency model. This is useful for both internal cache prefetching (e.g.,
stream buﬀers) and more aggressive cores.

**Speculative Cores**

Consider a core that executes instructions in program order, but also does
branch prediction wherein subsequent instructions, including loads and
stores, begin execution, but may be squashed (i.e., have their eﬀects nulliﬁed)
on a branch misprediction. These squashed loads and stores can be made to look
like non-binding prefetches, enabling this speculation to be correct because it
has no eﬀect on SC. A load after a branch prediction can be presented to the L1
cache, wherein it either misses (causing a non-binding GetS prefetch) or hits
and then returns a value to a register. If the load is squashed, the core
discards the register update, erasing any functional eﬀect from the load—as if
it never happened. The cache does not undo non-binding prefetches, as doing so
is not necessary and prefetching the block can help performance if the load
gets re-executed. For stores, the core may issue a non-binding GetM prefetch
early, but it does not present the store to the cache until the store is
guaranteed to commit.

> ```
> squashed [skwɑːʃt] :挤进;粉碎;制止;打断;塞入;去除;压软(或挤软、压坏、压扁等);把…压(或挤)变形
> ```
>
> 考虑一个按程序顺序执行指令的核心，但也进行分支预测，其中后续指令（包括加载和存
> 储e开始执行，但可能会因分支错误预测而被squashed（即，使其影响无效）。这些squa
> shed的加载和存储可以看起来像non-binding 预取，从而使这种推测是正确的，因为它对
> SC 没有影响。分支预测之后的load可以呈现给L1高速缓存，其中它或者未命中
> （导致非绑定GetS预取）或者命中，然后将值返回到寄存器。如果负载被squashed，内核就
> 会丢弃寄存器更新，从而消除负载的任何功能影响，就好像它从未发生过一样。
> 缓存不会撤消非绑定预取，因为这样做是不必要的，并且如果重新执行加载，预取块可以
> 提高性能。 对于存储，核心可能会提前发出非绑定 GetM 预取，但在保证存储提交之前，
> 它不会将存储呈现给缓存。
