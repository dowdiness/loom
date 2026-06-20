# Parser-Generation De-Risk Spike — Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Prove whether a grammar-as-data parser can replace lambda's hand-written recursive-descent parser as a drop-in, and whether doing so is materially cheaper to author and reuse.

**Architecture:** The spike creates an isolated `examples/lambda/src/spike/` package containing a hand-authored grammar IR, an interpreter that lowers that IR to a `parse_root : (@core.ParserContext[@token.Token, @syntax.SyntaxKind]) -> Unit` closure, and tests that compare it against lambda's public syntax grammar. Parser B reuses loom's lexer, `SyntaxGrammar`, `ParserContext`, incremental pipeline, projection-identity helpers, and reuse machinery unchanged; only `parse_root` differs. The decision gate is explicit: GO requires safety and ergonomics, not a holistic pass.

**Tech Stack:** MoonBit 0.10.0+84519ca0a; packages `dowdiness/lambda/spike`, `@lambda`, `@token`, `@syntax`, `@lexer`, `@loom`, `@core`, `@seam`, `@pipeline`, `@cells`.

## Global Constraints

- MoonBit toolchain: this repo pins setup-moonbit `0.10.0+84519ca0a`. Follow `moonbit-base.md` idioms: `match`/`guard` over if-chains; arrow callbacks `x => …` / `() => ()` (NOT `() => {}`); `Type::Type(...)` constructors; `for .. in` not `loop`; views; `const` at top level; justify every `let mut`.
- Validation commands (run from `examples/lambda/`): `moon check` after EVERY file edit; `moon test -p dowdiness/lambda/spike` for the spike package; `moon info && moon fmt` before any commit; module-shaped fmt check `NEW_MOON_MOD=0 moon -C examples/lambda fmt --check`.
- The spike is ADDITIVE and ISOLATED: new `examples/lambda/src/spike/` package only; zero edits to the main lambda package or to loom/seam/incr. No new loom-core APIs.
- B reuses loom's engine; do NOT write a new reuse engine, a new TokenBuffer, or a new ReuseCursor. The ONLY new parser logic is the IR + interpreter producing a `parse_root` closure.
- **Config-normalization invariant: A and B MUST share identical incremental config so only `parse_root` differs.** Both are built via `normalized_syntax_grammar` (Task 8) with `incremental_relex_enabled=false` and `block_reparse_spec=None`. VERIFIED confound: A's `lambda_grammar` uses `incremental_relex_enabled=false` + `block_reparse_spec=Some(...)` (`grammar.mbt:14-15`) while `SyntaxGrammar::new` defaults to `true`/`None` — so a B built with defaults would diverge from A on relex (newline edits) and block reparse (BlockExpr edits) for reasons unrelated to the grammar-IR under test. Never build A via `to_syntax_grammar()` (it bakes in A's config).
- NON-GOALS: no interpreter hot-path throughput benchmark (deferred per doc §8); no loomgen build; no AST/Term fold (syntax-only spike); no second projectional language built in THIS plan (it's a documented follow-up GATE); no migration of loom's pipeline to `AcceptedDerived` (independent, deferred); **no block-reparse parity and no incremental-relex-path parity** (both axes pinned OFF for A and B via normalization — `block_reparse_spec=Some` would route B through A's hand reparser inside blocks, defeating the test; B-equivalent block reparse is a documented follow-up for when block-reparse parity must be measured, and BlockExpr is not in the §5.5 minimal slice).
- This is a SPIKE: the GO/NO-GO outcome (with classified divergences + E1/E2/E3) is the deliverable, not a merged parser. If the stop condition fires (decision 9 "wrong model"), reaching that verdict with evidence is success.

---

## File Structure

- `examples/lambda/src/spike/moon.pkg.json` — isolated package manifest importing only lambda public packages and verified loom/seam/incr packages.
- `examples/lambda/src/spike/types.mbt` — spike-local grammar IR, rule identifiers, divergence classification, fixture, and measurement result types.
- `examples/lambda/src/spike/interpreter.mbt` — IR interpreter that walks grammar data and calls verified `ParserContext` primitives.
- `examples/lambda/src/spike/lambda_ir.mbt` — lambda grammar-IR value and B grammar construction.
- `examples/lambda/src/spike/leaves.mbt` — shared pure `project_lambda_leaves(root : @seam.SyntaxNode) -> Array[@core.ProjectionLeaf]` extractor.
- `examples/lambda/src/spike/oracle.mbt` — persistent A-vs-B harness with D1, D2a, D2b, and REUSE-PARITY at every edit step.
- `examples/lambda/src/spike/fixtures.mbt` — edit-sequence fixtures for LetDef, ParamList churn, Pratt App/Bop, malformed recovery, top-level reuse, and crippled-B positive control.
- `examples/lambda/src/spike/measurements.mbt` — E1/E2/E3 measurement helpers and results template data.
- `examples/lambda/src/spike/*_test.mbt` — focused tests for each independently reviewable deliverable.
- `docs/analysis/2026-06-20-parser-generation-spike-results.md` — final results template filled by the last task; records divergences, equivalence-bar call, E1/E2/E3, follow-up gate, and GO/NO-GO.
- `docs/README.md` — index update for the new results document when it is created by Task 14.

## Verified API Surface To Use Verbatim

The implementation must not assume any loom/lambda symbol outside this list. If a future worker needs another symbol, first define a spike-local wrapper or artifact in `examples/lambda/src/spike/` and classify why it is needed.

- `pub fn[T, K] SyntaxGrammar::new(spec~ : @core.LanguageSpec[T, K], lex~ : (String) -> @core.LexResult[T], incremental_relex_enabled? : Bool, block_reparse_spec? : @core.BlockReparseSpec[T, K]?, mode_relex? : @core.ModeRelexState[T]?) -> SyntaxGrammar[T, K]`
- `pub fn[T, K] SyntaxGrammar::parse_cst(Self[T, K], String) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError`
- `pub fn[T, K, Ast] Grammar::to_syntax_grammar(Self[T, K, Ast]) -> SyntaxGrammar[T, K]` — exists, but the spike does **NOT** use it for A: it copies A's incremental config (`relex=false`, `block_reparse=Some`), which is a confound. Build A via `normalized_syntax_grammar(@lambda.lambda_grammar.spec, @lambda.lambda_grammar.lex)` instead. Listed only so workers recognize and avoid it.
- `pub fn[T : Eq + @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] new_syntax_parser(String, SyntaxGrammar[T, K], runtime? : @cells.Runtime) -> @pipeline.SyntaxParser`
- `pub fn[T : Eq + @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] assert_incremental_edit_matches_full_parse(String, String, @core.Edit, String, SyntaxGrammar[T, K]) -> Int`
- `pub fn @core.tree_diff(@seam.CstNode, @seam.CstNode) -> Array[@core.Edit]` — ⚠ lives in `dowdiness/loom/core` (import `@core`), NOT re-exported by the `@loom` facade. ALWAYS call it as `@core.tree_diff(...)`; `@loom.tree_diff` is unbound and fails `moon check`. (Empty array == structurally identical, up to hash collisions.)
- `pub fn[Id] realign_projection_identities(@core.ProjectionIdentityBaseline[Id], String, Array[@core.ProjectionLeaf], (@core.ProjectionLeaf) -> Id, edit? : @core.Edit) -> Array[@core.StableProjectionLeaf[Id]]`
- `pub fn SyntaxParser::apply_edit(Self, @core.Edit, String) -> Unit`
- `pub fn SyntaxParser::snapshot(Self) -> @cells.Derived[SyntaxSnapshot]`
- `pub fn SyntaxParser::set_source(Self, String) -> Unit`
- `pub fn SyntaxParser::syntax_tree(Self) -> @cells.Derived[@seam.SyntaxNode]`
- `pub fn SyntaxParser::diagnostics(Self) -> @cells.Derived[@core.DiagnosticSet]`
- `pub struct SyntaxSnapshot { source : String; syntax : @seam.SyntaxNode; diagnostics : @core.DiagnosticSet; reuse_count : Int } derive(Eq, Debug)`
- `@cells.Derived[V]` value read idiom: `.read_or_abort() -> V`.
- `pub struct LanguageSpec[T, K] { whitespace_kind : K; error_kind : K; incomplete_kind : K; root_kind : K; eof_token : T; parse_root : (ParserContext[T, K]) -> Unit; reuse_size_threshold : Int }`
- `pub fn[T, K] LanguageSpec::new(K, K, K, T, incomplete_kind? : K, parse_root? : (ParserContext[T, K]) -> Unit, reuse_size_threshold? : Int) -> Self[T, K]`
- `pub struct DiagnosticSet { /* private */ } derive(Eq, Debug)`; methods: `items(Self) -> Array[Diagnostic]`, `length(Self) -> Int`, `is_empty(Self) -> Bool`, `format(Self) -> Array[String]`, `equal` via derived Eq.
- `pub(all) struct Edit { start : Int; old_len : Int; new_len : Int }`; constructors (VERIFIED against `edit.mbt` — the args mix lengths and offsets, do not guess): `Edit::new(start, old_len, new_len)` (all three are LENGTHS), `Edit::insert(position, length)` (2nd is a LENGTH), `Edit::delete(start, end)` (2nd is an END OFFSET → `old_len = end - start`), `Edit::replace(start, old_end, new_end)` (BOTH 2nd and 3rd are END OFFSETS → `old_len = old_end - start`, `new_len = new_end - start`). ⚠ The 3rd arg of `replace` is `new_end`, NOT a length. **Author every edit-sequence fixture with `Edit::new(start, old_len, new_len)`** (unambiguous lengths) to avoid a silent off-by-`start` fixture that mutates a different span than intended and produces a FALSE D2a divergence. The harness assertions catch a malformed fixture, but a wrong fixture wastes a debugging cycle.
- `pub fn[T, K] ParserContext::mark(Self[T, K]) -> Int`
- `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::node(Self[T, K], K, () -> Unit) -> Unit`
- `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::node_with_recovery(Self[T, K], K, () -> Bool, (T) -> Bool) -> Unit`
- `pub fn[T, K : @seam.ToRawKind] ParserContext::wrap_at(Self[T, K], Int, K, () -> Unit) -> Unit`
- `pub fn[T, K : @seam.ToRawKind] ParserContext::start_node(Self[T, K], K) -> Unit`
- `pub fn[T, K : @seam.ToRawKind] ParserContext::start_at(Self[T, K], Int, K) -> Unit`
- `pub fn[T, K] ParserContext::finish_node(Self[T, K]) -> Unit`
- `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::emit_token(Self[T, K], K) -> Unit`
- `pub fn[T, K : @seam.ToRawKind] ParserContext::emit_error_placeholder(Self[T, K]) -> Unit`
- `pub fn[T, K : @seam.ToRawKind] ParserContext::emit_incomplete_placeholder(Self[T, K]) -> Unit`
- `pub fn[T : @seam.IsTrivia, K] ParserContext::peek(Self[T, K]) -> T`
- `pub fn[T : @seam.IsTrivia, K] ParserContext::peek_nth(Self[T, K], Int) -> T`
- `pub fn[T : Eq + @seam.IsTrivia, K] ParserContext::at(Self[T, K], T) -> Bool`
- `pub fn[T : @seam.IsTrivia + @seam.IsEof, K] ParserContext::at_eof(Self[T, K]) -> Bool`
- `pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::expect(Self[T, K], T, K) -> Bool`
- `pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::error(Self[T, K], String) -> Unit`
- `pub fn[T : Eq + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::separated_list(Self[T, K], K, T, () -> Bool, element_start? : () -> Bool, wrap_element? : Bool) -> Int`
- `pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until(Self[T, K], (T) -> Bool) -> Int`
- `pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] ParserContext::bump_error(Self[T, K]) -> Unit`
- `pub fn[T, K] ParserContext::too_many_errors(Self[T, K], Int) -> Bool`
- `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::try_reuse_repeat_group(Self[T, K]) -> Bool`
- `pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] ParserContext::flush_trivia(Self[T, K]) -> Unit`
- `pub fn[Id] ProjectionIdentityTracker::new() -> Self[Id]`
- `pub fn[Id] ProjectionIdentityTracker::from_baseline(ProjectionIdentityBaseline[Id]) -> Self[Id]`
- `pub fn[Id] ProjectionIdentityTracker::realign_success(Self[Id], String, Array[ProjectionLeaf], (ProjectionLeaf) -> Id, edit? : Edit) -> Array[StableProjectionLeaf[Id]]`
- `pub fn[Id] ProjectionIdentityTracker::commit_success(Self[Id], String, Array[StableProjectionLeaf[Id]]) -> Unit`
- `pub fn[Id] ProjectionIdentityTracker::record_failed_input(Self[Id], String, source_before_edit? : String, edit? : Edit) -> Unit`
- `pub fn[Id] ProjectionIdentityTracker::baseline(Self[Id]) -> ProjectionIdentityBaseline[Id]?`
- `pub struct ProjectionLeaf { start : Int; end : Int; key : String } derive(Eq, Debug)`; `pub fn ProjectionLeaf::new(Int, Int, String) -> Self`
- `pub struct StableProjectionLeaf[Id] { start : Int; end : Int; key : String; id : Id } derive(Eq, Debug)`; `pub fn[Id] StableProjectionLeaf::new(Int, Int, String, Id) -> Self[Id]`
- `pub fn ProjectionStringIdAllocator::new((String, Int) -> String) -> Self`
- `pub fn ProjectionStringIdAllocator::from_baseline(ProjectionIdentityBaseline[String], (String, Int) -> String) -> Self`
- `pub fn ProjectionStringIdAllocator::allocate(Self, ProjectionLeaf) -> String`
- `pub fn[Id] ProjectionIdentityBaseline::new(String, Array[StableProjectionLeaf[Id]]) -> Self[Id]`; `leaves(Self) -> Array[StableProjectionLeaf[Id]]`; `source(Self) -> String`
- `pub fn @seam.SyntaxNode::from_cst(@seam.CstNode, offset? : Int) -> @seam.SyntaxNode`
- `@seam.SyntaxNode` methods used by the leaf extractor: `cst_node(Self) -> @seam.CstNode`; `children(Self) -> Array[@seam.SyntaxNode]`; `direct_children_of_kind(Self, @seam.RawKind) -> Array[@seam.SyntaxNode]`; `required_direct_child_of_kind(Self, @seam.RawKind, message~ : String) -> Result[@seam.SyntaxNode, _]`; `required_direct_token_of_kind(Self, @seam.RawKind, message~ : String) -> Result[@seam.SyntaxToken, _]`. A token's `.text() -> String`, `.start() -> Int`, `.end() -> Int`. A `SyntaxKind` value's `.to_raw() -> @seam.RawKind`.
- `pub let lambda_grammar : @loom.Grammar[@token.Token, @syntax.SyntaxKind, @ast.Term]`
- `pub fn @lambda.parse_cst(String) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError`
- `pub fn @lexer.lex(String) -> @core.LexResult[@token.Token]`

### Task 0: Scaffold Isolated Spike Package

**Files:** `examples/lambda/src/spike/moon.pkg.json`, `examples/lambda/src/spike/spike_smoke_test.mbt`

**Interfaces:**

- Consumes `pub fn @lambda.parse_cst(String) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError`.
- Produces no public API yet.

- [ ] Create `examples/lambda/src/spike/moon.pkg.json` with only public imports:

```json
{
  "import": [
    {
      "path": "dowdiness/lambda",
      "alias": "lambda"
    },
    {
      "path": "dowdiness/lambda/token",
      "alias": "token"
    },
    {
      "path": "dowdiness/lambda/syntax",
      "alias": "syntax"
    },
    {
      "path": "dowdiness/lambda/lexer",
      "alias": "lexer"
    },
    {
      "path": "dowdiness/loom",
      "alias": "loom"
    },
    {
      "path": "dowdiness/loom/core",
      "alias": "core"
    },
    {
      "path": "dowdiness/loom/pipeline",
      "alias": "pipeline"
    },
    {
      "path": "dowdiness/seam",
      "alias": "seam"
    },
    {
      "path": "dowdiness/incr/cells",
      "alias": "cells"
    }
  ]
}
```

- [ ] Run `cd examples/lambda && moon check`; expect PASS and no references to private `lambda_spec` or `parse_lambda_root`.
- [ ] Write `examples/lambda/src/spike/spike_smoke_test.mbt`:

```moonbit
test "spike package can call public lambda parse_cst" {
  let (_, diagnostics) = @lambda.parse_cst("let x = 1")
  inspect(diagnostics.is_empty(), content="true")
}
```

- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Add lambda parser generation spike package"`.

### Task 1: Add Shared Projection Leaf Extractor

**Files:** `examples/lambda/src/spike/leaves.mbt`, `examples/lambda/src/spike/leaves_test.mbt`

**Interfaces:**

- Consumes `@seam.SyntaxNode` methods: `children(Self) -> Array[@seam.SyntaxNode]`, `direct_children_of_kind(Self, @seam.RawKind) -> Array[@seam.SyntaxNode]`, `required_direct_token_of_kind(Self, @seam.RawKind, message~ : String) -> Result[@seam.SyntaxToken, _]`.
- Consumes `pub struct ProjectionLeaf { start : Int; end : Int; key : String } derive(Eq, Debug)`; `pub fn ProjectionLeaf::new(Int, Int, String) -> Self`.
- Produces `pub fn project_lambda_leaves(root : @seam.SyntaxNode) -> Array[@core.ProjectionLeaf]`.

- [ ] Write a failing test that parses `let x = 1\nlet y = x`, converts CST to syntax with `@seam.SyntaxNode::from_cst`, calls `project_lambda_leaves`, and expects at least two keys: `var:x` and `int:1`.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because `project_lambda_leaves` is missing.
- [ ] Implement `examples/lambda/src/spike/leaves.mbt` as a pure traversal. NOTE the actual semantics (keep the doc comment honest): it fires on ANY node that has a direct `IdentToken` or `IntToken` child — so it emits a `var:` leaf not only for `VarRef` nodes but also for `LetDef` names and `ParamList` parameters, and binder `x` collides with use `x` on the same key `var:x`. This is acceptable for the spike (the extractor only needs to be a deterministic, A/B-symmetric function of the CST — duplicate keys are fine; the tracker handles repeated keys), but it is NOT a realistic projection. Write the doc comment to say exactly this, and list it as an E2 honesty caveat in Task 12 (a real consumer would key off node kind / binding structure). Implementation:

```moonbit
pub fn project_lambda_leaves(root : @seam.SyntaxNode) -> Array[@core.ProjectionLeaf] {
  let acc = Array::new()
  collect_lambda_leaves(root, acc)
  acc
}

fn collect_lambda_leaves(node : @seam.SyntaxNode, acc : Array[@core.ProjectionLeaf]) -> Unit {
  collect_var_ref_leaf(node, acc)
  collect_int_literal_leaf(node, acc)
  for child in node.children() {
    collect_lambda_leaves(child, acc)
  }
}

fn collect_var_ref_leaf(node : @seam.SyntaxNode, acc : Array[@core.ProjectionLeaf]) -> Unit {
  match node.required_direct_token_of_kind(@syntax.IdentToken.to_raw(), message="var ref identifier") {
    Ok(token) => {
      acc.push(@core.ProjectionLeaf::new(token.start(), token.end(), "var:" + token.text()))
    }
    Err(_) => ()
  }
}

fn collect_int_literal_leaf(node : @seam.SyntaxNode, acc : Array[@core.ProjectionLeaf]) -> Unit {
  match node.required_direct_token_of_kind(@syntax.IntToken.to_raw(), message="integer literal") {
    Ok(token) => {
      acc.push(@core.ProjectionLeaf::new(token.start(), token.end(), "int:" + token.text()))
    }
    Err(_) => ()
  }
}
```

- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Add lambda spike projection leaves"`.

### Task 2: Define Grammar IR Types

**Files:** `examples/lambda/src/spike/types.mbt`, `examples/lambda/src/spike/types_test.mbt`

**Interfaces:**

- Produces `pub enum RuleId { Source; Definition; Expression; Binary; Application; Atom; ParamList } derive(Eq, Debug)`.
- Produces `pub enum Expr { Node(@syntax.SyntaxKind, Expr); Emit(@token.Token, @syntax.SyntaxKind); Expect(@token.Token, @syntax.SyntaxKind, String); Ref(RuleId); Choice(Array[Alt]); RepeatTopLevel(RuleId, Bool); RepeatWhile(fn(@token.Token) -> Bool, Expr); WrapIfNext(Int, @syntax.SyntaxKind, fn(@token.Token) -> Bool, Expr); ManualParamList; ErrorUntil(fn(@token.Token) -> Bool, String); Empty }`.
- Produces `pub struct Alt { starts : fn(@token.Token) -> Bool; body : Expr } derive(Debug)`.
- Produces `pub struct GrammarIr { source : Expr; definition : Expr; expression : Expr; binary : Expr; application : Expr; atom : Expr; param_list : Expr } derive(Debug)`.
- Produces `pub fn GrammarIr::rule(Self, RuleId) -> Expr`.

- [ ] Write a failing test that constructs a minimal `GrammarIr` with `Expr::Empty` for each rule and asserts the source rule matches `Expr::Empty` via pattern match (NOT `==`):

```moonbit
test "minimal grammar IR exposes rules" {
  let ir = GrammarIr::{
    source: Expr::Empty,
    definition: Expr::Empty,
    expression: Expr::Empty,
    binary: Expr::Empty,
    application: Expr::Empty,
    atom: Expr::Empty,
    param_list: Expr::Empty,
  }
  match ir.rule(RuleId::Source) {
    Expr::Empty => ()
    _ => fail("expected Empty rule")
  }
}
```

- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because IR types are missing.
- [ ] Implement the IR exactly as spike-local data. NOTE: `Expr`, `Alt`, and `GrammarIr` carry closure fields (`fn(@token.Token) -> Bool`), so they CANNOT `derive(Eq)` or `derive(Debug)` — declare those three WITHOUT derives and assert their values by pattern match. Reserve `derive(Eq, Debug)` for the plain-data types only (`RuleId`, and the result structs in later tasks). The closures are a deliberate spike shortcut (partial defunctionalization rather than a fully-normalized data IR); their imperative cost is accounted for in E2 (Task 12), so flag them there rather than hiding them.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Define lambda grammar IR spike types"`.

### Task 3: Implement Interpreter Core For Nodes And Tokens

**Files:** `examples/lambda/src/spike/interpreter.mbt`, `examples/lambda/src/spike/interpreter_core_test.mbt`

**Interfaces:**

- Consumes `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::node(Self[T, K], K, () -> Unit) -> Unit`.
- Consumes `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::emit_token(Self[T, K], K) -> Unit`.
- Consumes `pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::expect(Self[T, K], T, K) -> Bool`.
- Consumes `pub fn[T : @seam.IsTrivia, K] ParserContext::peek(Self[T, K]) -> T`.
- Produces `pub fn interpret(ir : GrammarIr) -> (@core.ParserContext[@token.Token, @syntax.SyntaxKind]) -> Unit`.
- Produces `pub fn run_expr(ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind], ir : GrammarIr, expr : Expr) -> Unit`.

- [ ] Write a failing smoke test using an IR whose source rule parses one integer literal node, then build a B grammar and parse `"1"`.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because `interpret` is missing.
- [ ] Implement `interpret` and `run_expr` for `Empty`, `Emit`, `Expect`, `Node`, `Ref`, and `Choice`. Keep every unsupported constructor explicit with a spike-local diagnostic error path, not a silent no-op.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS for integer literal smoke.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Interpret core lambda grammar IR nodes"`.

### Task 4: Add Pratt Sub-Engine For Application And Binary Operators

**Files:** `examples/lambda/src/spike/interpreter.mbt`, `examples/lambda/src/spike/lambda_ir.mbt`, `examples/lambda/src/spike/pratt_test.mbt`

**Interfaces:**

- Consumes `pub fn[T, K] ParserContext::mark(Self[T, K]) -> Int`.
- Consumes `pub fn[T, K : @seam.ToRawKind] ParserContext::wrap_at(Self[T, K], Int, K, () -> Unit) -> Unit`.
- Consumes `pub fn[T : @seam.IsTrivia, K] ParserContext::peek(Self[T, K]) -> T`.
- Produces spike-local `pub fn parse_application_ir(ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind], ir : GrammarIr) -> Unit`.
- Produces spike-local `pub fn parse_binary_ir(ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind], ir : GrammarIr) -> Unit`.

- [ ] Write failing tests for `"let x = f y"` and `"let x = a + b - c"` comparing B's fresh CST to A's fresh CST via `@core.tree_diff`.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because Pratt lowering is not implemented.
- [ ] Implement application to reproduce A's call shape: `let mark = ctx.mark(); parse_atom; match ctx.peek() { <atom-start> => ctx.wrap_at(mark, @syntax.AppExpr, fn() { while <atom-start> { parse_atom } }) ; _ => () }`.
- [ ] Implement binary to reproduce A's call shape: `let mark = ctx.mark(); parse_application; match ctx.peek() { Plus|Minus => ctx.wrap_at(mark, @syntax.BinaryExpr, fn() { while … { emit Plus/Minus token; parse_application } }) ; _ => () }`.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS for Pratt smoke.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Add lambda spike Pratt interpreter"`.

### Task 5: Lower Top-Level Repetition To Repeat-Group Reuse

**Files:** `examples/lambda/src/spike/interpreter.mbt`, `examples/lambda/src/spike/lambda_ir.mbt`, `examples/lambda/src/spike/reuse_lowering_test.mbt`

**Interfaces:**

- Consumes `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::try_reuse_repeat_group(Self[T, K]) -> Bool`.
- Consumes `pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] ParserContext::flush_trivia(Self[T, K]) -> Unit`.
- Consumes `pub fn[T : @seam.IsTrivia, K] ParserContext::peek(Self[T, K]) -> T`.
- Produces spike-local `pub fn parse_top_level_repeat(ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind], ir : GrammarIr, cripple_reuse : Bool) -> Unit`.

- [ ] Write a failing test where B parses two top-level `let` definitions, applies an edit to the second definition through `@loom.new_syntax_parser`, reads `parser.snapshot().read_or_abort()`, and asserts `reuse_count > 0`.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because top-level IR does not call `ctx.try_reuse_repeat_group()`.
- [ ] Implement `RepeatTopLevel(rule, cripple_reuse)` so non-crippled B lowers to A's top-level loop shape: while `token_starts_definition(ctx.peek())`, first call `ctx.try_reuse_repeat_group()`, flush trivia or consume newlines, continue on reuse success, otherwise parse the definition rule.
- [ ] Ensure `build_b_syntax_grammar` in Task 8 passes `reuse_size_threshold=0`.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS for reuse smoke.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Lower grammar IR repetition to repeat-group reuse"`.

### Task 6: Reproduce ParamList Shape Without Assuming `separated_list`

**Files:** `examples/lambda/src/spike/interpreter.mbt`, `examples/lambda/src/spike/lambda_ir.mbt`, `examples/lambda/src/spike/param_list_test.mbt`

**Interfaces:**

- Consumes `pub fn[T, K] ParserContext::mark(Self[T, K]) -> Int`.
- Consumes `pub fn[T, K : @seam.ToRawKind] ParserContext::start_at(Self[T, K], Int, K) -> Unit`.
- Consumes `pub fn[T, K] ParserContext::finish_node(Self[T, K]) -> Unit`.
- Consumes `pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::expect(Self[T, K], T, K) -> Bool`.
- Consumes `pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::error(Self[T, K], String) -> Unit`.
- Consumes `pub fn[T, K : @seam.ToRawKind] ParserContext::emit_error_placeholder(Self[T, K]) -> Unit`.
- Produces spike-local `pub fn parse_param_list_exact(ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind]) -> Unit`.

- [ ] Write failing A-vs-B fresh parse tests for parameter lists including `(x)`, `(x, y)`, and `(x,)`. Compare `@core.tree_diff(a_cst, b_cst)` and diagnostics.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because B's param list is missing or structurally different.
- [ ] Implement `ManualParamList` to target A's exact raw loop shape: mark, emit left paren, emit identifier-or-placeholder, then while comma emit comma and identifier-or-placeholder, expect right paren, then `ctx.start_at(mark, @syntax.ParamList); ctx.finish_node()`.
- [ ] Do not lower lambda's ParamList through `ParserContext::separated_list` in the production B grammar. Keep a separate experimental helper only if needed to produce a classified divergence finding.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS or a classified D2a divergence recorded in Task 11 as replication residual if matching remains declarative.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Match lambda ParamList shape in grammar IR"`.

### Task 7: Add Error And Placeholder Constructs

**Files:** `examples/lambda/src/spike/interpreter.mbt`, `examples/lambda/src/spike/error_recovery_test.mbt`

**Interfaces:**

- Consumes `pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::error(Self[T, K], String) -> Unit`.
- Consumes `pub fn[T, K : @seam.ToRawKind] ParserContext::emit_error_placeholder(Self[T, K]) -> Unit`.
- Consumes `pub fn[T, K : @seam.ToRawKind] ParserContext::emit_incomplete_placeholder(Self[T, K]) -> Unit`.
- Consumes `pub fn[T, K : @seam.ToRawKind] ParserContext::start_node(Self[T, K], K) -> Unit`.
- Consumes `pub fn[T, K] ParserContext::finish_node(Self[T, K]) -> Unit`.
- Consumes `pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] ParserContext::bump_error(Self[T, K]) -> Unit`.
- Consumes `pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until(Self[T, K], (T) -> Bool) -> Int`.
- Produces spike-local `pub fn emit_missing(ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind], message : String) -> Unit`.
- Produces spike-local `pub fn parse_error_node_until(ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind], stop : fn(@token.Token) -> Bool) -> Unit`.

- [ ] Write failing A-vs-B fresh parse tests for `let = 1`, `let x =`, and `let x = 1 +`.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because placeholders or error nodes differ.
- [ ] Implement missing-token placeholders using `ctx.error("…"); ctx.emit_error_placeholder()`.
- [ ] Implement unexpected-token blocks using `ctx.start_node(@syntax.ErrorNode); while not sync { ctx.bump_error() }; ctx.finish_node()`.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS or classified D2a divergences for recovery ownership.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Add lambda spike recovery constructs"`.

### Task 8: Assemble B LanguageSpec And SyntaxGrammar

**Files:** `examples/lambda/src/spike/lambda_ir.mbt`, `examples/lambda/src/spike/b_grammar_test.mbt`

**Interfaces:**

- Consumes `pub fn[T, K] LanguageSpec::new(K, K, K, T, incomplete_kind? : K, parse_root? : (ParserContext[T, K]) -> Unit, reuse_size_threshold? : Int) -> Self[T, K]`.
- Consumes `pub fn[T, K] SyntaxGrammar::new(spec~ : @core.LanguageSpec[T, K], lex~ : (String) -> @core.LexResult[T], incremental_relex_enabled? : Bool, block_reparse_spec? : @core.BlockReparseSpec[T, K]?, mode_relex? : @core.ModeRelexState[T]?) -> SyntaxGrammar[T, K]`.
- Consumes `pub fn @lexer.lex(String) -> @core.LexResult[@token.Token]`.
- Produces `pub fn lambda_spike_ir(cripple_reuse? : Bool) -> GrammarIr`.
- Produces `pub fn normalized_syntax_grammar(spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind], lex : (String) -> @core.LexResult[@token.Token]) -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind]` — the shared config-normalizer both A and B go through.
- Produces `pub fn build_b_syntax_grammar(cripple_reuse? : Bool) -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind]`.

- [ ] Write a failing parse smoke test for B on `let x = 1\nlet y = x + 2` using `build_b_syntax_grammar().parse_cst(source)`.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because B grammar construction is missing.
- [ ] Implement `lambda_spike_ir` as a hand-authored value covering Source, Definition, Expression, Binary, Application, Atom, and ParamList.
- [ ] Implement `build_b_syntax_grammar` exactly around public APIs:

```moonbit
pub fn build_b_syntax_grammar(cripple_reuse? : Bool) -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  let ir = lambda_spike_ir(cripple_reuse=cripple_reuse.or(false))
  let parse_root = interpret(ir)
  let b_spec = @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    // Deliberately OMIT incomplete_kind to mirror A's lambda_spec construction
    // exactly (A omits it too). VERIFIED: LanguageSpec::new defaults
    // incomplete_kind to error_kind (parser.mbt:83) = @syntax.ErrorToken for
    // lambda, so A and B get the identical incomplete_kind. The spike invariant
    // is "only parse_root differs"; passing it explicitly is equivalent but
    // breaks the literal mirror, so do not pass it.
    parse_root=parse_root,
    reuse_size_threshold=0,
  )
  normalized_syntax_grammar(b_spec, @lexer.lex)
}

///|
/// Build a SyntaxGrammar with the spike's NORMALIZED incremental config, so the
/// ONLY difference between A and B is `spec.parse_root`. Both A and B go through
/// this. VERIFIED confound (grammar.mbt:14-15): A's lambda_grammar uses
/// incremental_relex_enabled=false + block_reparse_spec=Some(...), but
/// SyntaxGrammar::new defaults are true/None — so without normalization, newline
/// edits (relex) and BlockExpr edits (block reparse) would diverge in reuse_count
/// and diagnostics because of PARSER CONFIG, not the grammar-IR under test. We
/// pin both axes OFF for A and B: relex=false (matches A; full relex each edit is
/// correct, just unoptimized) and block_reparse=None (NOT Some(lambda_block_reparse_spec)
/// — that spec's get_reparser invokes A's HAND reparser, which would run A's
/// parser inside blocks for B too, defeating the test). Block-reparse parity and
/// incremental-relex-path parity are deferred follow-ups (see Global Constraints
/// / NON-GOALS); BlockExpr is not in the minimal slice anyway.
pub fn normalized_syntax_grammar(
  spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind],
  lex : (String) -> @core.LexResult[@token.Token],
) -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  @loom.SyntaxGrammar::new(
    spec~,
    lex~,
    incremental_relex_enabled=false,
    block_reparse_spec=None,
  )
}
```

- [ ] Verify B's `LanguageSpec` argument list is byte-for-byte the same shape as A's `lambda_spec` except for `parse_root`: positional `(@syntax.WhitespaceToken, @syntax.ErrorToken, @syntax.SourceFile, @token.EOF)` then named `reuse_size_threshold=0`, with `incomplete_kind` omitted on BOTH. Any extra/missing argument is a confound that makes D2a diverge independently of `parse_root`.

- [ ] If `Option::or` is not available in MoonBit core, replace it with a local `bool_or_default(value : Bool?, fallback : Bool) -> Bool` helper in `types.mbt`.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS for B smoke.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Assemble lambda grammar IR syntax grammar"`.

### Task 9: Build Persistent A-vs-B Oracle Harness

**Files:** `examples/lambda/src/spike/oracle.mbt`, `examples/lambda/src/spike/fixtures.mbt`, `examples/lambda/src/spike/oracle_test.mbt`

**Interfaces:**

- Consumes `pub let lambda_grammar : @loom.Grammar[@token.Token, @syntax.SyntaxKind, @ast.Term]` and its PUBLIC read-only fields `.spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind]` and `.lex : (String) -> @core.LexResult[@token.Token]`. (`Grammar`'s fields are `pub`/read-only cross-package — `loom/src/grammar.mbt` — so the spike reads A's spec + lex WITHOUT importing the private `lambda_spec` binding.) Do **NOT** use `Grammar::to_syntax_grammar()` for A: it copies A's incremental config (`incremental_relex_enabled=false`, `block_reparse_spec=Some(...)`), which is a confound that must be normalized away.
- Consumes `pub fn normalized_syntax_grammar(...)` (Task 8) — both A and B are built through it so the ONLY difference is `parse_root`.
- Consumes `pub fn[T : Eq + @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] new_syntax_parser(String, SyntaxGrammar[T, K], runtime? : @cells.Runtime) -> @pipeline.SyntaxParser`.
- Consumes `pub fn SyntaxParser::apply_edit(Self, @core.Edit, String) -> Unit`.
- Consumes `pub fn SyntaxParser::snapshot(Self) -> @cells.Derived[SyntaxSnapshot]`.
- Consumes `pub fn[T, K] SyntaxGrammar::parse_cst(Self[T, K], String) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError`.
- Consumes `pub fn @core.tree_diff(@seam.CstNode, @seam.CstNode) -> Array[@core.Edit]` (from `@core`, NOT `@loom`).
- Consumes `pub fn[Id] ProjectionIdentityTracker::new() -> Self[Id]`.
- Consumes `pub fn[Id] ProjectionIdentityTracker::realign_success(Self[Id], String, Array[ProjectionLeaf], (ProjectionLeaf) -> Id, edit? : Edit) -> Array[StableProjectionLeaf[Id]]`.
- Consumes `pub fn[Id] ProjectionIdentityTracker::commit_success(Self[Id], String, Array[StableProjectionLeaf[Id]]) -> Unit`.
- Consumes `pub fn[Id] ProjectionIdentityTracker::record_failed_input(Self[Id], String, source_before_edit? : String, edit? : Edit) -> Unit`.
- Consumes `pub fn ProjectionStringIdAllocator::new((String, Int) -> String) -> Self`.
- Consumes `pub fn ProjectionStringIdAllocator::allocate(Self, ProjectionLeaf) -> String`.
- Produces `pub struct EditStep { label : String; before : String; after : String; edit : @core.Edit } derive(Debug)`.
- Produces `pub struct OracleStepResult { label : String; d1_ok : Bool; d2a_ok : Bool; d2b_ok : Bool; reuse_parity_ok : Bool; diagnostics_empty : Bool; a_reuse_count : Int; b_reuse_count : Int } derive(Debug, Eq)`.
- Produces `pub fn run_oracle_fixture(initial : String, steps : Array[EditStep], b : @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind]) -> Array[OracleStepResult]`.

- [ ] Write failing tests for a fixture sequence with at least one valid edit, one malformed intermediate, and one recovery edit. The test must assert that each `OracleStepResult` has `d1_ok`, `d2a_ok`, `d2b_ok`, and `reuse_parity_ok`.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because the oracle harness is missing.
- [ ] Build A's and B's grammars through the SAME normalizer so only `parse_root` differs: `let a_grammar = normalized_syntax_grammar(@lambda.lambda_grammar.spec, @lambda.lambda_grammar.lex)` and `let b_grammar = build_b_syntax_grammar()` (which also calls `normalized_syntax_grammar`). Do NOT use `@lambda.lambda_grammar.to_syntax_grammar()` — it would give A `incremental_relex_enabled=false` + `block_reparse_spec=Some(...)` while B gets the normalized config, so newline/BlockExpr edits would diverge on config, not `parse_root`.
- [ ] Implement one persistent `SyntaxParser` for A (`@loom.new_syntax_parser(initial, a_grammar)`) and one for B (`@loom.new_syntax_parser(initial, b_grammar)`), both seeded from the same initial source.
- [ ] On every step, call `a_parser.apply_edit(step.edit, step.after)` and `b_parser.apply_edit(step.edit, step.after)`, then read `parser.snapshot().read_or_abort()`.
- [ ] Assert D1 for both A and B by fresh parsing the same source with each parser's grammar and checking `@core.tree_diff(snapshot.syntax.cst_node(), fresh_cst)` empty and `snapshot.diagnostics == fresh_diagnostics` (FULL `==` is correct here: D1 is same-impl incremental-vs-fresh, so message strings must match exactly).
- [ ] Assert D2a structurally. CST: `@core.tree_diff(a_snapshot.syntax.cst_node(), b_snapshot.syntax.cst_node())` empty. Diagnostics: do NOT use full `==` (cross-impl B need not reproduce A's exact wording). Instead zip `a_snapshot.diagnostics.items()` and `b_snapshot.diagnostics.items()` and compare the STRUCTURAL fields pairwise — `source`, `severity`, `code`, and `primary` (the `TextRange?`) — plus equal `length()`. A `message`-string-only difference is NOT a D2a structural divergence: record it as a SEPARATE low-priority `ReplicationResidual` (message wording), so a structural finding (different code/range/severity/count) is never masked by, nor confused with, error-text wording noise. (The D2b success/failure classification still keys off `is_empty()`/count, which is unaffected by this split.)
- [ ] Implement a small spike-local helper `diagnostics_structurally_equal(a : @core.DiagnosticSet, b : @core.DiagnosticSet) -> Bool` over `Diagnostic`'s public fields (`source`, `severity`, `code`, `primary`), and a `message_strings_equal(...)` companion for the residual classification.
- [ ] Assert D2b by extracting leaves from each snapshot's CST with `project_lambda_leaves`, driving separate `ProjectionIdentityTracker[String]` and `ProjectionStringIdAllocator` instances identically, and comparing emitted `Array[@core.StableProjectionLeaf[String]]` every step.
- [ ] Apply malformed-intermediate classification exactly: if shared diagnostics are non-empty, call `tracker.record_failed_input(source, source_before_edit=before, edit=edit)` and do not commit; if empty, call `tracker.realign_success(source, leaves, leaf => alloc.allocate(leaf), edit=edit)` then `tracker.commit_success(source, stable)`.
- [ ] **Record what D2b does and does NOT prove in this harness (honesty scoping — required; carry it into the results doc).** Because both trackers are fed the SAME edits and the SAME success/failure classification (derived from shared, D2a-equal diagnostics) and `project_lambda_leaves` is a deterministic function of each CST, a D2b A-vs-B mismatch under target (i) *implies* a D2a mismatch — so **D2b is not an independent discriminator of path-dependent last-good churn as wired.** Its genuinely-independent residual is the **hash-collision blind spot**: `tree_diff` returns early on equal `CstNode.hash` (`diff.mbt:12`), so a hash collision makes D2a report empty-diff on structurally-different trees, which the leaf extraction then sees through. Keep D2b for exactly two reasons: (1) the hash-collision guard, and (2) a direct assertion of the consumer-facing stable-ID invariant. Do NOT claim it independently proves "no last-good / authoring-cache churn" under (i). The genuinely-independent path-dependence test requires driving the tracker with consumer-style INDEPENDENT baseline/edit bookkeeping (not shared variables) — that belongs to the real-consumer / projectional-language follow-up gate (Task 13), not this lambda spike.
- [ ] Assert REUSE-PARITY every step with `a_snapshot.reuse_count == b_snapshot.reuse_count`.
- [ ] Add fixture builders for LetDef, ParamList churn, App/Bop Pratt, deliberate error/incomplete input, and top-level reuse.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS or classified oracle failures to be handled by Task 11.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Add persistent lambda parser parity oracle"`.

### Task 10: Add Crippled-B Positive Control For Reuse-Parity

**Files:** `examples/lambda/src/spike/lambda_ir.mbt`, `examples/lambda/src/spike/reuse_positive_control_test.mbt`

**Interfaces:**

- Consumes `pub fn build_b_syntax_grammar(cripple_reuse? : Bool) -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind]`.
- Consumes `pub fn run_oracle_fixture(initial : String, steps : Array[EditStep], b : @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind]) -> Array[OracleStepResult]`.
- Produces no new public API.

- [ ] Write the positive-control test before implementation: build crippled B with `build_b_syntax_grammar(cripple_reuse=true)`, run the top-level-edit fixture, and assert D1/D2a/D2b all pass while at least one `reuse_parity_ok` is false.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because crippled B is not selectable or does not diverge on reuse.
- [ ] Implement the cripple flag so IR repetition omits `ctx.try_reuse_repeat_group()` only for the positive-control grammar.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS and prove the detector catches the central mechanism risk.
- [ ] If crippled B does not fail reuse-parity while passing D1/D2a/D2b, stop and record "reuse-parity detector unproven"; do not proceed to GO.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Calibrate reuse parity oracle with crippled B"`.

### Task 11: Add Divergence Classifier And Stop Condition

**Files:** `examples/lambda/src/spike/types.mbt`, `examples/lambda/src/spike/oracle.mbt`, `examples/lambda/src/spike/divergence_classifier_test.mbt`

**Interfaces:**

- Consumes `pub struct OracleStepResult { label : String; d1_ok : Bool; d2a_ok : Bool; d2b_ok : Bool; reuse_parity_ok : Bool; diagnostics_empty : Bool; a_reuse_count : Int; b_reuse_count : Int } derive(Debug, Eq)`.
- Produces `pub enum DivergenceClass { NoDivergence; ReplicationResidual(String); WrongModelStop(String) } derive(Eq, Debug)`.
- Produces `pub fn classify_divergence(result : OracleStepResult, requires_imperative_escape_hatch : Bool, note : String) -> DivergenceClass`.
- Produces `pub fn classify_reuse_parity(result : OracleStepResult, reuse_delta : Int, frame_boundary_explained : Bool, note : String) -> DivergenceClass`.

- [ ] Write failing tests for three classifications: all checks pass → `NoDivergence`; D2a fails but the note says the CST shape can be matched by declarative IR → `ReplicationResidual`; any safety divergence requiring lambda-specific imperative escape-hatch code → `WrongModelStop`.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because classifier is missing.
- [ ] Implement the classifier as the written stop rule: a divergence is "replication residual" if B can match A within the declarative IR model; it is "wrong model → STOP and report unsuitable" if matching A requires lambda-specific imperative escape-hatch code.
- [ ] Write failing tests for `classify_reuse_parity`, which MUST distinguish the two collapsed cases a scalar `reuse_count` delta hides: (a) a SMALL, frame-boundary-explained delta where B reuses at a slightly different granularity but still drives `try_reuse_repeat_group` → `ReplicationResidual` (the IR's frame boundaries can be re-aligned to A's `node`/`wrap_at`/repeat-group boundaries within the declarative model); (b) a LARGE/systematic delta where B's count stays at the no-reuse floor on a top-level edit (B structurally cannot drive loom's repeat-group reuse) → `WrongModelStop`. The crippled-B positive control (Task 10) is the calibration anchor for case (b); a benign 1-frame difference is case (a). Without this, the 4th oracle check halts/passes without a principle.
- [ ] Implement `classify_reuse_parity`: `reuse_delta == 0` → `NoDivergence`; `frame_boundary_explained == true` (small, attributable to a re-alignable frame boundary) → `ReplicationResidual(note)`; otherwise (B at the no-reuse floor / unattributable systematic gap) → `WrongModelStop(note)`. Record the chosen `frame_boundary_explained` rationale per fixture in the results doc — do NOT auto-pass any reuse delta silently (no-silent-caps).
- [ ] Wire oracle tests so every divergence result (safety AND reuse-parity) is accompanied by a classification note before the final decision task.
- [ ] Treat the ParamList separated-list divergence as a required classified finding if it occurs: target A's exact shape first, then classify any residual D2a mismatch instead of hiding it.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Classify parser generation spike divergences"`.

### Task 12: Measure E1 And E2 Ergonomics

**Files:** `examples/lambda/src/spike/measurements.mbt`, `examples/lambda/src/spike/measurements_test.mbt`, `docs/analysis/2026-06-20-parser-generation-spike-results.md`

**Interfaces:**

- Produces `pub struct ErgonomicsMeasurement { e1_ir_lines : Int; e1_hand_slice_lines : Int; e1_full_parser_upper_reference_lines : Int; e2_lambda_escape_hatch_lines : Int; e2_loomgen_escape_hatch_lines : Int; notes : Array[String] } derive(Eq, Debug)`.
- Produces `pub fn ergonomics_measurement_template() -> ErgonomicsMeasurement`.

- [ ] Write failing tests that assert `e1_full_parser_upper_reference_lines == 814` and that notes include the transliteration-bias caveat.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because measurement template is missing.
- [ ] Implement `ergonomics_measurement_template` with placeholders represented as explicit `0` values plus notes that instruct the final worker to fill measured line counts before decision.
- [ ] Measure E1 honestly against the equivalent slice of `examples/lambda/src/cst_parser.mbt`, not the full 814-line file. Record 814 only as full-parser upper reference.
- [ ] Record E1 caveat: writing IR while looking at A understates from-scratch authoring cost; do not over-trust E1.
- [ ] Measure E2 as lambda-specific imperative code in the IR/interpreter beyond the declarative model. Include lines required to reproduce `ParamList`, recovery ownership, and Pratt quirks if they are not general IR features.
- [ ] Account for the IR's closure fields (the `fn(@token.Token) -> Bool` predicates and `ManualParamList`). Classify each as either a GENERAL IR feature (a reusable token-predicate combinator, does not count against E2) or a LAMBDA-SPECIFIC escape hatch (hand-written imperative logic the declarative model could not express, counts against E2). Record the split explicitly — this is the boundary the GO decision hinges on, since closures that are really escape hatches are exactly "hand-writing with extra steps."
- [ ] Apply E2 to loomgen plumbing too: record `views.mbt` judgment-residue examples from doc §4.5 as Layer 1 E2 evidence, but do not build loomgen in this spike.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike docs/analysis/2026-06-20-parser-generation-spike-results.md && git commit -m "Measure parser generation ergonomics gates"`.

### Task 13: Record E3 Second-Grammar Reuse Probe Without Building The Follow-Up Language

**Files:** `examples/lambda/src/spike/measurements.mbt`, `docs/analysis/2026-06-20-parser-generation-spike-results.md`

**Interfaces:**

- Produces `pub struct ReuseProbePlan { vehicle : String; e3_measurement : String; projectional_follow_up_gate : String; built_in_this_spike : Bool } derive(Eq, Debug)`.
- Produces `pub fn e3_follow_up_gate() -> ReuseProbePlan`.

- [ ] Write failing test that asserts `e3_follow_up_gate().built_in_this_spike == false` and that the vehicle text names a second, more projectional/CRDT language.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because E3 gate artifact is missing.
- [ ] Implement `e3_follow_up_gate` to document one shared vehicle with separate gates: safety-sprawl via D2a, ergonomics-sprawl via E1/E2, and reuse via E3 marginal authoring cost.
- [ ] In the results doc, state lambda validates mechanism and oracle only; it does not retire §8 projectional escape-hatch-sprawl risk.
- [ ] In the results doc, require the second language before B graduates from hypothesis to target.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike docs/analysis/2026-06-20-parser-generation-spike-results.md && git commit -m "Document second grammar reuse gate"`.

### Task 14: Fill Decision Document And Index

**Files:** `docs/analysis/2026-06-20-parser-generation-spike-results.md`, `docs/README.md`

**Interfaces:**

- Consumes all results from Tasks 9-13.
- Produces final written decision template with fields: safety summary, D1, D2a, D2b, REUSE-PARITY, positive control, divergence classifications, equivalence-bar call, E1, E2, E3, projectional-language follow-up gate, and GO/NO-GO.

- [ ] Create or fill `docs/analysis/2026-06-20-parser-generation-spike-results.md`:

```md
# Parser-Generation Spike Results

**Date:** 2026-06-20
**Status:** Evidence record

## Safety

- D1:
- D2a:
- D2b:
- REUSE-PARITY:
- Crippled-B positive control:

## Divergences

| Fixture | Check | Classification | Evidence | Stop? |
| --- | --- | --- | --- | --- |

## Equivalence Bar

- Targeted bar: (i) structurally identical to A.
- Result:
- If not (i), migration implication for bar (ii):

## Ergonomics

- E1:
- E1 caveats:
- E2 lambda:
- E2 loomgen plumbing:
- E3:

## Projectional Follow-Up Gate

- Vehicle:
- Safety-sprawl measurement:
- Ergonomics-sprawl measurement:
- Reuse measurement:

## Decision

- Safety gate:
- Ergonomics gate:
- GO/NO-GO:
- Rationale:
```

- [ ] Update `docs/README.md` Analysis section with a link to the results document.
- [ ] Run `cd examples/lambda && moon info && moon fmt`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon -C examples/lambda fmt --check`; expect PASS.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Decide ADR/no-ADR at plan closure time. Expected rule: if the spike chooses not to implement grammar-as-data, creates a reusable policy, or changes the parser-generation roadmap, create an ADR; if it only records inconclusive evidence, add `No ADR needed:` with the reason when archiving.
- [ ] Commit: `git add docs/analysis/2026-06-20-parser-generation-spike-results.md docs/README.md && git commit -m "Record parser generation spike decision"`.

## Self-Review

Spec coverage:

- D1: Task 9 asserts every step against fresh parses for both A and B.
- D2a: Task 9 asserts every step with `tree_diff` and diagnostic equality.
- D2b: Tasks 1 and 9 define shared leaves and run tracker/allocator every step, including malformed intermediates. Task 9 also records the honesty scoping: under target (i) D2b is not an independent path-dependence discriminator (shared edits/commits collapse it to D2a); its independent residual is the `tree_diff` hash-collision blind spot + a direct consumer-invariant assertion. Genuine independence is deferred to the consumer-style follow-up (Task 13).
- REUSE-PARITY: Tasks 5, 9, 10, and 11 lower repetition to reuse, assert counter parity every step, prove the detector fires with crippled B (positive control), and classify a reuse delta as frame-boundary `ReplicationResidual` vs no-reuse-floor `WrongModelStop` (so the scalar counter halts/passes on a principle, not silently).
- Grammar IR + interpreter: Tasks 2-8 define IR, core interpreter, Pratt, top-level reuse, ParamList, recovery, and B grammar assembly.
- Fixtures: Task 9 covers LetDef, ParamList churn, Pratt App/Bop, deliberate malformed input, recovery, top-level reuse, and positive-control input.
- Stop condition: Task 11 defines `DivergenceClass` and the explicit wrong-model stop rule.
- Follow-up gate: Task 13 documents the second projectional/CRDT language as required before graduation.
- E1: Task 12 measures IR authoring cost against equivalent hand-code slice and records 814 only as full-parser upper reference.
- E2: Task 12 measures lambda escape-hatch lines and loomgen plumbing judgment residue separately.
- E3: Task 13 records the second-grammar marginal authoring-cost probe as a separate measurement sharing the follow-up vehicle.
- GO: Task 14 records safety AND ergonomics as an explicit conjunction.

Placeholder scan:

- No task may leave `TBD`, "similar to", or "add error handling" placeholders in code edits.
- Measurement templates may start with explicit zero values only when accompanied by a required later step to replace them before decision.
- The final results document starts as a template in Task 14 but is not a completed deliverable until all fields are filled.

Type-consistency check:

- All loom, pipeline, core, seam, lexer, lambda, token, and syntax signatures named above are copied from the verified API surface.
- Every non-verified function/type named in tasks is explicitly produced as a spike-local artifact in `examples/lambda/src/spike/`.
- A is reached only through public API: its parse logic via `@lambda.lambda_grammar.spec` / `.lex` (public read-only `Grammar` fields) wrapped by `normalized_syntax_grammar`, plus `@lambda.parse_cst` for fresh-parse comparisons. NOT via `to_syntax_grammar()` (config confound) and never via the private `lambda_spec`.
- A and B grammars are BOTH built through `normalized_syntax_grammar` (`incremental_relex_enabled=false`, `block_reparse_spec=None`), so the only difference is `parse_root` (A = `lambda_grammar.spec.parse_root`; B = the spike interpreter closure via `@core.LanguageSpec::new(...)`).
- All CST comparisons call `@core.tree_diff` (in `dowdiness/loom/core`), never `@loom.tree_diff` (unbound on the facade).
- No task imports package-private `lambda_spec` or `parse_lambda_root`.
