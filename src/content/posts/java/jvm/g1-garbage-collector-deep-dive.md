---
title: "G1 Garbage Collector deep dive"
postSlug: g1-garbage-collector-deep-dive
author: Cuong
date: 2026-07-17
description: "Learning JVM like a madman BONUS"
tags:
  - java
  - jvm
  - springboot
  - gc
---

In [The GC collectors](/posts/the-gc-collectors/) we introduced G1 at a high level — what it is, its pros and cons. This bonus post is the long version: *why* G1 was designed the way it is, and *how* each of its moving parts actually works. If you only wanted the summary, the main post has it; if you want to understand G1 like a madman, read on.

<!--
G1 grounding: HotSpot GC Tuning Guide (Java 21), Chapter 7. Cite as "Tuning Guide §7".
-->

### Why G1? The design goals
#### The history
Before 2000, faster CPUs solved everything: manufacturers mainly improved performance by increasing clock speed.
```text
1995      ~100 MHz
2000      1 GHz
2002      2 GHz
2004      3+ GHz   (plateau begins)
```
If your GC became slow, newer CPUs simply executed it faster and at that time:
- heaps were relatively small
- CPUs had only 1 or 2 cores
- existing GCs worked reasonably well
But around 2003–2005, CPU clock speeds stopped increasing. Because of heat, instead of building a single faster CPU:
```text
1 CPU
6 GHz
```
manufacturers started building multi-core CPUs:
```text
4 cores
3 GHz

8 cores
3 GHz

16 cores
3 GHz
```
> Performance improvements now came from parallelism, not higher clock speed.

Alongside more cores, memory became dramatically cheaper, so companies could suddenly buy machines with:
- 4 GB
- 8 GB
- 16 GB
- 64 GB
> So applications started using very large Java heaps.

#### The limitations of current collectors
Old GCs (serial, parallel, cms) were designed for a different world. Old:
```text
1 CPU
512 MB heap

GC stops application
↓

Works fine
```
New: 
```text
8 CPUs
16 GB heap

GC stops application
↓

Pause becomes several seconds
```
> The CPU has more cores...but the GC isn't using them effectively.

Serial GC uses only one thread even if your machine has 8 cores, only one core is collecting garbage.

Parallel GC can use multiple threads but there is still a problem: almost all GC work happens during a Stop-The-World pause. So although GC is faster your application is still frozen. Pause time is another problem: as heap size increases, pause times become unacceptable.

CMS introduced concurrent collection, that sounds great, but CMS never compacts the old generation. Over time the old generation fragments, and eventually a *concurrent mode failure* forces a single-threaded, stop-the-world, compacting Full GC — exactly the multi-second pause CMS was supposed to avoid. So even though CMS ran concurrently, it couldn't reliably keep pauses low on large heaps.

In short, with the evolution of hardware:
```text
16 cores
32 GB RAM
```
Old collectors behaved like this:
```text
Serial GC

1 thread
large pauses

↓

Cannot utilize hardware
```
or
```text
CMS

Concurrent

↓

But fragments the old gen → Full GC pauses
```
> Java suddenly had powerful hardware but no GC designed for it.

#### This is why G1 was designed
G1 was created because computer hardware shifted from "faster single CPUs with small memory" to "many-core CPUs with huge memory," and the existing Java garbage collectors were no longer designed for that new reality. The Oracle tuning guide describes G1 as:

> G1 is a generational, incremental, parallel, mostly concurrent, stop-the-world,
> and evacuating garbage collector which monitors pause-time goals in each of the
> stop-the-world pauses.
>
> — *HotSpot GC Tuning Guide §7*

We will go through each of these G1 concepts in the sections below.

### A region-based heap
![G1 Garbage Collector Heap Layout](<images/g1-heap-layout.png>)

Here's the thing that trips people up: **G1 is generational too.** It makes the same bet as Serial and Parallel — the weak generational hypothesis, *most objects die young* — and still splits objects into a young and an old generation. So if the core idea is identical, what actually changed?

The answer is the **physical layout of the heap**, not the generational model sitting on top of it.

#### How Serial and Parallel lay out the heap

Serial and Parallel carve the heap into a *handful of large, contiguous spaces*: one young generation (eden + two survivor spaces) and one old generation, each a single continuous address range.

```text
Serial / Parallel

|            Young             |            Old              |
| Eden           | S0 | S1     |                            |
|<----- one contiguous block per generation ------------->|
```

Simple and cache-friendly, but it welds together two decisions that don't have to be:

- A generation **is** its memory — the young gen is one contiguous span, the old gen is another.
- Collection is **all-or-nothing per generation** — a young collection evacuates the *entire* eden; an old/full collection must walk and compact the *entire* old generation in a single stop-the-world pause.

That second property is the killer on large heaps. If the old generation is 30 GB, a full collection has 30 GB of work to do in one pause, and there is no way to ask for "just a slice." Pause time is chained to generation size, and generation size is chained to heap size — the exact wall we hit in the section above.

> Serial / Parallel: a generation is a *place*. To collect it, you collect the whole place.

#### How G1 lays out the heap

G1 snaps that chain. It partitions the heap into a set of **equally sized regions**, each a contiguous range of virtual memory, sized ergonomically to give roughly **2048 regions** (up to 32 MB each by default; override with `-XX:G1HeapRegionSize`). A region is the unit of *both* allocation and reclamation (Tuning Guide §7).

Crucially, **a region has no fixed generational role.** At any moment each region is free, or tagged eden / survivor / old — and that tag is reassigned over the region's lifetime. The generations still exist, but now they're just *sets of regions* scattered across the heap rather than contiguous spans:

```text
G1   (E=eden  S=survivor  O=old  H=humongous  _=free)

| E | O | _ | O | E | S | O | H | H | _ | E | O | S | _ | O | E |
   the "young generation" = whichever regions are tagged E / S,
   wherever they happen to sit — not a contiguous block
```

This single change is what makes the rest of G1 possible:

- **Logical generations.** Young and old are labels, not locations. G1 grows the young gen by tagging a few more free regions as eden and shrinks it by tagging fewer — no resizing of a contiguous space.
- **Collect a *subset*, not a whole generation.** Because reclamation is per-region, G1 chooses *how many* regions to collect in a pause. Pause time now scales with the number of regions picked, not with the size of the heap — precisely what a pause-time goal needs.
- **Garbage-First.** Since it's choosing regions anyway, G1 collects the ones with the most garbage first (hence the name) — the most reclaimed space for the least work.
- **Compaction for free.** G1 reclaims a region by *evacuating* it: copying the live objects into a fresh region, then freeing the old one wholesale. Copying compacts by construction, so G1 doesn't fragment the old gen the way CMS did.

> G1: a generation is a *label on regions*. To collect, you pick a subset of regions — the pause is sized by your choice, not by the heap.

#### Humongous objects

There's one object that doesn't fit this model cleanly: one that is **≥ half a region**. G1 calls these **humongous** and allocates each as a *sequence of contiguous old-generation regions*, with the object starting at the first region in the run (Tuning Guide §7). Two costs come with that:

- **Wasted tail.** An object needing 2.5 regions occupies 3, and the leftover half-region is unusable until the whole object is reclaimed.
- **Harder to reclaim.** Humongous regions are normally freed only at the end of a marking cycle (or in a Full GC), so short-lived huge objects can linger.

If humongous allocations start hurting, the usual lever is a *larger* region size (`-XX:G1HeapRegionSize`) so fewer objects cross the half-region threshold.

### The collection cycle: young-only vs space-reclamation

The naming here trips everyone up, so start with the one fact that dissolves most of the confusion:

> **Every G1 collection is a young collection.** Each pause *always* evacuates the young regions. What changes between phases is the *extra* work that rides along on top of that young collection.

Once you see that, the phases stop looking like near-duplicates. They're the same base operation — evacuate young — with a different passenger bolted on:

```text
Normal young collection      →  young regions only
Concurrent Start collection  →  young regions  +  kick off marking
Mixed collection             →  young regions  +  some old regions
```

So the phases aren't three different *kinds* of collection competing to do the same job. They're three answers to the question *"what else should this young pause do?"* — and G1 walks through them in a fixed cycle (Tuning Guide §7).

#### The young-only phase: let the old generation fill up

The cycle opens with the **young-only phase**, a run of ordinary **Normal young collections**. Each one evacuates eden and survivor regions, ages survivors, and promotes the oldest into the old generation. Nothing touches the old generation *for reclamation* here — quite the opposite. The whole point of this phase is to let the old generation *fill up gradually* as promotions accumulate.

This is the part that feels counterintuitive: the young-only phase isn't trying to reclaim old-gen space. It's the phase where old-gen garbage *builds up*, one promotion at a time, until there's enough of it to be worth a cleanup.

> Young-only ≠ "cleaning the young gen and ignoring the old." It's "only collecting young, while the old gen slowly fills."

#### The Concurrent Start collection:

Eventually the young-only phase has to hand off to space-reclamation so the piled-up old-gen garbage actually gets freed. But G1 can't just start collecting old regions — and *why not* is the whole reason Concurrent Start exists.

Remember the "Garbage-First" promise: G1 wants to collect the old regions that are **mostly garbage**, because those give back the most space for the least copying. But to know *which* old regions are mostly garbage, G1 has to know which objects in the old gen are still **live**. And it has no such map — the young-only phase only ever tracked young regions. Before it can reclaim any old region intelligently, G1 must first **scan the old generation and mark what's live.**

That scan is the job of the **concurrent marking cycle**, and **the Concurrent Start collection is what boots it up.** This is the answer to "what does Concurrent Start *do*":

```text
A Concurrent Start collection does two things in one pause:
  1. a completely normal young collection  (evacuate eden + survivors)
  2. + scan the GC roots and switch on concurrent marking of the old gen
```

So its real purpose isn't the young collection part — that's routine. Its purpose is to **kick off the liveness scan that space-reclamation depends on.** It's the starting gun for marking.

Now the WHY behind the design. Marking needs a *consistent starting snapshot* — it has to scan the GC roots (stacks, static fields, …) at a single frozen instant, or objects could shift underneath it and be missed. That requires a stop-the-world moment. But G1 was already going to stop the world for a young collection, and a young collection *already* scans exactly those roots. So rather than pay for a second, dedicated pause just to seed marking, G1 **piggybacks** the marking startup onto a young collection it had to do anyway:

```text
             old-gen occupancy reaches IHOP
                          │
   Normal   Normal   Normal   Concurrent Start   Normal ...
     │        │        │        │                  │
     └─ young ┘        └─ young + snapshot roots, start marking ─┘
                          reuses the young pause's STW root scan —
                          no separate pause just to start marking
```

> Concurrent Start = a young collection that also snapshots the roots and lights the fuse for marking. It exists so G1 can *start* scanning the old gen for live objects **without paying for an extra stop-the-world pause** — it hitches a ride on a young pause it was doing anyway.

Once lit, marking runs **concurrently** with the application — the expensive whole-old-gen scan does *not* stop the world, which is the entire point. More Normal young collections can happen while it runs. Marking then finalizes in two short stop-the-world pauses, **Remark** and **Cleanup**; it's **Cleanup** that makes the call on whether there's enough reclaimable old-gen garbage to be worth a space-reclamation phase at all.

- If **yes**, the young-only phase signs off with one **Prepare Mixed** young collection (which works out the minimum set of old regions to collect to stay within the pause goal) and hands over to space-reclamation.
- If **no**, G1 skips space-reclamation entirely, stays in the young-only phase, and lets the old gen keep filling — Concurrent Start can even bail early via a *concurrent mark undo* if it discovers there's nothing worth marking.

(The internals of *how* marking stays correct while the application mutates the heap concurrently — SATB, the write barrier, what Remark and Cleanup each finalize — get their own section below. Here they matter only as the bridge that carries G1 from young-only into space-reclamation.)

> Concurrent Start lives *inside* the young-only phase — it's still a young collection. The phase boundary isn't drawn when marking starts; it's drawn later, by Cleanup, once G1 actually knows there's old-gen space worth reclaiming.

#### The space-reclamation phase: mixed collections

Now that marking has told G1 which old regions are mostly garbage, it can finally reclaim old-gen space — and it does so through **Mixed collections**. A Mixed collection is, once again, a young collection: it evacuates all the young regions *plus* a chosen slice of old regions (the ones marking flagged as cheapest to clean). "Mixed" = young regions mixed with some old regions in the same pause.

Crucially, G1 does **not** collect the whole old generation in one go. It spreads reclamation across *several* Mixed collections, taking a bite of old regions each time, so no single pause has to swallow the entire old gen — this is exactly the "collect a subset, not a whole generation" property from the region layout section paying off. The phase ends when G1 predicts that evacuating still more old regions wouldn't free enough space to justify the pause cost.

Then the whole cycle restarts with a fresh young-only phase, and the old generation begins filling again.

```text
│───────── young-only phase ─────────│── space-reclamation ──│
 N   N   N   CS   N   N  [Rm][Cl][PM]  Mix  Mix  Mix          │  → back to young-only
                 │                      └── young + old ──┘
                 └ starts concurrent marking
 N  = Normal young collection      Rm = Remark (STW)
 CS = Concurrent Start (young)     Cl = Cleanup (STW)
 PM = Prepare Mixed (young)        Mix = Mixed collection (young + old)
```

#### The fallback: Full GC

All of the above assumes concurrent marking and incremental reclamation can keep up with the application's allocation rate. If they can't — if the application runs out of memory while G1 is still gathering liveness information — G1 falls back to a **Full GC**: a single-threaded-by-default, stop-the-world, whole-heap compaction, exactly the kind of long pause G1 exists to avoid (Tuning Guide §7). A Full GC in G1 is a signal that something is wrong — the heap is too small, IHOP fires too late, or allocation/promotion is outrunning reclamation — and it's the first thing to investigate when tuning.

### The concurrent marking cycle

The Concurrent Start collection starts marking; this section is what happens between that start and Cleanup. We already know *why* marking runs (to find the live objects in the old gen) and *where* it sits in the cycle (started by Concurrent Start, ended by Cleanup). What the section above left out is the hard part: **how does marking stay correct while the application keeps rewriting references at the same time?**

#### The problem: marking a moving target

Marking is a graph traversal — start from the GC roots, follow every reference, mark each reachable object as "live." That's easy if the graph holds still. But the whole point of G1 is that marking runs **concurrently**: the application keeps running, allocating, and — the dangerous part — **rewriting reference fields** while the marker walks the heap.

That opens a race that can lose a live object:

```text
At snapshot start:   root → B → C      (C reachable only through B.someRef)

During marking, before the marker has visited B:
    B.someRef = null                   // app deletes the last path to C
```

Without any safeguard, when the marker later reaches `B` the field is already `null` — it never discovers `C`, and `C` goes unmarked **even though it was live when marking began**. If G1 trusted that result, it would free a live object. Fatal.

#### SATB: freeze the graph logically, not physically

G1's answer is **Snapshot-At-The-Beginning (SATB)**. The name is the idea: marking works against a *virtual snapshot* of the object graph taken at the moment marking starts (the Concurrent Start pause — the tuning guide still calls this the **Initial Mark**). **Every object that was live at that moment is treated as live for the whole marking cycle**, no matter what happens to it afterward (Tuning Guide §7).

The snapshot is *logical* — G1 never copies the heap. It keeps the snapshot with a **pre-write barrier**: a small piece of code the runtime adds in front of every reference-field store while marking is running. Before a reference field is overwritten, the barrier records the **old** value into a per-thread SATB buffer, then lets the store go ahead. (This is how HotSpot implements SATB; the tuning guide names the algorithm but doesn't describe the barrier.)

Replay the losing race with the barrier on:

```text
    B.someRef = null
    └─ SATB barrier first logs the OLD value (C) → C will still be marked
```

Now the deletion can't hide `C`: overwriting the last pointer to it is exactly what reports `C` to the marker. The marker reads these buffers and marks everything in them (and everything reachable from those objects). Whatever is left in thread buffers when concurrent marking is almost done gets processed in the **Remark** pause — and that is *why* Remark must stop the world: it needs a moment when no thread can add anything more to its buffer.

#### The price: floating garbage

The rule SATB gives you — *live at snapshot ⇒ marked* — is on purpose **conservative**. It promises nothing the other way: an object that was live when the snapshot was taken but **dies during marking** is still marked live and still survives this cycle. That dead-but-kept memory is **floating garbage**. G1 accepts it on purpose — it's the price of not stopping the application — and just reclaims it in the *next* marking cycle (Tuning Guide §7).

> The snapshot can only be too *generous*, never too *strict*. Too generous means garbage waits one more cycle; too strict would mean freeing a live object. G1 picks the safe side and pays for it with a little floating garbage.

#### What Remark and Cleanup finalize

Concurrent marking does most of the work in the background, without stopping the app. Two short STW pauses finish it off — and their jobs are the *mechanism*, not the phase-level decisions we already saw:

- **Remark** finishes marking itself: it processes the last SATB buffers, completes marking, then does **reference processing** (soft/weak/phantom references) and **class unloading**, reclaims any regions that turned out **completely empty**, and cleans up marking's internal structures (Tuning Guide §7).
- **Cleanup** does the **accounting**: now that marking is done, G1 knows the live-byte count of every old region. It sorts them by how cheap they'll be to collect — most garbage and least connectivity first — and makes the go/no-go call on space-reclamation (the phase boundary from the Concurrent Start section).

Between the two, G1 rebuilds the bookkeeping it needs to collect old regions later — the remembered sets of the candidate regions, which the next section covers.

> Who does what: **concurrent marking** finds the live objects (the expensive part, done without stopping the app); **Remark** finishes that result; **Cleanup** turns it into a *plan* — which regions are worth collecting, and whether it's worth collecting at all.

And the way out we already saw: if Concurrent Start (or early marking) finds the old gen doesn't hold enough garbage to bother, G1 runs a **concurrent mark undo**, throws away the half-finished snapshot, and goes back to the young-only phase — no Remark, no Cleanup (Tuning Guide §7).


### Tracking cross-region references: Remembered Sets & the Collection Set

The region layout section made a promise: G1 can collect *a subset* of regions and pay a pause proportional to that subset, not to the whole heap. Mixed collections are where that promise gets cashed in — evacuate the young regions plus a handful of old ones, and leave the other tens of gigabytes of old gen untouched.

But evacuation has a catch. When G1 copies a live object out of a region into a fresh one, **every reference that pointed at the old location is now stale** and must be updated to the new address. Miss one, and the application follows a dangling pointer into reclaimed memory. So before G1 can free a region, it has to find *every* reference pointing *into* it.

Those references can live anywhere in the heap:

```text
| ... | O | ... |  E  | ... | O | ... |
        │           ▲
        └───────────┘
   an old-gen object points into an eden region we're about to evacuate
```

The naive way to find them is to scan the entire heap for pointers into the collection set. But that's exactly the whole-heap walk the region design was built to avoid — do it and the pause is back to scaling with heap size, promise broken.

#### The Remembered Set: "who points into me?"

G1's fix is to keep the answer precomputed. Every region carries a **remembered set (RSet)**: the set of locations *outside* the region that hold references *into* it (Tuning Guide §7). It's an inverted index of incoming pointers — instead of asking "what does this region point to?" (which you get by scanning the region itself), the RSet answers the reverse question, "**who points at this region?**", without touching the rest of the heap.

That makes evacuation cheap to bound. To collect a region, G1 scans that region's RSet, visits just those locations, and fixes up just those references:

```text
To evacuate region R:
  1. copy R's live objects to a fresh region
  2. walk R's RSet → each entry is a location holding a pointer into R
  3. rewrite those pointers to the objects' new addresses
  4. free R
```

No pointer into R can be missed, because by construction the RSet lists them all — and the work scales with the number of *inbound references*, not with the size of the heap. That's the mechanism that makes "collect a subset" actually cheap.

> The RSet inverts the reference graph for one region: not "where does R point?" but "who points into R?" — so evacuating R never requires scanning anything but R's RSet.

#### Cards: storing the RSet without storing every pointer

Recording the exact address of every inbound reference would be enormous — an RSet could rival the size of the heap it describes. So G1 stores **approximate** locations instead. It logically partitions the heap into **cards** — 512-byte areas by default — and an RSet entry is a compressed index of a *card*, not of a pointer (Tuning Guide §7). The bet is locality: references that sit close together tend to point at objects close together, so one card index stands in for many individual pointers.

The trade-off is a little extra scanning at collection time. An entry says only "somewhere in this 512-byte card there's a reference into me," so G1 rescans the whole card to find the actual pointer. Memory saved on the index, paid back as a bit of scan work — a deliberate space-for-time exchange.

#### Keeping RSets current: the post-write barrier + refinement

An RSet is only useful if it's up to date, and the application is *constantly* rewriting references. Every time it stores a reference that crosses from one region into another, some region's RSet may need a new entry. How does G1 notice?

This is the *second* write barrier in G1, and the pair is worth pausing on. The marking section introduced a **pre-write barrier** that feeds SATB. RSet maintenance uses a **post-write barrier**: a snippet the JIT emits *after* every reference-field store (this is HotSpot behavior — the guide describes the resulting refinement work, not the barrier code itself).

```text
Two barriers, two jobs:
  pre-write  barrier  → SATB / marking   (records the OLD reference, before the store)
  post-write barrier  → RSet maintenance (notes the store, after it crossed regions)
```

The post-write barrier's job is to notice cross-region stores cheaply. When the reference just written points into a different region than the field holding it, the barrier **dirties the card** covering that field. It does *not* update the RSet inline — that would make every pointer store expensive. Instead the dirty card is queued, and **concurrent refinement threads** drain the queue in the background, turning dirty cards into RSet entries off the application's critical path (Tuning Guide §7).

One optimization keeps this affordable: G1 doesn't bother recording references whose *source* is in the young generation. Why? Because the entire young gen is evacuated on *every* collection anyway — G1 will scan all of young regardless, so it finds those references for free. Only references originating in the **old** generation need remembering, and the barrier filters accordingly. (HotSpot behavior.)

This machinery is exactly where G1's steady-state overhead lives:

- **Memory:** every region pays for its RSet; across a large heap that adds up to a real fraction of it.
- **CPU:** a barrier on every reference store, plus refinement threads burning cores to keep RSets current.

Both are tunable. `-XX:G1RSetUpdatingPauseTimePercent` shifts refinement work between the concurrent threads and the GC pause; `-XX:G1ConcRefinementThreads` caps how many threads do it; concurrent refinement can even be disabled to hand all CPU back to the application, at the cost of doing that work inside the pause instead (Tuning Guide §7).

> RSets aren't free. They cost heap memory to store and a write-barrier-plus-refinement tax on every reference store — the price G1 pays to make "collect a subset of regions" possible. It's a large part of why G1's raw throughput sits a notch below Parallel's.

#### The Collection Set: which regions this pause will evacuate

The RSet tells G1 *how* to collect any one region cheaply. The **collection set (CSet)** is the decision of *which* regions to collect next — the set of source regions G1 will evacuate and reclaim in the pause (Tuning Guide §7). Its contents depend on the phase, which ties straight back to the collection-cycle section:

```text
Young-only phase   CSet = all young regions  (+ eager-reclaim humongous)
Space-reclamation  CSet = all young regions  +  a chosen slice of old regions
                          (drawn from the collection set candidates)
```

Young regions are *always* in the CSet — every G1 pause is a young collection, remember. What a mixed collection adds is some old regions, drawn from the **collection set candidates**: the old regions concurrent marking flagged as worth collecting.

And this is where "Garbage-First" finally becomes concrete. G1 selects candidates during the **Remark** pause and ranks them by two properties (Tuning Guide §7):

- **Liveness** — regions with *little* live data (lots of garbage) go first; they give back the most space for the least copying.
- **Connectivity** — regions with *few* inbound references (small RSets) go first; they're cheaper to evacuate because there are fewer pointers to fix up.

Regions that wouldn't free enough to justify the effort are dropped outright — anything below `-XX:G1HeapWastePercent` of the heap is left uncollected. G1 spends its pause budget on the most rewarding regions and simply tolerates the garbage in the rest.

> CSet = *what we collect this pause*; RSet = *how we collect any one region cheaply*. The candidate list is sorted garbage-first — most free space and least connectivity first — so each mixed pause reclaims as much as it can afford within the pause goal.

One last thread back to marking. The RSets of old candidate regions aren't maintained continuously — they're **rebuilt lazily, between the Remark and Cleanup pauses**, exactly once G1 has decided those regions are candidates (Tuning Guide §7). That's the bookkeeping the previous section promised Cleanup leaves behind: by the time space-reclamation starts, every candidate old region has a fresh RSet, ready to be evacuated cheaply. Then, at the start of each evacuation pause, a **Merge Heap Roots** step unions the per-region RSets of all CSet regions into one deduplicated structure, so the copying phase can process them in parallel (Tuning Guide §7).

### Meeting the pause-time goal

Every section so far has been building toward one capability: G1 can size a pause to a budget instead of to the heap. The region layout made a *subset* collectable; RSets made collecting a subset *cheap*; marking decided *which* subset is worth it. This section is where those pieces are spent — **how G1 actually keeps each pause inside the time you asked for.**

#### The goal is a hint, not a contract

You state the target with one flag:

```text
-XX:MaxGCPauseMillis=<n>     default: 200
```

Read the word carefully: it's a **hint**, not a guarantee. G1 is explicitly *not* a real-time collector — it "tries to meet set pause-time targets with high probability over a longer time, but not always with absolute certainty for a given pause" (Tuning Guide §7). If a pause overshoots, nothing throws; G1 just feeds the miss back into its model and adjusts.

And crucially, the goal is a target for *how much work to do per pause*, **not a cap G1 will hit at any cost.** Set it absurdly low (say 1ms) and G1 doesn't refuse or break correctness — it shrinks the work in each pause, collecting fewer regions each time and therefore collecting *more often*. Push it too far and you get frequent tiny pauses that add up to terrible throughput. The knob trades pause length against pause frequency; it can't conjure free time.

> `MaxGCPauseMillis` is a request for *shorter pauses*, answered by *doing less per pause* — which means *more pauses*. It never buys you less total GC work.

#### The prediction model: budget from measured history

G1 doesn't guess how long a pause will take — it **predicts** it from what past pauses actually cost. It "achieves predictability by tracking information about previous application behavior and garbage collection pauses to build a model of the associated costs," then "uses this information to size the work done in the pauses" (Tuning Guide §7).

The model remembers the things that actually drive pause length:

- how long it took to evacuate young generations of a given **size**,
- how many objects had to be **copied**,
- how **interconnected** those objects were — i.e. how much RSet/card scanning the copy required.

These are tracked as a *decaying average plus variance*, with recent pauses weighted more heavily, so the model tracks the application's current behavior rather than its ancient past. Before a pause, G1 asks the model "how much work fits in the budget?" and sizes the collection to the answer.

> The pause budget isn't a static setting G1 obeys blindly — it's a live estimate. G1 measures how expensive its own pauses are and uses that measurement to decide how much to attempt next time.

#### Lever 1 — young-gen size (the young-only phase)

In the young-only phase the collection set is fixed: *all* young regions, always. So the only way to make a pause bigger or smaller is to change **how many young regions there are.** That's exactly what G1 tunes.

At the end of every normal young collection, G1 resizes the young generation for the next mutator cycle, adaptively, between two bounds (Tuning Guide §7):

```text
-XX:G1NewSizePercent      default 5    → min young gen (% of heap)
-XX:G1MaxNewSizePercent   default 60   → max young gen (% of heap)

  smaller young  →  pauses come sooner, each is shorter
  larger  young  →  pauses come later, each is longer
```

G1 picks the size the model predicts will *just* fit the pause goal — the largest young gen that still evacuates within the budget, so it collects as rarely as it can while honoring the target.

There's a catch worth knowing: if you pin the young generation yourself with `-XX:NewSize`/`-XX:MaxNewSize`, you take this lever away from G1 and **pause-time control is disabled** (Tuning Guide §7). You've told G1 the size; it can no longer flex it to hit your goal. It's usually a mistake to set both a pause goal and a fixed young size.

#### Lever 2 — how many old regions (the space-reclamation phase)

In a mixed collection the young regions are already there (pinned to roughly the *minimum*, to leave as much of the budget as possible for old-gen work). Now the lever is **how many old candidate regions to add** to the CSet. G1 fills the pause in three tranches (Tuning Guide §7):

```text
Mixed-collection CSet = young (minimum)
                      + [1] a mandatory minimum of old regions
                      + [2] more old regions, while the model predicts time remains
                      + [3] an "optional" set, evacuated incrementally if time is left
```

1. **Mandatory minimum** — `candidates / G1MixedGCCountTarget` regions (default target **8**), which guarantees the pile of candidates gets cleared over roughly 8 mixed collections rather than one giant pause. This is the "spread reclamation across several pauses" property made concrete.
2. **More, up to the budget** — additional candidates are added until the model predicts **80%** of the remaining pause time would be used.
3. **Optional set** — a reserve G1 evacuates incrementally *only if* the pause still has time left after the first two, so a good prediction is turned into extra reclaimed space instead of wasted budget.

The phase ends when there are no candidate regions left worth collecting — then it's back to young-only.

#### Bounding frequency too: the MMU

One pause fitting the budget isn't enough — a hundred budget-sized pauses back to back would still freeze the app. So the goal is really a pair of flags defining a **minimum mutator utilization (MMU)** (Tuning Guide §7):

```text
-XX:MaxGCPauseMillis=<p>          most GC time allowed ...
-XX:GCPauseIntervalMillis=<i>     ... in any window of this length

  ⇒ in every time window of length i, at most p ms goes to GC pauses
  ⇒ the mutator is guaranteed at least (i − p)/i of every window
```

So the contract isn't only "each pause ≤ p"; it's "over *any* sliding window of length `i`, GC never steals more than `p`." That bounds pause *frequency*, not just pause *length* — the real guarantee an interactive app needs.

> Meeting the goal = a **model** that predicts pause cost from measured history + two **levers** (young-gen size in young-only, old-region count in mixed) to size each pause to the budget + an **MMU** that bounds how often those pauses may fire. G1 spends its whole design on making that budget honorable — with high probability, not certainty.

### Design trade-offs / when to reach for G1

G1 is the default collector since Java 9, and for a large, latency-sensitive server it's usually the right default. But "default" isn't "always best" — everything G1 does to bound pause time is *paid for* somewhere, and other collectors make the opposite trade on purpose. Here's the honest ledger.

#### What G1 costs you

Almost every mechanism in this post has a running price attached:

- **Throughput tax.** The two write barriers (pre-write for SATB, post-write for RSets), the refinement threads, and the concurrent marking cycle all steal CPU that would otherwise run the application. The guide states it plainly: with G1 "application throughput also tends to be slightly lower" than the throughput collectors (Tuning Guide §7). You're paying CPU for shorter pauses.
- **RSet memory.** Every region carries a remembered set; across a large heap those add up to a real fraction of it. Predictable pauses aren't free in *space* either.
- **Floating garbage.** SATB's snapshot rule keeps objects that die *during* marking alive for one more cycle. The heap runs a little fuller than strictly necessary — the deliberate price of not stopping the application to mark.
- **Humongous fragmentation.** Objects ≥ half a region get their own run of regions with a wasted tail, and they're reclaimed late. A workload full of large arrays/strings can fragment badly unless you raise `G1HeapRegionSize`.
- **A worse worst case.** When concurrent work can't keep up, G1 falls back to a single-threaded, whole-heap, stop-the-world **Full GC** — a pause *longer* than a well-tuned Parallel collection would ever have shown. G1's average is excellent; its bad day is bad.

#### The sweet spot

G1 earns all of that back when the workload matches its assumptions:

- **Large heaps** — multi-GB, where a whole-generation compacting pause (Serial/Parallel) would be seconds long. Incremental, subset-based reclamation is the whole point.
- **A pause target in the tens-to-few-hundred-ms range.** That's what the prediction model and MMU are built to hold. `MaxGCPauseMillis` in the low hundreds is G1's home turf.
- **Allocation/promotion rates that vary over time.** The adaptive young-gen sizing and cost model continuously re-tune to the app — exactly the case where a fixed-size collector would need constant hand-tuning.
- **A "just works" default.** For a typical latency-sensitive service you get good pauses out of the box with little tuning.

#### When to reach for something else

| Your priority | Better fit | Why |
| --- | --- | --- |
| Raw throughput, pauses don't matter (batch, ETL) | **Parallel** | No barrier/refinement/marking overhead; higher throughput, simpler. |
| Strict low latency — sub-ms, pause independent of heap size | **ZGC** (or Shenandoah) | Concurrent evacuation; pause times "under a millisecond" and independent of heap size (Tuning Guide §9), at some throughput cost. |
| Tiny heap, single core, short-lived process, container with 1 CPU | **Serial** | G1's concurrent machinery is pure overhead here; Serial is smaller and simpler. |

> Reach for G1 when the heap is big, the pause target is a few hundred ms, and the load shifts over time — the case its adaptive, subset-collecting design was built for. Reach *past* it when you want maximum throughput (Parallel), sub-millisecond pauses (ZGC), or a footprint small enough that concurrency isn't worth its overhead (Serial).
