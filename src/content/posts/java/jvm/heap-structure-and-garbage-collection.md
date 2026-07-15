---
title: "Heap structure and garbage collection"
postSlug: heap-structure-and-garbage-collection
author: Cuong
date: 2026-07-10
description: "Learning JVM like a madman PART 4"
tags:
  - java
  - jvm
  - springboot
---

In the [previous blog](/posts/jvm-runtime-data-areas/), we saw that class instances and arrays are stored in heap memory. The heap is also called *shared memory*, because it's the place where multiple threads share the same data.

You can't talk about the heap for long without talking about the Garbage Collector (GC). The two go hand in hand: the heap is the large memory area where a program stores its objects, and the GC is the background service that reclaims unused objects so the program can reuse that space.

So today we'll start with some GC terminology and then dig into the structure of the heap — because understanding GC is what makes the design of the Java heap make sense.

## I. Understanding Java Garbage Collection

### 1.1 Why garbage collection matters

GC matters for a few key reasons:

**Productivity and stability**: without automatic memory management, code needs a memory ownership contract:
-   Who allocates memory?
-   Who releases it?
-   Does ownership transfer when an object is passed to another library?
-   Is reference counting used?
-   Who breaks cyclic structures?

Different libraries may use different ownership conventions. Combining them becomes difficult. GC provides a common contract:

> An object becomes reclaimable when it is no longer reachable.

This makes large ecosystems easier to compose. Objects can cross framework and library boundaries without every component agreeing on a manual deallocation protocol.

**Complex object graphs**: complex applications usually do not hold memory as one simple flat array. They may contain:
- trees,
- graphs,
- caches,
- indexes,
- linked structures,
- framework objects,
- application objects.

As these structures become interconnected, manual lifetime management becomes increasingly difficult.

**Concurrent algorithms**: some concurrent algorithms naturally create immutable or temporary objects and simply stop referencing them later. Automatic memory management makes these patterns practical because the algorithm does not need an explicit reclamation protocol for every object.

### 1.2 GC terminology

#### 1.2.1 Concurrent collector

A concurrent collector runs while your application is running without stopping your application.
``` text
time --->

Application: [RUN][RUN][RUN][RUN]
GC:              [GC ][GC ][GC ]
```
> the word concurrent means the collector is concurrent to your application

#### 1.2.2 Parallel collector

A parallel collector uses more than one thread to do garbage collection. It's parallel with itself.
``` text
GC worker 1: [work]
GC worker 2: [work]
GC worker 3: [work]
GC worker 4: [work]
```
> GC is **parallel within itself**.

#### 1.2.3 Stop the world

**Stop-the-world (STW)** means application threads cannot continue normal execution while a GC operation is performed. Conceptually:

``` text
Application: [RUN][RUN]------PAUSED------[RUN]
GC:                   [ GC WORK ]
```

#### 1.2.4 Monolithic operation

A monolithic GC operation must finish as one indivisible operation before the application can safely continue.

``` text
Application: [RUN]----------------[RUN]
GC:               [A B C D E F]
```

For example, after moving objects, the JVM must ensure references do not lead application code to invalid old locations. (if we've moved an object from point A to point B, we can't let the program run unless we make sure the program doesn't follow a wrong pointer. And there's a lot of pointers to fix)

#### 1.2.5 Incremental operation

Incremental is when you could take a big problem like that and chunk it into pieces and you can say I'll do this much and at the end of the increment I can let the program run (a large operation is divided into smaller safe chunks) : 

``` text
Application: [RUN][RUN][RUN][RUN]
GC:              [A]     [B] [C]
```

GC'll stop the world. GC'll do a little bit. GC get to a place where it's safe to allow the program to run. GC'll let it run a little bit then GC'll stop it again (each increment reaches a state where application execution can safely resume)

#### 1.2.6 "Mostly" keyword

In English, **mostly** means sometimes, right? It also means sometimes not. So in the context of GC, it has the same idea, whenever you see the word **mostly** attributed to garbage collection, we have to read it the opposite of what the rest of the sentence says :
- **Mostly concurrent** means some phases are stop-the-world.
- **Mostly incremental** means some work may still be monolithic.
- **Mostly parallel** means some work is not parallel.

#### 1.2.7 Conservative collector

A **conservative collector** is a collector that's not quite aware of where all the pointers are. It doesn't quite know if something's a pointer or an integer. And when you don't quite know if something is a pointer or an integer, you have to be conservative in treatment.

The main benefit of conservative GC is simplicity and compatibility with code/compiler environments that were not designed for GC. But the cons is: 
- An object may be retained unnecessarily.
- Moving objects is difficult because when copying is done the pointers to the copied objects must be updated, and if it's not clear whether a given bit value is an object pointer or just a numeric value, it cannot be safely determined whether or not it should be modified when the object is copied

Ex:

``` text
void foo() {
    int x = 4096;
}
```

```text
Stack Frame

slot 0 = 0x1000
slot 1 = 0x2000
slot 2 = 0x3000
```

0x1000 is found but what does 0x1000 mean? Is it an integer whose value happens to be 4096 (4096 decimal = 0x1000) or a reference to the object at address 0x1000. A conservative GC does not know the type of this slot and therefore it conservatively assumes:
```text
slot 0
   |
   v
0x1000 Person("Alice")
```
So it marks Person("Alice") as alive but in reality slot 0 = integer 4096. There is no reference to Alice, Alice is actually garbage but conservative GC keeps it alive.

#### 1.2.8 Precise collector

A **precise collector** is a collector which knows where every single reference, every single object pointer is at all times or at any time where the collector needs to run. It's necessary to be precise in order to move objects. Otherwise, we just talked about the problem. But the other thing is that the work to be precise is actually not really the garbage collector doing work. The garbage collector has it easy. Somebody else has to tell GC where all the pointers are. That somebody else is usually the compilers. The JVM and JIT compiler cooperate to provide metadata describing references in:
- stacks,
- registers,
- temporary execution state.
This enables moving collectors.

#### 1.2.9 Safepoint

A **GC safepoint** is an execution state where the JVM has sufficient knowledge about object references for GC-related operations.
The JVM may know:
``` text
register R1 -> object reference
register R2 -> integer
stack slot 4 -> object reference
stack slot 5 -> long
```

A **global safepoint** requires *every* relevant JVM thread to reach a safepoint before the JVM can safely perform a global operation (a stop-the-world GC pause is one such operation).

But threads don't stop the instant they're asked. A thread can only pause at the **safepoint locations** the compiler placed in the code — typically loop back-edges, method entry/exit, and allocation points. When the JVM requests a global safepoint, it raises a flag and then *waits* for each thread to reach its next safepoint check and park itself. The whole operation can't start until the **slowest** thread arrives.

``` text
Thread 1 --[parks quickly]------------[idle, waiting]-------|
Thread 2 --[parks quickly]------------[idle, waiting]-------|
Thread 3 --[still running a long loop...]-------[parks]-----|
                                                ^           ^
                                    slowest thread     GC work
                                       arrives          starts
          |<--------- time to safepoint ---------->|<- GC work ->|
          |<----------- application-observed stop time --------->|
```

This creates an important distinction. The application is frozen for the **sum** of two phases:

``` text
time to safepoint          (waiting for all threads to stop)
+
time performing GC work    (the actual collection)
=
application-observed stop time
```

A thread can be slow to reach a safepoint for reasons that have nothing to do with GC — a long counted loop the JIT compiled without a safepoint poll, a big array copy running uninterruptibly, or the OS simply having swapped the thread out. Meanwhile the threads that already parked sit idle, so this waiting time is a real pause even though *no collecting has happened yet*.

That's why a GC log that measures only collector work may not explain the entire application pause: it reports the "GC work" box above, but the application felt the whole line.

### 1.3 Core collection mechanisms
There are three fundamental jobs of a **precise** collector:
- Identify live objects.
- Recycle memory occupied by dead objects.
- Move objects when necessary.

Different algorithms combine these jobs differently, for example : 
- Mark/Sweep/Compact (for Old Generations)
- Copying collector (for Young Generations)

#### 1.3.1 Marking
How does the GC know that an object is "garbage"? Most people think that the GC counts how many references point to an object like reference counting. But GC does not work that way, because reference counting has a classic fatal weakness: two objects may reference each other in a cycle
```text
---A holds B 
B holds A---
```
even though nothing else in the application uses either of them. Their reference counts would still be `1`, so they would remain alive forever even though they are effectively garbage.

Instead, there is a much cleaner principle called **reachability** or marking. Marking is the good magic thing that lets us know where the live stuff is and where the dead stuff is and where you don't need to worry about cyclical things. It starts from a set of roots called **GC Roots**---local references on the stacks of running threads, static fields, references from JNI, and so on. From those roots, the GC follows reference links through the object graph and marks everything it can reach as "alive."

After traversal finishes, any object that cannot be reached from any GC Root is considered garbage. It does not matter if those unreachable objects reference one another in complicated cycles. Conceptually:

``` text
GC Roots
   |
   +--> A --> B --> D
   |
   +--> C

X --> Y
^     |
+-----+
```

The collector traverses:

``` text
A, B, D, C
```

`X` and `Y` are not reachable from roots, so their cycle does not make them alive.

**Complexity**: The complexity of marking is linear to the live set or the **live object graph**, not simply total heap capacity. A larger heap does not automatically mean proportionally more marking
work if the live set remains unchanged.

#### 1.3.2 Sweeping
After marking:

``` text
marked   -> live
unmarked -> dead
```
A sweeper scans memory and makes dead regions reusable, example:
``` text
Before:
[A live][B dead][C live][D dead]

After sweep:
[A live][ free ][C live][ free ]
```
The collector may add free regions to free lists.
**Complexity** : Sweeping scans heap regions, so its work is related to the amount of
heap memory being swept. this differs from live-set-oriented algorithms.

#### 1.3.3 Fragmentation and Compaction
Mark-Sweep alone creates an annoying problem, After repeated allocation and reclamation:

``` text
[A][free][B][free][C][free][D]
```

Total free memory may be large, but no individual hole may be large enough for a requested object. Example:

``` text
free = 20 MB total
largest contiguous hole = 2 MB
requested array = 10 MB
```

The JVM cannot place the array in ten separate holes because one Java object requires a suitable contiguous object layout from the JVM's perspective. This is **fragmentation** and this is the reason we need **Compaction**

**Compaction** moves live objects together toward one side of the memory region, merging all scattered free gaps into one contiguous free area on the other side. After compaction, allocating a new object can once again be almost as simple as stack-style allocation: move a pointer at the
boundary of the free area.

``` text
Before:
[A][free][B][free][C][free]

After:
[A][B][C][       free       ]
```

But copying the object's bytes may be easy. The difficult part (Remapping) is ensuring references to the object are handled correctly. Move an object:

``` text
B: address 0x1000
        |
        v
B: address 0x5000
```

Update references:

``` text
A.field ---> 0x1000
```
must become:
``` text
A.field ---> 0x5000
```
This is why object relocation and reference remapping are central GC problems.

**Complexity** of compaction is linear with marking because it does not need to process dead objects individually. It mainly needs to move live objects and fix references to live objects.

#### 1.3.4 Copying collector
A major advantage of Mark-Sweep-Compact is that it does not inherently require a second space equal to the entire source space. Copying collector, on the other hand, divides memory conceptually into:

``` text
From Space
To Space
```

Initially:

``` text
From: [A][B][C][D]
To:   [             ]
```

Suppose `A` and `C` are reachable.

The collector traverses from roots and copies reachable objects:

``` text
From: [A][B][C][D]
To:   [A][C]
```

After collection:

``` text
new active space: [A][C][ free ... ]
```

## II. Heap structure - How is the Heap divided ?
Heap is not a flat, uniform space. It is divided into multiple areas, each with a different fate, and the GC treats each area very differently. 
```text
Why is it divided into so many areas ?
```
To answer the question, let's take a look at the section above, where we discussed GC and how the GC knows that an object is "garbage" (1.3). We see the Mark-Sweep-Compact alogirthm, but generational GC is based on the observation (Weak generational hypothesis):
> Most allocated objects die young.
> The relatively small number of objects that survive their early life tend to live for a long time.

Think about objects that are created, used for a few lines of code, and then discarded: temporary variables in loops, `StringBuilder` instances used to build a string, temporary collections, request objects, and intermediate values. On the other hand, some objects survive for a long time: caches, connection pools, configuration objects, and infrastructure objects that
remain alive for most of the application's lifetime.

Based on it, the JVM traditionally divides the Heap into two major areas:
- **Young Generation** for newly created objects.
- **Old Generation**, also called **Tenured Generation**, for long-lived objects.

![Heap split into Young Generation (Eden, S0, S1) and Old Generation](<images/young-generation.png>)

### 2.1 Young Generation
The Young Generation is the memory region where all newly created objects are allocated and most objects are already dead and only a small number survive. The cheapest strategy is therefore not Sweep-Compact but **Copying collector**, also called **Mark-Copy**. (1.3.4)

The idea is very practical: instead of carefully scanning and reclaiming every dead object, just find the few survivors, copy them somewhere else, and reset the entire old area in one operation. The dead objects disappear implicitly when the region is cleared; there is no need to sweep them one by one.

Traditionally, the Young Generation is divided into three parts: one large **Eden** space and two smaller **Survivor** spaces, usually called **S0** and **S1**. So a simplified object lifecycle looks like this:
- Newly created objects normally land in Eden first. Think of Eden as a delivery room: every new object starts there.
- When Eden fills up, a lightweight collection called a **Minor GC** occurs. The collector finds the live objects in Eden and in the currently used Survivor space, copies them into the empty Survivor space, and then resets Eden and the old Survivor space.
- Each time an object survives one of these collections, its age increases.
- Across Minor GC cycles, surviving objects are copied back and forth between S0 and S1 while their ages continue to increase.
- When an object reaches a certain age threshold, the JVM decides that it is probably long-lived and **promotes** it to the Old Generation. In HotSpot the maximum tenuring threshold is `15` — the age is stored in only 4 bits of the object header, so 15 is the hard ceiling — and the threshold can be lowered with `-XX:MaxTenuringThreshold` (e.g. `2`).

```text
`new → Eden → Eden fills → Minor GC → if still alive, copy to Survivor → survive enough GC cycles → promote to Old Generation`
```

### 2.2 Old Generation
This is where long-lived objects reside—those that have graduated from the Young Generation and where Mark-Sweep-Compact-style thinking becomes useful.

The Old Generation has the opposite population profile from the Young Generation: most objects are still alive, and only a relatively small number are dead so : 
=> Using Copying here would be wasteful. The collector would have to copy almost the entire region and would need enough destination space to hold nearly all of the Old Generation.
=> So, conceptually, an old-generation collector can keep objects in place, **Mark** the live objects, **Sweep** the scattered dead objects, and occasionally **Compact** the region to reduce fragmentation. (1.3)

A simple rule to remember is:
> **Copying is valuable when the survival rate is low, as in the Young Generation.**
> **Mark-Sweep-Compact-style collection is valuable when the survival rate is high, as in the Old Generation.**

#### What happens when the Old Generation is full?
When the Old Generation fills up, we are no longer talking about a lightweight Minor GC. Depending on the collector and terminology, old-generation collection may be described as a **Major GC**. More
expensive still is a **Full GC**, which involves the whole Heap and may also involve class metadata cleanup.

These collections are expensive largely because they can involve what application developers fear most: **Stop-The-World (STW)** pauses. During an STW pause, application threads are stopped while the JVM
performs GC work.

Minor GC is also stop-the-world in the traditional HotSpot collectors (Serial, Parallel, G1) — the entire young collection runs inside the pause — but that pause is short because the Young Generation is relatively small and the collector only needs to copy a small number of surviving objects. Only the modern concurrent collectors (ZGC, Shenandoah) push most of this work off the pause.

A Full GC over a multi-gigabyte Heap can cause a much more noticeable pause---from hundreds of milliseconds to seconds in some workloads. That may be enough to stall a request, trigger a health-check timeout, or make an orchestrator believe a service is unhealthy and restart it.

This is why so much garbage-collector engineering focuses on one question: 
> **how can we reclaim memory while minimizing Stop-The-World time ?**
I won't go into detail on each GC (that will be a separate post) because the current post is already long, but in short we can see that 
- Serial GC uses a simpler single-threaded approach.
- Parallel GC uses multiple GC threads to finish collection work faster. 
- G1 divides the Heap into many regions and tries to perform collection in controlled increments. 
- Modern low-latency collectors such as ZGC and Shenandoah move much more work concurrently with the application and aim to keep pauses extremely small.

> Each of these approaches is really just a different strategy for handling one long-standing challenge — the point where your program has to pause everything it's doing.

## III. Conclusion
After sections I and II we know the Heap structure and the strength of GC in memory management. But as a developer, relying entirely on the GC without being careful in your own code is also misleading. 

There is a very common misconception that Java has a GC, therefore Java applications cannot have memory leaks. That is false. The GC can only reclaim objects that are no longer reachable.

If your own code accidentally keeps a reference to objects that should have been discarded---for example, a static `Map` that keeps receiving entries and never removes them, a listener that is registered but never unregistered, or a `ThreadLocal` that is not cleaned up in a thread-pool environment---then those objects are still reachable from the GC's point of view => The GC sees that the anchor rope is still attached, so it politely leaves the objects alone.

As a result, the Old Generation can slowly grow. Full GC may happen more and more frequently while reclaiming very little memory, until the process eventually reaches the `-Xmx` limit and throws:

``` text
OutOfMemoryError: Java heap space
```

The dangerous part is that this kind of leak may never appear during a short test. It accumulates quietly, drop by drop, until a service that has been running perfectly for two weeks suddenly fails at 2 a.m.

The GC frees you from manually calling `free()`, but it absolutely does not free you from thinking about which objects should remain alive and which objects should be allowed to die.

That is why understanding GC has never been about memorizing the Eden-Survivor-Tenured diagram. Later, you may tune G1, use ZGC, or move to a runtime with a completely different GC model. Names such as S0 and S1 may disappear with implementation details and versions. What remains is the underlying way of thinking:
- Objects have lifecycles.
- Most objects die young.
- A small number survive for a long time.
- When the live set is small, copying survivors can be very efficient.
- When the live set is large, collecting mostly in place may be more appropriate.
- Every garbage collector is ultimately wrestling with two old questions: **does anyone still truly need this data, and who is responsible for allowing it to be reclaimed at the right time?**

Once you understand that, seeing repeated Full GC events in a log at midnight should not immediately make you increase `-Xmx` and hope for the best. The better question is:
> **These objects should have died a long time ago. What in my code is still stubbornly holding the anchor rope?**
