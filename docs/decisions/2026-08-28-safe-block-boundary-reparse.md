# ADR: Admit Only Grammar-Owned Paragraph Start Reparse

**Date:** 2026-08-28
**Status:** Accepted
**Issue:** [#933](https://github.com/dowdiness/loom/issues/933)
**Implementation plan:** N/A — correctness-first investigation and bounded implementation.

## Context

Block reparse previously required every edit to be strictly inside the old
candidate. This preserved ownership but sent a plain replacement at the first
character of a Markdown paragraph through the document-wide reuse-cursor path.
On large Markdown documents, that fallback is dominated by
`parse_tokens_indexed` even when the paragraph remains locally owned.

A mechanical inclusive comparison is unsafe. A block start can also be a
heading, list, quote, fence, indented-code, thematic-break, container, or
recovery boundary. A block end can be shared with a terminator, sibling, EOF,
or newly created block. Only the grammar can decide whether the old candidate
still owns the final range.

## Decision

Adopt a **narrow GO** for exact-start replacements of Markdown paragraphs.

`BlockReparseSpec` becomes opaque and is constructed through
`BlockReparseSpec::new`. Its optional grammar-owned boundary admission callback
is fail-closed by default. Core calls it only for non-strict candidates and
before detached lexing. The callback sees the old candidate, triggering edit,
and a zero-copy view of final candidate text. Strict-interior edits bypass it
and preserve their existing path.

Markdown admits a boundary candidate only when all of these hold:

- the candidate is a paragraph;
- the edit starts exactly at the paragraph start;
- the edit replaces or deletes old text rather than inserting at a shared edge;
- neither old nor new edit extent reaches the candidate's right boundary; and
- both old and final candidate text retain a plain paragraph start.

The existing grammar selector and token-stream balance check remain additional
fail-closed gates. Every isolated parser must consume its token stream and emit
exactly one replacement node of the candidate kind; direct tokens, sibling
nodes, and kind changes are rejected before splice. Boundary candidates also
require a complete detached lex stream: parallel token/start arrays, in-range
non-decreasing and non-overlapping spans, the exact configured zero-width EOF
sentinel at the candidate end, and replacement text length equal to the
candidate source. Exact token equality, rather than raw-kind equality, keeps
full lex validation, detached validation, and isolated final-EOF consumption on
one sentinel identity contract. Together these conditions prove full candidate
text coverage without rebuilding a second string. Strict-interior reparsing
retains support for fully consumed sparse token streams with explicit starts.
Core still falls through to normal incremental parsing whenever a required gate
cannot prove a complete replacement.

Core retains why each candidate was enumerated. A selected strict-interior
failure preserves the established full-fallback rule. A selected owned-boundary
failure skips any further boundary candidates and resumes at the first enclosing
strict-interior candidate that was eligible before boundary admission. Selector
`None` retains its existing permission to try the next eligible parent.

Do not admit:

- insertion at an exact start or old block end;
- edits reaching the exact new block end;
- terminator or EOF boundary edits;
- newline insertion or removal that can move ownership;
- marker-changing edits;
- ATX or Setext headings, lists, block quotes, fenced or indented code,
  thematic breaks, HTML blocks, empty blocks, or newly created blocks; or
- JSON and Lambda boundaries, whose specs omit boundary admission and retain
  the constructor's strict default.

## Correctness evidence

The permanent Markdown differential matrix compares each edit with a fresh
full parse and requires equality of final source/text coverage, CST and raw
kinds, structured diagnostics and ranges, compatibility `Block` AST,
MarkdownIR, and CommonMark HTML. It covers LF, CRLF, CR, and EOF; top-level,
adjacent, list, and block-quote contexts; insertion, deletion, same-length and
length-changing replacement; newline and marker edits; malformed input; and the
required block forms. An adversarial prefix sweep additionally probes heading,
list, quote, fence, HTML, ordered-list, reference-definition, thematic-break,
Unicode, and malformed-prefix transitions; every admitted probe must satisfy the
same full-parse oracle. An accepted edit also proves that an unaffected following
sibling remains structurally shared. Core robustness cases reject malformed
detached streams with overlap/gap cancellation, decreasing starts, misplaced
EOF, a non-EOF token sharing the EOF raw kind, out-of-range ends, and
non-parallel arrays while retaining the strict-path sparse-start compatibility
case. A synthetic nested-candidate case proves that owned-boundary parser failure
resumes at an enclosing strict candidate, while the existing strict-to-strict
selected-failure case continues to forbid widening.

The public strict-ancestor characterization remains unchanged: exact starts,
exact ends, and right-edge insertions are not returned by the strict helper.
Boundary enumeration is private to the orchestrator and cannot bypass grammar
admission.

## Performance evidence

A permanent JavaScript release benchmark uses 16 distributed edit locations,
20 warm-ups, and 44 measured samples. It reports median, p95, and maximum for
500- and 2,500-block documents.

Representative candidate medians on the investigation machine:

| Blocks | Main exact-start fallback | Candidate exact-start | Main strict interior | Candidate strict interior | Main ownership fallback | Candidate ownership fallback |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 500 | 1.75 ms | 0.11–0.12 ms | 0.08 ms | 0.07–0.09 ms | 1.69 ms | 1.67–1.85 ms |
| 2,500 | 13.11 ms | 0.18–0.30 ms | 0.18 ms | 0.17–0.18 ms | 13.35 ms | 12.95–13.79 ms |

The candidate materially improves the admitted case without a demonstrated
strict-interior or normal-fallback regression. Markdown rows measure ancestor
search, detached lexing, the complete block-reparse operation, an explicitly
unattributed remainder, splice, and fallback `parse_tokens_indexed`; the
remainder is not presented as an isolated phase. A core white-box JavaScript
release benchmark directly invokes isolated parsing, diagnostics, and CST build
on 16 distinct rotating streams containing seven grammar tokens plus final EOF.
After correcting the fixture, two local means were 1.03 µs and 1.68 µs
across 10 × 91,500 and 10 × 47,128 runs respectively.

These are informational local measurements, not CI thresholds.

## Rationale

The opaque constructor deepens the existing `BlockReparseSpec` instead of
adding a second policy type, cache, queue, worker, or lifecycle. It centralizes
the safe default and prevents future internal fields from forcing every grammar
through another record-literal migration. Placing admission before detached
lexing keeps rejected boundary probes from taxing the fallback path. Passing a
final candidate `StringView` is narrower than exposing the complete new source,
avoids rejected-path allocation, and keeps syntax ownership grammar-local.

Insertion at a shared edge remains rejected even when a particular fixture
would parse identically. The old tree does not uniquely identify which sibling
owns that zero-width edit, so local ownership is not proven.

## Alternatives reconsidered

A second investigation pass prototyped the richer-context direction anticipated
by the 2026-06-14 context-deferral ADR in its narrowest form: pass `Edit` to the
existing post-lex selector and use that selector as the sole admission point.
Parity held, but marker-changing fallback paid detached Markdown lexing before
it could decline. In the same JS release harness, the 500-block fallback median
rose from about 1.68 ms with preflight admission to 2.14 ms; the 2,500-block row
rose from about 13.25 ms to 13.56 ms. A full callback context record or public grammar decision enum would preserve
that late-decline cost while exposing more interface than this issue proves
necessary. Reject both for #933. The private admission tag retained by core is
not grammar context: it records only whether a candidate already belonged to
the strict baseline or was added by boundary probing, so failure can restore the
pre-existing strict opportunity without changing callback cost.

Reparsing a synchronization island containing multiple siblings could support
more boundary forms, but Loom currently proves and splices one old node and
merges diagnostics for one contiguous owned range. Establishing stable island
edges across Markdown containers, lazy continuation, Setext ownership, and
recovery would be a separate incremental-parser design, not a safer version of
this bounded change.

Slicing candidate tokens from the persistent `TokenBuffer` after updating it
was also considered. It could remove a measured 0.01–0.02 ms detached lex phase,
but would require exact token-boundary extraction, local EOF synthesis,
full-source diagnostic partitioning, and mode-session orchestration. The
end-to-end admitted path is already about 0.1–0.2 ms, so that mechanism is not
justified by the measured residual.

## Consequences

- This is an intentional pre-1.0 source-breaking API migration. Existing
  record-literal users migrate once to `BlockReparseSpec::new`; the repository
  has no external indexed uses or published release to preserve.
  Grammars that do not pass `may_reparse_boundary` remain strict by construction;
  the existing selector contract remains unchanged. `reparse_block` now states
  the already-required token equality bound explicitly so detached EOF identity
  matches normal complete-lex validation.
- The generated interface replaces exposed record fields with one opaque type
  and constructor, avoiding accidental field coupling and future migrations.
- Markdown exact-start paragraph replacements become independent of document
  size apart from ancestor discovery and path copying.
- Malformed detached boundary lex streams fail closed before parser selection;
  strict-interior sparse-start compatibility remains unchanged. A failed owned
  boundary attempt cannot suppress an enclosing strict candidate.
- All other boundary classes continue to use the existing normal incremental
  parser.
- A future syntax form needs its own differential matrix and explicit grammar
  admission; this ADR is not permission to change strict comparisons globally.
