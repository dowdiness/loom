# ADR: High-level Markdown Block parsing uses the source-bound semantic projection

**Date:** 2026-08-11
**Status:** Accepted
**Supersedes:** [Markdown Block projection cutover](2026-08-10-markdown-block-adapter-cutover.md)
**Related:** [Markdown semantic read](2026-08-10-markdown-semantic-read.md)
**Implementation plan:** Issue-scoped follow-up to [Issue #913](https://github.com/dowdiness/loom/issues/913) after the source-bound semantic-read parity gate.

## Context

The direct CST-to-`Block` fold and the source-aware MarkdownIR-backed projection now pass the required parity matrix, including block quotes, thematic breaks, soft breaks, nested lists, ordered markers, fenced-code indentation, malformed links, recovery, source endings, and diagnostics. Leaving both paths as high-level semantic owners would let future fixes drift across the seam.

## Decision

`parse_markdown` is the high-level projection seam: it constructs a `MarkdownDocument`, snapshots its diagnostics, creates one detached `MarkdownSemanticRead`, and returns `markdown_semantic_read_to_block(read)` with those diagnostics. `parse` delegates to the same path and retains its existing tolerant lex-error behavior. The source-bound IR-backed projection is authoritative for future high-level Block semantics; a divergence from the retained direct fold is an intentional semantic change, not a reason to restore a second high-level owner.

The source-aware adapter remains the chosen target because `Block` requires concrete source facts for code values, link spelling, list prefixes, and break handling. The IR-only `experimental_markdown_ir_to_block(read.ir())` path remains a separate compatibility surface. `parse_cst`, `markdown_grammar`, `markdown_fold_node`, and the `Parser[Block]` editor path remain available and unchanged for low-level compatibility. Canopy and Loomark consumers are outside this cutover.

## Rationale

The document-backed projection keeps the source and semantic tree paired while
allowing `Block` to retain concrete facts that MarkdownIR alone does not own.
Making it the sole high-level owner prevents future fixes from diverging
between the direct CST fold and the source-aware adapter. Retaining the direct
fold, `parse_cst`, and editor attachment surfaces preserves existing low-level
and long-lived consumer contracts while this semantic owner becomes
authoritative.

## Consequences

- High-level parsing now pays for MarkdownIR lowering and source-aware adaptation; the established full-parse benchmarks must continue to track that cost.
- Existing parity cases retain their observed `Block` values today, while future semantic fixes have one high-level owner.
- The direct source-aware fold remains only as a parity/benchmark oracle and no longer owns production high-level parsing.
- Diagnostics, `parse_markdown`'s return shape, and `parse`'s lex-error behavior remain unchanged.
