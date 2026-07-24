---
title: "JVM default ergonomics"
postSlug: jvm-default-ergonomics
author: Cuong
date: 2026-07-24
description: "Learning JVM like a madman (bonus section)"
tags:
  - java
  - jvm
---

This post is a bonus section of the series "Learning JVM like a madman". Today we will explore **JVM default ergonomics**; we will go through the definition and test it with some example code. Grab a coffee and have fun ☺️.

> One note: today's topic doesn't cover GC tuning, because there is so much that could be presented. Going into the detail of GC tuning — young GC, old GC, new heap ratio, and so on — each of those things has its own 10+ flags to tune. So it's not my job today, but in the near future 😛

## I. JVM default ergonomics

Most of us assume that if we don't configure any JVM options, then the JVM simply runs with "default settings." While this is technically true, it is easy to misunderstand what "default" really means. The JVM is **not running without optimization**. Instead, the JVM is already making **performance optimization decisions on your behalf**. It automatically chooses:
- The garbage collector
- Initial and maximum heap size
- Number of GC threads
- JIT compilation strategy
- Various runtime parameters

These automatic decisions are collectively called **JVM ergonomics**.

> JVM default ergonomics is the built-in feature where the Java Virtual Machine automatically selects the garbage collector, compiler type, and heap size based on your computer's hardware to boost performance

### Ergonomics Are Already an Optimization

A common software engineering principle you may know is: make it run first, don't optimize prematurely. Interestingly, the JVM itself does not follow this advice 😉.

The moment a Java application starts, the JVM immediately begins optimizing its execution by selecting configuration values that it believes are appropriate for the current machine and workload. Even if you never specify a single JVM option, you are still accepting an optimization strategy—just one chosen by the JVM instead of yourself. Doing nothing is **not** the absence of optimization. It simply means:
> "I trust the JVM's optimization decisions."

### What Is the Goal of JVM Ergonomics?
The primary goal of JVM ergonomics is **not to maximize performance**. Instead, its goal is to make almost every Java application run reasonably well without requiring manual tuning. The JVM attempts to balance several competing objectives:
- Good throughput
- Acceptable latency
- Reasonable memory footprint
- Minimal user configuration

In other words, ergonomics tries to find a configuration that works well for the majority of applications on the majority of machines. Its philosophy is:

> "The application should start successfully and perform reasonably well."

This is very different from trying to achieve the absolute best performance. So from the JVM's perspective:
- The application starts successfully.
- Garbage collection behaves reasonably.
- Memory usage stays within safe limits.
- Performance is acceptable for most workloads.

However, production systems often have very different goals. As backend engineers, we usually care about:
- Maximum throughput
- Lowest possible latency
- Lowest cloud infrastructure cost
- Predictable GC behavior
- Stable response times under heavy load
> These goals are far more aggressive than the JVM's generic defaults.


### Ergonomics Are a Starting Point

JVM ergonomics should not be viewed as the final configuration of a production system. Instead, it should be viewed as a **starting point**. For small applications, development environments, or internal tools, the defaults are often sufficient.

Nowadays, for most of our production systems—cloud-native or on-premise, both running in Kubernetes—the default configuration may leave significant performance improvements unexplored. Relying solely on ergonomics is not necessarily wrong. However, it may indicate that performance has never been evaluated or optimized for the application's actual workload.

Understanding what the JVM automatically chooses is the first step toward making informed tuning decisions. In the next section, we will walk through some coding examples to understand its choices.

## II. Real world example of JVM ergonomics

To *see* ergonomics in action we don't need a real application. We just start a JVM and ask it one question: **"what did you decide?"**. The interesting part is that the answer changes depending on the size of the machine the JVM runs on. So the plan is to run the same JVM on machines of different sizes and watch its decisions change.

We won't buy several laptops for this. Instead we fake the machine size with **Docker**. A container lets us cap how much CPU and memory the JVM is allowed to see, so one laptop can pretend to be a tiny 128MB box or a roomy 4GB box. The image we use is an Ubuntu-based **Temurin JDK 21**, so the JVM inside the container behaves like the one on the laptop.

You can find the full script in the [jvm-ergonomics](https://github.com/nncuong1/jvm-ergonomics) repository. Here is what each piece does.

### The program under test is deliberately empty

`Hello.java` has an empty `main`. We are not measuring the program — we are measuring the **JVM's decisions**. An empty program keeps the measurement clean: nothing allocates memory or spawns threads to distort the defaults.

### We fake a machine with a Docker container

`docker run --cpus=... --memory=...` starts the JVM with exactly the CPU and memory limits we hand it. The script takes those as arguments:
- arg 1 — number of CPUs (default `1`)
- arg 2 — memory limit (default `128m`)
- arg 3 — optional heap percentage, which pins the initial/min/max heap to a percentage of the container's memory

So `./test21.sh 2 2g` asks: *"on a 2-CPU, 2GB machine, what does the JVM choose?"*

### We ask the JVM to print its final settings

The flag `-XX:+PrintFlagsFinal` makes the JVM dump every configuration flag **after** ergonomics has run — the real values it settled on, not the raw defaults. We never run a workload; the JVM resolves its flags, prints them, and exits. Then we `grep` for the two things we care about:
- `HeapSize` / `RAM` → the heap sizes ergonomics derived from the memory limit.
- `UseSerial` / `UseG1` / `UseParallel` → which garbage collector ergonomics picked.

(`-XX:+AlwaysPreTouch` only forces the JVM to actually touch the heap pages it reserves. It does not change the decision — it just makes the reservation real.)

### What we are looking for

By running the same script across different `--cpus` and `--memory` combinations, we can watch the JVM flip its choices at certain thresholds — a different heap size here, a different collector there. Those crossover points **are** the ergonomics rules, observed directly instead of read from the docs.

And here is the result:

| CPUs | Memory | Collector | MaxHeapSize (bytes) | MaxHeapSize |
| ---- | ------ | ------------ | ------------------- | ----------- |
| 1    | 128m   | UseSerialGC  | 67108864            | 64 MB       |
| 1    | 256m   | UseSerialGC  | 132120576           | 126 MB      |
| 1    | 400m   | UseSerialGC  | 132120576           | 126 MB      |
| 1    | 500m   | UseSerialGC  | 132120576           | 126 MB      |
| 2    | 1024m  | UseSerialGC  | 268435456           | 256 MB      |
| 2    | 400m   | UseSerialGC  | 132120576           | 126 MB      |
| 2    | 2g     | UseG1GC      | 536870912           | 512 MB      |
| 2    | 1791m  | UseSerialGC  | 469762048           | 448 MB      |
| 2    | 1792m  | UseG1GC      | 469762048           | 448 MB      |

So guess what the trend is here? There are actually **two separate decisions** hiding in this table — how big the heap is, and which collector runs — and each flips at its own threshold.

### The heap-size trend

The heap is a **percentage of the container memory**, but the percentage changes in three bands:

- **Up to ~256 MB → heap is 50% of memory.** `128m` gives a `64 MB` heap. This is HotSpot's `MinRAMPercentage = 50`, a floor so a tiny box still gets a usable heap.
- **Between ~256 MB and ~512 MB → heap stays flat at around 126 MB.** `256m`, `400m`, and `500m` all land on the same `126 MB`. This is the crossover zone where the 50% line and the 25% line meet.
- **Above ~512 MB → heap is 25% of memory.** `1024m → 256 MB`, `2048m → 512 MB`, `1791m → 448 MB`. This is the default `MaxRAMPercentage = 25`.

### The collector trend

Collector selection is a **separate** decision from heap size — it depends on whether the box looks *server-class*, which HotSpot defines as **≥ 2 CPUs AND ≥ 1792 MB memory**. Both must hold:

- Every `1`-CPU row is `SerialGC`, no matter the memory — one core never qualifies for G1.
- The `1791m → 1792m` pair is the giveaway: same 2 CPUs, heap stays `448 MB` across both, but the collector flips **exactly at 1792 MB** — `1791m` is Serial, `1792m` is G1.

Notice the two decisions are **orthogonal**: `1791m` and `1792m` get identical heaps but different collectors. Heap sizing and collector selection are computed independently.

### So don't rely on ergonomics for heap sizing

The heap-size trend has a sharp practical edge, especially in Kubernetes. If you rely on ergonomics for your heap, **the JVM only ever claims 25% of the container memory** (once you're above ~512 MB). It's not that the JVM ignores extra memory — it *does* scale with the container — but it only takes a quarter of it.

So picture the common scenario: your ops team bumps a pod from 2 GB to 4 GB to "give the app more room." Kubernetes now reserves 4 GB for that pod, but the JVM heap only grows from `512 MB` to `1 GB`. The other ~3 GB is reserved in the cluster and paid for, but the JVM never uses it as heap. Everyone assumes the app got more headroom; in reality ~75% of the increase is invisible to the heap.

The takeaway: **if you're not tuning the JVM yourself, at least set the heap explicitly.** Go to your configuration and pin `-Xmx` (or `-XX:MaxRAMPercentage`) instead of trusting the 25% default. Otherwise a memory change made by someone who doesn't know about ergonomics silently fails to reach the heap.

> One reminder for accuracy: everything in this section — the 50%/25% percentages, the flat 126 MB band, and the 1792 MB server-class threshold — is **HotSpot ergonomics behavior, not mandated by the JVM specification**. JVMS only guarantees that a garbage-collected heap exists (§2.5.3). These exact numbers are HotSpot's choices for the Java 21 baseline and can change between versions, which is all the more reason not to rely on them.

## III. Conclusion

The heap example above was about *one* setting. The real lesson is bigger: **in a container, don't run on ergonomics at all.** Not even when you've read this post and think you know what the JVM will pick — because the values shift between Java versions, and "knowing the default" is not the same as controlling it.

The reason isn't only technical, it's operational. In a Kubernetes environment everyone around your app wants **precision** — what is running, how much memory, how many CPUs:

- The **ops / SRE team** needs to know how the pod behaves to size and alert on it.
- The **provisioning / budget team** needs to know how much memory and CPU to buy.

If the JVM quietly decides for itself, none of these teams can see the truth from the outside. The container says 4 GB; the JVM uses 1 GB; nobody agrees on what the app actually needs.

So the rule of thumb — my advice is: **do not `java -jar myapp.jar`.** Running with zero flags hands three important decisions to the defaults. Instead, always set them yourself:

- **Set the heap explicitly** — for containers prefer a percentage (`-XX:MaxRAMPercentage`) over a fixed `-Xmx`, so it tracks the pod's memory limit instead of a raw default.
- **Set the garbage collector explicitly** (`-XX:+UseG1GC`, `-XX:+UseZGC`, …) rather than letting the 2-CPU / 1792 MB threshold decide for you.
- **Know how many CPUs the JVM can see** — GC threads, JIT threads, and the collector choice all scale off the CPU count, and a container's limit is not always what the JVM detects.

We'll dig into each of those knobs — how to pick them and how the JVM reads the CPU limit — but not today, maybe another bonus section in the future 😉. W guys 😘.