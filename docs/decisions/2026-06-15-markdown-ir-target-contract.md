# ADR: MarkdownIR Target Contract

**Date:** 2026-06-15
**Status:** Proposed
**Issue:** [#323](https://github.com/dowdiness/loom/issues/323)
**Related:** [#331](https://github.com/dowdiness/loom/issues/331), [#337](https://github.com/dowdiness/loom/issues/337), [#340](https://github.com/dowdiness/loom/issues/340), [#335](https://github.com/dowdiness/loom/issues/335), [#336](https://github.com/dowdiness/loom/issues/336)
**Implementation plan:** N/A — M0 architecture/target-contract note only.

## Context

Loom's Markdown example currently parses into a CST and folds that tree directly
into `Block` / `Inline`. Canopy consumes `@markdown.Block` through projection
memos, source maps, and editor edit operations. That model is editor-facing and
must remain first-class.

The MarkdownIR roadmap needs a separate semantic/transform layer before mdast
export, CommonMark HTML conformance, source-preserving rewrites, or canonical
formatting are implemented. mdast is an ecosystem export target, not the
basement representation, and MarkdownIR must not become a second lossless CST by
copying every token and trivia node.

## Decision

Use [MarkdownIR: Architecture and Target Contract](../architecture/markdown-ir.md)
as the M0 target contract for MarkdownIR work.

The target pipeline is:

```text
CST / SyntaxNode -> MarkdownIR -> target views and backends
```

where target views include the existing `Block` / `Inline` editor projection
model, mdast/unist JSON export, CommonMark HTML rendering, source-preserving
rewrite, and canonical formatting.

MarkdownIR owns semantic structure, origins, and selected transform-relevant
surface metadata. CST/SyntaxNode remains the source-fidelity truth. Exact source
preservation is performed by combining IR origins with the original source/CST,
not by cloning arbitrary CST tokens or trivia into IR nodes.

## Rationale

A dedicated MarkdownIR lets Loom share one typed semantic layer across editor,
export, conformance, rewrite, and formatting targets while keeping each target's
contract explicit. Keeping `Block` / `Inline` as an adapter target protects the
existing Canopy editor path. Keeping mdast as an adapter avoids importing
JavaScript ecosystem compromises into the core transform layer.

The anti-CST-cloning rule preserves the separation between source fidelity and
semantic transformation. It gives transforms enough information to preserve
important author choices while avoiding a duplicated token stream that would be
hard to validate, hard to migrate, and easy to confuse with parser truth.

## Consequences

M0 work should finish documentation, invariants, constructor policy, extension
scope, migration plan, and package-boundary review before implementing public IR
types.

M1 can then prove the architecture with a heading/paragraph vertical slice:
`SyntaxNode -> MarkdownIR -> Block/Inline`, mdast export, rewrite smoke tests,
and an initial performance/memoization policy.

Future CommonMark, mdast, rewrite, and incremental work should cite the target
contract when deciding whether a field belongs in MarkdownIR, remains in the
CST/source, or is target-adapter-only.
