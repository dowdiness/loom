# ADR: Parser-Bound Markdown Semantic Publications

**Date:** 2026-08-30
**Status:** Accepted
**Issue:** N/A — product-driven performance and retention investigation.
**Implementation plan:** N/A — bounded implementation validated against the direct lowering oracle.

## Context

A long-lived `SyntaxParser` already made Loomark Preview syntax updates
incremental, but every visible refresh still lowered the complete MarkdownIR
document. A 2,500-block Preview also retained prior full JavaScript source
strings because token payloads and detached block text could remain V8
`SlicedString` values backed by an earlier source generation.

A previous reactive keyed MarkdownIR shell reduced successful edits but made
ownership fallback materially slower. Structural reconciliation, multi-generation
maps, Warm/Cold state, and a new generic parser cache would add identity,
eviction, and recovery policy beyond the demonstrated need.

## Decision

Add a parser-bound `MarkdownSemanticSession` that retains exactly one successful
publication. Each publication contains canonical MarkdownIR and opaque
monotonic revision keys for its top-level blocks.

The session has only two update paths:

1. Reuse unchanged top-level blocks when physical CST continuity, clean
   diagnostics, stable definitions, equal block count, and exactly one changed
   block prove the update safe. Relative origins are shifted only for semantic
   forms whose visible meaning is position-independent.
2. Otherwise perform canonical direct whole-document lowering. The direct
   result immediately becomes the sole seed for the next publication.

`Raw`, `Recovered`, non-inline reference surfaces, changed definitions,
diagnostics, structural edits, and ambiguous ownership fail closed to direct
lowering. Semantic extensions are fixed when the session is constructed and
are passed to changed-block lowering.

Revision keys are sufficient conditions for reusing rendered top-level
subtrees. Callers may seed a replacement session with the prior session's first
unused key, preventing a mounted view from confusing two parser lifetimes.
The session exposes keys read-only and never exposes its mutable retained
arrays.

On JavaScript, materialize payload and block-local strings through an explicit
copy. `StringView::to_owned` alone may preserve a V8 backing source; the copy is
required to stop prior complete source generations from remaining reachable.
Native and Wasm keep the ordinary owned-string path.

Do not introduce an incremental graph, structural hash, general keyed parser
API, multiple generations, eviction policy, or background compaction for this
boundary.

## Correctness evidence

Permanent white-box tests compare every session publication with fresh direct
lowering. They cover repeated publication, GFM task-list edits,
length-changing insertion and origin shifting, definition changes, diagnostics,
block-count fallback, and immediate post-fallback recovery. A separate test
proves a caller-owned revision-key sequence continues across session
replacement.

The owning Loomark integration keeps one parser and one semantic session per
healthy engine lifetime. Independent review found and corrected replacement
sessions initially restarting revision keys at zero; the engine now carries the
unused-key floor across `Broken` and replacement states.

## Performance and retention evidence

In Chromium with 2,500 top-level blocks, fresh contexts, reversed execution
order, and five runs, the integrated product episode measured these p95 ratios
against direct lowering:

| Scenario | Candidate / baseline |
| --- | ---: |
| Exact edit | 0.763 |
| Length-changing insertion | 0.758 |
| Ownership fallback, pooled | 0.956 |
| Post-fallback recovery, pooled | 0.685 |

One of five paired fallback runs measured 1.101; the pooled p95 and the median
paired ratio (0.954) remained within the 1.03 adoption gate. These are local
product measurements, not CI thresholds.

After explicit Chromium garbage collection, 1,000 edits increased used heap by
about 29 MB for the candidate and 235 MB for the direct baseline. After 5,000
candidate edits, the increase was about 35 MB, consistent with retained state
bounded by document shape rather than edit count.

## Consequences

- Consumers that need repeated MarkdownIR publications may own one session per
  `SyntaxParser`; one-shot APIs remain canonical and unchanged.
- The new public session and publication types are pre-1.0 APIs with a narrow
  parser-bound lifetime and read-only publication surface.
- Safe local edits avoid whole-document lowering. Conservative misses pay the
  existing direct cost and do not require a separate recovery phase.
- JavaScript token payload construction performs an intentional copy to avoid
  retaining larger backing sources.
- Top-level revision keys are presentation-neutral reuse evidence, not stable
  document identities and not durable serialization keys.
- Retained render closures may add document-size-proportional heap, but old
  source generations no longer grow with edit count.

## Alternatives rejected

- **Reactive keyed MarkdownIR shell:** failed the ownership-fallback gate.
- **Structural reconciliation or hashing:** comparison cost exceeded direct
  lowering and introduced collision or equality policy.
- **Warm/Cold and multi-generation caches:** required duplicate representations,
  cooling policy, eviction, and recovery work.
- **Periodic parser compaction:** removed retained generations but introduced
  150–500 ms synchronous pauses.
- **Generic incremental-query integration:** requires stable occurrence identity
  and retention policy not justified by this Markdown-specific boundary.
