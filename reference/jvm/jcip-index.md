# Java Concurrency in Practice — Navigation Index

Reference: **Java Concurrency in Practice** — Brian Goetz with Tim Peierls,
Joshua Bloch, Joseph Bowbeer, David Holmes, Doug Lea (Addison-Wesley, 2006).
File: `reference/pdfs/java-concurrency-in-practice.pdf` (425 PDF pages)

## Version coverage

Written in **2006 against Java 5/6**. Blog baseline is **Java 21** — mind the
skew. Enduring (trust it): the JSR-133 memory model, happens-before,
visibility/lock semantics, AQS, CAS. Dated or absent (verify against Java 21):
thread-pool/`Executor` APIs and defaults, and anything post-2006 — virtual
threads & structured concurrency (21), `CompletableFuture` (8), `VarHandle` (9),
parallel streams / `ForkJoinPool` (7/8). It also predates the removal of
`Thread.stop`/`suspend` and deprecation of `finalize`. It is *silent* on features
newer than Java 6, not wrong — don't extrapolate it onto them.

## Role of this source

This is a **practitioner** reference, not a specification. For concurrency,
the *authoritative* spec is **JLS Chapter 17 (the Java Memory Model)** — JVMS
explicitly defers threads/locks to it. So treat JCIP as a strong **secondary
source**: use it for intuition, patterns, correct usage, and the *why*; when a
post makes a hard guarantee about memory-model semantics, that guarantee is
ultimately grounded in JLS §17, and JCIP Chapter 16 is its readable companion.

## How to read a section

Page numbers below are the book's **printed** page numbers (from its Contents).

> **PDF page = printed page + 21**

Example: §16.1 (Java Memory Model) is printed p.337 → read PDF page **358**.
(Read PDFs in windows of ≤20 pages.)

## Chapter map (printed pages)

| Ch | Title | Printed p. | PDF p. |
|----|-------|-----------|--------|
| — | **Part I — Fundamentals** | 13 | 34 |
| 1 | Introduction | 1 | 22 |
| 2 | Thread Safety (atomicity, locking, guarding state) | 15 | 36 |
| 3 | Sharing Objects (visibility, publication/escape, confinement, immutability, safe publication) | 33 | 54 |
| 4 | Composing Objects (thread-safe class design, confinement, delegation) | 55 | 76 |
| 5 | Building Blocks (concurrent collections, blocking queues, synchronizers) | 79 | 100 |
| — | **Part II — Structuring Concurrent Applications** | 111 | 132 |
| 6 | Task Execution (Executor framework) | 113 | 134 |
| 7 | Cancellation and Shutdown (interruption, JVM shutdown) | 135 | 156 |
| 8 | Applying Thread Pools (sizing, ThreadPoolExecutor) | 167 | 188 |
| 9 | GUI Applications | 189 | 210 |
| — | **Part III — Liveness, Performance, Testing** | 203 | 224 |
| 10 | Avoiding Liveness Hazards (deadlock) | 205 | 226 |
| 11 | Performance and Scalability (Amdahl's law, lock contention) | 221 | 242 |
| 12 | Testing Concurrent Programs | 247 | 268 |
| — | **Part IV — Advanced Topics** | 275 | 296 |
| 13 | Explicit Locks (Lock, ReentrantLock, read-write locks) | 277 | 298 |
| 14 | Building Custom Synchronizers (condition queues, AQS) | 291 | 312 |
| 15 | Atomic Variables and Nonblocking Synchronization (CAS) | 319 | 340 |
| 16 | **The Java Memory Model** (happens-before, publication, init safety) | 337 | 358 |
| A | Annotations for Concurrency (@GuardedBy, @Immutable, …) | 353 | 374 |

## Highest-value sections for JVM-journey posts

| Topic | § | Printed p. |
|-------|---|-----------|
| Atomicity & race conditions | 2.2 | 19 |
| Intrinsic locks / `synchronized` | 2.3 | 23 |
| Visibility & stale data | 3.1 | 33 |
| Publication and escape | 3.2 | 39 |
| Safe publication | 3.5 | 49 |
| `synchronized` vs `ReentrantLock` | 13.4 | 285 |
| AbstractQueuedSynchronizer (AQS) | 14.5 | 311 |
| CAS / hardware support | 15.2 | 321 |
| **Java Memory Model / happens-before** | 16 | 337 |
| Initialization safety (final fields) | 16.3 | 349 |
