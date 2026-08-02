# Blog posts — writing rules

Applies to every post in this folder and below (`java/jvm` and
any series added later). Topic-specific reference material lives in each
series' own `AGENTS.md`.

## Writing for readers

When drafting or rewriting explanatory prose, follow these rules:

1. **Idea first, jargon second.** Lead with the plain concept a reader can hold
   in their head in one sentence; only then bring in the mechanism and the formal
   terms. Don't open with "parameter passing, stack frame creation, branching."
2. **Simple English — no fancy metaphors.** Say the plain thing. Prefer "the
   bigger win is indirect" over "the payoff is second-order"; prefer "inlining
   has to happen first — it unlocks the rest" over "the door the rest walk
   through." If a phrase needs decoding, rewrite it.
3. **List, don't pile into one long paragraph.** If a thing has N benefits, steps,
   or cases, write a short lead line and then N `-` sub-bullets — one per point.
   Don't bury four ideas in one dense sentence.
4. **Show with a tiny before/after example** when it's clearer than describing
   (e.g. `square(dx) + square(dy)` → `dx*dx + dy*dy` for inlining).
5. **Separate the small win from the big one.** State explicitly which benefit is
   minor and which is the point — don't list every benefit at equal weight.
6. **Keep the technical accuracy.** Simplifying the wording never means dropping
   flag names, exact terms, or the spec-vs-implementation distinction — those
   stay. (In the JVM series that's "the spec guarantees X; HotSpot additionally
   does Y"; in the Spring series it's "this is the contract; this is what 6.2.11
   happens to do".)

## Prose, not outline

A file that will become a post is **finished prose**, not a set of notes about
what the post should contain. Lines like "this section answers question 2" or
"keep this paragraph, cut that one" are instructions to the author, and a reader
seeing them has no idea what they're reading. If a file is deliberately still an
outline, name it `*-outline.md` and say so at the top.

## Show the measurement

Prefer printed output over assertion. When a post claims the framework or the
runtime behaves a certain way, run it and paste what it actually printed, then
pin the versions that produced it. A measured claim that surprises you is worth
more than three correct ones you already expected.
