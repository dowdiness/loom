# Migrate lambda printers onto the `interpret` fold — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two hand-recursing printers in `examples/lambda/ast/pretty_traits.mbt` with pure catamorphisms driven by `interpret`, deleting the duplicated recursion.

**Architecture:** Both printers become `TermSym` instances folded by `interpret`. Precedence stays compositional (each node reports its own `prec`; the parent wraps via a `wrap_*` helper). The only top-down flag (Module top-level vs nested) is eliminated by making `mod` **always-brace** — round-trip-safe because `{ … }` parses to the same `Module` and `consume_delimiters` accepts newline-separated defs inside braces.

**Tech Stack:** MoonBit; `dowdiness/lambda` (root package) + `dowdiness/lambda/ast` package; `@pretty` layout combinators; `@qc` property tests.

## Global Constraints

- Run all `moon` commands from `examples/lambda/` (the module root).
- `moon check` after every file edit; `moon check --deny-warn` before each commit (CI promotes warnings to errors; this is how dead helpers are detected).
- One file per `edit` call; re-read between edits for a fresh hash.
- `moon info && moon fmt` before the final commit; inspect `git diff *.mbti`.
- Accepted output changes (all verified round-trip-safe): curried lambdas print uncollapsed `(a) => (b) => …`; `let`-bound lambdas print `let f = (x) => …` (no `fn` sugar); every `Module` is braced `{ … }`; `to_source` uses minimal parens.
- Do NOT stage the `egraph` submodule (unrelated dirty pointer).
- Branch: `migrate-consumers-onto-interpret` (already checked out; do not create a new branch).

---

## File Structure

- `ast/pretty_traits.mbt` — **rewritten**: add `SourceText` struct + `TermSym` impl; edit `PrettyLayout::mod` to brace; rewire `term_to_source` and `to_layout` to `interpret`; delete both hand-recursion clusters and the helpers they exclusively used.
- `ast/sym.mbt` — delete `Pretty` struct + its `TermSym` impls (Task 3).
- `ast/sym_test.mbt` — repoint 4 `Pretty` cases to `SourceText` (Task 3).
- `issue305_syntax_test.mbt`, `parse_tree_test.mbt`, `parser_test.mbt` (root package) — update churned literal snapshots (Task 1).
- `pretty_roundtrip_test.mbt` (root package) — add nested-Module positive control (Task 2).

The `print_term(incr) == print_term(full)` comparisons in `phase4_correctness_test.mbt` and `block_reparse_test.mbt` compare two prints from the *same* printer, so they stay equal — **no change needed**.

---

## Task 1: Migrate the string printer to `SourceText`

**Files:**
- Modify: `examples/lambda/ast/pretty_traits.mbt` (add `SourceText`; rewire `term_to_source`; delete the string hand-recursion cluster)
- Modify: `examples/lambda/issue305_syntax_test.mbt`
- Modify: `examples/lambda/parse_tree_test.mbt`
- Modify: `examples/lambda/parser_test.mbt`

**Interfaces:**
- Consumes: existing `interpret[T : TermSym](Term) -> T`, the `prec_*` constants, and the `Bop` enum (`Plus`/`Minus`) — all already in scope.
- Produces: `pub(all) struct SourceText { repr : String; prec : Int }` with a full `TermSym for SourceText` impl; `term_to_source(term) -> String` redefined to `(interpret(term) : SourceText).repr`. `print_term` and `@pretty.Source::to_source` are unchanged (they already delegate to `term_to_source`).

- [ ] **Step 1: Update the churned string snapshots to their predicted new values**

In `issue305_syntax_test.mbt`:
- line 16: `content="(x, y) => (x y)"` → `content="(x) => (y) => x y"`
- line 35: `content="let answer = 42\nanswer"` → `content="{ let answer = 42\nanswer }"`

In `parse_tree_test.mbt`:
- line 37: `content="(1 + 2)"` → `content="1 + 2"`
- line 52: `content="(f x)"` → `content="f x"`
- line 92: `content="(f, x) => (f x)"` → `content="(f) => (x) => f x"`

In `parser_test.mbt` line 533, replace the assertion:
```moonbit
  inspect(printed.contains("fn f(x)"), content="true")
```
with:
```moonbit
  inspect(printed.contains("let f = (x) =>"), content="true")
```

(Leave `issue305_syntax_test.mbt:4,10`, `parse_tree_test.mbt:8,18,28`, and `error_recovery_test.mbt` untouched — those outputs do not change.)

- [ ] **Step 2: Run the affected tests and confirm they now FAIL**

Run: `moon test`
Expected: FAIL — the updated snapshots mismatch because `term_to_source` still emits the old sugared output (e.g. `parse_tree_test` reports actual `(1 + 2)` vs expected `1 + 2`).

- [ ] **Step 3: Add `SourceText` and rewire `term_to_source`; delete the string hand-recursion cluster**

In `ast/pretty_traits.mbt`, add the `SourceText` interpretation (place it just below the `prec_*` constants, before `PrettyLayout`):

```moonbit
///|
/// SourceText: compact, minimal-parenthesized source-text interpretation.
/// Named `SourceText` (not `Source`) to avoid colliding with the `@pretty.Source`
/// trait that `Term` implements. Mirrors `PrettyLayout`'s precedence discipline:
/// each node reports its own `prec`; the parent wraps a child via `wrap_source`.
pub(all) struct SourceText {
  repr : String
  prec : Int
}

///|
fn wrap_source(child : SourceText, ctx_prec : Int) -> String {
  if child.prec < ctx_prec {
    "(" + child.repr + ")"
  } else {
    child.repr
  }
}

///|
pub impl TermSym for SourceText with fn int_lit(n) {
  { repr: n.to_string(), prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn variable(x) {
  { repr: x, prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn lam(x, body) {
  { repr: "(" + x + ") => " + body.repr, prec: prec_lam }
}

///|
pub impl TermSym for SourceText with fn app(f, a) {
  { repr: wrap_source(f, prec_app) + " " + wrap_source(a, prec_atom), prec: prec_app }
}

///|
pub impl TermSym for SourceText with fn bop(op, l, r) {
  let sym = match op {
    Plus => "+"
    Minus => "-"
  }
  {
    repr: wrap_source(l, prec_bop) + " " + sym + " " + wrap_source(r, prec_bop + 1),
    prec: prec_bop,
  }
}

///|
pub impl TermSym for SourceText with fn if_then_else(c, t, e) {
  { repr: "if " + c.repr + " then " + t.repr + " else " + e.repr, prec: prec_if }
}

///|
pub impl TermSym for SourceText with fn let_def(name, init) {
  { repr: "let " + name + " = " + init.repr, prec: prec_top }
}

///|
pub impl TermSym for SourceText with fn mod(defs, body) {
  let parts : Array[String] = defs.map(fn(d) { "let " + d.0 + " = " + d.1.repr })
  parts.push(body.repr)
  { repr: "{ " + parts.join("\n") + " }", prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn unit() {
  { repr: "()", prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn unbound(x) {
  { repr: "<unbound: " + x + ">", prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn error_term(msg) {
  { repr: "<error: " + msg + ">", prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn hole(_n) {
  { repr: "_", prec: prec_atom }
}
```

Then redefine `term_to_source` (currently around line 233) to:

```moonbit
///|
fn term_to_source(term : Term) -> String {
  (interpret(term) : SourceText).repr
}
```

Then **delete** the entire string hand-recursion cluster (these functions are now unreferenced): `term_to_source_with_prec`, `module_contents_to_source`, `module_to_block_source`, `expression_to_source`, `function_body_to_source`, `lambda_body_to_source`, `def_to_source`, `params_to_source`. (Keep `collect_lambda_params` — the layout hand-recursion still uses it until Task 2.)

- [ ] **Step 4: Lint**

Run: `moon check --deny-warn`
Expected: clean. If it reports an unused function, it is a member of the delete cluster that was missed — delete it. If it reports `collect_lambda_params` unused, that is wrong at this stage (layout still uses it) — re-check you did not delete a layout helper.

- [ ] **Step 5: Run the full suite and confirm the updated snapshots pass**

Run: `moon test`
Expected: PASS. The Step 1 snapshots now match. `sym_test.mbt` (still using `Pretty`) is unaffected. The `print_term(a) == print_term(b)` comparisons stay green. If any *other* literal snapshot fails, triage it: confirm the new output still parses (`parse(output)` round-trips), then update the expected value; if it no longer parses, STOP and report.

- [ ] **Step 6: Commit**

```bash
cd examples/lambda
git add ast/pretty_traits.mbt issue305_syntax_test.mbt parse_tree_test.mbt parser_test.mbt
git commit -m "refactor(lambda): drive to_source via SourceText interpret fold

Delete term_to_source_with_prec hand-recursion; SourceText is a pure
TermSym catamorphism with minimal-paren precedence and always-braced
modules. Update churned string snapshots.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Migrate the layout printer + always-brace + positive control

**Files:**
- Modify: `examples/lambda/ast/pretty_traits.mbt` (edit `PrettyLayout::mod`; rewire `to_layout`; delete the layout hand-recursion cluster)
- Modify: `examples/lambda/pretty_roundtrip_test.mbt` (add positive control)

**Interfaces:**
- Consumes: `interpret`, the existing `PrettyLayout` struct + its `TermSym` impl, the `@pretty` combinators (`group`/`nest`/`line`/`hardline`/`separate`), and the taggers (`kw`/`ident`/`op_text`/`punc`).
- Produces: `to_layout` (the `@pretty.Pretty for Term` impl) returns `(interpret(self) : PrettyLayout).layout`; `PrettyLayout::mod` emits a braced group with `prec_atom`.

- [ ] **Step 1: Write the positive-control round-trip test**

In `pretty_roundtrip_test.mbt`, append:

```moonbit
///|
/// Positive control: a block-bodied lambda contains a nested Module, the exact
/// case `has_non_roundtrippable` discards from the @qc property. Always-braced
/// output must reparse to the same term.
test "roundtrip: block-bodied lambda (nested module)" {
  let term : @ast.Term = @ast.Term::Module(
    [
      (
        "f",
        @ast.Term::Lam(
          "x",
          @ast.Term::Module(
            [("y", @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Int(1)))],
            @ast.Term::Var("y"),
          ),
        ),
      ),
    ],
    @ast.Term::Var("f"),
  )
  let formatted = @pretty.pretty_print(term)
  let reparsed = parse(formatted) catch { _ => @ast.Term::Error("parse failed") }
  inspect(reparsed == term, content="true")
}
```

- [ ] **Step 2: Run the positive control and confirm it currently PASSES**

Run: `moon test -p dowdiness/lambda -f pretty_roundtrip_test.mbt` (if the `-f` filter returns 0 tests, run `moon test` and read the `roundtrip: block-bodied lambda` line).
Expected: PASS — the current hand-recursion already braces nested modules. This establishes the baseline so a regression in Step 4 is attributable to the migration, not a pre-existing parse gap.

- [ ] **Step 3: Edit `PrettyLayout::mod` to always brace**

In `ast/pretty_traits.mbt`, replace the body of `pub impl TermSym for PrettyLayout with fn mod(defs, body)` (currently the flat shape, around line 485) with the braced shape:

```moonbit
///|
pub impl TermSym for PrettyLayout with fn mod(defs, body) {
  let def_layouts : Array[@pretty.Layout[@pretty.SyntaxCategory]] = defs.map(fn(
    d,
  ) {
    let (name, val) = d
    kw("let") +
    @pretty.text(" ") +
    ident(name) +
    @pretty.text(" ") +
    op_text("=") +
    @pretty.text(" ") +
    @pretty.nest(val.layout)
  })
  let defs_doc = @pretty.separate(@pretty.hardline(), def_layouts)
  let contents = if def_layouts.is_empty() {
    body.layout
  } else {
    defs_doc + @pretty.hardline() + body.layout
  }
  {
    layout: @pretty.group(
      punc("{") +
      @pretty.nest(@pretty.line() + contents) +
      @pretty.line() +
      punc("}"),
    ),
    prec: prec_atom,
  }
}
```

(The `prec` changes from `prec_top` to `prec_atom`: a braced block is self-delimiting, so it never needs outer parens.)

- [ ] **Step 4: Rewire `to_layout` and delete the layout hand-recursion cluster**

Replace the `@pretty.Pretty for Term` impl body (around line 524):

```moonbit
///|
pub impl @pretty.Pretty for Term with fn to_layout(self) {
  (interpret(self) : PrettyLayout).layout
}
```

Then **delete** the layout hand-recursion cluster (now unreferenced): `term_to_pretty_layout`, `term_to_pretty_layout_in_expr`, `term_to_pretty_layout_with_context`, `def_to_layout`, `module_contents_to_layout`, `module_to_block_layout`, `function_body_to_layout`, `lambda_body_to_layout`, and now `collect_lambda_params` and `params_to_layout` (their last callers are gone).

- [ ] **Step 5: Lint and let `--deny-warn` confirm dead helpers**

Run: `moon check --deny-warn`
Expected: clean. If it names any remaining unused helper, delete the exact function it names and re-run. Do NOT delete anything it does not flag (the taggers, `wrap_if_needed`, and `prec_*` constants are still used by the `PrettyLayout` impls).

- [ ] **Step 6: Run the full suite, triage layout churn, verify the property**

Run: `moon test`
Expected: the positive control (Step 1) still PASSES; the `@qc` `property: parse(pretty_print(term)) == term` PASSES; `print_term(a) == print_term(b)` comparisons PASS. Some `pretty_print`/`to_layout` literal snapshots may change (top-level modules now braced). For each failure: confirm the new output still parses, then `moon test --update` to accept. If any output no longer parses, STOP and report — do not blanket-update.

- [ ] **Step 7: Commit**

```bash
cd examples/lambda
git add ast/pretty_traits.mbt pretty_roundtrip_test.mbt
# add any snapshot files touched by `moon test --update`
git add -u
git commit -m "refactor(lambda): drive to_layout via PrettyLayout interpret fold

Rewire to_layout to interpret; always-brace PrettyLayout::mod (round-trip
safe, drops the top_level flag); delete the layout hand-recursion. Add a
nested-module positive-control round-trip test (the @qc property discards
that case).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Retire `Pretty`, repoint `sym_test`

**Files:**
- Modify: `examples/lambda/ast/sym.mbt` (delete `Pretty` struct + impls)
- Modify: `examples/lambda/ast/sym_test.mbt` (repoint 4 cases to `SourceText`)
- Modify: `examples/lambda/ast/pretty_traits.mbt` (fix stale comment)

**Interfaces:**
- Consumes: `SourceText` (from Task 1).
- Produces: nothing new; removes the `Pretty` type from the package's public API (`.mbti` will lose it).

- [ ] **Step 1: Repoint the 4 `sym_test` cases to `SourceText` with predicted values**

In `ast/sym_test.mbt`:
- line 44: `(@ast.interpret(term) : @ast.Pretty).repr, content="(1 + 2)"` → `(@ast.interpret(term) : @ast.SourceText).repr, content="1 + 2"`
- line 54: `(@ast.interpret(term) : @ast.Pretty).repr, content="(x) => x"` → `(@ast.interpret(term) : @ast.SourceText).repr, content="(x) => x"`
- line 60: `(@ast.interpret(term) : @ast.Pretty).repr, content="let x = 1"` → `(@ast.interpret(term) : @ast.SourceText).repr, content="let x = 1"`
- lines 69–72: `(@ast.interpret(term) : @ast.Pretty).repr, content="let x = 1\nlet y = 2\nx"` → `(@ast.interpret(term) : @ast.SourceText).repr, content="{ let x = 1\nlet y = 2\nx }"`

Also rename the three test names containing `Pretty` for clarity (optional but recommended): `"interpret: Pretty and Term from same source"` → `"interpret: SourceText and Term from same source"`, `"interpret: Pretty Lam"` → `"interpret: SourceText Lam"`, `"interpret: Pretty LetDef"` → `"interpret: SourceText LetDef"`, `"interpret: Pretty Module"` → `"interpret: SourceText Module"`.

- [ ] **Step 2: Run `sym_test` and confirm it PASSES (green baseline before deletion)**

Run: `moon test -p dowdiness/lambda/ast`
Expected: PASS — the repointed `SourceText` cases match their predicted values, and `Pretty` still exists (unused by tests now). This confirms the `SourceText` predictions are correct *before* removing `Pretty`, so any failure after Step 3 is attributable to the deletion, not a wrong expectation.

- [ ] **Step 3: Delete `Pretty` from `sym.mbt`**

In `ast/sym.mbt`, delete the `Pretty` struct definition (currently lines ~122–126) and all `pub impl TermSym for Pretty with fn …` blocks (currently lines ~128–192). Leave the `Term` identity impls, `children_of`, `rebuild_from`, and `interpret` untouched.

- [ ] **Step 4: Fix the stale comment in `pretty_traits.mbt`**

In `ast/pretty_traits.mbt`, the `@pretty.Source for Term` doc comment (line 3) currently reads "Delegates to the existing Pretty TermSym interpretation." Change it to:

```moonbit
/// Source trait: compact parseable text that roundtrips through the parser.
/// Delegates to the SourceText TermSym interpretation via interpret.
```

- [ ] **Step 5: Lint and test**

Run: `moon check --deny-warn && moon test -p dowdiness/lambda/ast`
Expected: clean + PASS. If `moon check` reports `Pretty` still referenced, a `sym_test` case was missed in Step 1 — fix it.

- [ ] **Step 6: Regenerate interfaces, format, inspect `.mbti`**

Run: `moon info && moon fmt`
Then: `git diff ast/ast.pkg.generated.mbti` (or the package's `.mbti`)
Expected: the diff removes `Pretty` and its impls and adds `SourceText` + its impls. Confirm no *other* public symbol changed (no widened trait bounds, no removed unrelated exports).

- [ ] **Step 7: Full suite + commit**

Run: `moon test`
Expected: PASS across the whole example.

```bash
cd examples/lambda
git add ast/sym.mbt ast/sym_test.mbt ast/pretty_traits.mbt
git add -u   # picks up regenerated .mbti and fmt changes
git commit -m "refactor(lambda): retire test-only Pretty in favor of SourceText

Pretty was a redundant fully-parenthesized string interpretation used
only by sym_test. SourceText (minimal-paren, the production to_source
printer) subsumes it. Repoint the 4 sym_test cases; fix stale comment.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Component 1 (layout printer: brace `mod`, rewire `to_layout`, delete cluster) → Task 2. ✓
- Component 2 (add `SourceText`, rewire `term_to_source`, delete string cluster) → Task 1. ✓
- Component 3 (delete `Pretty`, repoint `sym_test`, fix stale comment) → Task 3. ✓
- Error handling (`unbound`/`error_term`/`hole` totality preserved) → covered by `SourceText` impls (Task 1) and unchanged `PrettyLayout` impls. ✓
- Testing: positive control → Task 2 Step 1; full-suite triage → Task 1 Step 5 / Task 2 Step 6; `@qc` green → Task 2 Step 6; `moon info`/`.mbti` diff → Task 3 Step 6. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; every snapshot change states exact before/after strings. ✓

**Type consistency:** `SourceText { repr : String; prec : Int }` and `wrap_source(SourceText, Int) -> String` defined in Task 1, consumed by name in Task 3. `interpret`, `prec_*`, `Bop`, `@pretty` combinators, and taggers are all pre-existing. `PrettyLayout::mod` returns `{ layout, prec }` matching the existing struct. ✓

**Ordering safety:** Task 1 adds `SourceText` before Task 3 references it; `Pretty` survives through Tasks 1–2 (sym_test stays green) and is removed only in Task 3; `collect_lambda_params` is kept in Task 1 (layout still uses it) and deleted in Task 2. ✓
