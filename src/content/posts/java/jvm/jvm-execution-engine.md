---
title: "JVM Execution Engine: From Bytecode to Optimized Machine Code"
postSlug: jvm-execution-engine
author: Cuong
date: 2026-07-20
description: "Learning JVM like a madman PART 6"
tags:
  - java
  - jvm
  - jit
---

In the previous blogs, we learned how JVM manages classes and organizes memory. But after classes are loaded and memory is allocated, how does the JVM actually execute your code? And how does Java achieve performance comparable to—or even exceeding—compiled languages like C++? This is where the Execution Engine comes into play.

## I. What the Execution Engine actually is

At a high level, the JVM execution engine is responsible for executing bytecode instructions and turning them into machine-level operations that the underlying hardware can understand.
The Execution Engine has three main responsibilities:
- Interpret bytecode instructions sequentially (via the Interpreter)
- Optimize frequently executed code by compiling it to native machine code (via the JIT Compiler)
- Reclaim memory from objects that are no longer in use (via the [Garbage Collector](/posts/the-gc-collectors/))


## II. Interpretation — the starting point

Most of you may know that when you run the javac command, or compile-on-save in your IDE, your Java program is compiled from Java source code into JVM bytecode. This is a binary representation of your Java program. It’s more compact and simpler than the source code. However, a conventional processor in your laptop or server can’t actually execute JVM bytecode.

To run your Java program, the JVM interprets the bytecode. The Interpreter reads bytecode instructions one by one, decodes them, and executes them immediately—without any compilation step.

### A tiny example

Let's make this concrete. Take a method that couldn't be simpler:

```java
int add(int a, int b) {
    return a + b;
}
```

Compile it with `javac`, then disassemble the `.class` file with `javap -c` to see the bytecode the JVM will actually run:

```
int add(int, int);
  Code:
     0: iload_1
     1: iload_2
     2: iadd
     3: ireturn
```

Four instructions. To understand them you need two pieces of the JVM's execution model (JVMS §2.6): every method call gets a **frame**, and each frame holds a **local variable array** and an **operand stack**. The locals hold the method's arguments and variables; the operand stack is the scratch space where the actual work happens. Because `add` is an instance method, slot `0` is `this`, so `a` lands in slot `1` and `b` in slot `2`.

Now watch the interpreter run `add(2, 3)`, one bytecode at a time:

| Instruction | What it does | Operand stack after |
| --- | --- | --- |
| `iload_1` | push local `1` (`a` = 2) | `[2]` |
| `iload_2` | push local `2` (`b` = 3) | `[2, 3]` |
| `iadd` | pop two ints, push their sum | `[5]` |
| `ireturn` | pop the result and return it | `[]` → returns `5` |

This is the whole interpreter loop in miniature: fetch an instruction (opcode byte), decode what it means, mutate the operand stack, move to the next one. Notice there are no CPU registers or memory addresses here—everything is expressed against that abstract operand stack, which is exactly why a normal processor can't run bytecode directly, and why the JVM has to stand in the middle.

## III. The problem: interpretation is too slow

The interpreter we just watched is wonderfully simple, and that simplicity has a real payoff: it starts *instantly*. There's no compile step, so the first time a method is called the JVM can run it immediately. For code that executes only a handful of times, interpreting is exactly the right trade—you'd spend more time compiling it than you'd ever save.

But look closely at what that loop pays on *every single instruction*:

1. **Fetch** the next opcode byte.
2. **Decode** it—figure out which operation the byte `0x60` stands for, how many operand bytes follow it, and where its inputs live. In a textbook interpreter this is a giant `switch (opcode)`, so every instruction pays for a branch to reach its handler.
3. **Execute** the handler, pushing and popping the operand stack.

Here's the catch: the bytecode never changes, yet the interpreter redoes all of that work *from scratch every time an instruction runs*. A loop that runs ten million times re-decodes the exact same opcodes ten million times. The result of the decode is identical on every pass, but the interpreter throws it away and rediscovers it on the next.

And the per-instruction dispatch is only half the cost. The other half is that the interpreter can only ever see *one* instruction at a time. Because every value is expressed against the abstract operand stack, it keeps getting shuffled to and from memory instead of staying in a CPU register. And because the interpreter never looks *across* instructions, it misses every optimization that needs a wider view:

- it can't notice that a tiny method is called in a loop and paste its body inline;
- it can't keep a loop counter in a register across iterations;
- it can't drop a bounds check it already proved safe.

A native compiler does all of these; the interpreter, by design, does none.

**The 90/10 rule.** In practice this waste is concentrated. Most programs spend the overwhelming majority of their runtime in a tiny fraction of their code—hot loops and a handful of frequently called methods. (The old rule of thumb is "90% of the time in 10% of the code"; the exact numbers don't matter, the skew does.) The vast bulk of the bytecode barely runs at all, so interpreting it costs nothing worth worrying about. But that small hot fraction runs *constantly*, and interpreting it—re-decoding, re-dispatching, bouncing through the operand stack—millions of times over is exactly where the JVM wastes the most time.

That observation is the whole key. If the JVM could *identify* the hot fraction and pay a compilation cost only there—translating that bytecode into native machine code once, so the CPU runs it directly with no interpreter loop at all—it would get the best of both worlds: instant startup for cold code, and near-native speed for the code that actually matters. That is exactly what the Just-In-Time compiler does.

## IV. Just-In-Time (JIT) compilation

> **A note on scope.** Everything from here on is **HotSpot implementation detail**, not the JVM Specification.

The interpreter is slow for the reasons we just picked apart: it re-decodes and re-dispatches every instruction, and it can never see *across* instructions to optimize. So alongside the interpreter, the JVM ships a second execution path—an optimizing compiler that translates bytecode into the native machine code your processor runs directly. This is the **JIT (Just-In-Time) Compiler**.

The name is the whole idea. A JIT compiler doesn't compile *ahead* of running the program; it compiles *while the program is running*, "just in time" for the code that turns out to matter. That sounds like a handicap next to a C++ compiler that gets to think for as long as it likes before the program ever starts—but it's actually the source of Java's edge, and it helps to see why by placing the three strategies side by side.

### Three points on a spectrum

| Strategy | When it compiles | Startup | Peak speed | What it knows |
| --- | --- | --- | --- | --- |
| **AOT** (C, C++, Rust) | Before the program runs | Instant—no runtime step | Fast | Only what's provable *statically*, at build time |
| **Pure interpretation** | Never | Instant | Slow, forever | Nothing it can act on |
| **JIT** (HotSpot) | At runtime, on hot code | Fast to start executing—interprets first, no compile-first wait | Fast, after warm-up | The program's *actual* runtime behavior |

Ahead-Of-Time compilation buys peak speed but pays for it up front: the compiler runs once, before the program starts, and every optimization it makes has to hold for *every possible* execution, because it can't see how the program will actually be used. Pure interpretation is the opposite trade—no compile step ever, so startup is instant, but the code stays slow for its whole life.

> **A caveat on "instant."** This column is about *compilation* delay only. The JIT avoids a compile-first wait, but the JVM still pays a real startup cost the native binaries don't—booting the VM and loading, verifying, and linking classes. That's why a normal JVM app starts in ~hundreds of milliseconds (and a big framework like Spring Boot in seconds), not the ~5 ms of a C++ binary. AOT for Java (GraalVM Native Image) is what closes *that* gap.

The JIT refuses to pick. It starts in the interpreter (instant startup, no compile cost) and, crucially, uses that interpreter run to *watch the program execute*. Only when a piece of code proves itself hot does it pay to compile that piece—and by then the JVM has something a static compiler never gets: a live profile of what this program, on this run, actually does. Which branch is taken 99% of the time? Which concrete type does this call site really see? Which method is called so often it should be pasted inline? Armed with those answers, the JIT can make optimizations that would be unsound at build time—and that is the mechanism behind the surprising claim that a JIT can, on the right workload, *outrun* an AOT-compiled binary. (We'll make that concrete in [section VI](#vi-the-optimizations-that-make-java-fast).)

### Finding the hot code: counters

For any of this to work, the JVM first has to *identify* which code is hot—and it does so with almost embarrassingly simple bookkeeping. HotSpot keeps two counters attached to each method:

- an **invocation counter**, bumped each time the method is entered, and
- a **back-edge counter**, bumped every time control jumps *backward*—which is exactly what the bottom of a loop does on each iteration.

The back-edge counter is what lets the JVM notice a method that's called only *once* but spins in a ten-million-iteration loop. For example:

```java
public static void main(String[] args) {
    long sum = 0;
    for (int i = 0; i < 100_000_000; i++) {
        sum += i;                 // the loop body runs 100 million times...
    }
    System.out.println(sum);
}
```

`main` is entered exactly **once**, so its invocation counter stops at 1 and would *never* trip a compile threshold on its own. But every trip around the `for` loop takes a backward jump to the top, so the back-edge counter climbs toward 100 million and blows past its threshold almost immediately. Without the back-edge counter the JVM would happily interpret this loop to the bitter end; with it, the JVM spots the hot loop, compiles the body to native code, and—because `main` is still sitting mid-loop on the stack—swaps the running interpreted loop for the compiled version *without waiting for the method to be called again*. That mid-flight swap is **On-Stack Replacement (OSR)**, and it's precisely why the back-edge counter exists. (More on OSR in [section VI](#vi-the-optimizations-that-make-java-fast).)

When a counter crosses a threshold, the method is queued for compilation. This detecting-and-compiling of hot spots is literally where the HotSpot VM gets its name. In the classic single-compiler model there was one knob, `-XX:CompileThreshold` (default `10000`), and crossing it meant "compile this now." Modern HotSpot runs *tiered* compilation by default, so the reality is more layered—there are several thresholds feeding several compilers—but the core idea is unchanged: cheap counters find the hot fraction, and only that fraction pays the compilation cost. We'll unpack the tiers next.

### Watching it happen

None of this has to be taken on faith—you can watch the JVM compile your code in real time with `-XX:+PrintCompilation`:

```
java -XX:+PrintCompilation YourProgram
```

Each line is printed as a method gets compiled. A trimmed sample:

```
  113    1       3       java.lang.String::hashCode (55 bytes)
  152    9       4       java.lang.String::equals (81 bytes)
  158   14 %     4       YourProgram::hotLoop @ 6 (43 bytes)
  201    9       3       java.lang.String::equals (81 bytes)   made not entrant
```

Reading the columns left to right:

- a timestamp in milliseconds since startup,
- a compilation ID,
- a flags column,
- the **tier level** (that `3` and `4`—the subject of the next section),
- and the method with its bytecode size.

Two details are already worth noticing. The `%` on the third line marks an **On-Stack Replacement** compilation (a hot loop being swapped out mid-run), and `made not entrant` on the last line is the JVM *throwing away* a compiled method—a hint that an optimistic assumption was later invalidated and the code had to be recompiled or dropped back to the interpreter. That "compile on a bet, undo it if the bet fails" behavior is **deoptimization**, and it's central to how the JIT gets away with its most aggressive optimizations. We'll come back to it.

## V. Tiered compilation (C1 & C2)

The picture from the last section—"count until hot, then compile"—still hides a real tension. Compilation isn't free: the better the machine code you want, the longer the compiler has to think, and every millisecond it spends optimizing is a millisecond the hot code is *still* being interpreted while it waits. So which do you want, a compiler that produces good code slowly, or one that produces mediocre code fast?

HotSpot's answer, again, is to refuse the choice. It ships **two** JIT compilers:

- **C1** (the *client* compiler) — fast to compile, light on optimization. It gets native code onto the CPU quickly, but that code isn't the last word in speed.
- **C2** (the *server* compiler) — slow to compile, aggressive as it gets. It does the heavy optimizations from [section VI](#vi-the-optimizations-that-make-java-fast)—deep inlining, escape analysis, speculative devirtualization—and produces code that can beat a static compiler, but it takes far longer to think.

For years you had to pick one up front (`-client` vs `-server`). **Tiered compilation**, on by default since Java 8, uses both: C1 first to get a quick speedup, then C2 on the very hottest code to reach top speed—and, crucially, C1's compiled code *profiles the program as it runs* so that by the time C2 takes over, it has a rich picture of what the code actually does.

### The five levels

That handoff isn't a single jump from C1 to C2. HotSpot numbers **five levels**, and the difference between the C1 levels is entirely about *how much profiling they collect*:

| Level | Who runs it | Profiling collected | Speed of the code |
| --- | --- | --- | --- |
| **0** | Interpreter | full (counters + type profiles) | slowest |
| **1** | C1 | **none** | fast |
| **2** | C1 | basic (invocation + back-edge counters) | fast |
| **3** | C1 | **full** | fast |
| **4** | C2 | none (it *consumes* the profile) | fastest |

Collecting a profile costs something—every counter bump and type record is extra instructions in the compiled code—so the levels trade profiling against raw speed. Level 3 is "fast code that's also busy watching itself"; level 1 is "fast code with the watching stripped out."

### The common path: 0 → 3 → 4

The typical journey of a hot method is **0 → 3 → 4**:

1. It starts at **level 0**, interpreted, while the interpreter gathers the first profile.
2. Once it's warm, C1 compiles it at **level 3**—*full profiling* C1 code. It's now running native speed *and* recording detailed profile data: not just how often it runs, but which branches it takes and which concrete types show up at each call site.
3. When it crosses the higher C2 threshold, C2 compiles it at **level 4** using that level-3 profile to drive its aggressive optimizations. Level-4 code no longer profiles itself—it has what it needs and drops the overhead.

So the profile flows **interpreter → C1 → C2**: each stage runs the code *and* hands the next stage better information about it. This is why tiering isn't just "two compilers stapled together"—the intermediate C1 stage exists as much to *observe* as to speed things up.

Levels 1 and 2 are the off-ramps for when that ideal path doesn't fit:

- **Level 1** (C1, *no* profiling) is where a method C2 can't improve on—a trivial getter, say—goes straight, because there's no point paying to profile code that will never be worth C2's attention; it's already at its best.
- **Level 2** (C1, only basic counters) is a stopgap: if the C2 queue is backed up, a method may be compiled here to get *some* speedup now, then be re-profiled at level 3 and promoted to 4 once C2 catches up.

This is exactly what the tier column in `-XX:+PrintCompilation` was showing back in [section IV](#iv-just-in-time-jit-compilation): a `3` is full-profile C1, a `4` is C2, and a method printed twice—first `3`, later `4`—is one you just watched climb the ladder. You can turn tiering off with `-XX:-TieredCompilation` to force the old single-C2 behavior, or cap it with `-XX:TieredStopAtLevel=1` (handy for short-lived programs that never run long enough for C2 to pay off), but the default tiered path is what almost every real workload wants.

## VI. The optimizations that make Java fast

This is the payoff for all that machinery: *what* C2 does with a hot method and its profile. It's also where we finally settle the §IV promise—that a JIT can *outrun* a C++ binary. (Reminder: everything here is **HotSpot behavior, not the spec**.)

The optimizations, most important first:

- **Inlining — the mother of optimizations.** The simplest one to picture: instead of *calling* a small method, the compiler copies its body straight into the caller. So this—

  ```java
  int square(int x) { return x * x; }
  int dist = square(dx) + square(dy);
  ```

  —effectively becomes this:

  ```java
  int dist = dx*dx + dy*dy;
  ```

  Skipping the call itself (setting up arguments, jumping, returning) is the *small* win. The bigger win is indirect: once the body is pasted in, the compiler sees it all as one piece of code, so the other optimizations can now work *across* the old call boundary—constants fold, dead branches disappear, escape analysis reaches further. That's why inlining usually has to happen first: it unlocks the rest.

  But the compiler *doesn't* inline everything—and it shouldn't. Pasting a body in makes the compiled code bigger, and past a point that hurts: bloated code blows the CPU's instruction cache (which can make things *slower*), and C2 spends more time compiling. So HotSpot rations inlining, deciding call site by call site using two rough tests:

  - **Size** — how big is the callee? Tiny methods are always eligible (`-XX:MaxInlineSize`); larger ones only get inlined if they're hot, up to a bigger ceiling (`-XX:FreqInlineSize`). Past that, it refuses.
  - **Hotness** — how often does this call actually run? A hot call earns the larger size budget; a cold one doesn't get inlined at all.

  When a method you *expected* to be inlined wasn't, `-XX:+PrintInlining` makes the decision visible: it prints, for each call site, whether HotSpot inlined it and—if not—why ("callee is too large", "hot method too big", "not compilable", …).

- **Speculative devirtualization.** You can only inline a call if you know which method will actually run—but most Java calls are *virtual*, so the target depends on the object's real type. The profile usually tells us anyway:
  - Most call sites are **monomorphic**—the same concrete type every time (`list` was *always* an `ArrayList`).
  - So C2 compiles a direct call to that observed type, which *can* be inlined.
  - It guards the call with a cheap type check; if the type is ever different, the bet is off.
  - Net result: a virtual call you couldn't inline becomes one you can.

- **Speculation + deoptimization — the secret weapon.** Devirtualization is one case of C2's core trick: *bet on the profile, guard the bet, undo it if it breaks.*
  - Branch never taken in practice? Compile as if it can't happen.
  - Field never null? Drop the null check.
  - If a guard ever fails, HotSpot throws away the compiled code and drops back into the interpreter at the exact bytecode—**deoptimization** (an *uncommon trap*; the `made not entrant` from §IV's `PrintCompilation`).
  - *This is how a JIT beats AOT:* C++ must be correct for **every possible** run, so it can't drop a check it can't *prove* dead. The JIT only has to be correct for runs it has **actually seen**, and bails out otherwise.

- **Escape analysis — making allocations disappear.** The idea: if an object never leaves the method that created it, it doesn't need to live on the heap at all.
  - "Never escapes" means it's not stored in a field, not returned, and not passed anywhere that outlives the call.
  - Then C2 skips the heap via **scalar replacement**—it keeps the object's fields in registers, so there's no allocation and nothing for the GC to clean up later. (Often called "stack allocation," but usually the storage is removed outright.)
  - A lock on a non-escaping object is also deleted (**lock elision**).
  - On by default (`-XX:+DoEscapeAnalysis`); it's why allocation-happy idiomatic Java stays cheap.
  - Depends on inlining: a passed object only stops escaping once the callee is inlined.

- **Loop optimizations.** The hot 10% is mostly loops, so C2 works them hard:
  - **Loop unrolling** — copy the body several times, so there's less per-iteration bookkeeping (counter + back-edge test) and more parallel work to exploit.
  - **Auto-vectorization (SIMD)** — fed by unrolling: add 4–8 array elements in a single instruction.
  - **Bounds-check hoisting/elimination** — once the index is proven safe, the check moves out of the loop or is dropped, so Java's mandatory array-safety costs nothing in the inner loop.

- **On-Stack Replacement (OSR).** The fix for a loop that's hot but only entered once:
  - The problem: a `main` stuck in a 100M-iteration loop is called only *once*, so "recompile for the next call" never fires—there is no next call.
  - OSR swaps the running interpreted loop for compiled code *mid-flight*.
  - It captures the live frame (locals, operand stack, loop index) at a safe point and moves it into the compiled frame, which resumes on the next iteration.
  - It's the `%` flag in `PrintCompilation`—basically deoptimization in reverse (state moving *into* compiled code instead of out).

Together—inlining opening the doors, guarded speculation making unsound-looking bets safe, escape analysis erasing allocations, loop work attacking the hot 10%, OSR catching long loops in the act—these are why Java starts like a scripting language and, once warm, runs like a systems one.

## VII. Putting it all together

We've now seen every moving part on its own. Step back and watch a single hot method travel through all of them, because the whole design only makes sense as one pipeline:

```
  source (.java)
        │  javac  (compile time)
        ▼
  bytecode (.class)
        │  loaded & verified
        ▼
┌───────────────────────────────────────────────┐
│ Level 0 — INTERPRETER                          │
│  runs immediately, no compile cost             │
│  bumps invocation + back-edge counters,        │
│  gathers the first profile                     │
└───────────────────────────────────────────────┘
        │  counter crosses threshold → "hot"
        ▼
┌───────────────────────────────────────────────┐
│ Level 3 — C1 (full profiling)                  │
│  fast native code that *also* records          │
│  branch and type profiles                      │
└───────────────────────────────────────────────┘
        │  hotter still → C2 threshold
        ▼
┌───────────────────────────────────────────────┐
│ Level 4 — C2 (consumes the profile)            │
│  inlining, speculative devirtualization,       │
│  escape analysis, loop opts — top speed        │
└───────────────────────────────────────────────┘
        │
        │  a speculative bet fails (guard trips)
        └──────────────► DEOPTIMIZE ──────────────┐
                         "made not entrant",       │
                         resume in the interpreter │
                         at the exact bytecode ◄────┘
                         (re-profile, recompile)

  (long-running loop? OSR splices compiled code
   into the frame mid-iteration, same plumbing
   as deopt, run in reverse.)
```

The arrow that makes this a *loop* rather than a straight line is the one from C2 back to the interpreter. Every other execution model is one-directional—source compiles to code, code runs. HotSpot's is a feedback cycle: each stage runs the code *and* feeds the next stage a better picture of it, and when a bet turns out wrong the whole thing rolls back to the safe interpreter and starts the climb again with corrected information.

The three execution modes it moves between make different trade-offs, and it's worth seeing them lined up:

| | **Interpreter** | **C1** (client) | **C2** (server) |
| --- | --- | --- | --- |
| **Tier level** | 0 | 1–3 | 4 |
| **Startup / latency** | instant | quick | slow to compile |
| **Peak speed** | slowest | fast | fastest |
| **Optimization** | none | light, local | aggressive (inlining, escape analysis, loop opts) |
| **Profiling** | full | full at level 3, none at level 1 | none — *consumes* the profile |
| **Main job** | run now, watch the code | quick speedup + gather profile | top speed on the hot fraction |

No single row wins outright—which is exactly why HotSpot refuses to choose and runs all three, each covering the phase the others are bad at:

- the **interpreter** owns the first milliseconds,
- **C1** owns warm-up,
- **C2** owns steady state.

## Conclusion

That is the whole arc of the execution engine. 
- Bytecode starts life in the **interpreter**—instant to start, slow to run, but quietly profiling itself. 
- The 90/10 rule means only a sliver of that code is worth more, so cheap **counters** find the hot fraction and hand it to the **JIT**. 
- **Tiered compilation** then walks it up the ladder—interpreter to C1 to C2—each rung trading a little profiling overhead for more speed, until C2 unleashes the optimizations that actually matter: **inlining** first, which unlocks the rest, **speculative devirtualization** and **deoptimization** making unsound-looking bets safe, **escape analysis** erasing allocations, and the **loop optimizations** plus **OSR** attacking the hot loops directly. That feedback loop—run, profile, compile, and deoptimize when reality disagrees—is why Java can start like a scripting language and, once warm, run like a systems one.