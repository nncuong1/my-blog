# Kafka Exactly-Once — Navigation Index

Knowledge base for `src/content/posts/engineer/building-exactly-one-producer-consumer-with-java-spring.md`.

Run `./reference/kafka/sync.sh` to materialise the local sources. Everything it
clones is gitignored; only this file and `sync.sh` are committed.

Pinned versions:

| Source | Tag | Local path |
|--------|-----|-----------|
| Apache Kafka | **4.3.1** | `reference/kafka/apache-kafka/` |
| Spring for Apache Kafka | **v4.1.1** | `reference/kafka/spring-kafka/` |

Kafka 4.3.1 is deliberate: the post cites `https://kafka.apache.org/43/...`, and
`docs/design/design.md` in this clone **is** the source of that published page.

## Authority ranking of the four cited references

The post's `## References` list mixes four very different kinds of source. Rank
them before resolving any disagreement:

1. **Kafka source + `docs/` in this clone** — the ground truth. Config defaults
   and doc strings are generated from `ProducerConfig.java`, so the source *is*
   the documentation. Prefer this over every link below.
2. **`docs/design/design.md` §"Message Delivery Semantics"** (the post's 4th
   link) — Kafka's own normative prose, current as of 4.3.1. Local, verbatim,
   quotable.
3. **KIP-98** (3rd link) — the *design proposal* from 2017, not a description of
   today's behaviour. Authoritative on intent and vocabulary (PID, epoch,
   sequence number, coordinator, markers), **stale on concrete limits**. See the
   trap below.
4. **Confluent blog** (2nd link, Neha Narkhede, 2017) and **Kreps on Medium**
   (1st link, 2017) — secondary, explanatory, same 2017 vintage as KIP-98. Good
   for framing and for the *why*; never cite them for a number.

Note: the Medium link returns **HTTP 403** to non-browser clients, so it cannot
be re-fetched by tooling. Everything the post needs from it is also in
`design.md` §"Message Delivery Semantics" (the offsets-with-the-output idea) —
cite that instead when a hard claim depends on it.

## The version trap — read before trusting KIP-98

KIP-98 states that enabling idempotence **requires
`max.in.flight.requests.per.connection = 1`**. That was true in 2017 and is
false now. KAFKA-5494 (Kafka 1.0) raised it to 5, because the broker retains 5
batches of state per producer per partition.

Since the post recommends `max.in.flight.requests.per.connection = 5` with
idempotence on, it agrees with Kafka 4.3.1 and *contradicts* its own cited
KIP-98. That is correct but needs no apology in the prose — just don't let the
KIP talk you back down to 1.

## Verified against Kafka 4.3.1 source

Every producer config the post names, checked in the clone. `ProducerConfig.java`
= `apache-kafka/clients/src/main/java/org/apache/kafka/clients/producer/ProducerConfig.java`.

| Config | Default | Where |
|--------|---------|-------|
| `enable.idempotence` | `true` | `ProducerConfig.java:527-531` |
| `acks` | `"all"` (valid: `all`, `-1`, `0`, `1`) | `ProducerConfig.java:391-396` |
| `retries` | `Integer.MAX_VALUE` | `ProducerConfig.java:390` |
| `max.in.flight.requests.per.connection` | `5` (min 1) | `ProducerConfig.java:473-478` |
| `delivery.timeout.ms` | `120000` (120 s) | `ProducerConfig.java:406` |
| `transaction.timeout.ms` | `60000` (60 s) | `ProducerConfig.java:532-536` |
| `transactional.id` | `null` | `ProducerConfig.java:537-540` |

So the post's "on Kafka 3.0+ all four are already the defaults" holds at 4.3.1 —
all four of `enable.idempotence`, `acks`, `retries`,
`max.in.flight.requests.per.connection` are already at the recommended values.

**Where the "5" actually comes from** —
`apache-kafka/storage/src/main/java/org/apache/kafka/storage/internals/log/ProducerStateEntry.java:35`:

```java
public static final int NUM_BATCHES_TO_RETAIN = 5;
```

and the doc string at `ProducerConfig.java:275-276` says why the client limit
matches it:

> Additionally, enabling idempotence requires the value of this configuration to
> be less than or equal to 5, because broker only retains at most 5 batches for
> each producer. If the value is more than 5, previous batches may be removed on
> broker side.

Note the unit: the broker retains **5 batch metadata entries**, not 5 messages
and not 5 individual sequence numbers. The post's own aside about a
ProduceRequest carrying `[M1, M2, M3]` is the same distinction — keep the two
consistent.

Ordering, from `ProducerConfig.java:271-276`: with `enable.idempotence=true`
ordering is preserved **for any allowable value** (1–5); the reordering risk
applies when idempotence is off and retries are on.

Source files worth opening when a claim goes deeper than config:

- `clients/.../clients/producer/internals/TransactionManager.java` — client-side
  PID/epoch/sequence bookkeeping and the transaction state machine
- `storage/.../storage/internals/log/ProducerStateManager.java` and
  `ProducerStateEntry.java` — the broker-side dedup state the whole guarantee
  rests on
- `transaction-coordinator/src/main/java/` — coordinator and transaction log
- `clients/.../common/record/internal/DefaultRecordBatch.java` — where PID,
  epoch and base sequence actually live in the batch header

## Quotable primary text

`apache-kafka/docs/design/design.md`:

| Topic | Line |
|-------|------|
| §Message Delivery Semantics begins | `:179` |
| The three guarantees (at most / at least / exactly once) | `:183-185` |
| "read the fine print" — misleading exactly-once claims | `:189` |
| Committed = all ISR applied it | `:191` |
| Idempotent producer since 0.11.0.0, PID + sequence number | `:193` |
| Consumer's two orderings → at-most-once vs at-least-once | `:199-200` |
| Offsets written in the same transaction as output topics | `:203` |
| **External systems: two-phase commit vs storing offset with the output** | `:205` |
| "Kafka guarantees at-least-once delivery by default" | `:207` |
| §Using Transactions (`isolation.level=read_committed`, `enable.auto.commit=false`) | `:209-225` |

Line `:205` is the one that matters most for the post's consumer section — it is
Kafka's own statement of the idea the post attributes to Kreps:

> When writing to an external system, the limitation is in the need to
> coordinate the consumer's position with what is actually stored as output. The
> classic way of achieving this would be to introduce a two-phase commit between
> the storage of the consumer position and the storage of the consumers output.
> This can be handled more simply and generally by letting the consumer store its
> offset in the same place as its output.

## Spring side

`spring-kafka/spring-kafka-docs/src/main/antora/modules/ROOT/pages/kafka/exactly-once.adoc`
is short and worth reading in full. The sentence to build the consumer section
around, at `:13-14`:

> This means that, for a `read -> process -> write` sequence, it is guaranteed
> that the **sequence** is completed exactly once. (The read and process have at
> least once semantics).

Container behaviour (`exactly-once.adoc:4-9`): give the listener container a
`KafkaAwareTransactionManager`; it starts a transaction before invoking the
listener, `KafkaTemplate` operations join it, and on success the container calls
`producer.sendOffsetsToTransaction()` before commit. On exception it rolls back
and repositions the consumer.

Only `EOSMode.V2` exists in Spring Kafka 3.0+ (fetch-offset-request fencing,
KIP-447); brokers must be 2.5+. V2 removes the old producer-per-`group.id/topic/partition`
requirement.

Classes worth opening under `spring-kafka/spring-kafka/src/main/java/org/springframework/kafka/`:

- `transaction/KafkaTransactionManager.java`, `transaction/KafkaAwareTransactionManager.java`
- `core/DefaultTransactionIdSuffixStrategy.java` — how `transactional.id` suffixes are assigned
- `listener/` — container-level offset commit and after-rollback handling

## What each secondary source actually contributes

Summarised from a fetch, not verbatim — go to the primary sources above for
anything you intend to state as fact.

**KIP-98** — vocabulary and the transactional protocol flow:
`FindCoordinatorRequest` → `initTransactions()`/`InitPidRequest` →
`beginTransaction()` → `AddPartitionsToTxnRequest` on first write →
`ProduceRequest` (PID, epoch, sequence) → `sendOffsetsToTransaction()`
(`AddOffsetsToTxnRequest`, `TxnOffsetCommitRequest`) → `commitTransaction()`
(`EndTxnRequest`) → coordinator writes markers via `WriteTxnMarkersRequest`.
Broker rejects a sequence that isn't exactly one greater than the last committed:
lower → duplicate (ignorable), higher → `OutOfOrderSequenceException` (fatal).
Broker defaults it quotes (`transactional.id.timeout.ms` 7 days,
`max.transaction.timeout.ms` 15 min, `transaction.state.log.num.partitions` 50)
are 2017 values — re-check any you cite.

**Confluent blog** — the framing and the cost numbers: idempotence has
negligible producer overhead; transactional producer with 100 ms transactions
~3% throughput decline vs at-least-once. Also the explicit scope limit worth
quoting in the conclusion: exactly-once is guaranteed within Kafka's own
processing only, and side effects from an RPC to a remote store are **not**
covered.

## Open threads for this post
- The post covers idempotent producer + idempotent consumer (dedup table) but
  never mentions Kafka **transactions** as the other answer to the consumer
  problem — `sendOffsetsToTransaction` + `read_committed`. `exactly-once.adoc`
  is the material for that, if the Conclusion should acknowledge it.
- The Conclusion is empty.
