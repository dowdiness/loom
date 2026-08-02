# Markdown Local Unresolved Block Design

**Date:** 2026-08-02  
**Status:** Accepted  
**Tracker:** [#845](https://github.com/dowdiness/loom/issues/845)  
**Milestone:** Backlog — Core maintenance / benchmark-gated cleanup  
**Evidence:** [`4f743f7`](https://github.com/dowdiness/loom/commit/4f743f78ee3e61aec94f1b8c9b19ef9d7587cdca) on the throwaway `perf/markdown-keyed-lowering-bench` branch

## Problem

MarkdownIR is lowered lazily from the complete live `SyntaxNode`. That policy
keeps syntax-only consumers cheap and is still correct, but a consumer that
observes MarkdownIR after a local edit rebuilds every semantic block.

The measured prototype established two facts:

- caching block-local lowering with relative owned origins makes an exact full
  MarkdownIR observation about 2.85× faster on wasm-gc and 2.99× faster on
  JavaScript for a same-length local edit across 2,500 blocks; and
- making every cached block depend on one complete reference-definition table
  is correct but slower than coarse lowering when a definition changes: 1.62×
  slower on wasm-gc and 1.83× slower on JavaScript in the semantic-only dense
  reference case.

The second result follows from ownership, not an `incr` deficiency. Current
inline lowering resolves full, collapsed, and shortcut reference candidates
while constructing MarkdownIR. A resolved link copies the definition's
destination, title, and absolute definition-owned origins into the block result.
Consequently the block result is neither position-independent nor independent
of document-global definitions.

The production seam must cache only local syntax work. Reference resolution and
document placement must remain explicit later stages.

## Goals

- Preserve exact current MarkdownIR semantics, origins, and diagnostics.
- Reuse unchanged top-level block lowering across local and position-shifting
  edits.
- Make each resolved block depend only on the normalized reference labels it
  actually consumes.
- Keep the module private to the Markdown package until two external adapters
  require a real seam.
- Use existing `incr` cells, `DerivedMap`, runtime GC, and cache sweeping.
- Retain the existing lazy MarkdownIR policy and direct one-shot lowering.

## Non-goals

- No public Loom parser interface or generic incremental-collection interface.
- No change to CommonMark parsing, first-definition-wins behavior, adapter
  contracts, or MarkdownIR's public shape.
- No cache on the existing direct `Block` path; its persistent `CstFold` is
  already faster for full observation.
- No eager MarkdownIR field in parser snapshots.
- No claim that a cache improves one-shot export or fresh parse performance.
- No attempt to make recovery nodes reusable before exact diagnostics can be
  preserved; conservative fallback is allowed.
- No coupling to Canopy integration in this train.

## Module and seam

Introduce one private, in-process deep module in `examples/markdown`. Its
external interface to the Markdown lowering implementation has three
operations:

```moonbit nocheck
priv fn lower_local_unresolved_block(
  cst : @seam.CstNode,
) -> LocalBlockPlan

priv fn resolve_local_block(
  plan : LocalBlockPlan,
  lookup : (String) -> LinkReferenceDefinition?,
) -> ResolvedLocalBlock

priv fn place_resolved_local_block(
  block : ResolvedLocalBlock,
  base : Int,
) -> MarkdownIR
```

The exact private representation is implementation-owned. Callers do not
inspect reference candidates or walk fallback atoms. The deletion test is
satisfied: without this module, relative-origin ownership, unresolved-reference
selection, literal fallback, and placement would reappear in the reactive shell
and differential tests.

`lookup` is an explicit in-process capability, not a new trait or public port.
Pure tests provide a table lookup. The reactive shell provides a lookup whose
per-label read records `incr` dependencies. There is only one production
adapter, so introducing a public interface or trait would be a hypothetical
seam.

### Internal representation obligations

`LocalBlockPlan` must hide enough information to make resolution deterministic:

- block-owned origins relative to the top-level block start;
- normalized reference label;
- full, collapsed, or shortcut reference form;
- link versus image kind;
- already-lowered display/alt content;
- exact literal fallback atoms for the unresolved case;
- inline destination/title data for non-reference links;
- reference labels used by nested candidates; and
- whether exact recovery diagnostics require a contextual fallback.

The implementation must preserve the existing ordering of escaped recovery,
shortcut resolution, image resolution, and literalization. It must not model
every CST `LinkNode` as an independently resolvable candidate if doing so would
change nested-link/image precedence.

`LocalBlockPlan` and `ResolvedLocalBlock` implement exact structural equality
for `incr` backdating. Their equality must contain every field that affects the
final MarkdownIR value.

## Ownership rules

| Data | Owner | Cached local value | Resolution | Placement |
|---|---|---|---|---|
| Block/node/content origins | top-level CST block | relative | unchanged | add current block base |
| Inline destination/title origins | top-level CST block | relative | unchanged | add current block base |
| Reference label/use origins | top-level CST block | relative | select form | add current block base |
| Definition destination/title values | document definition index | absent | copy current value | unchanged |
| Definition-owned origins | document definition index | absent | copy current absolute origin | do not add block base |
| Document origin | live syntax root | absent | absent | construct from live root |
| Parser diagnostics | live parser snapshot | contextual | preserve or fall back | current absolute ranges |

Definition blocks remain absent from rendered flow output. The definition index
retains normalized first-definition-wins behavior and source-order semantics.

### Recovery policy

The first production slice must not invent partial diagnostic rebasing. A plan
whose `Raw` or `Recovered` result depends on document diagnostics may be marked
contextual internally and lowered through the existing live whole-document
context for that block. This fallback must reproduce current MarkdownIR and
diagnostics exactly.

Reusable diagnostic-free blocks remain cacheable in the same document. A later
change may introduce block-relative diagnostic facts only after an isolated
correctness and performance case justifies it.

## Reactive shell

The pure module is connected to the existing syntax-only parser by a thin
imperative shell:

```text
live syntax
  ├─ document layout: [(CstNode, current start)]
  ├─ definition index
  │    └─ DerivedMap<normalized label, definition?>
  └─ DerivedMap<CstNode, LocalBlockPlan>
         └─ DerivedMap<CstNode, ResolvedLocalBlock>
                └─ place from live layout → complete MarkdownIR
```

The resolved per-block computation calls `resolve_local_block` with a lookup
closure backed by the per-label definition map. Dynamic reads make the block
depend only on labels actually requested while keeping label discovery private.
When the document definition index changes, accessed per-label values reverify;
exact equality backdates unchanged labels before dependent block resolution.

The final document derived always visits the current top-level layout because a
full MarkdownIR value must contain current absolute origins. Reuse avoids
repeating syntax interpretation and unrelated reference resolution; it does not
claim sublinear full-value materialization.

### Lifecycle

Both keyed maps are scope-owned. The shell runs the existing runtime GC at the
same editor lifecycle points used by other long-lived reactive consumers, then
calls `DerivedMap::sweep_cache` to remove disposed entries. No new eviction
policy is introduced.

Deterministic tests inspect computation counts and `cache_len` around GC and
sweep. Wall-clock timing is not the lifecycle correctness oracle.

## Correctness matrix

Every scenario compares the new path with
`experimental_markdown_ir_from_syntax_with_diagnostics` using exact IR and
diagnostic equality before, after, and after reversing an edit.

| Family | Required scenarios |
|---|---|
| Local structure | heading, paragraph, containers, lists, code, HTML, duplicate blocks |
| Inline links | valid and invalid destination/title; escaped punctuation; nested emphasis/code |
| References | full, collapsed, shortcut, link, image, unresolved literal fallback |
| Definitions | add, remove, value change, title change, duplicate, normalized-label change |
| Placement | prepend, delete prefix, move equivalent block, same-length edit |
| Recovery | malformed intermediate, parser diagnostics, `Raw`, `Recovered`, source ID/ranges |
| Limits | empty label, whitespace/case normalization, 999-character accepted label, over-limit fallback |

The existing official CommonMark link/image/reference fixtures remain a
mandatory semantic oracle. Target adapters continue to consume only final
MarkdownIR and never perform definition lookup.

## Deterministic invalidation contract

Instrumented white-box tests must prove:

1. A local edit re-lowers only changed structural block keys.
2. A definition value edit re-lowers zero local block plans.
3. A definition for label `x` re-resolves blocks that request `x` and does not
   re-resolve blocks that request only `y`.
4. A definition edit preserves literal fallback/resolution transitions exactly.
5. Prepending an unrelated block reuses structurally identical local plans;
   placement still observes every output block.
6. Repeated edit/delete cycles followed by runtime GC and cache sweep do not
   retain dead keys without bound.

These counts are merge gates. Wall time supplements them but cannot weaken
them.

## Performance contract

Keep setup and parsing outside semantic-only measurements. Run release
benchmarks on wasm-gc and JavaScript with the same edit-and-restore cycle and
observation on both sides.

Required corpora:

- 2,500 independent blocks with no reference definitions;
- mixed realistic Markdown with containers, code, HTML, links, and images;
- sparse references with many unrelated labels;
- dense references sharing one label; and
- prepend/move edits that change absolute placement.

Production integration proceeds only if:

- the exact keyed local-edit path retains a material improvement on both
  deployment targets;
- unrelated-definition edits avoid local lowering and unrelated resolution;
- dense same-label edits do not regress materially against coarse lowering
  after syntax parsing is held constant; and
- fresh one-shot lowering remains on the existing direct path.

Base/head commands, exact commits, means, variance, and deterministic counts
are recorded in `docs/performance/benchmark_history.md`. A permanent benchmark
gate requires A/A calibration after the production harness stabilizes.

## Delivery sequence

### PR 1 — Pure unresolved local core (#846)

- Add private `LocalBlockPlan` and `ResolvedLocalBlock` implementation.
- Extract current link/image literal fallback and reference selection without
  changing final MarkdownIR behavior.
- Implement relative owned origins and definition-origin ownership rules.
- Add exact differential tests for valid, unresolved, nested, limit, and
  diagnostic-fallback scenarios.
- Do not add `incr` wiring or public symbols.

### PR 2 — Reactive keyed shell (#847)

- Add document layout, per-CST local/resolved maps, and per-label definition
  projections using existing `incr` interfaces.
- Add deterministic invalidation counters and GC/sweep lifecycle tests.
- Preserve the direct one-shot and existing Block paths.
- Keep the new path private and opt-in for benchmark/test consumers.

### PR 3 — Existing editor integration and gates (#332)

- Route the existing editor projection through the keyed path without making
  parser snapshots eager.
- Run the complete correctness/performance matrix on wasm-gc and JavaScript.
- Add an A/A-calibrated regression gate only if stable.
- Update the MarkdownIR performance ADR, architecture documentation, and
  benchmark history.
- Delete production copies of prototype helpers; retain the throwaway branch as
  primary-source evidence.

#332 remains blocked until #843, #846, and #847 close. It is the real production
consumer; this train does not create an otherwise-unused public MarkdownIR
attachment.

## Stop and escalate if

- Exact literal fallback requires exposing unresolved candidates in public
  MarkdownIR.
- Correct recovery requires changing parser diagnostic ownership or public
  parser snapshots.
- Per-label dependencies require a new generic `incr` interface.
- The pure core cannot reproduce current official reference fixtures exactly.
- The isolated production prototype loses the measured improvement on either
  wasm-gc or JavaScript.
- Cache retirement requires a new runtime-wide eviction policy rather than the
  existing GC and sweep lifecycle.

## Decision record

Update the existing MarkdownIR performance ADR. No new ADR is needed because
this design materially qualifies that existing memoization policy rather than
establishing an unrelated project-wide rule.
