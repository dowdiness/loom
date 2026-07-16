# Markdown Code Span Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Active

**Issue:** [#484](https://github.com/dowdiness/loom/issues/484)

**Design:** [Markdown Code Span and Authoring Contract Design](../specs/2026-07-14-markdown-code-span-authoring-contract-design.md), approved and revised at `4199140` to defer authoring-fact delivery until a concrete block-editor host owns snapshot identity.

**Goal:** Implement CommonMark code spans in the native Markdown parser with lossless CST/source behavior, correct semantic normalization, and linear delimiter matching.

**Architecture:** Baseline lexer indentation becomes a structural `Indentation` prefix followed by ordinary line tokens. The Markdown CST parser keeps per-line classification through a private `LinePrefix`; each semantic inline container uses a pure-lookahead prepass to map eligible backtick runs to their next equal-length successor. CST conversion and MarkdownIR lowering normalize successful span content while exposing a content origin only when raw content is contiguous.

**Tech Stack:** MoonBit; Loom parser context; native Markdown lexer/CST parser; MarkdownIR; CommonMark fixture oracle.

## Global Constraints

- This issue changes only `examples/markdown`; it adds no Grammar IR node, loomgen annotation, public Loom-core API, or `ParserContext` conditional-commit primitive.

**2026-07-15 accepted deviation:** Before Task 2, this branch added a reusable
core prerequisite: `BlockReparseSpec` now selects a candidate-local parser
from its old node, new source, and re-lexed tokens; mode-aware relex snapshots
are session-owned. This changes the public Loom-core contract and migrates
JSON and Lambda consumers. The prerequisite is documented by
[Widen Block Reparse Only After Explicit Decline](../../decisions/2026-07-15-block-reparse-ancestor-widening.md)
and remains in separate commits from Markdown's baseline-indentation migration,
preserving independent review and revert boundaries. Tasks 2–4 retain the
original Markdown-only scope.
- `ParserContext::lookahead` remains unconditional rollback. The delimiter prepass is pure: it restores position, node/event stacks, diagnostics, and lexical mode.
- Lexer output is one payload-free `BacktickToken` per maximal contiguous run; all run lengths and text derive from existing source-range access.
- Per semantic inline container, successor indexing is $O(T+R)$ time and $O(R)$ temporary storage for $T$ tokens and $R$ backtick runs. Never rescan to a boundary for each candidate.
- Only an outer-inline run preceded by an odd-length contiguous source-backslash suffix is ineligible to open. A same-length run closes inside a successful span regardless of its preceding backslashes; those backslashes remain raw content.
- A run without an equal-length successor is ordinary literal text. It emits no parser diagnostic, `ErrorNode`, recovered semantic node, `Inline::Error`, or authoring fact.
- Normalize only a successful raw interior: convert each line ending to one ASCII space; remove exactly one boundary ASCII space only if both boundaries are ASCII spaces and a non-space remains; preserve every other character, including Unicode whitespace and backslashes. Do not call generic escape stripping.
- Baseline indentation emits exact `IndentationToken` plus normal line-start tokens. A Markdown-private `LinePrefix` captures prefix span and width before block classification, then resets at every physical-line boundary.
- Root/list-relative indented-code lowerers collect every direct non-newline child text in source order and retain current join/deindent behavior. Delete the `IndentedCodeText` path after all callers migrate.
- `InlineCode.content_origin` is `Some` only for contiguous raw interior content. A structural continuation prefix yields `None`; content-only source rewrites reject that case instead of guessing a range.
- Deferred by design: no authoring facade, `UnmatchedBacktickRun` carrier, snapshot/revision abstraction, editor decoration, or completion behavior. A future host-integration issue owns that work.
- Tests are behavior-level and test-first. Every task ends with focused checks before its commit. Plan prose describes responsibilities and invariants, not paste-ready implementation.

---

### Task 1: Atomically migrate baseline indentation, classification, and lowering

**Files:**
- Modify: `examples/markdown/token.mbt`, `examples/markdown/syntax_kind.mbt`, `examples/markdown/lexer.mbt`, `examples/markdown/lex_mode.mbt`, `examples/markdown/cst_parser.mbt`, `examples/markdown/inline_parser.mbt`, `examples/markdown/indentation_policy.mbt`, `examples/markdown/inline_policy.mbt`, `examples/markdown/code_block_value.mbt`, `examples/markdown/markdown_ir_lowering.mbt`
- Regenerate: `examples/markdown/pkg.generated.mbti` from the migrated package in the same commit; do not hand-edit the generated interface.
- Modify tests: `examples/markdown/lexer_test.mbt`, `examples/markdown/parser_test.mbt`, `examples/markdown/source_fidelity_test.mbt`, `examples/markdown/markdown_ir_test.mbt`
- Inspect: `examples/markdown/mode_lexer.mbt`

**Interfaces:**
- Consumes: the existing opaque `IndentedCodeText` lexer path and its parser/lowering consumers.
- Produces: an exact `IndentationToken` plus ordinary line tokens for every nonblank physical line; a private `LinePrefix` captured before classification; and byte-equivalent root/list-relative indented-code values.

- [x] Add red lexer streams whose first post-prefix token is a backtick, heading marker, block-quote marker, list marker, or fence candidate at root and list-relative indentation. Add parser, fidelity, and MarkdownIR cases for marker offsets, setext, block-quote continuation, nested lists, paragraph/list continuation, and multi-line indented code whose first content is backtick/heading/list/fence/quote-like text.
- [x] Run the focused cases and confirm they fail only because the current opaque indented-line representation cannot preserve the required token stream or direct-child fidelity.
- [x] In one migration, replace `IndentedCodeText` in token/syntax-kind declarations with `Indentation`; make line-start lexing emit the exact prefix and resume the ordinary classifier for the remainder using existing tab-column arithmetic; and repair every former Markdown-package consumer in the listed files before removing the legacy variant.
- [x] Introduce the smallest Markdown-private `LinePrefix { text, columns }` plus a `parse_prefixed_block` boundary in `cst_parser.mbt`. It inspects—but does not consume—the prefix and following token, selects the same block class that an unindented line would select, then passes the prefix explicitly into that class’s parser. Each selected parser opens its own node before emitting the prefix, so the `IndentationToken` is a direct structural child of the heading, paragraph, block quote, list item, or code block it qualifies; no parser-global prefix state survives a physical-line boundary.
- [x] Thread `LinePrefix` through root and list-item continuation classification: prefix columns, not marker-token text, decide marker/body offsets, setext eligibility, block-quote continuation, nested-container minimum indentation, and indented-code thresholds. Replace opaque-line code-block collection with a line-sequence helper that emits the prefix then every normal direct non-newline child in source order; update both lowerers to retain current `line_parts` join/deindent behavior and remove every `IndentedCodeTextToken` branch.
- [x] Assert CST parent/span ownership: the prefix remains a direct structural child, ordinary inline children remain source-adjacent, and non-code paragraph/heading/list/quote/fence classification still wins when indentation does not classify as indented code.
- [x] Run focused lexer, parser, source-fidelity, code-block, and MarkdownIR filters, then `moon check` and `moon info` for `examples/markdown`. Expected: all new and established cases pass with lossless prefix spans, normal remainder token kinds, unchanged established code-block values, and a regenerated interface with no `IndentedCodeText` variant.
- [x] Commit: `refactor(markdown): decompose baseline indentation` (`e999d19`).

### Task 2: Lex, index, and parse code spans with literal fallback

**Files:**
- Modify: `examples/markdown/lexer.mbt`, `examples/markdown/cst_parser.mbt`, `examples/markdown/inline_parser.mbt`, `examples/markdown/inline_convert.mbt`, `examples/markdown/markdown_ir.mbt`, `examples/markdown/markdown_ir_lowering.mbt`
- Modify tests: `examples/markdown/lexer_test.mbt`, `examples/markdown/inline_test.mbt`, `examples/markdown/parser_test.mbt`, `examples/markdown/error_recovery_test.mbt`, `examples/markdown/markdown_ir_test.mbt`
- Create whitebox benchmark: `examples/markdown/delimiter_index_wbtest.mbt`

**Interfaces:**
- Consumes: payload-free `BacktickToken` source spans, `ParserContext` source access and unconditional `lookahead`, and existing block-specific soft-line continuation predicates.
- Produces: a private semantic-inline-container driver that owns both delimiter pre-indexing and emission, a private equal-length successor map, `InlineCodeNode` direct delimiters/raw children, and exact literal source text for every unconsumed run in both CST conversion and MarkdownIR.

- [x] Add red lexer, CST, recovery, Inline, and MarkdownIR tests for maximal runs, unequal interior runs, unmatched literal fallback with the full run spelling preserved, odd-parity escaped outer runs followed by later valid pairs, even-parity eligible outer runs, an escaped literal `\`` pair whose semantic value is one backtick, backslashes before matching closers, and following emphasis/link syntax.
- [x] Run those focused cases and confirm failures name missing maximal-run tokenization, matching, literal fallback, or recovery behavior rather than harness setup.
- [x] Make the lexer emit exactly one `BacktickToken` for every maximal contiguous run without semantic payload. Its source slice remains the authority for run length and text.
- [x] Introduce one private container driver in `cst_parser.mbt`, parameterized by the existing block-specific soft-line continuation decision. Before emission it runs one pure `lookahead` across the entire paragraph, heading, list-item paragraph, or block-quote paragraph; it derives outer-opener eligibility from contiguous trailing source-backslash parity and builds equal-length successors in one traversal.
- [x] Pass the same private map through inline emission for that whole semantic container. Only eligible indexed runs open `InlineCodeNode`; consume their indexed equal-length closer; preserve every intervening token as raw direct content; and emit every unconsumed run as literal source text without synthetic delimiters, errors, or recovery nodes.
- [x] Update direct literal-token lowering in both `Inline` conversion and MarkdownIR lowering: an unconsumed `BacktickToken` contributes `token.text()` rather than a fixed one-character delimiter spelling, and a preceding text segment plus that literal run are normalized as one contiguous escape-processing segment. Keep the generic delimiter helper for fixed-spelling tokens; successful `InlineCodeNode` normalization remains Task 3.
- [x] Add a Markdown-level post-prepass regression proving successful parsing has no diagnostic, `ErrorNode`, or `Recovered` MarkdownIR node and preserves following inline parsing. Cite the existing core whitebox lookahead tests as proof of internal state restoration; this task changes no Loom-core file.
- [x] Add `delimiter_index_wbtest.mbt` benchmarks that access the private successor-index helper, construct distinct unmatched runs of lengths 1 through R, and prebuild token/context inputs before timing only that traversal for R = 512, 1024, and 2048. Record median nanoseconds per run from `moon bench --release`; reject the implementation if the 2048-run rate exceeds the 512-run rate by 2.5×. This isolates repeated run scans from lexer work proportional to source bytes and becomes Task 4’s adversarial-delimiter evidence.
- [x] Run focused lexer, inline, parser, recovery, and stress filters. Expected: no observable prepass leakage, no cross-container closer, linear delimiter work, and all new cases pass.
- [ ] Commit: `feat(markdown): parse indexed code spans`

### Task 3: Lower normalized code-span semantics and origin boundaries

**Files:**
- Modify: `examples/markdown/markdown_ir_lowering.mbt`, `examples/markdown/inline_convert.mbt`, `examples/markdown/markdown_ir_rewrite.mbt`
- Modify tests: `examples/markdown/markdown_ir_test.mbt`, `examples/markdown/source_fidelity_test.mbt`, `examples/markdown/commonmark_html_fixture_test.mbt`
- Modify if fixture additions are necessary: `examples/markdown/commonmark_html_fixture_data_test.mbt`

**Interfaces:**
- Consumes: successful `InlineCodeNode` direct delimiters/interior children, structural continuation prefixes, and current `MarkdownIR::InlineCode(value, content_origin)` with its enclosing node origin.
- Produces: normalized rendered code values, full delimiter-inclusive node origins, contiguous-only content origins, and content-only rewrites that refuse discontinuous raw content.

- [ ] Add red MarkdownIR, source-fidelity, rewrite, and selected CommonMark 0.31.2 fixture tests for newline replacement, boundary-space removal, all-space preservation, Unicode/interior whitespace, literal backslashes, unequal interior runs, contiguous content, and structural-prefix crossings. Encode fixture IDs in test names.
- [ ] Run focused cases and confirm they fail only in code-span normalization, raw-origin selection, rewrite refusal, or HTML output.
- [x] Concatenate only direct raw-content children between the first and last direct delimiter. Skip structural continuation prefixes by role, normalize once with the approved three rules, preserve all other characters, and never call generic escape stripping.
- [x] Retain the full node origin including delimiters. Assign `Some` content origin only to one contiguous raw interior; assign `None` to structural-prefix crossings. Make content-only rewrite reject `None` rather than infer an envelope-relative range, while preserving valid full-node rewrites.
- [x] Run MarkdownIR, source-fidelity, rewrite, mdast, and selected CommonMark HTML checks. Expected: semantic HTML matches the oracle, no rewrite invents a raw range, and all new cases pass.
  - Deviation (2026-07-15): normalization/origin regressions were added after implementation and passed on first execution; `moon test examples/markdown/markdown_ir_test.mbt` later passed 110/110, and official fixtures #329, #331, #334, and #335 passed in `commonmark_html_fixture_test.mbt` (23/23). The red-baseline acceptance criteria remain intentionally unchecked.
- [ ] Commit: `feat(markdown): lower normalized code spans`

### Task 4: Complete verification and document closure

**Files:**
- Modify: `docs/README.md`, this plan, and `docs/decisions/2026-07-06-markdown-inline-native-only.md` only after implementation evidence shows the proposed amendment is accurate
- Modify test/fixture files only for verified gaps found by this task

**Interfaces:**
- Consumes: completed parser behavior and focused-test evidence from Tasks 1–3.

- [x] Run the full Markdown package suite, incremental/parser/source-fidelity tests, MarkdownIR property tests, mdast parity, CommonMark HTML fixtures, and the 512/1024/2048 adversarial delimiter benchmark/check established in Task 2.
- [ ] Run workspace `moon check` and diagnostics for each changed Markdown file using `moon ide`; repair only actual exhaustive-match/interface fallout from Tasks 1–3.
- [ ] Update the native-only ADR only if the final code confirms the exact scoped claim: Markdown code-span parsing remains native and does not justify Grammar IR or conditional-commit API expansion.
- [ ] Update `docs/README.md` for plan/ADR status. Mark this plan executed only after every checkbox has concrete verification evidence; archive it only under `docs/development/agent-docs-protocol.md`.
- [ ] Record `No ADR needed:` only if no accepted architectural boundary changes; otherwise create/update the ADR and index it. The deferred authoring-fact integration requires neither an API nor ADR in this issue.
- [ ] Commit documentation separately: `docs: close markdown code span plan`.

## Pre-execution review checklist

- [x] Global constraints map to Tasks 1–3: maximal runs; unconditional lookahead; linear map; escape parity; literal fallback; normalization; continuation boundaries; indentation; origins; no authoring API.
- [x] Focused tests cover behavior, recovery non-events, source fidelity, and a stress case; they do not assert implementation text.
- [x] Task interfaces use existing Markdown types and introduce no public Loom-core interface.
- [x] The current checkout reconciles all named paths and no implementation begins without a fresh independent algorithm/plan review by a model different from the executor.
