# ADR: MarkdownIR Performance, Memoization, and Eager/Lazy Policy

**Date:** 2026-06-16
**Status:** Accepted
**Issue:** [#339](https://github.com/dowdiness/loom/issues/339)
**Updated by:** [#777](https://github.com/dowdiness/loom/issues/777),
[#845](https://github.com/dowdiness/loom/issues/845),
[#332](https://github.com/dowdiness/loom/issues/332)
**Implementation plan:** N/A — issue-scoped benchmark and policy note.

## Context

MarkdownIR sits between the parser's CST/`SyntaxNode` and target views such as
`Block`/`Inline`, mdast JSON, source rewrites, and canonical formatting. Adding
this layer is intended to give Loom one typed semantic tree that can feed
multiple backends, but it also risks memory/time overhead in editor hot paths if
the IR is built eagerly or duplicated across independent consumers.

Issue #339 asked for an explicit policy covering:

- whether MarkdownIR is built eagerly on every parse snapshot or lazily by
  consumers;
- whether MarkdownIR is cached with `CstFold` or a new memo layer;
- which target views share the same IR memo;
- acceptable memory overhead;
- how diagnostics and source origins are stored without duplicating CST text;
- and what benchmark should guard regressions.

## Decision

1. **MarkdownIR is built lazily on demand, not eagerly on every parse snapshot.**
   The parser publishes `SyntaxNode`; consumers that need MarkdownIR lower it
   when they read their derived value. This avoids paying the IR cost for
   consumers that only need CST diagnostics or the direct `Block` path.

2. **`CstFold` is NOT the MarkdownIR memoization boundary.**
   `CstFold` keys its cache by the position-independent structural hash of a
   `CstNode` and returns the cached `Ast` verbatim on a hit. MarkdownIR stores
   absolute UTF-16 source origins derived from `SyntaxNode::start/end`. If a
   position-shifting edit moves an otherwise unchanged subtree, `CstFold` would
   reuse an IR value whose origins point to the old source positions, breaking
   origin invariants and corrupting preserve/local rewrites. Therefore
   `experimental_markdown_ir_from_syntax` performs a direct recursive walk and
   rebuilds origins from the live `SyntaxNode` on every call.

3. **No additional memo layer is justified at the M1 heading/paragraph slice.**
   An initial benchmark (see below) shows the direct recursive MarkdownIR path
   is faster than a fresh `SyntaxNode -> Block` fold on both a realistic mixed
   document and a 50x scaled document. The lowering is cheap enough that adding
   a position-aware memo layer would add complexity without evidence of benefit.

4. **Targets share MarkdownIR by deriving from the same lazy lowering call.**
   The `Block`/`Inline` editor view, mdast export, preserve/local rewrite, and
   canonical formatter all consume the `MarkdownIR` value produced by a single
   `experimental_markdown_ir_from_syntax(root)` call. They do not each run a
   separate lowering pass, and they do not each hold a private memo.

5. **Diagnostics and source origins stay reference-shaped, not copied text.**
   MarkdownIR stores UTF-16 code-unit origins and validated semantic fields. It
   does not copy CST tokens, trivia, or source text. Consumers slice the
   original source via origins when exact preservation is required. This keeps
   the IR's memory footprint proportional to tree size, not document bytes.

## Benchmark

The benchmark lives in `examples/markdown/src/benchmark_test.mbt` under the
`markdown: * - lowering ...` names. It pre-parses a mixed Markdown document to a
`SyntaxNode`, then times:

- `SyntaxNode -> Block` via a fresh `@core.CstFold::new(markdown_fold_node)`.
- `SyntaxNode -> MarkdownIR -> Block` via
  `experimental_markdown_ir_from_syntax` followed by
  `experimental_markdown_ir_to_block`.

The document is `realistic_markdown_doc()` from the same file, which contains
headings, paragraphs, an unordered list, a fenced code block, and inline markup
(bold, italic, inline code, links). A 50x scaled variant is also measured to
check scaling behavior.

Measured on the wasm-gc backend (`moon bench --release`):

| Document | `SyntaxNode -> Block` | `SyntaxNode -> MarkdownIR -> Block` | Delta |
|---|---|---|---|
| Realistic (~55 lines) | 29.84 µs | 11.53 µs | IR faster |
| 50x scaled (~1000 lines) | 409.78 µs | 160.46 µs | IR faster |

The MarkdownIR path is faster for the M1 slice because it uses a light direct
recursive walk instead of `CstFold`'s structural-hash cache. At the time of the
#339 benchmark, lists and code blocks still lowered to cheap `Unsupported`
nodes while the direct fold did full work for those constructs; #324 broadened
that IR coverage afterward without changing the lazy/non-memoized policy. The
benchmark result shows that a fresh, non-memoized MarkdownIR lowering is not a
performance regression and therefore does not justify the complexity of a
position-aware memo layer at M1.

### 2026-08-02 reassessment

Issue [#838](https://github.com/dowdiness/loom/issues/838) repeated the lowering
measurements after MarkdownIR coverage expanded. The historical claim that the
MarkdownIR route is faster is now **stale**: on the same local release run,
`SyntaxNode -> MarkdownIR -> Block` took 189.66 µs versus 88.34 µs for direct
`SyntaxNode -> Block` on the realistic JavaScript corpus, and 9.72 ms versus
8.78 ms on its 50x form. The corresponding wasm-gc results were 135.86 µs
versus 63.82 µs and 6.18 ms versus 5.47 ms. Stage-isolation measurements also
put direct MarkdownIR construction above a cold AST fold.

The decision remains current: MarkdownIR is lazy, optional, and cannot use the
position-independent `CstFold` cache while it carries absolute origins. The new
evidence strengthens the case against eager construction in parser snapshots;
it does not by itself justify a new position-aware memo. Full commands and the
performance envelope are recorded in
[`docs/performance/benchmark_history.md`](../performance/benchmark_history.md).

The completed 10,000-line residual matrix further separates IR construction
from its Block adapter. On a code-heavy corpus, constructing MarkdownIR carries
the same superlinear fenced-code value extraction seen by direct Block lowering,
while adapting an already constructed IR remains milliseconds rather than
seconds. The owning seam is `code_block_value` rebuilding the whole document
string once per fenced block, not the absence of a MarkdownIR memo. The policy
therefore remains **current**, and that isolated implementation cost is tracked
separately in [#843](https://github.com/dowdiness/loom/issues/843).

The #843 implementation removes that isolated cost without changing this
policy. Fenced-code values are now assembled from local CST token text and do
not request an owning source snapshot. Direct Block and MarkdownIR lowering
pass their already-owned source explicitly for indented-code visual-column
handling. In the same-machine 10,000-line residual comparison, MarkdownIR
construction falls from 1.82 s to 37.05 ms on JavaScript and from 1.94 s to
34.45 ms on wasm-gc; the 2,000-to-10,000 scale ratio returns to the expected
linear band. Full base/head evidence and commands remain in
[`docs/performance/benchmark_history.md`](../performance/benchmark_history.md).

The compatibility `markdown_fold_node` path also remains source-linear for
indented code. It reuses the current owning string only when a source-backed
CST token's raw span matches its positioned span and the string covers the live
root; synthetic or token-local CSTs fall back to explicit reconstruction. This
keeps the optimization deterministic and cache-free while avoiding a new
public source-ownership API. A 500-block normal-test guard fixes zero fallback
reconstructions for parsed indented input, and 2k/10k JS and wasm-gc controls
track the compatibility path beside explicit-source lowering.

A correctness-first keyed-lowering prototype then tested the memoization driver
that the residual matrix did not cover. A top-level block result with relative
owned origins can be placed downstream to reproduce complete MarkdownIR exactly
for valid local/prepend edits, duplicate blocks, inline/reference links,
containers, lists, block quotes, fenced code, and HTML. On a 2,500-block local
edit, exact keyed observation was 2.85× faster on wasm-gc and 2.99× faster on
JavaScript than whole-document lowering.

The prototype also rejects the simplest document-global dependency model.
Making every cached block depend on one exact reference-definition snapshot is
correct, but a semantic-only definition edit made the keyed path 1.62× slower
than a coarse loop on wasm-gc and 1.83× slower on JavaScript because every entry
was invalidated. Current lowering also copies absolute definition origins into
each resolved reference node, coupling local syntax work to document placement.

Therefore this evidence does not authorize caching resolved MarkdownIR blocks.
The proposed production seam first preserves unresolved reference syntax in a
private position-independent block plan, then resolves through explicit
per-label dependencies and places origins from the live layout. Recovery
diagnostics and stale-key retirement remain correctness gates. The existing
lazy policy, direct one-shot path, and Block `CstFold` remain unchanged. See the
[design specification](../superpowers/specs/2026-08-02-markdown-local-unresolved-block-design.md)
and the throwaway evidence commit
[`4f743f7`](https://github.com/dowdiness/loom/commit/4f743f78ee3e61aec94f1b8c9b19ef9d7587cdca).

The production #332 attachment keeps that unresolved/resolved split private and
adds a keyed Block projection over resolved local IR. `Scope::collect()` from
Incr 0.15.0 now owns runtime GC and retirement of every scope-owned map after
the attachment reads its terminal Block watch. The 2,500-block edit-and-restore
measurement includes the authoritative IR-to-Block adapter and the defensive
copy returned to the consumer: 25.93 ms versus 91.23 ms for direct IR-to-Block
on JavaScript, and 20.92 ms versus 79.80 ms on wasm-gc. Full evidence and the
much faster remaining `Parser[Block]` compatibility control are recorded in
[`docs/performance/benchmark_history.md`](../performance/benchmark_history.md).

### Checked canonical formatter policy

Issue #777 adds a separate cost boundary for checked canonical formatting. Its
functional core explores the finite Cartesian grammar lazily in complete
primary-cost layers, sorting lexically and globally deduplicating each proven
layer before the imperative validation shell reparses candidates through
`parse_cst` and diagnostic-aware MarkdownIR lowering. This is an explicitly
requested formatter operation, not part of parser snapshots or MarkdownIR
lowering, so it does not change the lazy/non-memoized policy above.

The blocking regression signal is deterministic work, not wall time:

- every benchmark motif snapshots generated candidates, search expansions, and
  validation reparses in a normal white-box test;
- a deterministic 256-case source-free corpus is run twice and snapshots its
  replay transcript, digest, and maximum work;
- the calibrated defaults allow 256 candidates and 512 expansions per inline
  container, with document caps of 256 candidates and 512 expansions multiplied
  by the number of containers; and
- the calibration corpus observed per-container maxima of 49 deduplicated
  candidates and 20 expanded states, plus document maxima of 20 deduplicated
  candidates and 49 search states. The corresponding two-times margins are 98,
  40, 40, and 98 against defaults of 256, 512, 256, and 512 respectively.

Release benchmarks cover first-candidate success, late success, bounded
failure, flat adjacency, recursive nesting, marker/backslash-heavy text,
link/code opacity, and Unicode punctuation on wasm-gc and JavaScript. They are
informational for #777: the base revision cannot compile the new checked API,
so there is no equivalent base/head A/B workload or defensible A/A-derived
wall-clock threshold. The existing parser/lowering performance guard is not
reused for this distinct operation. A future wall-time gate requires a stable
cross-revision harness and successful A/A calibration first.

## Rationale

`CstFold` is the right memoization boundary for position-independent ASTs such
as the current `Block`/`Inline` editor model. It is the wrong boundary for
MarkdownIR because MarkdownIR nodes carry absolute source origins. Loom's
`docs/api/cst-traversal-idioms.md` explicitly warns that an algebra which bakes
absolute `node.start()` / `node.end()` into its result will return stale offsets
after position-shifting edits. The M1 IR therefore lowers fresh from the live
`SyntaxNode` on every demand.

Building MarkdownIR eagerly would force every parser snapshot to pay the
lowering cost even when no consumer asks for it; laziness keeps the parser
surface unchanged and respects consumers that only need CST or direct `Block`
output.

Memory overhead is bounded because MarkdownIR nodes are small: origins are
two-integer spans, and IR nodes carry validated semantic payloads rather than
token arrays. One-shot calls retain no cache. A live editor attachment retains
only scope-owned keyed local work and retires stale generations through
`Scope::collect()` at the editor's safe point.

## Production keyed implementation

The production implementation satisfies the following constraints:

- cache only position-independent block-local semantic data keyed by structural
  CST identity;
- preserve unresolved full, collapsed, and shortcut reference syntax so local
  lowering does not depend on document definitions;
- resolve references through explicit per-label definition dependencies;
- place block-relative origins from the current live layout;
- preserve recovery diagnostics exactly; and
- define stale-key retirement for long-lived editor sessions.

Keying by absolute source range is rejected because it discards the prepend/move
reuse proven by the relative-origin prototype. Incr 0.15.0's
`Scope::collect()` is the generic maintenance boundary; Markdown consumers do
not coordinate runtime GC or individual map sweeps.

## Consequences

- `experimental_markdown_ir_from_syntax` performs a direct recursive walk of
  `SyntaxNode` and rebuilds IR origins on every call. No `CstFold` is used.
- The fold algebra `experimental_markdown_ir_fold_node` stays package-private.
- One-shot/export consumers continue to use `experimental_markdown_ir_from_syntax`
  directly.
- Long-lived editor integrations use `attach_markdown_projection` over a
  `SyntaxParser`; the attachment owns keyed reuse, collection, and disposal.
  One-shot consumers continue to call direct lowering and create no attachment.
- The M1 exit criterion "eager/lazy and memoization policy is stated with an
  initial benchmark" is satisfied.
