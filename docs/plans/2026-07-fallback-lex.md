# Line-mode lexer fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `#loom.fallback_lex("fn")` so generated line-mode lexers delegate ordinary no-match input to a hand-written mode lexer while preserving `Invalid` when no fallback is declared.

**Architecture:** Extend `VariantDecl` with term-level fallback metadata. Parse and validate the modifier alongside existing lexer modifiers, including same-mode conflict detection. Collect fallback names during line-mode generation and emit a direct `(String, Int) -> (LexStep[Token], LexMode)` call in each mode's no-match path. Keep the current `Invalid` path when the mode has no fallback.

**Tech Stack:** MoonBit, `loomgen` annotation parser, source emitter, white-box tests, fixture regeneration.

## Global Constraints

- Preserve existing `#loom.line_pattern` behavior when no `#loom.fallback_lex` is declared.
- Reuse `is_valid_lex_fn_name` for fallback function references.
- Fallback functions use the existing mode-function signature `(String, Int) -> (LexStep[Token], LexMode)`.
- Reject malformed annotations before writing generated output.
- Add tests and documentation in the same patch.
- Run `moon fmt --check`, `moon check loomgen --target native`, `moon test loomgen --target native`, and `moon test --target native`.

---

### Task 1: Record fallback metadata in annotations

**Files:**
- Modify: `loomgen/parse_annotations.mbt:33-59, 615-674, 1425-1485`
- Test: `loomgen/emit_lexer_wbtest.mbt` near existing `line_pattern` validation tests

**Interfaces:**
- Produces `VariantDecl.fallback_lex : String?` for later emitter use.
- Keeps the existing `is_valid_lex_fn_name(String) -> Bool` contract.

- [ ] **Step 1: Write failing parser tests**

Add these tests before implementation:

```moonbit
///|
test "parse_annotations accepts fallback_lex on a line_mode term" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("x")
    #|  X
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum Term {
    #|  #loom.leaf
    #|  #loom.lexmode("LineStart")
    #|  #loom.line_mode
    #|  #loom.fallback_lex("lex_inline")
    #|  Node
    #|  #loom.root
    #|  Root
    #|  #loom.errornode
    #|  ErrorNode
    #|} derive(Eq)
  match parse_annotations(src) {
    Ok(a) =>
      match a.term_enum {
        Some(term) =>
          match term.variants[0].fallback_lex {
            Some(name) => inspect(name, content="lex_inline")
            None => abort("fallback_lex metadata missing")
          }
        None => abort("term enum missing")
      }
    Err(msg) => abort("unexpected parse error: " + msg)
  }
}

///|
test "parse_annotations rejects fallback_lex on token variants" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.line_pattern("x")
      #|  #loom.fallback_lex("lex_inline")
      #|  X
      #|  #loom.error
      #|  Error(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "only valid on #loom.term variants",
  )
}

///|
test "parse_annotations rejects fallback_lex without line_mode" {
  expect_parse_err(
    (
      #|#loom.term
      #|pub(all) enum Term {
      #|  #loom.leaf
      #|  #loom.lexmode("LineStart")
      #|  #loom.fallback_lex("lex_inline")
      #|  Node
      #|  #loom.root
      #|  Root
      #|  #loom.errornode
      #|  ErrorNode
      #|} derive(Eq)
    ),
    "without #loom.line_mode",
  )
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `moon test loomgen --target native -f "fallback_lex"`

Expected: FAIL because `VariantDecl` has no `fallback_lex` field and the modifier is unknown.

- [ ] **Step 3: Add the field and parser support**

Add after `line_mode : Bool`:

```moonbit
// #700. Names a hand-written fallback lexer for line-mode no-match input.
fallback_lex : String?
```

Initialize `fallback_lex` to `None` in `extract_variants`, parse `#loom.fallback_lex` with `first_string_from_apply`, and include it in the `VariantDecl` record.

Add a `"fallback_lex"` modifier case in `classify_role` requiring exactly one string argument. Reject token variants carrying it. On term variants require both `line_mode` and `lexmode_name`.

Reuse `is_valid_lex_fn_name` to reject invalid function references.

Add same-mode conflict validation: for every pair of term variants with the same non-`None` `lexmode_name`, reject when both fallback names are non-`None` and differ.

- [ ] **Step 4: Run focused parser tests**

Run: `moon test loomgen --target native -f "fallback_lex"`

Expected: PASS.

- [ ] **Step 5: Commit parser changes**

```bash
git add loomgen/parse_annotations.mbt loomgen/emit_lexer_wbtest.mbt
git commit -m "feat(loomgen): parse fallback_lex line-mode metadata"
```

### Task 2: Generate fallback delegation

**Files:**
- Modify: `loomgen/emit_line_lexer.mbt:32-129, 143-190`
- Test: `loomgen/emit_lexer_wbtest.mbt`
- Modify: `loomgen/fixtures/line_pattern_fixture.mbt`
- Regenerate: `loomgen/fixtures/line_pattern_fixture.g.mbt`
- Modify: `loomgen/regenerate_fixtures.mbt` only if fixture regeneration needs no further changes

**Interfaces:**
- `emit_mode_line_lexer` receives `fallback_lex : String?`.
- `emit_line_lexer` builds `Map[String, String]` of mode fallback names.
- No fallback emits the existing `Invalid` branch; fallback emits `return <fn>(source, pos)`.

- [ ] **Step 1: Add failing emitter tests**

Add assertions for the fixture output:

```moonbit
inspect(generated.contains("return lex_inline(source, pos)"), content="true")
inspect(generated.contains("Not a block-level token (line_pattern)"), content="false")
```

Add a separate no-fallback source and assert its generated output still contains `Not a block-level token (line_pattern)`.

- [ ] **Step 2: Run focused emitter tests and verify failure**

Run: `moon test loomgen --target native -f "line_mode"`

Expected: FAIL because the fixture has no fallback annotation and generated output still emits `Invalid`.

- [ ] **Step 3: Add fallback collection and emission**

While collecting `line_modes` in `emit_line_lexer`, collect fallback names into `Map[String, String]`. For each line-mode term variant:

```moonbit
match v.lexmode_name {
  Some(name) => {
    line_modes.add(name)
    match v.fallback_lex {
      Some(fn_name) => fallback_map.set(name, fn_name)
      None => ()
    }
  }
  None => ()
}
```

Pass `fallback_map.get(mode)` into `emit_mode_line_lexer`. Replace only the no-match emission with:

```moonbit
match fallback_lex {
  Some(fn_name) =>
    b.write_string("  return " + fn_name + "(source, pos)\n")
  None => {
    b.write_string("  let next = " + core_qual + ".next_char_offset(source, pos)\n")
    b.write_string(
      "  (" + core_qual +
      ".LexStep::Invalid(at=pos, width=next - pos, " +
      "message=\"Not a block-level token (line_pattern)\"), " +
      mode_name + ")\n",
    )
  }
}
```

- [ ] **Step 4: Add fallback annotation to the line-pattern fixture**

Add `#loom.fallback_lex("lex_inline")` to the `LineStart` line-mode term metadata in `loomgen/fixtures/line_pattern_fixture.mbt`.

- [ ] **Step 5: Regenerate the golden fixture**

Run: `moon run loomgen --target native -- --regenerate-fixtures`

Expected: `loomgen/fixtures/line_pattern_fixture.g.mbt` contains `return lex_inline(source, pos)` in `lex_line_start`.

- [ ] **Step 6: Run emitter tests**

Run: `moon test loomgen --target native -f "line_mode"`

Expected: PASS, including both fallback and no-fallback behavior.

- [ ] **Step 7: Commit emitter changes**

```bash
git add loomgen/emit_line_lexer.mbt loomgen/emit_lexer_wbtest.mbt loomgen/fixtures/line_pattern_fixture.mbt loomgen/fixtures/line_pattern_fixture.g.mbt
git commit -m "feat(loomgen): delegate line-mode fallthrough to fallback lexer"
```

### Task 3: Document the public annotation

**Files:**
- Modify: `loomgen/README.md` in the line-mode lexer section
- Modify: `docs/README.md` if the new public design/ADR links are not present

**Interfaces:**
- Documents syntax, validity constraints, function signature, and no-fallback compatibility behavior.

- [ ] **Step 1: Update loomgen README**

Add:

```markdown
`#loom.fallback_lex("fn")` on a `#loom.line_mode` term variant names the
mode-specific lexer used when no line pattern matches. The function has the
same shape as a generated mode function: `(String, Int) ->
(@core.LexStep[Token], LexMode)`. Without the annotation, the generated mode
retains its `Invalid` no-match fallback for backward compatibility.
```

- [ ] **Step 2: Verify docs wording against generated output**

Confirm the README example uses `return lex_inline(source, pos)` and does not claim that the fallback function receives a match length.

- [ ] **Step 3: Commit documentation**

```bash
git add loomgen/README.md docs/README.md
git commit -m "docs(loomgen): document fallback_lex annotation"
```

### Task 4: Verify the complete change

**Files:**
- No source changes expected; inspect all changed files and generated output.

- [ ] **Step 1: Format check**

Run: `moon fmt --check`

Expected: exit 0 with no diff.

- [ ] **Step 2: Package check**

Run: `moon check loomgen --target native`

Expected: exit 0.

- [ ] **Step 3: Loomgen tests**

Run: `moon test loomgen --target native`

Expected: all loomgen tests pass, including fallback positive, negative, conflict, and backward-compatibility tests.

- [ ] **Step 4: Full project tests**

Run: `moon test --target native`

Expected: all project tests pass.

- [ ] **Step 5: Regeneration determinism**

Run: `moon run loomgen --target native -- --regenerate-fixtures`, then `git diff --exit-code -- loomgen/fixtures/line_pattern_fixture.g.mbt`.

Expected: no generated fixture diff.
