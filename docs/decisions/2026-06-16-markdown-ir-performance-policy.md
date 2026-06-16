# ADR: MarkdownIR Performance, Memoization, and Eager/Lazy Policy

**Date:** 2026-06-16
**Status:** Accepted
**Issue:** [#339](https://github.com/dowdiness/loom/issues/339)
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

The MarkdownIR path is faster for the M1 slice for two reasons: it uses a
light direct recursive walk instead of `CstFold`'s structural-hash cache, and
it currently lowers lists and code blocks to cheap `Unsupported` nodes while
the direct fold does full work for those constructs. Even accounting for the
 apples-to-oranges comparison on unsupported constructs, the result shows that
a fresh, non-memoized MarkdownIR lowering is not a performance regression and
therefore does not justify the complexity of a position-aware memo layer at M1.

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
token arrays. There is no persistent IR cache, so memory is reclaimed with the
returned value once consumers finish with it.

## Future work

If MarkdownIR lowering later becomes a measurable bottleneck, a position-aware
memo layer can be introduced. Such a layer must either:

- key cache entries by absolute source range plus structural content, not by
  `CstNode.hash` alone; or
- re-derive origins from the live `SyntaxNode` on every cache hit, storing only
  position-independent semantic data in the cached value.

Either approach requires design work beyond the M1 slice and should be driven
by a new benchmark showing the need.

## Consequences

- `experimental_markdown_ir_from_syntax` performs a direct recursive walk of
  `SyntaxNode` and rebuilds IR origins on every call. No `CstFold` is used.
- The fold algebra `experimental_markdown_ir_fold_node` stays package-private.
- One-shot/export consumers continue to use `experimental_markdown_ir_from_syntax`
  directly.
- Editor integrations that need MarkdownIR should attach a `@incr.Derived` over
  `parser.syntax_tree()` and call `experimental_markdown_ir_from_syntax` inside
  the derived closure. The reactive graph handles memoization at the snapshot
  level, while origins are always derived from the current `SyntaxNode`.
- The M1 exit criterion "eager/lazy and memoization policy is stated with an
  initial benchmark" is satisfied.
