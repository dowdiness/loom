# Loomgen HTML Element Properties Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete #607 by generating tag classification and element-property predicates, then wiring HTML raw-text, void-element, parse-local native tag-stack, and registered HostGuard behavior without changing the structural `OpenTag(String)` payload.

**Architecture:** `#loom.tag` metadata is stored on classifier-enabled `#loom.term` variants and generates `classify_element(String) -> SyntaxKind?` alongside the existing `is_void_element` / `is_raw_text_element` helpers. HTML keeps the name-only `OpenTag(String)` payload; lexer and parser use the classifier, while complete opening-tag text and attributes remain available from token source spans. The HTML grammar uses a compile-once `make_html_parse_root()` adapter: each parse allocates a fresh tag stack and passes stack-capturing native/guard registries to `interpret_compiled`.

**Tech Stack:** MoonBit, loomgen annotation parser and source emitter, `@core.LanguageSpec`, `@grammar.GrammarIr`, `@grammar.compile`, `@grammar.interpret_compiled`, native MoonBit whitebox tests, generated `.g.mbt` fixtures.

## Global Constraints

- Preserve `OpenTag(String)` as a name-only payload; source fidelity for attributes and original spelling is tested through the token source span/text path.
- Reuse existing `SyntaxKind`; do not add a parallel `ElementKind` taxonomy.
- Existing untagged `#loom.void` / `#loom.rawtext` property-only fixtures remain valid.
- `#loom.tag` is scoped to classifier-enabled `#loom.term` enums.
- Canonical tag matching uses ASCII lowercase only; Unicode case folding is not used.
- Unknown/custom tags return `None` from `classify_element` and retain their original name.
- Duplicate canonical tag names are generation errors with both conflicting variants identified.
- `#loom.void` and `#loom.rawtext` cannot coexist on one variant.
- Grammar compilation happens once; mutable tag-stack state is allocated once per parse invocation.
- Compile-time missing guard names raise `MissingHostGuard`; a missing runtime guard-map entry follows the existing interpreter contract and returns `false`.
- No project-wide formatter, linter, or test suite is run inside individual tasks; run focused checks after each task and the complete relevant suites at the end.

## File Map

- Modify `loomgen/parse_annotations.mbt`: parse and validate `#loom.tag`, store canonical tag metadata, enforce classifier-scoped property rules and duplicate diagnostics.
- Modify `loomgen/emit_element_props.mbt`: preserve existing property-only output and emit the classifier from classifier-enabled term metadata.
- Modify `loomgen/main.mbt` / relevant emitter wiring: pass classifier metadata and write the generated classifier output in the existing generated syntax package.
- Modify `loomgen/*_wbtest.mbt`: annotation validation, case-fold duplicate rejection, classifier output, unknown fallback, and generated-source assertions.
- Modify `examples/html/meta/term_kind.mbt`: add tag-specific `SyntaxKind` variants with `#loom.tag`, `#loom.void`, and `#loom.rawtext` annotations.
- Modify generated HTML syntax/spec files through the existing loomgen regeneration workflow; do not hand-edit generated output.
- Modify `examples/html/lexer.mbt`: replace raw-text membership with generated classification while preserving source spans and `OpenTag(String)` payload.
- Modify `examples/html/cst_parser.mbt`: replace handwritten void/raw-text checks, use canonical names for matching, and connect native stack operations.
- Modify `examples/html/grammar.mbt`, `examples/html/html_spec.mbt`, or a focused HTML adapter file: add `make_html_parse_root()`, compile the IR once, and pass per-parse native/guard maps to `interpret_compiled`.
- Modify `examples/html/*_test.mbt`: direct acceptance tests and parse-between-invocations state-isolation tests.
- Modify `docs/superpowers/specs/2026-07-19-loomgen-html-element-properties-design.md` and `docs/decisions/2026-07-19-loomgen-html-element-properties.md` only if implementation reveals a contract correction; keep the proposed ADR status until acceptance is complete.

---

### Task 1: Lock annotation validation with failing tests

**Files:**
- Modify: `loomgen/attribute_ast_wbtest.mbt` or the existing annotation validation whitebox test file
- Modify: `loomgen/regression_wbtest.mbt` if the malformed enum fixtures belong there
- Reference: `loomgen/parse_annotations.mbt`

**Interfaces:**
- Consumes: current `parse_annotations(source)` test helper and `VariantDecl` diagnostics.
- Produces: failing tests that define the exact `#loom.tag` validation contract before implementation.

- [ ] **Step 1: Write failing tests**

Add focused tests for:

```moonbit
test "tag annotation stores canonical tag metadata" {
  let src = "#loom.term\npub(all) enum Term {\n#loom.tag(\"SCRIPT\")\n#loom.rawtext\n#loom.node\nScript\n}"
  let parsed = parse_annotations(src)
  // Assert the Script variant carries canonical tag name "script".
}

test "tag annotation rejects duplicate ASCII-case-folded names" {
  let src = "#loom.term\npub(all) enum Term {\n#loom.tag(\"Br\")\n#loom.node\nBr\n#loom.tag(\"br\")\n#loom.node\nBrLower\n}"
  expect_parse_error(src, "duplicate canonical tag name")
}

test "tag annotation rejects invalid and empty names" {
  expect_parse_error(tag_fixture(""), "tag name")
  expect_parse_error(tag_fixture("my tag"), "tag name")
}

test "classifier-enabled property variant requires tag annotation" {
  let src = classifier_enum_with_untagged_void_variant()
  expect_parse_error(src, "#loom.tag")
}

test "void and rawtext annotations remain mutually exclusive" {
  expect_parse_error(tagged_void_and_rawtext_fixture(), "both #loom.void and #loom.rawtext")
}
```

Use the repository's existing `inspect` / `expect_parse_err` style rather than inventing a new assertion helper unless the current test file already has no reusable helper.

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
rtk moon test --target native loomgen --filter 'tag annotation|canonical|rawtext'
```

Expected: failures because `#loom.tag` is not yet stored or validated.

- [ ] **Step 3: Commit the failing tests**

```bash
rtk proxy git add loomgen/attribute_ast_wbtest.mbt loomgen/regression_wbtest.mbt
rtk proxy git commit -m "test(loomgen): specify HTML tag annotation validation"
```

---

### Task 2: Implement tag metadata, canonicalization, and classifier emission

**Files:**
- Modify: `loomgen/parse_annotations.mbt`
- Modify: `loomgen/emit_element_props.mbt`
- Modify: `loomgen/main.mbt` and the exact generated-output wiring discovered before editing
- Test: tests committed in Task 1 plus focused emitter whitebox tests

**Interfaces:**
- Consumes: validated classifier-enabled `VariantDecl` metadata from Task 1.
- Produces: `classify_element(name : String) -> SyntaxKind?` in the generated syntax package; existing property-only fixtures remain unchanged.

- [ ] **Step 1: Implement only the minimum metadata and validation**

Add a variant field for the raw/canonical tag name following existing `is_void` / `is_rawtext` metadata patterns. Normalize ASCII A–Z to a–z. Validate empty names, allowed ASCII tag-name characters, duplicate canonical names, and classifier-scoped property rules. Do not change untagged property-only fixture behavior.

- [ ] **Step 2: Extend the emitter with classifier output**

Generate a deterministic match function using the existing `SyntaxKind` variants:

```moonbit
pub fn classify_element(name : String) -> SyntaxKind? {
  match ascii_lower(name) {
    "br" => Some(Br)
    "script" => Some(Script)
    _ => None
  }
}
```

Use the repository's available lowercase helper or emit a local ASCII normalizer; do not use Unicode case folding. Keep `is_void_element` and `is_raw_text_element` generation intact for untagged fixtures.

- [ ] **Step 3: Run focused loomgen tests**

Run:

```bash
rtk moon fmt loomgen
rtk moon check --target native loomgen
rtk moon test --target native loomgen --filter 'tag annotation|canonical|element property|classifier'
```

Expected: Task 1 tests pass; generated classifier output tests pass; existing void fixture tests remain green.

- [ ] **Step 4: Commit the generator change**

```bash
rtk proxy git add loomgen/parse_annotations.mbt loomgen/emit_element_props.mbt loomgen/main.mbt loomgen/*_wbtest.mbt
rtk proxy git commit -m "feat(loomgen): generate canonical HTML element classifier"
```

---

### Task 3: Add classifier fallback and source-fidelity tests before HTML migration

**Files:**
- Modify: `loomgen/*_wbtest.mbt`
- Modify: `examples/html/lexer_test.mbt`
- Modify: `examples/html/parser_test.mbt`

**Interfaces:**
- Consumes: generated `classify_element(String) -> SyntaxKind?` from Task 2.
- Produces: observable contracts for unknown/custom fallback, ASCII case-folding, and attribute source spans.

- [ ] **Step 1: Write failing consumer tests**

Add tests for:

```moonbit
test "classifier returns None for custom tag" {
  inspect(@syntax.classify_element("my-widget"), content="None")
}

test "HTML preserves attribute source through token span" {
  let tokens = lex("<div class=\"foo\">").tokens()
  // Assert OpenTag payload is "div" and the token's source text is "<div class=\"foo\">".
}

test "known tags classify case-insensitively" {
  inspect(@syntax.classify_element("BR"), content="Some(Br)")
  inspect(@syntax.classify_element("ScRiPt"), content="Some(Script)")
}
```

- [ ] **Step 2: Run tests and verify the expected failure**

Run:

```bash
rtk moon test --target native examples/html/lexer_test.mbt examples/html/parser_test.mbt
```

Expected: generated classifier APIs and/or source-span assertion are not yet available in the generated HTML artifacts.

- [ ] **Step 3: Regenerate HTML artifacts and implement the minimum classifier consumer**

Use the documented loomgen commands in `examples/html/README.mbt.md`. Regenerate syntax and spec outputs; do not hand-edit `.g.mbt` files. Keep `OpenTag(String)` name-only and obtain complete opening-tag text through the token span API.

- [ ] **Step 4: Run the focused consumer tests**

Expected: custom tags return `None`, mixed-case known tags classify correctly, and attributes are recovered from source span/text while payload remains the tag name.

- [ ] **Step 5: Commit the classifier consumer tests and generated artifacts**

```bash
rtk proxy git add examples/html loomgen/*_wbtest.mbt
rtk proxy git commit -m "test(html): lock classifier fallback and source fidelity"
```

---

### Task 4: Migrate lexer and parser membership behavior

**Files:**
- Modify: `examples/html/lexer.mbt`
- Modify: `examples/html/cst_parser.mbt`
- Test: `examples/html/lexer_test.mbt`, `examples/html/parser_test.mbt`

**Interfaces:**
- Consumes: generated classifier and predicates from Task 3.
- Produces: one canonical classification path for raw-text mode, void behavior, and open/close matching.

- [ ] **Step 1: Add failing behavior tests**

Add tests for:

```moonbit
test "mixed-case script uses raw-text mode" { /* <SCRIPT>x < y</script> */ }
test "mixed-case void tag does not create children" { /* <BR> */ }
test "custom tag remains generic" { /* <my-widget>x</my-widget> */ }
test "close matching uses canonical names but diagnostics preserve spelling" { /* <DIV>x</div> */ }
```

- [ ] **Step 2: Run the focused tests and verify failures**

```bash
rtk moon test --target native examples/html/lexer_test.mbt examples/html/parser_test.mbt
```

Expected: tests expose the current duplicated membership functions and raw string close matching.

- [ ] **Step 3: Replace handwritten membership checks**

For each `OpenTag(name)`, call `classify_element(name)` once, then apply generated predicates only for `Some(kind)`. Preserve `None` as generic behavior. Canonicalize names for matching and raw-text mode; retain source spelling for diagnostics. Remove `is_void_tag` and `is_raw_text_tag` after all callers migrate.

- [ ] **Step 4: Run focused HTML tests**

```bash
rtk moon fmt examples/html
rtk moon check --target native examples/html
rtk moon test --target native examples/html/lexer_test.mbt examples/html/parser_test.mbt
```

Expected: all existing and new HTML tests pass.

- [ ] **Step 5: Commit the migration**

```bash
rtk proxy git add examples/html
rtk proxy git commit -m "feat(html): use generated element classification"
```

---

### Task 5: Add compile-once, parse-local native and HostGuard adapter

**Files:**
- Modify: `examples/html/grammar.mbt`
- Modify: `examples/html/html_spec.mbt` or create the focused HTML adapter file if that is the existing package convention
- Modify: `examples/html/parser_test.mbt`
- Test: focused `loom/grammar` compile/interpreter tests only if an uncovered API contract is discovered

**Interfaces:**
- Consumes: HTML IR, native rule names, guard names, classifier behavior, and migrated parser from Task 4.
- Produces: `make_html_parse_root()` that compiles once and invokes `interpret_compiled` with fresh per-parse registries.

- [ ] **Step 1: Write failing lifecycle tests**

Add tests for:

```moonbit
test "registered HostGuard validates matching tag stack" { /* <div>x</div> */ }
test "HostGuard reports mismatched close tag" { /* <div>x</span> */ }
test "unclosed stack is diagnosed at end of parse" { /* <div>x */ }
test "void tags do not enter the stack" { /* <br> */ }
test "tag stack does not leak between parse invocations" {
  // Parse an unclosed document, then parse a valid independent document with the same grammar.
  // The second parse must have no diagnostic caused by the first stack.
}
test "compile rejects an unregistered HostGuard name" { /* MissingHostGuard */ }
```

- [ ] **Step 2: Run tests and verify failure**

```bash
rtk moon test --target native examples/html/parser_test.mbt
```

Expected: lifecycle tests fail because the current HTML entry point has no compiled IR adapter or registered HostGuard stack.

- [ ] **Step 3: Implement the compile-once adapter**

Implement the exact design contract:

```moonbit
fn make_html_parse_root() -> (@core.ParserContext[Token, SyntaxKind]) -> Unit raise @grammar.GrammarCompileError {
  let compiled = @grammar.compile(html_ir, native_names=..., guard_names=...)
  fn(ctx) {
    let stack = fresh_tag_stack()
    let natives = html_native_registry(stack)
    let guards = html_guard_registry(stack)
    @grammar.interpret_compiled(compiled, natives~, guards~)(ctx)
  }
}
```

Wire that parse-root closure into the generated `LanguageSpec` factory used by `@loom.Grammar::new`. Do not call `@grammar.interpret` per parse and do not store the stack in `LanguageSpec` or module-global mutable state.

- [ ] **Step 4: Run focused lifecycle tests**

```bash
rtk moon check --target native examples/html
rtk moon test --target native examples/html/parser_test.mbt
```

Expected: matching, mismatch, unclosed, void-stack, missing-guard, and cross-parse isolation tests pass.

- [ ] **Step 5: Commit the adapter**

```bash
rtk proxy git add examples/html
rtk proxy git commit -m "feat(html): add compile-once native guard adapter"
```

---

### Task 6: Full #607 acceptance verification and documentation closure

**Files:**
- Modify: `docs/decisions/2026-07-19-loomgen-html-element-properties.md` to change `Status: Proposed` to `Accepted` only after all evidence passes
- Modify: `docs/superpowers/specs/2026-07-19-loomgen-html-element-properties-design.md` only for verified implementation links/status
- Modify: `docs/README.md` only if links/status text change
- Test: `loomgen`, `examples/html`, generated artifact checks

**Interfaces:**
- Consumes: all previous task commits and generated outputs.
- Produces: evidence that every #607 acceptance row passes and the ADR can be accepted.

- [ ] **Step 1: Run focused generator verification**

```bash
rtk moon check --target native loomgen
rtk moon test --target native loomgen
```

Expected: zero errors and all loomgen tests pass, including tag validation, duplicate canonical names, classifier output, and property-only fixture compatibility.

- [ ] **Step 2: Run focused HTML verification**

```bash
rtk moon check --target native examples/html
rtk moon test --target native examples/html
```

Expected: zero errors and all HTML tests pass, including source-span fidelity, unknown fallback, mixed-case behavior, generated predicates, raw-text mode, tag-stack behavior, HostGuard registration, and parse isolation.

- [ ] **Step 3: Verify generated artifacts and stale helper removal**

```bash
rtk proxy grep -n 'is_void_tag\|is_raw_text_tag' examples/html
rtk proxy grep -n 'classify_element\|is_void_element\|is_raw_text_element' examples/html loomgen
rtk proxy git diff --check
```

Expected: no handwritten membership helper definitions remain; generated classifier and predicates are present; diff check is clean.

- [ ] **Step 4: Update ADR status and evidence**

Change the ADR to `**Status:** Accepted` and add the merged PR / acceptance evidence only after the implementation is complete. Do not mark the design or ADR accepted while any acceptance row remains unchecked.

- [ ] **Step 5: Commit documentation closure**

```bash
rtk proxy git add docs/README.md docs/decisions/2026-07-19-loomgen-html-element-properties.md docs/superpowers/specs/2026-07-19-loomgen-html-element-properties-design.md
rtk proxy git commit -m "docs: accept HTML element property design"
```

## Plan Self-Review

- Spec coverage: annotation storage/validation, classifier generation, SyntaxKind reuse, unknown fallback, ASCII case folding, source-span fidelity, raw-text lexer mode, parser membership, compile-once adapter, parse-local state, native push/pop, HostGuard compile/runtime semantics, stale helper removal, direct acceptance tests, and ADR closure are each assigned to a task.
- Failing tests precede implementation for annotation validation, duplicate case folding, unknown fallback, source fidelity, mixed-case behavior, native stack behavior, parse-between-invocation isolation, and registered HostGuard dispatch.
- No `Option A/B` integration ambiguity remains; Task 5 uses `make_html_parse_root` plus `interpret_compiled`.
- No placeholder task is used; each task names files, interfaces, commands, and expected outcomes.
- Generated files are regenerated through existing loomgen workflows and are not hand-authored.
