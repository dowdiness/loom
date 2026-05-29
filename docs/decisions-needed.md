# Decisions Needed

Items the triage agent flagged as `needs-human-review` — mixed signals or insufficient evidence to classify automatically. Each entry has a **Source**, **Context**, **Blocks**, and **Evidence** section. Add human notes under any item to preserve across future triage runs.

## Zero-copy lexing (issue #61) — resolved
**Source:** GitHub issue #61 — "Explore token text as source spans (zero-copy lexing)"
**Context:** `CstToken` now stores `(source, start, end)` spans and exposes `text() -> StringView`. The generic parser builds non-interned span-backed CSTs and emits parser-owned reuse events that rebase unchanged token spans onto the current source buffer.
**Blocks:** Nothing.
**Evidence:** `seam/cst_node_wbtest.mbt`, `seam/event_wbtest.mbt`, and `seam/interner_wbtest.mbt` cover span preservation and interner source-lifetime behavior.
**Added:** 2026-04-18
**Resolved:** 2026-05-30

### Surrogate codepoint fix (issue #46) — resolved
**Source:** GitHub issue #46 — "Parser crashes on strings with lone surrogate codepoints (0xD800–0xDFFF)"
**Context:** Verified in the Unicode follow-up after canopy #251. `ParserContext::token_text_at` now returns a raw `StringView` slice, and recovery keeps invalid-token spans from ending inside a surrogate pair.
**Blocks:** Nothing.
**Evidence:** `loom/src/core/parser_wbtest.mbt` covers lone-surrogate token text and token spans that split a surrogate pair. `loom/src/core/lex_step_wbtest.mbt` covers non-BMP scalar preservation for no-progress, zero-width invalid, and width-one invalid recovery.
**Added:** 2026-04-18
**Resolved:** 2026-05-13
