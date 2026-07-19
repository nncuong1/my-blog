---
title: "The GC collectors"
postSlug: the-gc-collectors
author: Cuong
date: 2026-07-17
description: "Learning JVM like a madman PART 5"
tags:
  - java
  - jvm
  - springboot
  - gc
---

In the [previous blog](/posts/heap-structure-and-garbage-collection/), we learned about heap structure, and that the purpose of a garbage collector is to free the application developer from manual dynamic memory management. Today, let's take a look at the different types of collectors, each with different performance characteristics.

## I. Serial Collector

The serial collector uses a single thread to perform all garbage collection work, which makes it relatively efficient because there is no communication overhead between threads.

It's best-suited to single processor machines because it can't take advantage of multiprocessor hardware, although it can be useful on multiprocessors for applications with small data sets (up to approximately 100 MB). The serial collector is selected by default on certain hardware and operating system configurations, or can be explicitly enabled with the option -XX:+UseSerialGC.

## II. Parallel Collector

The parallel collector, also known as the throughput collector, is a generational collector similar to the serial collector. The primary difference between the serial and parallel collectors is that the parallel collector has multiple threads that are used to speed up garbage collection.

The parallel collector is intended for applications with medium-sized to large-sized data sets that are run on multiprocessor or multithreaded hardware. You can enable it by using the -XX:+UseParallelGC option.

## III. Garbage-First (G1) Garbage Collector

G1 is the **default collector since Java 9**, selected by default on most hardware and operating system configurations, or explicitly enabled with `-XX:+UseG1GC`.

It's a generational, **mostly concurrent**, region-based collector. Instead of splitting the heap into a few large contiguous generations, G1 partitions it into ~2048 equally sized **regions** and treats "young" and "old" as labels on regions rather than fixed locations. It does most of its marking work concurrently with the application, then evacuates a chosen *subset* of regions per pause — collecting the regions with the most garbage first (hence "Garbage-First") — to keep pause times bounded. Its central promise is to meet a **pause-time goal** (`-XX:MaxGCPauseMillis`, default 200ms) with high probability while still delivering good throughput.

> Want the long version? See the bonus deep dive: [G1 Garbage Collector deep dive](/posts/g1-garbage-collector-deep-dive/) — why G1 was designed this way, the region layout, the collection cycle, concurrent marking (SATB), remembered sets, and pause-time prediction.

### Pros
- **Predictable, tunable pauses** — you set a pause-time target and G1 sizes each collection to fit it, even on large heaps.
- **Scales to large heaps** — comfortably handles multi-GB heaps that make Serial/Parallel pauses unacceptable.
- **Compacts as it collects** — evacuation copies live objects into fresh regions, so the old generation doesn't fragment the way CMS's did (no surprise compacting Full GC).
- **Good general-purpose default** — a balanced trade-off between latency and throughput for most server applications.

### Cons
- **Lower raw throughput than Parallel** — write barriers and remembered-set maintenance tax every reference store.
- **Memory overhead** — remembered sets consume a real fraction of the heap.
- **Floating garbage** — objects that die mid-marking survive one extra cycle.
- **Humongous objects** — objects ≥ half a region waste space and are harder to reclaim.
- **Not sub-millisecond** — pauses are bounded but still land in the tens-to-hundreds-of-ms range, and a Full GC fallback is possible if G1 can't keep up with allocation.

## IV. The Z Garbage Collector (ZGC)

ZGC is a **scalable, low-latency** collector. It was introduced experimentally in Java 11 (JEP 333), became production-ready in Java 15 (JEP 377), and gained a generational mode in Java 21 (JEP 439). Enable it with `-XX:+UseZGC` (add `-XX:+ZGenerational` for the generational mode, which is opt-in on Java 21 and slated to become the default).

Where G1 keeps pauses *bounded*, ZGC aims to make them *disappear*: it does essentially **everything concurrently** with the application — marking, relocation/compaction, and reference processing — leaving only tiny, fixed-cost stop-the-world work (scanning thread roots). It achieves this using **colored pointers** (GC metadata stored inside the object reference) and **load barriers** (a check that fires when the application reads a reference, fixing up any pointer to a relocated object on the fly). The result is pause times that stay **sub-millisecond and do not grow with heap size or live-set size**.

### Pros
- **Sub-millisecond pauses** — max pause times typically stay under a millisecond regardless of workload.
- **Pauses independent of heap size** — they don't grow as the heap or live set grows, so ZGC scales from a few hundred MB to **multi-terabyte** heaps.
- **Concurrent compaction** — objects are relocated while the application runs, so the heap stays compact without long stop-the-world compaction.

### Cons
- **Throughput tax** — the load barrier on reference reads costs throughput; ZGC generally trades some throughput for its latency guarantees.
- **Extra heap headroom** — it needs spare memory to relocate objects into while collecting concurrently, so it wants a larger heap than a throughput collector would.
- **Higher memory/CPU overhead** — colored pointers and concurrent work add bookkeeping and CPU cost.
- **64-bit only** — the colored-pointer scheme requires a 64-bit address space.

ZGC's sweet spot is **latency-critical services on large heaps** where even a few-hundred-millisecond G1 pause is unacceptable.

## V. Side-by-side comparison

| | **Serial** | **Parallel** | **G1** | **ZGC** |
|---|---|---|---|---|
| **Enable flag** | `-XX:+UseSerialGC` | `-XX:+UseParallelGC` | `-XX:+UseG1GC` (default) | `-XX:+UseZGC` |
| **Generational?** | Yes (young + old) | Yes (young + old) | Yes (regions labeled young/old) | Yes, since Java 21 (`+ZGenerational`) |
| **GC threads** | Single-threaded | Multi-threaded | Multi-threaded | Multi-threaded |
| **Young gen** | Copying (STW) | Copying (STW) | Evacuation / copy (STW) | Concurrent relocation |
| **Old gen** | Mark-**sweep**-compact (STW) | Mark-**sweep**-compact (STW) | **Evacuation — no sweep** | **Concurrent relocation — no sweep** |
| **Reclaim mechanism** | Sliding compaction in place | Sliding compaction in place | Copy live objects out, free whole region | Copy live objects out concurrently |
| **Concurrent work?** | None (fully STW) | None (fully STW) | Marking is concurrent; evacuation is STW | Almost everything concurrent |
| **Compacts?** | Yes | Yes | Yes | Yes |
| **Fragmentation?** | No | No | No | No |
| **Typical pause** | Highest | High but parallelized | Bounded (target-driven, 10s–100s ms) | Sub-millisecond |
| **Throughput** | Low overhead | Great | Good | Good |
| **Latency** | High pauses | Long worst-case acceptable | Controllable | Ultra-low |
| **Best for** | Low overhead, small containers | Workloads where long worst-case latencies are acceptable | Long-lived services with heaps below ~16 GB | Long-lived services with heaps above ~4 GB |

### The key point: only two of the four ever "sweep"

Notice the **Old gen** row. The name **"Mark-Sweep-Compact"** appears only under Serial and Parallel — and even there, the "sweep" is *not* a CMS-style in-place free-list build; it's the address-computation walk of a **sliding mark-compact**, which is why neither fragments.

**G1 and ZGC do not sweep at all.** They reclaim by **evacuation** (a.k.a. relocation): live objects are *copied out* to fresh space, and the source region is then freed wholesale. Nothing is walked object-by-object to be freed in place.

- **G1** evacuates during its (stop-the-world) young and mixed collections; the concurrent phase only *marks*. Whole-region reclaim means no fragmentation and no separate compaction step.
- **ZGC** does the same relocation but **concurrently** with the application, using colored pointers and load barriers to keep references valid while objects move.

So across all four: **everyone compacts, nobody fragments** — but the *how* differs fundamentally. Serial/Parallel slide-compact in place (the only two with a "sweep" phase in the name), while G1 and ZGC copy-and-free by region.
