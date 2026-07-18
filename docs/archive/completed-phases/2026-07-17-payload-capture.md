# `#loom.payload` Capture Extraction Implementation Plan
**Status:** Complete

Completion evidence: #688 implementation and Markdown migration verified by `rtk moon test --target native loomgen` (212 passed), `rtk moon test --target native examples/markdown` (318 passed), `rtk moon fmt --check`, `rtk git diff --check`, and `rtk bash check-docs.sh`.

Decision record: [ADR: Regex Capture Payload Annotations](../../decisions/2026-07-17-payload-capture.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate payload-bearing tokens from regex capture references in `#loom.pattern` and `#loom.line_pattern`, with Markdown runtime equivalence and custom-lexer fallback.

**Architecture:** Store ordered payload expressions in private `VariantDecl` metadata. Lexically rewrite capture placeholders only outside MoonBit strings/comments, validate the rewritten expression with MoonBit parsing/checking, and share a private payload-construction emitter between character- and line-level lexers. Existing custom lexers remain the fallback for partial or complex payload construction.

**Tech Stack:** MoonBit, `loomgen`, generated MoonBit lexer fixtures, `rtk moon ide/check/test`.

## Global Constraints

- Preserve #529 fail-closed pattern allowlist policy.
- Preserve diagnostic precedence, diagnostic positions, cursor recovery, and nullability semantics.
- Preserve generated output and runtime behavior for patterns without payload annotations.
- Keep parser and IR private; add no public capture API.
- Do not add unrelated regex syntax.
- Permit arbitrary MoonBit expressions after lexical placeholder rewriting and MoonBit parse/check validation.
- Use `rtk` for every MoonBit command.

---

### Task 1: Add failing payload annotation and expression tests

**Files:**
- Modify: `loomgen/parse_annotations_wbtest.mbt`
- Modify: `loomgen/emit_lexer_wbtest.mbt`
- Create or modify: `loomgen/payload_expr_wbtest.mbt`

**Interfaces:**
- Consumes: existing `parse_annotations`, `emit_lexer`, and fixture helpers.
- Produces: failing executable contracts for metadata parsing, placeholder rewriting, diagnostics, and generated payload construction.

- [x] **Step 1: Write parser failure tests** for valid ordered payload metadata, nullary payload rejection, payload arity mismatch, partial payload metadata, and capture index overflow.
- [x] **Step 2: Write lexical-rewriter tests** proving `$1` inside a string literal and `$2` inside a comment remain unchanged, while `$1.length() - 1`, `String::new()`, and ordinary standard-library syntax are preserved.
- [x] **Step 3: Write emitter golden assertions** for one `#loom.pattern` token and one `#loom.line_pattern` token, including a two-field constructor.
- [x] **Step 4: Run focused tests and confirm they fail** using `rtk moon test --target native loomgen`; record the first expected missing-symbol or assertion failures.

---

### Task 2: Parse and validate private payload metadata

**Files:**
- Modify: `loomgen/parse_annotations.mbt`
- Modify: `loomgen/parse_annotations_wbtest.mbt`

**Interfaces:**
- Consumes: existing `VariantDecl`, annotation normalization, role classification, and pattern validation.
- Produces: `VariantDecl.payloads : Array[String]` or the repository-equivalent private field, populated in annotation order.

- [x] **Step 1: Extend `VariantDecl` with ordered payload expressions**, defaulting to an empty array in `extract_variants`.
- [x] **Step 2: Recognize `#loom.payload` as a modifier** requiring exactly one string literal argument; reject malformed arguments with the existing annotation diagnostic style.
- [x] **Step 3: Validate payload arity** against `arg_count`; reject nullary annotations and more annotations than constructor fields.
- [x] **Step 4: Preserve partial payload metadata** so emitter validation can select the documented custom-lexer fallback behavior.
- [x] **Step 5: Add capture-reference scanning** against the selected pattern. Specify the implementation: increment a private `capture_count` in `PatternParser::parse_group` for each plain capturing `Group`, or perform a post-parse traversal over `Pattern::Group`; use the chosen count consistently for `$N` validation. Leave the existing allowlist parser unchanged; reject references above the group count.
- [x] **Step 6: Run `rtk moon ide analyze ./loomgen --target native` and the focused annotation tests.**

---

### Task 3: Implement lexical placeholder rewriting and expression validation

**Files:**
- Create: `loomgen/payload_expr.mbt`
- Create or modify: `loomgen/payload_expr_wbtest.mbt`
- Modify: `loomgen/moon.pkg` only if the existing MoonBit parser/check dependency requires an explicit package update.

**Interfaces:**
- Consumes: a payload expression string, generated match variable name, and private capture metadata.
- Produces: a generated MoonBit expression string with placeholders replaced, or a generation error.

- [x] **Step 1: Implement a scanner state machine** for normal code, string literals, line comments, and block comments; only recognize `$N`, `$N_start()`, `$N_end()`, and `$0_match_length()` in normal code.
- [x] **Step 2: Emit capture text expressions** using the concrete generated match API selected from the repository's regex implementation: a participating group yields its captured `StringView`/text, and a nonparticipating group is wrapped with the API's `unwrap_or("")` equivalent.
- [x] **Step 3: Emit absolute source byte start/end expressions** from `StringView::start_offset()` and `length()`; add a nonzero lexer-position test proving offsets are absolute.
- [x] **Step 4: Preserve all non-placeholder text byte-for-byte**, including escaped strings, comments, and standard-library calls.
- [x] **Step 5: Validate the rewritten expression by wrapping it in a synthetic MoonBit function body (for example `fn __loom_validate_payload() { <rewritten_expr> }`) and passing that complete top-level source through the existing MoonBit parser/check path; return a generation error instead of emitting invalid source.
- [x] **Step 6: Run lexical-rewriter tests and `rtk moon ide analyze ./loomgen --target native`.**

---

### Task 4: Lower payload construction in both lexer emitters

**Files:**
- Modify: `loomgen/emit_lexer.mbt`
- Modify: `loomgen/emit_line_lexer.mbt`
- Modify: `loomgen/emit_lexer_wbtest.mbt`
- Modify: `loomgen/fixtures/pattern_lexer_fixture.mbt`
- Modify or create: `loomgen/fixtures/line_pattern_payload_fixture.mbt`
- Modify or create: corresponding generated `.g.mbt` fixtures.

**Interfaces:**
- Consumes: `VariantDecl.payloads`, the shared payload expression rewriter, existing match length/rest variables, and constructor names.
- Produces: inline constructor expressions only when every constructor field has a payload; otherwise existing custom-lexer generation.

- [x] **Step 1: Add a private shared helper** that returns either a fully rewritten constructor expression or a generation error.
- [x] **Step 2: Integrate the helper into character-level pattern emission** while preserving longest-match selection and `TokenInfo` length calculation.
- [x] **Step 3: Integrate the helper into line-level emission** while preserving declaration order, mode filtering, fallback behavior, and next-mode transitions.
- [x] **Step 4: Keep partial payload annotations on the custom-lex path** and retain the existing missing-custom-lex diagnostic when no fallback exists.
- [x] **Step 5: Regenerate/update golden fixtures** and assert generated code contains capture construction and does not call custom lex for fully annotated variants.
- [x] **Step 6: Run focused `loomgen` tests, `rtk moon check --target native loomgen`, and `rtk moon fmt --check` on touched MoonBit files.**

---

### Task 5: Migrate Markdown payload consumers and prove equivalence

**Files:**
- Modify: `examples/markdown/token.mbt` or the actual annotated token source identified during implementation.
- Modify: `examples/markdown/lexer.mbt` or its generated lexer source boundary.
- Modify: `examples/markdown/lexer_test.mbt`
- Modify: relevant generated Markdown fixture/output files.

**Interfaces:**
- Consumes: generated payload construction from Task 4.
- Produces: generated `HeadingMarker(Int)` and `CodeFenceOpen(Int, String)` payloads with unchanged values and token lengths.

- [x] **Step 1: Add failing generated-lexer/runtime tests** for heading levels 1 and 2, code fences with empty info, ordinary info, Unicode info, and token lengths.
- [x] **Step 2: Replace the mechanical heading extraction with `#loom.payload` annotations** while retaining custom logic only where the grammar needs it.
- [x] **Step 3: Replace the mechanical code-fence extraction with two payload annotations** for fence length and info text.
- [x] **Step 4: Remove only obsolete custom lexer code made redundant by the migration; preserve unrelated Markdown lexer behavior.**
- [x] **Step 5: Run `rtk moon test --target native examples/markdown` and compare all payload assertions with the pre-migration expected values.**

---

### Task 6: Verify invariants and finish documentation

**Files:**
- Modify: touched implementation/test/fixture files only.
- Verify: `docs/superpowers/specs/2026-07-17-payload-capture-design.md` and this plan.

- [x] **Step 1: Run `rtk moon ide analyze ./loomgen --target native`.**
- [x] **Step 2: Run `rtk moon check --target native loomgen`.**
- [x] **Step 3: Run `rtk moon test --target native loomgen`.**
- [x] **Step 4: Run `rtk moon test --target native examples/markdown`.**
- [x] **Step 5: Run `rtk bash check-docs.sh`.**
- [x] **Step 6: Run `rtk git diff --check` and inspect generated diffs for unchanged no-payload output.
- [x] **Step 7: Record the 2026-08-17 keep/delete decision rule in the final issue/plan state; create or update an ADR only if the implementation establishes a reusable public policy or changes a public contract.**

Keep/delete rule: retain this feature if, by 2026-08-17, at least one downstream grammar uses `#loom.payload` in production and its generated lexer tests exercise the resulting payload. Delete the feature if no production grammar adopts it by that date.
