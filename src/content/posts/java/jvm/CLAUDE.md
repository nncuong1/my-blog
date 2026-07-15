# JVM posts — working context

This folder holds my blog series *"Learning the JVM like a madman."* Posts here
are technical deep-dives on the Java Virtual Machine.

## Primary reference: the JVM Specification

When answering questions or writing/editing content in this folder, treat the
official spec as the source of truth:

- **PDF:** `reference/pdfs/jvms21.pdf` — *The Java® Virtual Machine
  Specification, Java SE 21 Edition* (626 pages).
- **Navigation index:** `reference/jvm/jvms21-index.md` — chapter/section →
  page map, plus the **PDF-page = printed-page + 10** offset.

### How to use it

1. Don't scan the whole PDF. Open `reference/jvm/jvms21-index.md` first, find
   the relevant section, convert the printed page to a PDF page, then Read just
   that window (≤20 pages).
2. Ground factual claims (memory areas, class loading/linking/initialization
   order, bytecode semantics, `class` file structure, verification rules) in the
   spec before asserting them. Prefer the spec's exact terminology.
3. When a post makes a precise claim, cite the section (e.g. "JVMS §2.5.3") so
   it's verifiable.
4. If the spec and common blog folklore disagree, the spec wins — and that gap
   is often worth calling out in the post.

### When *not* to consult the spec

Copyediting tasks — checking English grammar, spelling, phrasing, or Markdown
syntax/formatting of finished content — do **not** need the spec or any
reference. Just do the proofread. Only reach for the spec when a task turns on
*technical accuracy*. (If a copyedit surfaces a claim that looks technically
wrong, flag it separately rather than silently "fixing" the facts.)

### When the spec doesn't cover it

The spec is authoritative but **not comprehensive**. It defines the *abstract*
JVM and deliberately leaves implementation details open (§2.13 "Public Design,
Private Implementation"). It says **nothing** about, e.g.:

- GC algorithms (G1, ZGC, generational heaps, TLABs) — only that a heap exists
  and is garbage-collected.
- JIT compilation (C1/C2, tiered compilation, inlining, escape analysis).
- HotSpot internals (Metaspace, PermGen, compressed oops, object header layout).
- JVM flags, tuning, ergonomics, and real performance characteristics.

For these, follow a tiered policy:

1. **In spec scope → the spec is authoritative on correctness, but not
   sufficient.** "Wins" means only this: on a direct *contradiction* about
   something the spec defines, the spec settles it — don't let blog folklore
   override the definition. It does **not** mean the spec is the only source or
   a complete answer. The spec is terse and formal; still build the answer from
   secondary sources to explain, give intuition, add examples, and — importantly
   — cross-check that I'm reading the dense spec text correctly. Verify facts
   *against* the spec; cite the section for the load-bearing claims.
2. **Implementation detail → use secondary sources and label them.** Draw on the
   other `reference/pdfs/` books, JEPs, OpenJDK/HotSpot docs. Say explicitly
   "this is HotSpot behavior, not mandated by the spec." Naming that boundary
   ("the spec guarantees X; HotSpot additionally does Y") is usually the most
   valuable point for the post.
3. **Genuinely unknown → say so.** Never fabricate a "JVMS §X" citation for
   something the spec doesn't state. Fake authority is worse than a stated gap.

## Concurrency, threads & locks

JVMS says almost nothing about the memory model — it **defers threads and locks
to JLS Chapter 17 (the Java Memory Model)**. So for these topics the JVM spec is
*not* the authority. Use:

- **PDF:** `reference/pdfs/java-concurrency-in-practice.pdf` — *Java Concurrency
  in Practice* (Goetz et al., 2006).
- **Navigation index:** `reference/jvm/jcip-index.md` — chapter map + the
  **PDF-page = printed-page + 21** offset.

JCIP is a strong **secondary/practitioner** source (tier 2), not a spec: lean on
it for happens-before intuition, `synchronized`/lock semantics, visibility,
safe publication, AQS, and CAS. When a post asserts a hard memory-model
*guarantee*, note that it ultimately rests on **JLS §17**; JCIP Chapter 16
(printed p.337) is the readable companion. Same navigation discipline: consult
the index, convert the page, read a ≤20-page window — don't scan the whole book.

## Garbage collection & heap tuning

JVMS says **nothing** about GC algorithms — only that a garbage-collected heap
exists (§2.5.3). For the heap-structure/GC posts (e.g.
`heap-structure-and-garbage-collection.md`), use Oracle's official tuning guide:

- **PDF:** `reference/pdfs/hotspot-virtual-machine-garbage-collection-tuning-guide.pdf`
  — *HotSpot Virtual Machine Garbage Collection Tuning Guide*, Oracle, Java 21
  (57 pages). Covers G1 (the default), the generational model, TLABs, the
  Serial/Parallel/Z collectors, ergonomics, and the tuning flags.

This is a **HotSpot implementation** source (tier 2), not the spec: everything in
it is HotSpot behavior, not mandated by JVMS. Say so explicitly ("the spec
guarantees a garbage-collected heap; HotSpot's G1 additionally does X"). It's a
good match for the Java 21 baseline, so prefer it over older GC folklore for
current defaults and flag names. No navigation index exists yet — the guide is
short, so read the relevant window directly.

## Other references

Other PDFs in `reference/pdfs/` (Effective Java, etc.) are available as secondary
sources when relevant.

## Version awareness

**Baseline: Java 21 (LTS)** — matches JVMS 21. Write version-sensitive claims
against this baseline. *(If we retarget, change this line.)*

References span very different eras, so watch for version skew:

- **JVMS 21** (2023) — current for the abstract VM & `class` file format.
- **JCIP** (2006) — Java 5/6 era. Its *concepts* (JSR-133 memory model,
  happens-before, visibility/lock semantics, AQS, CAS) are still current. Its
  *APIs, defaults, and advice* predate a lot: virtual threads & structured
  concurrency (21), `CompletableFuture` (8), `VarHandle` (9), parallel streams /
  `ForkJoinPool` (7/8), and it still covers the since-removed/deprecated
  `Thread.stop`/`suspend` and `finalize`.

Policy:

1. Separate **stable concepts** (memory model, class loading model, runtime data
   areas, bytecode semantics) from **version-drifting surface** (APIs, defaults,
   deprecations, implementation choices). Trust older sources for the former;
   verify the latter against Java 21.
2. **Pin the version** on any version-sensitive claim: "since Java N", "as of
   Java 21", "removed in Java N".
3. On conflict, the **newer authoritative source for Java 21 wins** — but the
   *evolution* is often the best blog material ("JCIP does X; since Java N you'd
   reach for Y instead").
4. If a source simply **predates** a feature (JCIP knows nothing of virtual
   threads), it is *silent*, not *wrong* — don't extrapolate it onto new
   constructs.

## Style

These are learning-journal deep-dives: precise, first-principles, and honest
about implementation-vs-spec distinctions (e.g. "the spec doesn't mandate a
'PermGen' or 'Metaspace' — those are HotSpot implementation choices").
