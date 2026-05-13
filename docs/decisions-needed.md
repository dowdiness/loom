# Decisions Needed

Items the triage agent flagged as `needs-human-review` — mixed signals or insufficient evidence to classify automatically. Each entry has a **Source**, **Context**, **Blocks**, and **Evidence** section. Add human notes under any item to preserve across future triage runs.

### Zero-copy lexing (issue #61)
**Source:** GitHub issue #61 — "Explore token text as source spans (zero-copy lexing)"
**Context:** Issue proposes representing token text as source spans instead of owned `String`s to avoid allocations during lexing. Recent StringView threading work (completed 2026-04-02) may have already addressed part of the motivation, but `CstToken` still owns its `text` field.
**Blocks:** Nothing directly — it's a performance exploration, not on any critical path.
**Evidence:** Open issue labeled `enhancement` + `performance`. `archive/completed-phases/2026-04-02-stringview-threading-design.md` already delivered StringView threading, which overlaps the motivation. Need a human read to decide whether `CstToken.text` remains worth rewriting after that work.
**Added:** 2026-04-18

### Surrogate codepoint fix (issue #46) — resolved
**Source:** GitHub issue #46 — "Parser crashes on strings with lone surrogate codepoints (0xD800–0xDFFF)"
**Context:** Verified in the Unicode follow-up after canopy #251. `ParserContext::token_text_at` now returns a raw `StringView` slice, and recovery keeps invalid-token spans from ending inside a surrogate pair.
**Blocks:** Nothing.
**Evidence:** `loom/src/core/parser_wbtest.mbt` covers lone-surrogate token text and token spans that split a surrogate pair. `loom/src/core/lex_step_wbtest.mbt` covers non-BMP scalar preservation for no-progress, zero-width invalid, and width-one invalid recovery.
**Added:** 2026-04-18
**Resolved:** 2026-05-13
