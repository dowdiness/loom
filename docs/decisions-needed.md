# Decisions Needed

Items the triage agent flagged as `needs-human-review` — mixed signals or insufficient evidence to classify automatically. Each entry has a **Source**, **Context**, **Blocks**, and **Evidence** section. Add human notes under any item to preserve across future triage runs.

### Zero-copy lexing (issue #61)
**Source:** GitHub issue #61 — "Explore token text as source spans (zero-copy lexing)"
**Context:** Issue proposes representing token text as source spans instead of owned `String`s to avoid allocations during lexing. Recent StringView threading work (completed 2026-04-02) may have already addressed part of the motivation, but `CstToken` still owns its `text` field.
**Blocks:** Nothing directly — it's a performance exploration, not on any critical path.
**Evidence:** Open issue labeled `enhancement` + `performance`. `archive/completed-phases/2026-04-02-stringview-threading-design.md` already delivered StringView threading, which overlaps the motivation. Need a human read to decide whether `CstToken.text` remains worth rewriting after that work.
**Added:** 2026-04-18

### Surrogate codepoint fix (issue #46)
**Source:** GitHub issue #46 — "Parser crashes on strings with lone surrogate codepoints (0xD800–0xDFFF)"
**Context:** Issue is closed, but triage could not find a corresponding plan, archive entry, or commit that specifically handles lone UTF-16 surrogates. Possible that the fix happened under an unrelated commit message, or the issue was closed without a targeted fix.
**Blocks:** Nothing if already fixed. If not fixed, the parser still crashes on malformed input.
**Evidence:** Closed GitHub issue #46, severity error. No plan file or archive entry mentioning surrogates. Recent `fix/*` branches do not reference surrogates. Needs manual verification — either point to the commit that fixed it or reopen.
**Added:** 2026-04-18
