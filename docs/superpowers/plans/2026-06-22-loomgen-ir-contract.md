# loomgen IR Contract Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Status:** Complete — all 10 tasks implemented on branch `feat/loomgen-ir-contract` (commits `999d555`..`a4ec9ba`), pending PR. The `dowdiness/loom/grammar` package ships the generic `[T,K]` IR + `Pred[T]` + tree-walking interpreter; the lambda spike drives B through the reified IR + a spike-local probe; D1/D2a/D2b re-validated on the reified IR (lambda spike 67/67, @grammar 17/17).

**Decision record:** The design decision is recorded in [the design spec](../specs/2026-06-21-loomgen-ir-contract-design.md); its §5.3 was corrected at execution with the two-residue accounting (`ManualNewlineAppExpr` **and** atom-position error recovery — §5.1 predicted only the former). Execution deltas from the plan: Tasks 7+8 merged (the probe holds the newline residue, so the baseline never went red); `ManualBlockDelimiterCheck` reified via `RequireSep`/grown vocabulary rather than `CountedRepeat`, which was removed in Task 10 as a superseded, consumerless node. No separate ADR — this is spike-stage-1 of the loomgen direction already tracked by [analysis/2026-06-20-parser-generation-direction.md](../../analysis/2026-06-20-parser-generation-direction.md); a finalizing ADR is warranted only when `@grammar` is consumed by a production parser (deferred).

**Goal:** Build the minimal `loom/src/grammar/` IR contract from the approved loomgen design: generic `[T,K]` grammar data, reified predicates, dense rule-slot interpretation, a tree-walking interpreter, lambda spike migration, and fresh D1/D2a/D2b oracle validation.

**Architecture:** Add a new one-way `dowdiness/loom/grammar` package that depends on `dowdiness/loom/core` and produces only `parse_root : (@core.ParserContext[T,K]) -> Unit` closures for existing `@core.LanguageSpec`. The engine remains unaware of the IR. Lambda consumes the new package by replacing its spike-local closure IR with reified generic data and re-running the parity oracle. The committed backend is only the tree-walking interpreter.

**Tech Stack:** MoonBit 0.10.0+84519ca0a; packages `dowdiness/loom/grammar`, `dowdiness/loom/core`, `dowdiness/lambda/spike`, `@lambda`, `@token`, `@syntax`, `@lexer`, `@loom`, `@core`, `@seam`, `@pipeline`, `@cells`.

## Global Constraints

- MoonBit (moonbit-base conventions)
- `moon check` after every edit
- `moon test -p <pkg>` for affected package
- `moon info && moon fmt` before commit
- TDD (failing test FIRST, run it red, minimal impl, run green, commit)
- one-way `grammar→core`
- no `Opaque` predicate
- minimal contract (non-goals fenced)

Non-goals fenced:

```text
- No author-facing grammar spec format.
- No AST/Term derivation.
- No Layer-1 plumbing codegen.
- No L1-A RawKind registry fix.
- No analyzing/table-driven interpreter.
- No code emitter.
- No block-reparse or incremental-relex parity expansion.
```

---

## Verified API Surface

Use these signatures exactly. They are verified against `loom/src/core/pkg.generated.mbti`.

```moonbit
pub struct LanguageSpec[T, K] {
  whitespace_kind : K
  error_kind : K
  incomplete_kind : K
  root_kind : K
  eof_token : T
  parse_root : (ParserContext[T, K]) -> Unit
  reuse_size_threshold : Int
}
pub fn[T, K] LanguageSpec::new(K, K, K, T, incomplete_kind? : K, parse_root? : (ParserContext[T, K]) -> Unit, reuse_size_threshold? : Int) -> Self[T, K]

pub struct ParserContext[T, K] {
  // private fields
}
pub fn[T : Eq + @seam.IsTrivia, K] ParserContext::at(Self[T, K], T) -> Bool
pub fn[T : @seam.IsTrivia + @seam.IsEof, K] ParserContext::at_eof(Self[T, K]) -> Bool
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::emit_token(Self[T, K], K) -> Unit
pub fn[T, K : @seam.ToRawKind] ParserContext::emit_error_placeholder(Self[T, K]) -> Unit
pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::expect(Self[T, K], T, K) -> Bool
pub fn[T, K] ParserContext::finish_node(Self[T, K]) -> Unit
pub fn[T, K] ParserContext::mark(Self[T, K]) -> Int
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::node(Self[T, K], K, () -> Unit) -> Unit
pub fn[T : @seam.IsTrivia, K] ParserContext::peek(Self[T, K]) -> T
pub fn[T : @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] ParserContext::skip_until(Self[T, K], (T) -> Bool) -> Int
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::try_reuse_repeat_group(Self[T, K]) -> Bool
pub fn[T, K : @seam.ToRawKind] ParserContext::wrap_at(Self[T, K], Int, K, () -> Unit) -> Unit
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::error(Self[T, K], String) -> Unit
```

The lambda spike files are absent in this checkout, but exist on `origin/main`. Use the prompt's embedded verified spike IR as the source of truth when porting `examples/lambda/src/spike/*.mbt`.

### Task 1: Scaffold `loom/src/grammar`

**Files**

- Create `loom/src/grammar/moon.pkg`
- Create `loom/src/grammar/pred.mbt`
- Create `loom/src/grammar/pred_test.mbt`

**Interfaces**

- Consumes `dowdiness/loom/core` as `@core`.
- Produces `pub enum Pred[T] { Any; IsToken(T); OneOf(Array[T]); Not(Pred[T]) } derive(Eq, Debug)`.
- Produces `pub fn[T : Eq] Pred::test(Self[T], T) -> Bool`.

- [ ] Write `loom/src/grammar/moon.pkg`:

```moonbit
import {
  "dowdiness/loom/core",
  "dowdiness/seam",
  "moonbitlang/core/debug",
}
```

- [ ] Run `moon check`; expect FAIL because the new package has no test target yet is acceptable only until the failing test is added.

```text
$ moon check
expect: no type errors from package discovery
```

- [ ] Write failing tests in `loom/src/grammar/pred_test.mbt`:

```moonbit
test "Pred::test covers primitive predicate vocabulary" {
  inspect(Pred::Any.test(1), content="true")
  inspect(Pred::IsToken(2).test(2), content="true")
  inspect(Pred::IsToken(2).test(3), content="false")
  inspect(Pred::OneOf([1, 3, 5]).test(3), content="true")
  inspect(Pred::OneOf([1, 3, 5]).test(2), content="false")
  inspect(Pred::Not(Pred::IsToken(4)).test(5), content="true")
  inspect(Pred::Not(Pred::IsToken(4)).test(4), content="false")
}
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect FAIL because `Pred` is missing.

```text
$ moon test -p dowdiness/loom/grammar
expect: FAIL, unbound type or constructor Pred
```

- [ ] Implement `loom/src/grammar/pred.mbt`:

```moonbit
pub enum Pred[T] {
  Any
  IsToken(T)
  OneOf(Array[T])
  Not(Pred[T])
} derive(Eq, @debug.Debug)

pub fn[T : Eq] Pred::test(self : Self[T], token : T) -> Bool {
  match self {
    Any => true
    IsToken(expected) => token == expected
    OneOf(tokens) => tokens.any(t => t == token)
    Not(inner) => !inner.test(token)
  }
}
```

- [ ] Run `moon check`; expect PASS.

```text
$ moon check
expect: PASS
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect PASS.

```text
$ moon test -p dowdiness/loom/grammar
expect: PASS
```

- [ ] Run `moon info && moon fmt`; expect PASS and generated interface includes only `Pred` and `Pred::test`.

```text
$ moon info && moon fmt
expect: PASS
```

- [ ] Commit: `git add loom/src/grammar && git commit -m "Add grammar predicate contract"`.

### Task 2: Define Generic Grammar IR Data

**Files**

- Modify `loom/src/grammar/pred.mbt`
- Create `loom/src/grammar/ir.mbt`
- Create `loom/src/grammar/ir_test.mbt`

**Interfaces**

- Consumes `Pred[T]`.
- Produces `pub type RuleName = String`.
- Produces `pub enum Expr[T,K]`.
- Produces `pub struct Alt[T,K]`.
- Produces `pub struct GrammarIr[T,K]`.
- Produces `pub fn[T,K] GrammarIr::GrammarIr(Map[RuleName, Expr[T,K]], root~ : RuleName) -> GrammarIr[T,K]`.
- Produces `pub fn[T,K] GrammarIr::root(Self[T,K]) -> RuleName`.
- Produces `pub fn[T,K] GrammarIr::rules(Self[T,K]) -> Map[RuleName, Expr[T,K]]`.

- [ ] Write failing tests in `loom/src/grammar/ir_test.mbt`:

```moonbit
test "GrammarIr stores open string rule namespace" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Ref("expr"),
    "expr": Expr::Empty,
  }
  let ir = GrammarIr::GrammarIr(rules, root="source")
  inspect(ir.root(), content="source")
  match ir.rules()["expr"] {
    Some(Expr::Empty) => ()
    _ => fail("expected expr rule")
  }
}

test "IR has no closure predicate escape hatch" {
  let alt = Alt::Alt(starts=Pred::IsToken(1), body=Expr::Empty)
  match alt.starts() {
    Pred::IsToken(1) => ()
    _ => fail("expected reified start predicate")
  }
}
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect FAIL because `GrammarIr`, `Expr`, `Alt`, and `RuleName` are missing.

```text
$ moon test -p dowdiness/loom/grammar
expect: FAIL, unbound type GrammarIr
```

- [ ] Implement `loom/src/grammar/ir.mbt`:

```moonbit
pub type RuleName = String

pub enum Expr[T, K] {
  Node(K, Expr[T, K])
  Emit(T, K)
  Expect(T, K, String)
  Ref(RuleName)
  Choice(Array[Alt[T, K]])
  RepeatTopLevel(RuleName, Pred[T], Expr[T, K])
  Seq(Array[Expr[T, K]])
  PrattApp(RuleName, K, Pred[T])
  PrattBinary(RuleName, K, Array[(T, K)])
  RepeatWhile(Pred[T], Expr[T, K])
  WrapIfNext(K, Pred[T], Expr[T, K])
  CountedRepeat(Pred[T], Expr[T, K], min~ : Int, missing_message~ : String?)
  EmitError(String)
  ErrorUntil(Pred[T], String)
  ManualNewlineAppExpr
  Empty
} derive(Eq, @debug.Debug)

pub struct Alt[T, K] {
  starts : Pred[T]
  body : Expr[T, K]
} derive(Eq, @debug.Debug)

pub fn[T, K] Alt::Alt(starts~ : Pred[T], body~ : Expr[T, K]) -> Self[T, K] {
  { starts, body }
}

pub fn[T, K] Alt::starts(self : Self[T, K]) -> Pred[T] {
  self.starts
}

pub fn[T, K] Alt::body(self : Self[T, K]) -> Expr[T, K] {
  self.body
}

pub struct GrammarIr[T, K] {
  rules : Map[RuleName, Expr[T, K]]
  root : RuleName
} derive(Eq, @debug.Debug)

pub fn[T, K] GrammarIr::GrammarIr(rules : Map[RuleName, Expr[T, K]], root~ : RuleName) -> Self[T, K] {
  { rules, root }
}

pub fn[T, K] GrammarIr::rules(self : Self[T, K]) -> Map[RuleName, Expr[T, K]] {
  self.rules
}

pub fn[T, K] GrammarIr::root(self : Self[T, K]) -> RuleName {
  self.root
}
```

- [ ] Run `moon check`; expect PASS.

```text
$ moon check
expect: PASS
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect PASS.

```text
$ moon test -p dowdiness/loom/grammar
expect: PASS
```

- [ ] Run `moon info && moon fmt`; expect PASS and generated interface exposes the generic IR.

```text
$ moon info && moon fmt
expect: PASS
```

- [ ] Commit: `git add loom/src/grammar && git commit -m "Define generic grammar IR contract"`.

### Task 3: Resolve Rules To Dense Slots

**Files**

- Create `loom/src/grammar/compile.mbt`
- Create `loom/src/grammar/compile_test.mbt`

**Interfaces**

- Consumes `GrammarIr[T,K]`, `Expr[T,K]`, `Alt[T,K]`, and `RuleName`.
- Produces `pub suberror GrammarCompileError { MissingRoot(RuleName); MissingRef(RuleName); DuplicateRule(RuleName) }`.
- Produces `pub struct CompiledGrammar[T,K]`.
- Produces `pub fn[T,K] compile(GrammarIr[T,K]) -> CompiledGrammar[T,K] raise GrammarCompileError`.
- Produces `pub fn[T,K] CompiledGrammar::root_slot(Self[T,K]) -> Int`.
- Produces `pub fn[T,K] CompiledGrammar::rule(Self[T,K], Int) -> CompiledExpr[T,K]`.
- Produces `pub enum CompiledExpr[T,K]` with `RefSlot(Int)` instead of `Ref(RuleName)`.

- [ ] Write failing tests in `loom/src/grammar/compile_test.mbt`:

```moonbit
test "compile interns string rule refs to dense slots" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Ref("expr"),
    "expr": Expr::Emit(1, 10),
  }
  let compiled = compile(GrammarIr::GrammarIr(rules, root="source"))
  inspect(compiled.root_slot(), content="0")
  match compiled.rule(0) {
    CompiledExpr::RefSlot(1) => ()
    _ => fail("source should point at dense expr slot")
  }
}

test "compile rejects unresolved refs before parsing" {
  let rules : Map[RuleName, Expr[Int, Int]] = { "source": Expr::Ref("missing") }
  let result = try? compile(GrammarIr::GrammarIr(rules, root="source"))
  inspect(result, content="Err(MissingRef(\"missing\"))")
}
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect FAIL because `compile` is missing.

```text
$ moon test -p dowdiness/loom/grammar
expect: FAIL, unbound value compile
```

- [ ] Implement `CompiledExpr`, `CompiledAlt`, `CompiledGrammar`, and `compile`. Preserve author map order by first pushing the root rule, then the remaining rule names in deterministic sorted string order. Convert every nested `Expr::Ref(name)` to `CompiledExpr::RefSlot(slot)`. Reject every missing reference during compile.

```moonbit
pub suberror GrammarCompileError {
  MissingRoot(RuleName)
  MissingRef(RuleName)
  DuplicateRule(RuleName)
} derive(Eq, @debug.Debug)

pub enum CompiledExpr[T, K] {
  Node(K, CompiledExpr[T, K])
  Emit(T, K)
  Expect(T, K, String)
  RefSlot(Int)
  Choice(Array[CompiledAlt[T, K]])
  RepeatTopLevel(Int, Pred[T], CompiledExpr[T, K])
  Seq(Array[CompiledExpr[T, K]])
  PrattApp(Int, K, Pred[T])
  PrattBinary(Int, K, Array[(T, K)])
  RepeatWhile(Pred[T], CompiledExpr[T, K])
  WrapIfNext(K, Pred[T], CompiledExpr[T, K])
  CountedRepeat(Pred[T], CompiledExpr[T, K], min~ : Int, missing_message~ : String?)
  EmitError(String)
  ErrorUntil(Pred[T], String)
  ManualNewlineAppExpr
  Empty
} derive(Eq, @debug.Debug)

pub struct CompiledAlt[T, K] {
  starts : Pred[T]
  body : CompiledExpr[T, K]
} derive(Eq, @debug.Debug)

pub struct CompiledGrammar[T, K] {
  names : Array[RuleName]
  rules : Array[CompiledExpr[T, K]]
  root_slot : Int
} derive(Eq, @debug.Debug)
```

- [ ] Run `moon check`; expect PASS.

```text
$ moon check
expect: PASS
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect PASS.

```text
$ moon test -p dowdiness/loom/grammar
expect: PASS
```

- [ ] Run `moon info && moon fmt`; expect PASS.

```text
$ moon info && moon fmt
expect: PASS
```

- [ ] Commit: `git add loom/src/grammar && git commit -m "Compile grammar rules to dense slots"`.

### Task 4: Interpret Core Expressions

**Files**

- Create `loom/src/grammar/interpreter.mbt`
- Create `loom/src/grammar/interpreter_test.mbt`

**Interfaces**

- Consumes `pub fn[T : Eq + @seam.IsTrivia, K] ParserContext::at(Self[T, K], T) -> Bool`.
- Consumes `pub fn[T : @seam.IsTrivia + @seam.IsEof, K] ParserContext::at_eof(Self[T, K]) -> Bool`.
- Consumes `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::emit_token(Self[T, K], K) -> Unit`.
- Consumes `pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::expect(Self[T, K], T, K) -> Bool`.
- Consumes `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::node(Self[T, K], K, () -> Unit) -> Unit`.
- Consumes `pub fn[T : @seam.IsTrivia, K] ParserContext::peek(Self[T, K]) -> T`.
- Produces `pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] interpret(GrammarIr[T,K]) -> ((@core.ParserContext[T,K]) -> Unit) raise GrammarCompileError`.
- Produces `pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] interpret_compiled(CompiledGrammar[T,K]) -> (@core.ParserContext[T,K]) -> Unit`.

- [ ] Write failing tests in `loom/src/grammar/interpreter_test.mbt` using a tiny local token/kind pair:

```moonbit
enum TestToken {
  Int
  EOF
} derive(Eq, Show, @debug.Debug)

impl @seam.IsTrivia for TestToken with is_trivia(self) { false }
impl @seam.IsEof for TestToken with is_eof(self) { self == TestToken::EOF }
impl @seam.ToRawKind for TestToken with to_raw(self) { match self { Int => 1; EOF => 0 } }

enum TestKind {
  Root
  IntToken
  Error
  Incomplete
} derive(Eq, Show, @debug.Debug)

impl @seam.ToRawKind for TestKind with to_raw(self) {
  match self {
    Root => 10
    IntToken => 11
    Error => 12
    Incomplete => 13
  }
}

test "interpret emits a token through LanguageSpec parse_root" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(TestKind::Root, Expr::Emit(TestToken::Int, TestKind::IntToken)),
  }
  let parse_root = interpret(GrammarIr::GrammarIr(rules, root="source"))
  let spec = @core.LanguageSpec::new(
    TestKind::Root,
    TestKind::Error,
    TestKind::Root,
    TestToken::EOF,
    incomplete_kind=TestKind::Incomplete,
    parse_root=parse_root,
  )
  let tokens = [@core.TokenInfo::new(TestToken::Int, 1), @core.TokenInfo::new(TestToken::EOF, 0)]
  let ctx = @core.ParserContext::new(tokens, "1", spec)
  parse_root(ctx)
  inspect(true, content="true")
}
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect FAIL because `interpret` is missing.

```text
$ moon test -p dowdiness/loom/grammar
expect: FAIL, unbound value interpret
```

- [ ] Implement `interpret`, `interpret_compiled`, and private `run_expr` for `Empty`, `Emit`, `Expect`, `Node`, `RefSlot`, `Choice`, `Seq`, `RepeatWhile`, `EmitError`, and `ErrorUntil`. Resolve `Expect`'s message by wiring it: call `ctx.expect(tok, kind)`, and if it returns `false`, call `ctx.error(msg)` when `msg.length() > 0`.

```moonbit
pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] interpret(
  ir : GrammarIr[T, K]
) -> ((@core.ParserContext[T, K]) -> Unit) raise GrammarCompileError {
  interpret_compiled(compile(ir))
}

pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] interpret_compiled(
  grammar : CompiledGrammar[T, K]
) -> (@core.ParserContext[T, K]) -> Unit {
  ctx => run_expr(ctx, grammar, grammar.rule(grammar.root_slot()))
}
```

- [ ] Run `moon check`; expect PASS.

```text
$ moon check
expect: PASS
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect PASS.

```text
$ moon test -p dowdiness/loom/grammar
expect: PASS
```

- [ ] Run `moon info && moon fmt`; expect PASS.

```text
$ moon info && moon fmt
expect: PASS
```

- [ ] Commit: `git add loom/src/grammar && git commit -m "Interpret core grammar IR"`.

### Task 5: Add Incremental Parser Nodes

**Files**

- Modify `loom/src/grammar/interpreter.mbt`
- Create `loom/src/grammar/reuse_test.mbt`

**Interfaces**

- Consumes `pub fn[T, K] ParserContext::mark(Self[T, K]) -> Int`.
- Consumes `pub fn[T, K : @seam.ToRawKind] ParserContext::wrap_at(Self[T, K], Int, K, () -> Unit) -> Unit`.
- Consumes `pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] ParserContext::try_reuse_repeat_group(Self[T, K]) -> Bool`.
- Produces interpreter behavior for `RepeatTopLevel`, `WrapIfNext`, `PrattApp`, and `PrattBinary`.

- [ ] Write failing tests in `loom/src/grammar/reuse_test.mbt`:

```moonbit
test "WrapIfNext captures mark at runtime" {
  let expr : Expr[TestToken, TestKind] = Expr::WrapIfNext(
    TestKind::Root,
    Pred::IsToken(TestToken::Int),
    Expr::Emit(TestToken::Int, TestKind::IntToken),
  )
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = { "source": expr }
  let parse_root = interpret(GrammarIr::GrammarIr(rules, root="source"))
  let spec = @core.LanguageSpec::new(
    TestKind::Root,
    TestKind::Error,
    TestKind::Root,
    TestToken::EOF,
    incomplete_kind=TestKind::Incomplete,
    parse_root=parse_root,
  )
  let tokens = [@core.TokenInfo::new(TestToken::Int, 1), @core.TokenInfo::new(TestToken::EOF, 0)]
  let ctx = @core.ParserContext::new(tokens, "1", spec)
  parse_root(ctx)
  inspect(true, content="true")
}
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect FAIL because `WrapIfNext` is not interpreted.

```text
$ moon test -p dowdiness/loom/grammar
expect: FAIL, unsupported WrapIfNext
```

- [ ] Implement `WrapIfNext`: capture `let mark = ctx.mark()` before checking `pred.test(ctx.peek())`; when true, call `ctx.wrap_at(mark, kind, () => run_expr(ctx, grammar, body))`; otherwise run `body` directly.
- [ ] Implement `RepeatTopLevel`: loop while `!ctx.at_eof()` and `pred.test(ctx.peek())`; first try `ctx.try_reuse_repeat_group()`, otherwise run the compiled body. Do not carry the spike's `cripple_reuse` flag.
- [ ] Implement `PrattApp`: capture `mark`, run prefix by dense slot, then while the start predicate matches, wrap at the original mark and run another prefix.
- [ ] Implement `PrattBinary`: capture `mark`, run prefix by dense slot, then while the current token matches an operator table entry, emit the operator token and parse the next prefix under `ctx.wrap_at(mark, binary_kind, ...)`.

```moonbit
fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] op_kind(
  ops : Array[(T, K)],
  token : T,
) -> K? {
  for item in ops; found = None {
    guard found is None else { continue found }
    let (op, kind) = item
    if op == token {
      continue Some(kind)
    }
    continue found
  } nobreak {
    found
  }
}
```

- [ ] Run `moon check`; expect PASS.

```text
$ moon check
expect: PASS
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect PASS.

```text
$ moon test -p dowdiness/loom/grammar
expect: PASS
```

- [ ] Run `moon info && moon fmt`; expect PASS.

```text
$ moon info && moon fmt
expect: PASS
```

- [ ] Commit: `git add loom/src/grammar && git commit -m "Interpret incremental grammar nodes"`.

### Task 6: Add Lambda Vocabulary To `@grammar`

Code snippets in Tasks 6-10 are illustrative; executor fixes MoonBit surface details while preserving behavior (`min=_` patterns, manual `Show`, `@seam.RawKind(n)` wrapping, and generated interface spelling).

**Files**

- Modify `loom/src/grammar/ir.mbt`
- Modify `loom/src/grammar/compile.mbt`
- Modify `loom/src/grammar/interpreter.mbt`
- Create or modify blackbox `loom/src/grammar/*_test.mbt`

**Interfaces**

- Extends `pub enum Expr[T,K]` with `Fail`, `EmitOr`, `DiagnoseIf`, `ExpectSkip`, `ConsumeGated`, `RequireSep`, and `ErrorNodeUntil`.
- Extends `pub enum CompiledExpr[T,K]` and `lower()` with the same seven nodes, preserving `Ref` to `RefSlot(Int)` lowering.
- Enriches `RepeatTopLevel` from `(item, starts, tail)` to a delimiter-aware form such as `RepeatTopLevel(item : RuleName, starts : Pred[T], delim : Pred[T], delim_kind : K, between : Pred[T], between_msg : String, after_msg : String)`.
- Open question: keep this enriched signature or split a dedicated top-level node from the simpler `RepeatTopLevel`; either way, delimiter consumption after reuse hits is required.

- [ ] Write failing blackbox tests routed through `@core.parse_with(src, spec, lex, parse_root)` and `diagnostics.is_empty()`; one test per new node, plus one `RepeatTopLevel` reuse/delimiter test.
- [ ] For `Fail`, expect FAIL until the node calls `error(msg)` and `emit_error_placeholder()`.
- [ ] For `EmitOr(T,K,msg)`, expect FAIL until success emits `K` at `T` and failure emits the diagnostic placeholder.
- [ ] For `DiagnoseIf(Pred,msg)`, expect FAIL until matching `peek()` records a diagnostic without consuming.
- [ ] For `ExpectSkip(skip, skip_kind, expected, kind)`, expect FAIL until it delegates to `expect_after_skip(t => skip.matches(t), skip_kind, expected, kind)`.
- [ ] For `ConsumeGated(skip, skip_kind, lookahead)`, expect FAIL until it delegates to `consume_while_emit_if(t => skip.matches(t), skip_kind, t => lookahead.matches(t))`.
- [ ] For `RequireSep(skip, skip_kind, stop, alt, msg_alt, msg_else)`, expect FAIL until it consumes skip tokens with `consume_while_emit`, then emits `msg_alt` when `alt` matches or `msg_else` otherwise if no separator was present and `stop` is false.
- [ ] For `ErrorNodeUntil(error_kind, stop, msg)`, expect FAIL until it records `msg`, starts `error_kind`, bumps errors until `stop.matches(peek())`, and finishes the node; callers must guard EOF/stop with `Choice`.
- [ ] For enriched `RepeatTopLevel`, write the RED around `try_reuse_repeat_group()` followed by delimiter consumption, so a reused first definition does not prematurely exit before a later definition.
- [ ] Run `NEW_MOON_MOD=0 moon check -p src/grammar`; expect FAIL before implementation, then PASS after each node is implemented.
- [ ] Run `NEW_MOON_MOD=0 moon test -p dowdiness/loom/grammar`; expect each new RED to turn GREEN through `parse_with` + `is_empty`.
- [ ] Run `NEW_MOON_MOD=0 moon info && moon fmt`; expect PASS.
- [ ] Commit: `git add loom/src/grammar && git commit -m "Expand grammar IR contract"`.

### Task 7: Port Lambda Spike To `@grammar`

**Files**

- Modify `examples/lambda/src/spike/moon.pkg`
- Modify `examples/lambda/src/spike/types.mbt`
- Modify `examples/lambda/src/spike/lambda_ir.mbt`
- Modify `examples/lambda/src/spike/interpreter.mbt`
- Modify `examples/lambda/src/spike/*_test.mbt`

**Interfaces**

- Consumes `@grammar.Expr[@token.Token,@syntax.SyntaxKind]`, `@grammar.Pred[@token.Token]`, string `@grammar.RuleName`, and `@grammar.interpret`.
- Produces B grammar through the shared `@grammar` interpreter, not the spike-local closure IR.
- Deletes hand functions `parse_definition_ir`, `parse_param_list_exact`, `parse_block_delimiter_check`, and all `Manual*` dispatch arms except `ManualNewlineAppExpr` residue.

- [ ] Add `dowdiness/loom/grammar` to `examples/lambda/src/spike/moon.pkg`.
- [ ] Write a failing adapter test that parses `"let x = 1"` through `build_b_syntax_grammar()` and asserts `diagnostics.is_empty()`.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon test -p dowdiness/lambda/spike`; expect FAIL until B uses the shared IR.
- [ ] Replace spike-local `RuleId` with string rule names: `"source"`, `"definition"`, `"expression"`, `"binary"`, `"application"`, `"atom"`, and `"param_list"`.
- [ ] Rewrite all closure predicates to `@grammar.Pred::{Any,IsToken,OneOf,Not}`; do not add `Opaque` or host closures.
- [ ] Port `ManualParamList` to `WrapIfNext(ParamList, IsToken(LeftParen), Seq[Emit(LeftParen), Choice/RepeatWhile comma-loop, ExpectSkip(..., RightParen)])`; do not introduce `SeparatedList`.
- [ ] Port `ManualDefinition` to `Choice` over `Let` and `Fn` arms using `Node`, `Seq`, `EmitOr`, `DiagnoseIf`, `ExpectSkip`, `ConsumeGated`, and `Fail` as needed.
- [ ] Port `ManualBlockDelimiterCheck` to `RequireSep(IsToken(Newline), NewlineToken, OneOf([RBrace, EOF]), alt, msg_alt, msg_else)`.
- [ ] Move top-level trailing garbage out of `RepeatTopLevel` into source-rule composition with `Choice[Alt(EOF, Empty), Alt(Any, ErrorNodeUntil(ErrorNode, IsToken(EOF), msg))]`.
- [ ] Keep `parse_newline_app_expr` and `ManualNewlineAppExpr` only; delete all other `Manual*` constructors and dispatch.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon check -p dowdiness/lambda/spike`; expect PASS.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon test -p dowdiness/lambda/spike`; expect PASS or newline-only failures deferred to Task 8.
- [ ] Run `NEW_MOON_MOD=0 moon check -p src/grammar`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon test -p dowdiness/loom/grammar`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon info && moon fmt`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike loom/src/grammar && git commit -m "Port lambda spike to shared grammar IR"`.

### Task 8: Evidence-Gate `ManualNewlineAppExpr`

**Files**

- Modify `examples/lambda/src/spike/types.mbt`
- Modify `examples/lambda/src/spike/lambda_ir.mbt`
- Modify `examples/lambda/src/spike/interpreter.mbt`
- Modify `examples/lambda/src/spike/oracle.mbt`
- Create `examples/lambda/src/spike/newline_app_reification_test.mbt`

**Interfaces**

- Consumes `pub enum DivergenceClass { NoDivergence; ReplicationResidual(String); WrongModelStop(String) } derive(Eq, Debug)` from the spike, preserving this public shape.
- Produces one probe-only attempted reification for newline application.
- Produces one fallback branch that records residue and leaves lambda using the hand path if parity fails.

- [ ] Write failing oracle test in `examples/lambda/src/spike/newline_app_reification_test.mbt` that calls `run_newline_application_reification_probe()` and accepts `NoDivergence`, `ReplicationResidual`, or `WrongModelStop`.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon test -p dowdiness/lambda/spike`; expect FAIL because the probe is missing.
- [ ] Add a probe-only attempted reification using an interpreter mode stack, not a committed public `@grammar` feature; modes are exactly `AllowNewlineApplication` and `DisallowNewlineApplication`.
- [ ] Route recursive expression refs in the probe through the mode stack and compare only newline-application fixtures against the hand path.
- [ ] If D1/D2a/D2b pass for the probe, replace `ManualNewlineAppExpr` in `lambda_ir.mbt` with the reified expression and set `DivergenceClass::NoDivergence`.
- [ ] If any parity check fails, leave `ManualNewlineAppExpr` in `lambda_ir.mbt`, delete probe-only production dispatch, and record `DivergenceClass::ReplicationResidual("ManualNewlineAppExpr requires parameterized recursive mode")`.
- [ ] Do not add parameterized `Ref` or mode-stack machinery to `loom/src/grammar` in this task unless the probe passes all D1/D2a/D2b fixtures.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon check -p dowdiness/lambda/spike`; expect PASS.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon test -p dowdiness/lambda/spike`; expect PASS with either `NoDivergence` or recorded residue.
- [ ] Run `NEW_MOON_MOD=0 moon check -p src/grammar`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon test -p dowdiness/loom/grammar`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon info && moon fmt`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike loom/src/grammar && git commit -m "Classify newline application grammar residue"`.

### Task 9: Re-Validate D1/D2a/D2b Oracle

**Files**

- Modify `examples/lambda/src/spike/oracle.mbt`
- Modify `examples/lambda/src/spike/fixtures.mbt`
- Modify `examples/lambda/src/spike/oracle_test.mbt`
- Modify `examples/lambda/src/spike/measurements.mbt`

**Interfaces**

- Consumes A as lambda's normalized hand parser and B as the shared `@grammar` interpreter output.
- Consumes `@core.tree_diff(@seam.CstNode, @seam.CstNode) -> Array[@core.Edit]`.
- Consumes `pub fn[T : Eq + @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] @loom.new_syntax_parser(String, SyntaxGrammar[T,K], runtime? : @cells.Runtime) -> @pipeline.SyntaxParser`.
- Produces fresh reified-IR results for D1 fresh CST parity, D2a incremental-vs-full parity, and D2b projection identity parity.

- [ ] Rewrite the oracle setup so no PASS result is inherited from the closure spike; every comparison must run against the reified `@grammar` path.
- [ ] Write failing test `reified grammar IR passes D1 D2a D2b oracle or records residue` that asserts D1/D2a/D2b true and fails on `WrongModelStop`.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon test -p dowdiness/lambda/spike`; expect FAIL until the oracle calls the reified IR path.
- [ ] Port D1: parse every fixture with A and B, compare CSTs with `@core.tree_diff`, and fail on non-empty diffs unless explicitly classified as accepted newline residue.
- [ ] Port D2a: for every edit sequence, apply incremental edits to B and compare against B full parse after each edit.
- [ ] Port D2b: preserve projection identity comparison with the same leaf extractor as the spike; report mismatches as `WrongModelStop` unless tied to accepted newline residue.
- [ ] Keep reuse cripple toggling in the oracle harness only; do not add it back to `Expr`.
- [ ] Add watch-item fixture coverage for finding #1: `ExpectSkip` diagnostics and EOF behavior around soft-newline-aware expected tokens.
- [ ] Add watch-item fixture coverage for finding #4: block semicolon behavior around `RequireSep` and newline/brace stops.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon check -p dowdiness/lambda/spike`; expect PASS.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon check -p src/grammar`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon test -p dowdiness/loom/grammar`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon info && moon fmt`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike loom/src/grammar && git commit -m "Revalidate lambda oracle on reified grammar IR"`.

### Task 10: Public Interface And Contract Review

**Files**

- Modify `loom/src/grammar/pkg.generated.mbti`
- Modify `examples/lambda/src/spike/pkg.generated.mbti` if generated by `moon info`
- Modify no source files unless this review finds a contract violation.

**Interfaces**

- Consumes generated interface files from `NEW_MOON_MOD=0 moon info`.
- Produces a reviewed public API where `grammar` exposes the minimal contract: `Pred`, `RuleName`, `Expr` with the seven new public nodes plus enriched `RepeatTopLevel`, `Alt`, `GrammarIr`, compile errors, compiled grammar inspection needed by tests, and `interpret`.

- [ ] Run `NEW_MOON_MOD=0 moon info`; expect PASS and generated interface updates.
- [ ] Inspect `loom/src/grammar/pkg.generated.mbti`; verify the seven new nodes are public, `RepeatTopLevel` carries delimiter fields, `Ref` still lowers to `RefSlot(Int)`, and there is no `SeparatedList`.
- [ ] Verify no `Opaque`, no closure fields in public IR, no analyzing interpreter, no code emitter, no parameterized `Ref`, and no public mode-stack API unless Task 8 proved it with full D1/D2a/D2b parity.
- [ ] Inspect `loom/src/core/pkg.generated.mbti`; verify it has no import of `dowdiness/loom/grammar`.
- [ ] If `loom/src/core/pkg.generated.mbti` changed, stop and revert only the unintended core import/source change made by this plan; rerun `NEW_MOON_MOD=0 moon check -p src/grammar`.
- [ ] Run `moon fmt`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon check -p src/grammar`; expect PASS.
- [ ] Run `NEW_MOON_MOD=0 moon test -p dowdiness/loom/grammar`; expect PASS.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon check -p dowdiness/lambda/spike`; expect PASS.
- [ ] Run `cd examples/lambda && NEW_MOON_MOD=0 moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Commit: `git add loom/src/grammar examples/lambda/src/spike && git commit -m "Finalize grammar IR contract surface"`.

## Self-Review

- [ ] Spec coverage: confirm tasks implement new `loom/src/grammar/`, generic `[T,K]` IR, dense slot refs, `Pred[T]`, no `Opaque`, removal of `cripple_reuse`, runtime-mark `WrapIfNext`, resolved `Expect` message, three reducible hatches, evidence-gated newline residue, revalidated D1/D2a/D2b, and tree-walking interpreter only.
- [ ] Placeholder scan: search this plan for `TBD`, `TODO`, `similar`, `etc.`, and `placeholder`; replace any vague instruction with concrete code or command text before implementation starts.
- [ ] Type consistency: compare every cited `ParserContext` and `LanguageSpec` signature against `loom/src/core/pkg.generated.mbti`; if the generated interface differs on `origin/main`, update the implementation task before coding.
- [ ] Non-goal scan: verify no task builds an authoring grammar format, AST derivation, Layer-1 codegen, RawKind registry fix, analyzing/table-driven interpreter, code emitter, block-reparse parity, or incremental-relex parity.
- [ ] Documentation protocol: this plan adds a Markdown file under `docs/superpowers/plans/`; the implementation PR must update `docs/README.md` unless the maintainer explicitly waives that separate index change.
