# Parser API Simplification Implementation Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reconcile `IncrementalParser`/`ParserDb` feature asymmetries, clean the public API surface, make interners global, and rename both types to `ImperativeParser`/`ReactiveParser`.

**Architecture:** Seven sequential tasks: remove leaked internals → make interners global → add missing API methods → add CST equality skip → rename everything → write docs. Each task leaves tests green.

**Tech Stack:** MoonBit, `moon check`, `moon test`, `moon info`, `moon fmt`. Work from `loom/` directory for loom tests, `examples/lambda/` for integration tests.

---

### Task 1: Remove publicly mutable fields and dead methods

**Files:**
- Modify: `loom/src/incremental/incremental_parser.mbt`
- Modify: `examples/lambda/src/incremental_parser_test.mbt`
- Delete tests: `examples/lambda/src/interner_integration_test.mbt`
- Delete tests: `examples/lambda/src/node_interner_integration_test.mbt`

**Context:** `IncrementalParser` has four public mutable fields (`source`, `tree`, `syntax_tree`, `last_reuse_count`) that callers can corrupt. It also has four dead public methods (`stats`, `interner_size`, `node_interner_size`, `interner_clear`) that are implementation details. Task 2 makes interners global, which is why the interner test files are deleted here rather than updated.

**Step 1: Delete the interner test files**

```bash
cd /path/to/loom
rm examples/lambda/src/interner_integration_test.mbt
rm examples/lambda/src/node_interner_integration_test.mbt
```

**Step 2: Remove the stats test from incremental_parser_test.mbt**

In `examples/lambda/src/incremental_parser_test.mbt`, find and delete the test that calls `parser.stats()`:

```moonbit
// DELETE this entire test block:
test "IncrementalParser::stats returns debug info" {
  let parser = @loom.new_incremental_parser("42", lambda_grammar)
  let _ = parser.parse()
  let stats = parser.stats()
  inspect(stats.contains("IncrementalParser"), content="true")
  inspect(stats.contains("source_length"), content="true")
}
```

**Step 3: Add `priv` to the four public fields in `incremental_parser.mbt`**

In `loom/src/incremental/incremental_parser.mbt`, change the struct:

```moonbit
// BEFORE:
pub struct IncrementalParser[Ast] {
  priv lang : IncrementalLanguage[Ast]
  mut source : String
  mut tree : Ast?
  mut syntax_tree : @seam.SyntaxNode?
  mut last_reuse_count : Int
  priv interner : @seam.Interner
  priv node_interner : @seam.NodeInterner
}

// AFTER:
pub struct IncrementalParser[Ast] {
  priv lang : IncrementalLanguage[Ast]
  priv mut source : String
  priv mut tree : Ast?
  priv mut syntax_tree : @seam.SyntaxNode?
  priv mut last_reuse_count : Int
  priv interner : @seam.Interner
  priv node_interner : @seam.NodeInterner
}
```

**Step 4: Delete the four dead methods from `incremental_parser.mbt`**

Delete these four method blocks entirely:
- `IncrementalParser::interner_size` (lines ~32-36)
- `IncrementalParser::node_interner_size` (lines ~39-43)
- `IncrementalParser::interner_clear` (lines ~46-51)
- `IncrementalParser::stats` (lines ~122-128)

**Step 5: Run tests**

```bash
cd loom && moon check && moon test
cd ../examples/lambda && moon check && moon test
```

Expected: all tests pass. The deleted test files and test block are gone; nothing called those methods.

**Step 6: Regenerate interfaces and format**

```bash
cd loom && moon info && moon fmt
```

**Step 7: Commit**

```bash
git add -p
git commit -m "refactor: make IncrementalParser fields private, remove dead interner methods"
```

---

### Task 2: Global interners in loom/core

**Files:**
- Create: `loom/src/core/interners.mbt`
- Modify: `loom/src/core/lib.mbt`
- Modify: `loom/src/incremental/incremental_parser.mbt`
- Modify: `loom/src/incremental/incremental_language.mbt`
- Modify: `loom/src/factories.mbt`
- Modify: `examples/lambda/src/benchmarks/heavy_benchmark.mbt`

**Context:** Instead of each `IncrementalParser` owning its own interners, all parse calls share module-level globals. This follows rust-analyzer's pattern: tokens like `+`, `λ`, `if` are deduplicated globally. `ParserDb` also gets persistent interning for free.

**Step 1: Create `loom/src/core/interners.mbt`**

```moonbit
///|
/// Session-global token interner shared across all parse calls in this process.
/// Tokens are accumulated, never cleared — deduplication improves with use.
pub let core_interner : @seam.Interner = @seam.Interner::new()

///|
/// Session-global node interner shared across all parse calls.
pub let core_node_interner : @seam.NodeInterner = @seam.NodeInterner::new()
```

**Step 2: Update `build_tree_generic` in `lib.mbt` to always use globals**

Find `build_tree_generic` (around line 912) and replace it:

```moonbit
// BEFORE: took Interner? and NodeInterner? params
fn[T, K] build_tree_generic(
  buf : @seam.EventBuffer,
  spec : LanguageSpec[T, K],
  interner : @seam.Interner?,
  node_interner : @seam.NodeInterner?,
) -> @seam.CstNode {
  ...match (interner, node_interner) { ... }
}

// AFTER: always uses globals
fn[T, K] build_tree_generic(
  buf : @seam.EventBuffer,
  spec : LanguageSpec[T, K],
) -> @seam.CstNode {
  let ws = (spec.kind_to_raw)(spec.whitespace_kind)
  let root = (spec.kind_to_raw)(spec.root_kind)
  buf.build_tree_fully_interned(
    root,
    core_interner,
    core_node_interner,
    trivia_kind=Some(ws),
  )
}
```

**Step 3: Update `parse_tokens_indexed` to remove interner params**

Find the `parse_tokens_indexed` signature (around line 940) and remove the last two optional params:

```moonbit
// BEFORE:
pub fn[T, K] parse_tokens_indexed(
  source : String,
  token_count : Int,
  get_token : (Int) -> T,
  get_start : (Int) -> Int,
  get_end : (Int) -> Int,
  spec : LanguageSpec[T, K],
  cursor? : ReuseCursor[T, K]? = None,
  prev_diagnostics? : Array[Diagnostic[T]]? = None,
  interner? : @seam.Interner? = None,
  node_interner? : @seam.NodeInterner? = None,
) -> (@seam.CstNode, Array[Diagnostic[T]], Int)

// AFTER: remove last two params, update build_tree_generic calls inside body
pub fn[T, K] parse_tokens_indexed(
  source : String,
  token_count : Int,
  get_token : (Int) -> T,
  get_start : (Int) -> Int,
  get_end : (Int) -> Int,
  spec : LanguageSpec[T, K],
  cursor? : ReuseCursor[T, K]? = None,
  prev_diagnostics? : Array[Diagnostic[T]]? = None,
) -> (@seam.CstNode, Array[Diagnostic[T]], Int)
```

Also update every internal call to `build_tree_generic` inside `parse_tokens_indexed` — remove the `interner` and `node_interner` arguments.

**Step 4: Update `IncrementalLanguage` vtable to remove interner params**

In `loom/src/incremental/incremental_language.mbt`:

```moonbit
// BEFORE:
pub struct IncrementalLanguage[Ast] {
  priv full_parse : (String, @seam.Interner, @seam.NodeInterner) -> ParseOutcome
  priv incremental_parse : (
    String,
    @seam.SyntaxNode,
    @core.Edit,
    @seam.Interner,
    @seam.NodeInterner,
  ) -> ParseOutcome
  priv to_ast : (@seam.SyntaxNode) -> Ast
  priv on_lex_error : (String) -> Ast
}

// AFTER:
pub struct IncrementalLanguage[Ast] {
  priv full_parse : (String) -> ParseOutcome
  priv incremental_parse : (String, @seam.SyntaxNode, @core.Edit) -> ParseOutcome
  priv to_ast : (@seam.SyntaxNode) -> Ast
  priv on_lex_error : (String) -> Ast
}
```

Update the `IncrementalLanguage::new` constructor to match.

**Step 5: Update `IncrementalParser` struct and methods**

In `loom/src/incremental/incremental_parser.mbt`:

Remove the `priv interner` and `priv node_interner` fields from the struct.

Update `IncrementalParser::new` to not initialise them.

Update `IncrementalParser::parse`:
```moonbit
// Change: (self.lang.full_parse)(self.source, self.interner, self.node_interner)
// To:     (self.lang.full_parse)(self.source)
```

Update `IncrementalParser::edit`:
```moonbit
// Change: (self.lang.incremental_parse)(new_source, old_syntax, edit, self.interner, self.node_interner)
// To:     (self.lang.incremental_parse)(new_source, old_syntax, edit)
```

**Step 6: Update `factories.mbt`**

In `loom/src/factories.mbt`:

In `new_incremental_parser`: remove `let token_buf` and `let last_diags` interner locals, remove `interner=Some(interner)` and `node_interner=Some(node_interner)` from both `parse_tokens_indexed` calls, simplify the closure signatures.

In `new_parser_db`: remove `interner=Some(...)` and `node_interner=Some(...)` calls (they were already `None` — just remove the named args).

**Step 7: Remove interner references from heavy_benchmark.mbt**

In `examples/lambda/src/benchmarks/heavy_benchmark.mbt`, delete the lines that call `parser.interner_size()` and `parser.node_interner_size()`, and remove the `initial_token_size`, `initial_node_size`, `final_token_size`, `final_node_size` variables. Keep the benchmark logic, just remove the interner tracking.

**Step 8: Run tests**

```bash
cd loom && moon check && moon test
cd ../examples/lambda && moon check && moon test
```

Expected: all tests pass.

**Step 9: Regenerate and format**

```bash
cd loom && moon info && moon fmt
cd ../examples/lambda && moon info && moon fmt
```

**Step 10: Commit**

```bash
git add -p
git commit -m "refactor: move interners to module-level globals in loom/core"
```

---

### Task 3: Add `diagnostics()` to `IncrementalParser`

**Files:**
- Modify: `loom/src/incremental/incremental_language.mbt`
- Modify: `loom/src/incremental/incremental_parser.mbt`
- Modify: `loom/src/factories.mbt`
- Modify: `examples/lambda/src/incremental_parser_test.mbt`

**Context:** `last_diags` is currently captured inside the factory closure but never surfaced. Users cannot inspect parse errors without walking the AST for error nodes.

**Step 1: Write the failing test**

Add to `examples/lambda/src/incremental_parser_test.mbt`:

```moonbit
///|
test "IncrementalParser::diagnostics empty on valid source" {
  let parser = @loom.new_incremental_parser("λx.x", lambda_grammar)
  let _ = parser.parse()
  inspect(parser.diagnostics(), content="[]")
}

///|
test "IncrementalParser::diagnostics non-empty on invalid source" {
  let parser = @loom.new_incremental_parser("λ.x", lambda_grammar)
  let _ = parser.parse()
  inspect(parser.diagnostics().length() > 0, content="true")
}
```

**Step 2: Run to verify they fail**

```bash
cd examples/lambda && moon test -p dowdiness/lambda -f incremental_parser_test.mbt
```

Expected: compile error — `diagnostics` method not found.

**Step 3: Add `get_diagnostics` to `IncrementalLanguage` vtable**

In `loom/src/incremental/incremental_language.mbt`, add the field and update constructor:

```moonbit
pub struct IncrementalLanguage[Ast] {
  priv full_parse : (String) -> ParseOutcome
  priv incremental_parse : (String, @seam.SyntaxNode, @core.Edit) -> ParseOutcome
  priv to_ast : (@seam.SyntaxNode) -> Ast
  priv on_lex_error : (String) -> Ast
  priv get_diagnostics : () -> Array[String]   // NEW
}

pub fn[Ast] IncrementalLanguage::new(
  full_parse~ : (String) -> ParseOutcome,
  incremental_parse~ : (String, @seam.SyntaxNode, @core.Edit) -> ParseOutcome,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
  on_lex_error~ : (String) -> Ast,
  get_diagnostics~ : () -> Array[String],      // NEW
) -> IncrementalLanguage[Ast] {
  { full_parse, incremental_parse, to_ast, on_lex_error, get_diagnostics }
}
```

**Step 4: Add `diagnostics()` to `IncrementalParser`**

In `loom/src/incremental/incremental_parser.mbt`:

```moonbit
///|
pub fn[Ast] IncrementalParser::diagnostics(self : IncrementalParser[Ast]) -> Array[String] {
  (self.lang.get_diagnostics)()
}
```

**Step 5: Wire `get_diagnostics` in the factory**

In `loom/src/factories.mbt`, inside `new_incremental_parser`, the factory already captures `last_diags : Ref[Array[@core.Diagnostic[T]]]`. Add the closure and pass it:

```moonbit
// Add this closure before IncrementalLanguage::new call:
let get_diagnostics : () -> Array[String] = fn() {
  last_diags.val.map(fn(d) {
    d.message + " [" + d.start.to_string() + "," + d.end.to_string() + "]"
  })
}

// Then add to IncrementalLanguage::new:
@incremental.IncrementalLanguage::new(
  full_parse=...,
  incremental_parse=...,
  to_ast~,
  on_lex_error=grammar.on_lex_error,
  get_diagnostics~,   // NEW
)
```

**Step 6: Run tests**

```bash
cd loom && moon check && moon test
cd ../examples/lambda && moon check && moon test
```

Expected: new tests pass.

**Step 7: Regenerate, format, commit**

```bash
cd loom && moon info && moon fmt
git add -p
git commit -m "feat: add diagnostics() to IncrementalParser"
```

---

### Task 4: Add `reset()` to `IncrementalParser`

**Files:**
- Modify: `loom/src/incremental/incremental_parser.mbt`
- Modify: `examples/lambda/src/incremental_parser_test.mbt`

**Context:** No way to restart with new source without a new factory call. `reset()` is the synchronization bridge in hybrid editors: after a structural edit regenerates text, the parser must resync before accepting the next text edit.

**Step 1: Write the failing test**

Add to `examples/lambda/src/incremental_parser_test.mbt`:

```moonbit
///|
test "IncrementalParser::reset parses new source fresh" {
  let parser = @loom.new_incremental_parser("42", lambda_grammar)
  let _ = parser.parse()
  let result = parser.reset("λx.x")
  inspect(@ast.print_ast_node(result), content="(λx. x)")
}

///|
test "IncrementalParser::reset clears old tree state" {
  let parser = @loom.new_incremental_parser("λx.x", lambda_grammar)
  let _ = parser.parse()
  // Reset to completely different source
  let _ = parser.reset("1 + 2")
  // Subsequent edit from this new base should work correctly
  let edit = @core.Edit::new(start=5, old_len=0, new_len=2)
  let result = parser.edit(edit, "1 + 2 + 3")
  inspect(@ast.print_ast_node(result), content="((1 + 2) + 3)")
}
```

**Step 2: Run to verify failure**

```bash
cd examples/lambda && moon test -p dowdiness/lambda -f incremental_parser_test.mbt
```

Expected: compile error — `reset` method not found.

**Step 3: Implement `reset()` in `incremental_parser.mbt`**

```moonbit
///|
/// Reset the parser to a new source string, discarding all incremental state.
/// Use this when the source changes in a way that cannot be expressed as an Edit
/// (e.g. after a structural edit regenerates the text in a hybrid editor).
pub fn[Ast] IncrementalParser::reset(
  self : IncrementalParser[Ast],
  source : String,
) -> Ast {
  self.source = source
  self.syntax_tree = None   // discard old tree — forces full_parse on next call
  self.parse()
}
```

**Step 4: Run tests**

```bash
cd loom && moon check && moon test
cd ../examples/lambda && moon check && moon test
```

Expected: all pass.

**Step 5: Regenerate, format, commit**

```bash
cd loom && moon info && moon fmt
git add -p
git commit -m "feat: add reset() to IncrementalParser"
```

---

### Task 5: Add CST equality skip to `IncrementalParser`

**Files:**
- Modify: `loom/src/incremental/incremental_parser.mbt`
- Modify: `examples/lambda/src/incremental_parser_test.mbt`

**Context:** `ParserDb` skips `to_ast` when the CST hash is unchanged (e.g. editing only whitespace). `IncrementalParser` always calls `to_ast`. This task adds the same skip using a stored `prev_cst_hash`.

**Step 1: Write the failing test**

Add to `examples/lambda/src/incremental_parser_test.mbt`:

```moonbit
///|
test "IncrementalParser::edit returns same AST when CST is unchanged" {
  let parser = @loom.new_incremental_parser("1+2", lambda_grammar)
  let ast1 = parser.parse()
  // Edit: add trailing whitespace — CST content unchanged (whitespace is trivia)
  let edit = @core.Edit::new(start=3, old_len=0, new_len=1)
  let ast2 = parser.edit(edit, "1+2 ")
  // AST should be structurally equal (same content, same hash)
  inspect(
    @ast.print_ast_node(ast1) == @ast.print_ast_node(ast2),
    content="true",
  )
}
```

**Step 2: Run to confirm it currently passes (or fails for the wrong reason)**

```bash
cd examples/lambda && moon test -p dowdiness/lambda -f incremental_parser_test.mbt
```

Note: this test may already pass since `to_ast` is deterministic. The optimization is a performance improvement, not a behavioral change. The test verifies correctness.

**Step 3: Add `prev_cst_hash` field and update struct**

In `loom/src/incremental/incremental_parser.mbt`:

```moonbit
pub struct IncrementalParser[Ast] {
  priv lang             : IncrementalLanguage[Ast]
  priv mut source       : String
  priv mut tree         : Ast?
  priv mut syntax_tree  : @seam.SyntaxNode?
  priv mut last_reuse_count : Int
  priv mut prev_cst_hash : Int?   // NEW: hash of last successful CstNode
}
```

Update `IncrementalParser::new` to initialise `prev_cst_hash: None`.

**Step 4: Add CST equality check in `parse()` and `edit()`**

In `parse()`, after getting `new_syntax` from `full_parse`:

```moonbit
Tree(syntax, _) => {
  let new_hash = syntax.cst_node().hash
  let ast = match self.prev_cst_hash {
    Some(old_hash) if old_hash == new_hash => self.tree.unwrap()   // CST unchanged
    _ => (self.lang.to_ast)(syntax)
  }
  self.syntax_tree = Some(syntax)
  self.prev_cst_hash = Some(new_hash)
  self.last_reuse_count = 0
  ast
}
```

Apply the same pattern in `edit()` after getting the new syntax from `incremental_parse`.

On `LexError`, clear `prev_cst_hash`:

```moonbit
LexError(msg) => {
  self.syntax_tree = None
  self.prev_cst_hash = None
  self.last_reuse_count = 0
  (self.lang.on_lex_error)(msg)
}
```

Also reset `prev_cst_hash = None` in `reset()`.

**Step 5: Run tests**

```bash
cd loom && moon check && moon test
cd ../examples/lambda && moon check && moon test
```

Expected: all tests pass.

**Step 6: Regenerate, format, commit**

```bash
cd loom && moon info && moon fmt
git add -p
git commit -m "feat: add CST equality skip to IncrementalParser (skip to_ast when CST unchanged)"
```

---

### Task 6: Add `get_source()` to `ParserDb`

**Files:**
- Modify: `loom/src/pipeline/parser_db.mbt`
- Modify: `loom/src/pipeline/parser_db_test.mbt`

**Context:** `IncrementalParser` has `get_source()`. `ParserDb` does not. Minor asymmetry.

**Step 1: Write the failing test**

In `loom/src/pipeline/parser_db_test.mbt`, add:

```moonbit
///|
test "ParserDb::get_source returns current source" {
  let lang = make_test_language()
  let db = @pipeline.ParserDb::new("hello", lang)
  inspect(db.get_source(), content="hello")
  db.set_source("world")
  inspect(db.get_source(), content="world")
}
```

**Step 2: Run to verify failure**

```bash
cd loom && moon test -p dowdiness/loom/pipeline
```

Expected: compile error — `get_source` not found.

**Step 3: Implement in `parser_db.mbt`**

```moonbit
///|
/// Return the current source text.
pub fn[Ast] ParserDb::get_source(self : ParserDb[Ast]) -> String {
  self.source_text.get()
}
```

**Step 4: Run tests**

```bash
cd loom && moon check && moon test
```

Expected: all pass.

**Step 5: Regenerate, format, commit**

```bash
moon info && moon fmt
git add -p
git commit -m "feat: add get_source() to ParserDb"
```

---

### Task 7: Rename all types, files, and factory functions

**Files to rename (git mv):**
- `loom/src/incremental/incremental_parser.mbt` → `imperative_parser.mbt`
- `loom/src/incremental/incremental_language.mbt` → `imperative_language.mbt`
- `loom/src/pipeline/parser_db.mbt` → `reactive_parser.mbt`
- `loom/src/pipeline/parser_db_test.mbt` → `reactive_parser_test.mbt`
- `examples/lambda/src/incremental_parser_test.mbt` → `imperative_parser_test.mbt`
- `examples/lambda/src/lambda_parser_db_test.mbt` → `reactive_parser_test.mbt`
- `examples/lambda/src/incremental_differential_fuzz_test.mbt` → `imperative_differential_fuzz_test.mbt`
- `examples/lambda/src/benchmarks/parserdb_benchmark.mbt` → `reactive_parser_benchmark.mbt`

**Type/function renames (search-and-replace across all .mbt files):**

| Old | New |
|---|---|
| `IncrementalParser` | `ImperativeParser` |
| `ParserDb` | `ReactiveParser` |
| `IncrementalLanguage` | `ImperativeLanguage` |
| `ParseOutcome` | `ParseOutcome` (keep — internal, no user-facing rename needed) |
| `new_incremental_parser` | `new_imperative_parser` |
| `new_parser_db` | `new_reactive_parser` |

**Step 1: Rename files with git mv**

```bash
cd loom
git mv loom/src/incremental/incremental_parser.mbt loom/src/incremental/imperative_parser.mbt
git mv loom/src/incremental/incremental_language.mbt loom/src/incremental/imperative_language.mbt
git mv loom/src/pipeline/parser_db.mbt loom/src/pipeline/reactive_parser.mbt
git mv loom/src/pipeline/parser_db_test.mbt loom/src/pipeline/reactive_parser_test.mbt
git mv examples/lambda/src/incremental_parser_test.mbt examples/lambda/src/imperative_parser_test.mbt
git mv examples/lambda/src/lambda_parser_db_test.mbt examples/lambda/src/reactive_parser_test.mbt
git mv examples/lambda/src/incremental_differential_fuzz_test.mbt examples/lambda/src/imperative_differential_fuzz_test.mbt
git mv examples/lambda/src/benchmarks/parserdb_benchmark.mbt examples/lambda/src/benchmarks/reactive_parser_benchmark.mbt
```

**Step 2: Rename types and functions in all .mbt files**

Run these replacements across the entire loom/ and examples/ tree:

```bash
# From loom/ root:
find . -name "*.mbt" | xargs sed -i \
  -e 's/IncrementalParser/ImperativeParser/g' \
  -e 's/IncrementalLanguage/ImperativeLanguage/g' \
  -e 's/new_incremental_parser/new_imperative_parser/g' \
  -e 's/ParserDb/ReactiveParser/g' \
  -e 's/new_parser_db/new_reactive_parser/g'
```

**Step 3: Update re-exports in `loom/src/loom.mbt`**

```moonbit
// BEFORE:
pub using @incremental {type IncrementalParser}
pub using @pipeline {type ParserDb}

// AFTER:
pub using @incremental {type ImperativeParser}
pub using @pipeline {type ReactiveParser}
```

**Step 4: Update docs that reference old names**

Files to update (grep first to confirm):
- `docs/api/reference.md` — section 6 (Bridge Factories)
- `docs/api/pipeline-api-contract.md` — all references to `ParserDb`
- `docs/architecture/polymorphism-patterns.md`
- `loom/src/pipeline/README.md`
- `examples/lambda/README.md`
- `ROADMAP.md`
- `CLAUDE.md` (loom subdirectory)

For each: replace `IncrementalParser` → `ImperativeParser`, `ParserDb` → `ReactiveParser`, factory function names accordingly. Archive docs (`docs/archive/`) can be left unchanged — they describe historical state.

**Step 5: Run check and tests**

```bash
cd loom && moon check && moon test
cd ../examples/lambda && moon check && moon test
```

Expected: all tests pass with new names.

**Step 6: Regenerate interfaces and format**

```bash
cd loom && moon info && moon fmt
cd ../examples/lambda && moon info && moon fmt
```

**Step 7: Verify docs hierarchy**

```bash
cd ..  # repo root
bash check-docs.sh
```

Expected: no warnings.

**Step 8: Commit**

```bash
git add -p
git commit -m "refactor: rename IncrementalParser→ImperativeParser, ParserDb→ReactiveParser throughout"
```

---

### Task 8: Write documentation files

**Files:**
- Create: `docs/decisions/2026-03-02-two-parser-design.md`
- Create: `docs/api/choosing-a-parser.md`
- Create: `docs/api/imperative-api-contract.md`
- Modify: `docs/api/reference.md`
- Modify: `docs/README.md`

**Step 1: Write the ADR**

Create `docs/decisions/2026-03-02-two-parser-design.md`:

```markdown
# ADR: Two-Parser Design — ImperativeParser and ReactiveParser

**Date:** 2026-03-02
**Status:** Accepted

## Context

loom provides two parsers. This ADR records why both exist, what distinguishes them,
and the intended future trajectory.

## Decision

Keep two parsers with distinct update models:

- **`ImperativeParser`** — caller drives with explicit `Edit { start, old_len, new_len }` commands.
  Enables node-level CST reuse via `ReuseCursor`. Stateful session wrapper around a stateless core.
- **`ReactiveParser`** — caller sets source; `Signal`/`Memo` pipeline decides what to recompute.
  Composable with `@incr` reactive graphs. Stateless from the caller's perspective.

## Why both exist

Both are incremental — at different granularities:

| | `ImperativeParser` | `ReactiveParser` |
|---|---|---|
| Reuse granularity | CST node level (requires edit location) | Pipeline stage level (equality check) |
| Update model | `edit(Edit, String)` | `set_source(String)` |
| Reactive composition | Impossible — stateful across calls | Natural — Signal/Memo chain |
| Best for | CRDT text ops, high-frequency edits | Language servers, build tools, reactive UIs |

Node-level reuse is fundamentally impossible without knowing where the edit happened.
This constraint makes a separate imperative API necessary.

## Future trajectory

The Hazel project (tylr 2022, teen tylr 2023, Grove POPL 2025) shows the long-term path:

1. **Typed holes** — enrich error recovery to produce typed holes instead of untyped error
   nodes, enabling type checking and evaluation through incomplete expressions.
2. **Gradual structure editing** — token-level edit freedom with structural obligations
   auto-inserted (teen tylr's approach). `ImperativeParser` is the natural foundation.
3. **CRDT on action logs** (Grove) — CRDT operates on structured edit actions rather than
   text diffs. `ImperativeParser` handles the text-input path; `@incr` handles propagation.

In this trajectory, `ImperativeParser` remains the text-editing input path.
`ReactiveParser`'s `@incr` foundation expands to cover the full pipeline.

## References

- [eg-walker CRDT](https://arxiv.org/abs/2409.14252)
- [rust-analyzer interner design](https://github.com/rust-lang/rust-analyzer/tree/master/crates/intern)
- [Total Type Error Localization and Recovery with Holes (POPL 2024)](https://dl.acm.org/doi/10.1145/3632910)
- [Gradual Structure Editing with Obligations (VL/HCC 2023)](https://hazel.org/papers/teen-tylr-vlhcc2023.pdf)
- [Grove: Collaborative Structure Editor (POPL 2025)](https://hazel.org/papers/grove-popl25.pdf)
```

**Step 2: Write the choosing guide**

Create `docs/api/choosing-a-parser.md`:

```markdown
# Choosing a Parser

loom provides two parsers. Use this guide to pick the right one.

## Quick decision

**Can you provide an `Edit { start, old_len, new_len }` describing what changed?**

- **Yes** → `ImperativeParser` — you get node-level CST reuse
- **No** → `ReactiveParser` — set source string, memos handle the rest

## Comparison

| | `ImperativeParser` | `ReactiveParser` |
|---|---|---|
| Update method | `edit(Edit, String)` | `set_source(String)` |
| Node-level reuse | ✓ | ✗ |
| CST equality skip | ✓ | ✓ |
| Persistent interning | ✓ (global) | ✓ (global) |
| Reactive `@incr` composition | ✗ | ✓ |
| `diagnostics()` | ✓ | ✓ |
| `reset()` / `set_source()` | ✓ | ✓ |

## By use case

| Use case | Parser | Reason |
|---|---|---|
| Text editor (keystroke-level edits) | `ImperativeParser` | CRDT/edit ops → `Edit` → node reuse |
| Language server | `ReactiveParser` | Source string arrives, reactive graph updates |
| Build tool | `ReactiveParser` | Batch source changes, equality-based skip |
| Projectional editor import | `ReactiveParser` | One-shot text → AST bootstrap |
| Hybrid editor text input path | `ImperativeParser` + `reset()` | Edits → structural ops; reset on mode switch |

## Factory functions

```moonbit
// From @loom:
let p = new_imperative_parser(initial_source, grammar)  // → ImperativeParser[Ast]
let db = new_reactive_parser(initial_source, grammar)   // → ReactiveParser[Ast]
```

See [api/reference.md](reference.md) for full API.
See [decisions/2026-03-02-two-parser-design.md](../decisions/2026-03-02-two-parser-design.md) for design rationale.
```

**Step 3: Write the imperative API contract**

Create `docs/api/imperative-api-contract.md` modelled on `pipeline-api-contract.md`. Cover:
- `ImperativeParser[Ast]` struct (all fields private)
- `new_imperative_parser` factory
- `parse() -> Ast`
- `edit(Edit, String) -> Ast`
- `reset(String) -> Ast`
- `get_source() -> String`
- `get_tree() -> Ast?`
- `get_last_reuse_count() -> Int`
- `diagnostics() -> Array[String]`
- `ImperativeLanguage[Ast]` (advanced use)
- Stability levels (Stable / Deferred)

**Step 4: Update `docs/api/reference.md` section 6**

Replace the "Bridge Factories" section to use new names and link to `choosing-a-parser.md`.

**Step 5: Update `docs/README.md`**

Add entries under API Reference for the two new files. Move the plan entry from Active Plans section to indicate this plan is being implemented. Add the new ADR entry under Architecture Decisions.

**Step 6: Validate docs hierarchy**

```bash
bash check-docs.sh
```

Expected: no warnings.

**Step 7: Commit**

```bash
git add docs/
git commit -m "docs: add two-parser ADR, choosing guide, and ImperativeParser API contract"
```

---

## Verification

After all tasks, run the full test suite from the repo root:

```bash
cd loom && moon check && moon test        # expect: 76 tests pass
cd ../seam && moon check && moon test     # expect: 64 tests pass
cd ../incr && moon check && moon test     # expect: 194 tests pass
cd ../examples/lambda && moon check && moon test  # expect: 293+ tests pass
bash check-docs.sh                        # expect: no warnings
```
