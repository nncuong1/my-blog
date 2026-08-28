# Engineer posts — working context

This folder holds general backend-engineering posts — distributed systems,
messaging, and production patterns — as opposed to the language/runtime
deep-dives in `java/`. Current post: exactly-once producer and consumer with
Kafka and Spring Boot.

## Primary reference: the pinned Kafka source

There is no PDF spec for Kafka. The source of truth is upstream source and the
docs that ship with it, cloned locally and pinned to a tag:

- **Navigation index:** `reference/kafka/exactly-once-index.md` — authority
  ranking, verified config table with `file:line` citations, and a claim →
  source map. **Read this first.**
- **Materialise the sources:** `./reference/kafka/sync.sh` — clones
  `reference/kafka/apache-kafka/` (Apache Kafka **4.3.1**) and
  `reference/kafka/spring-kafka/` (Spring for Apache Kafka **v4.1.1**). Both are
  gitignored and reproducible; if the directories are missing, run the script.

### How to use it

1. Open `reference/kafka/exactly-once-index.md` before the sources. It already
   records the load-bearing facts with their `file:line`, so most questions are
   answered without opening a clone.
2. Kafka's published config docs are **generated from the source** —
   `clients/src/main/java/org/apache/kafka/clients/producer/ProducerConfig.java`
   holds every producer default and doc string. For a config name, default, or
   constraint, read that file rather than a docs page or a blog.
3. `apache-kafka/docs/design/design.md` is the source of the published
   `kafka.apache.org/43/design/` page — quote it directly for delivery-semantics
   prose.
4. Cite so a reader can verify: a config name plus its default, a KIP number, or
   a doc section. When a claim rests on broker internals, name the class
   (`ProducerStateEntry.NUM_BATCHES_TO_RETAIN`).
5. If upstream source and a blog post disagree, **the source wins** — and that
   gap is usually worth a sentence in the post.

### When *not* to consult the references

Copyediting — grammar, spelling, phrasing, Markdown formatting — needs no
reference. Just proofread. Only reach for the sources when a task turns on
*technical accuracy*. If a copyedit surfaces a claim that looks technically
wrong, flag it separately rather than silently "fixing" the facts.

## Version awareness — the big trap in this topic

**Baseline: Kafka 4.3.1 and Spring for Apache Kafka 4.1.1.** *(If we retarget,
change this line and `sync.sh`.)*

Almost every article about Kafka exactly-once was written in **2017**, around
KIP-98 and the 0.11.0.0 release. The *vocabulary* they establish (PID, epoch,
sequence number, transaction coordinator, markers, fencing) is still exactly
right. Their *numbers and constraints* are frequently stale. The concrete case
that bites this post:

- KIP-98 says idempotence requires
  `max.in.flight.requests.per.connection = 1`. Since **Kafka 1.0**
  (KAFKA-5494) the limit is **5**, because the broker retains 5 batches of
  producer state per partition.

Policy:

1. Separate the **stable model** (what at-most-once / at-least-once /
   exactly-once mean, why an ACK can be lost, why offset-commit and DB-write
   can't be atomic across two systems) from the **version-drifting surface**
   (config defaults, limits, EOS modes, API names). Trust the 2017 sources for
   the former; verify the latter against the pinned clone.
2. **Pin the version** on any version-sensitive claim: "since Kafka 3.0",
   "as of 4.3.1", "Spring Kafka 3.0+ only supports `EOSMode.V2`".
3. Never quote a number from a blog post. Numbers come from the source.
4. A source that simply **predates** a feature is *silent*, not *wrong* — don't
   extrapolate it forward.

## Honesty about the guarantee

This topic attracts overclaiming, and Kafka's own docs warn about it
(`design.md:189` — "it is important to read the fine print"). Keep these
boundaries explicit in the prose:

- Idempotence is scoped **per partition, per producer session**. Say so.
- Exactly-once holds for a `read → process → write` **sequence** completed
  inside Kafka. The read and the process themselves are at-least-once. Spring's
  own wording at `kafka/exactly-once.adoc:13-14` is the model here.
- Writing to an **external** system (a database, an RPC) is outside the
  guarantee. The two honest answers are storing the offset with the output
  (`design.md:205`) or an idempotent consumer keyed on a message ID — which is
  what this post builds.
- Distinguish **delivery** from **processing** exactly-once. Most confusion in
  this area is those two being used interchangeably.

## Style

Practitioner posts written from production experience: open on the concrete
setup a reader recognises, name the failure window precisely, then show the
mechanism that closes it. Diagrams of the failure sequence are load-bearing
here — keep them.

### Writing for readers

These rules apply to every series. See `src/content/posts/AGENTS.md`.
