# loomgen IR Contract Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

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

### Task 6: Reify Reducible Lambda Escape Hatches

**Files**

- Modify `loom/src/grammar/ir.mbt`
- Modify `loom/src/grammar/interpreter.mbt`
- Create `loom/src/grammar/counted_repeat_test.mbt`
- Modify `examples/lambda/src/spike/lambda_ir.mbt`
- Modify `examples/lambda/src/spike/interpreter.mbt`

**Interfaces**

- Consumes embedded spike hatches `ManualParamList`, `ManualDefinition`, and `ManualBlockDelimiterCheck`.
- Produces generic `WrapIfNext(K, Pred[T], Expr[T,K])` use for parameter lists.
- Produces generic `Node(K, Seq([...]))` plus `Choice` use for definitions.
- Produces generic `CountedRepeat(Pred[T], Expr[T,K], min~ : Int, missing_message~ : String?)` use for block delimiter checks.

- [ ] Write failing grammar package test in `loom/src/grammar/counted_repeat_test.mbt`:

```moonbit
test "CountedRepeat emits configured error when minimum is not reached" {
  let expr : Expr[TestToken, TestKind] = Expr::CountedRepeat(
    Pred::IsToken(TestToken::Int),
    Expr::Emit(TestToken::Int, TestKind::IntToken),
    min=1,
    missing_message=Some("expected at least one int"),
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
  let tokens = [@core.TokenInfo::new(TestToken::EOF, 0)]
  let ctx = @core.ParserContext::new(tokens, "", spec)
  parse_root(ctx)
  inspect(true, content="true")
}
```

- [ ] Run `moon test -p dowdiness/loom/grammar`; expect FAIL because `CountedRepeat` is not interpreted.

```text
$ moon test -p dowdiness/loom/grammar
expect: FAIL, unsupported CountedRepeat
```

- [ ] Implement `CountedRepeat`: count each successful `pred.test(ctx.peek())` iteration; run the body; after the loop, if `count < min` and `missing_message` is `Some(msg)`, call `ctx.error(msg)` and `ctx.emit_error_placeholder()`.
- [ ] Run `moon check`; expect PASS.
- [ ] Run `moon test -p dowdiness/loom/grammar`; expect PASS.
- [ ] In `examples/lambda/src/spike/lambda_ir.mbt`, replace `ManualParamList` with `Expr::WrapIfNext(@syntax.ParamList, Pred::IsToken(@token.LeftParen), Expr::Seq([...]))`.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] In `examples/lambda/src/spike/lambda_ir.mbt`, replace `ManualDefinition` with `Expr::Choice([Alt::Alt(starts=Pred::IsToken(@token.Let), body=...), Alt::Alt(starts=Pred::IsToken(@token.Fn), body=...)])`, using `Expr::Node(@syntax.LetDef, Expr::Seq([...]))` for the let arm.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] In `examples/lambda/src/spike/lambda_ir.mbt`, replace `ManualBlockDelimiterCheck` with `Expr::CountedRepeat(Pred::Not(Pred::OneOf([@token.RBrace, @token.EOF])), body, min=0, missing_message=Some("expected block delimiter"))`.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Delete now-unused `ManualParamList`, `ManualDefinition`, and `ManualBlockDelimiterCheck` dispatch from `examples/lambda/src/spike/interpreter.mbt`.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS for existing non-newline oracle fixtures.
- [ ] Run `moon info && moon fmt`; expect PASS.
- [ ] Commit: `git add loom/src/grammar examples/lambda/src/spike && git commit -m "Reify reducible lambda grammar hatches"`.

### Task 7: Port Lambda Spike To `@grammar`

**Files**

- Modify `examples/lambda/src/spike/moon.pkg`
- Modify `examples/lambda/src/spike/types.mbt`
- Modify `examples/lambda/src/spike/lambda_ir.mbt`
- Modify `examples/lambda/src/spike/interpreter.mbt`
- Modify `examples/lambda/src/spike/*_test.mbt`

**Interfaces**

- Consumes `pub enum @grammar.Expr[T,K]`.
- Consumes `pub enum @grammar.Pred[T]`.
- Consumes `pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K : @seam.ToRawKind] @grammar.interpret(@grammar.GrammarIr[T,K]) -> ((@core.ParserContext[T,K]) -> Unit) raise @grammar.GrammarCompileError`.
- Produces `pub fn build_b_syntax_grammar() -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind]`.

- [ ] Add `dowdiness/loom/grammar` to `examples/lambda/src/spike/moon.pkg`:

```moonbit
import {
  "dowdiness/lambda",
  "dowdiness/lambda/token",
  "dowdiness/lambda/syntax",
  "dowdiness/lambda/lexer",
  "dowdiness/loom",
  "dowdiness/loom/core",
  "dowdiness/loom/grammar",
  "dowdiness/loom/pipeline",
  "dowdiness/seam",
  "dowdiness/incr/cells",
}
```

- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Write failing adapter test in `examples/lambda/src/spike/ported_ir_test.mbt`:

```moonbit
test "lambda spike builds parser from shared grammar IR" {
  let grammar = build_b_syntax_grammar()
  let (_, diagnostics) = grammar.parse_cst("let x = 1")
  inspect(diagnostics.is_empty(), content="true")
}
```

- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because spike still uses local IR/interpreter.
- [ ] Replace spike-local `RuleId` with string `@grammar.RuleName` values: `"source"`, `"definition"`, `"expression"`, `"binary"`, `"application"`, `"atom"`, and `"param_list"`.
- [ ] Rewrite every declarative predicate closure to `@grammar.Pred`: `Any`, `IsToken`, `OneOf`, and `Not`. Do not add any closure or `Opaque` variant.
- [ ] Replace the seven fixed `GrammarIr` fields with `Map[@grammar.RuleName, @grammar.Expr[@token.Token, @syntax.SyntaxKind]]`.
- [ ] Build B with the shared interpreter:

```moonbit
pub fn build_b_syntax_grammar() -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  let ir = build_lambda_ir()
  let parse_root = @grammar.interpret(ir)
  let spec = @core.LanguageSpec::new(
    @syntax.SourceFile,
    @syntax.ErrorNode,
    @syntax.SourceFile,
    @token.EOF,
    incomplete_kind=@syntax.ErrorNode,
    parse_root=parse_root,
  )
  @loom.SyntaxGrammar::new(
    spec=spec,
    lex=@lexer.lex,
    incremental_relex_enabled=false,
    block_reparse_spec=None,
  )
}
```

- [ ] Keep only `ManualNewlineAppExpr` as the lambda-specific residue path; all other `Manual*` constructors must be gone from lambda spike code.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS or newline-only oracle failures classified in Task 8.
- [ ] Run `moon info && moon fmt`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Port lambda spike to shared grammar IR"`.

### Task 8: Evidence-Gate `ManualNewlineAppExpr`

**Files**

- Modify `examples/lambda/src/spike/types.mbt`
- Modify `examples/lambda/src/spike/lambda_ir.mbt`
- Modify `examples/lambda/src/spike/interpreter.mbt`
- Modify `examples/lambda/src/spike/oracle.mbt`
- Create `examples/lambda/src/spike/newline_app_reification_test.mbt`

**Interfaces**

- Consumes `pub enum DivergenceClass { NoDivergence; ReplicationResidual(String); WrongModelStop(String) } derive(Eq, Debug)` from the spike, preserving this public shape.
- Produces one attempted reification branch for newline application.
- Produces one fallback branch that records residue and leaves lambda using the hand path if parity fails.

- [ ] Write failing oracle test in `examples/lambda/src/spike/newline_app_reification_test.mbt`:

```moonbit
test "newline application reification attempt is evidence gated" {
  let result = run_newline_application_reification_probe()
  match result.divergence {
    DivergenceClass::NoDivergence => ()
    DivergenceClass::ReplicationResidual(_) => ()
    DivergenceClass::WrongModelStop(_) => ()
  }
}
```

- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL because `run_newline_application_reification_probe` is missing.
- [ ] Add a probe-only attempted reification using an interpreter mode stack, not a committed public `@grammar` feature. The mode stack has exactly two modes: `AllowNewlineApplication` and `DisallowNewlineApplication`.
- [ ] Route recursive expression refs in the probe through the mode stack and compare only the newline-application fixtures against the hand path.
- [ ] If D1/D2a/D2b pass for the probe, replace `ManualNewlineAppExpr` in `lambda_ir.mbt` with the reified mode-stack expression and set `DivergenceClass::NoDivergence`.
- [ ] If any parity check fails, leave `ManualNewlineAppExpr` in `lambda_ir.mbt`, delete the probe from production dispatch, and record `DivergenceClass::ReplicationResidual("ManualNewlineAppExpr requires parameterized recursive mode")` in the oracle result.
- [ ] Do not add parameterized `Ref` or mode-stack machinery to `loom/src/grammar` in this task unless the probe passes all D1/D2a/D2b fixtures.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS with either `NoDivergence` or recorded residue.
- [ ] Run `moon info && moon fmt`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Classify newline application grammar residue"`.

### Task 9: Re-Validate D1/D2a/D2b Oracle

**Files**

- Modify `examples/lambda/src/spike/oracle.mbt`
- Modify `examples/lambda/src/spike/fixtures.mbt`
- Modify `examples/lambda/src/spike/oracle_test.mbt`
- Modify `examples/lambda/src/spike/measurements.mbt`

**Interfaces**

- Consumes B grammar from `build_b_syntax_grammar()`.
- Consumes `@core.tree_diff(@seam.CstNode, @seam.CstNode) -> Array[@core.Edit]`.
- Consumes `pub fn[T : Eq + @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] @loom.new_syntax_parser(String, SyntaxGrammar[T,K], runtime? : @cells.Runtime) -> @pipeline.SyntaxParser`.
- Produces fresh reified-IR oracle results for D1 fresh CST parity, D2a incremental-vs-full parity, and D2b projection identity parity.

- [ ] Rewrite the oracle setup so A is still lambda's normalized hand parser and B is the shared `@grammar` interpreter output. Do not inherit any PASS result from the closure spike.
- [ ] Write failing test:

```moonbit
test "reified grammar IR passes D1 D2a D2b oracle or records residue" {
  let result = run_reified_ir_oracle()
  inspect(result.d1_passed, content="true")
  inspect(result.d2a_passed, content="true")
  inspect(result.d2b_passed, content="true")
  match result.divergence {
    DivergenceClass::NoDivergence => ()
    DivergenceClass::ReplicationResidual(_) => ()
    DivergenceClass::WrongModelStop(message) => fail(message)
  }
}
```

- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect FAIL until the oracle calls the reified IR path.
- [ ] Port D1: parse every fixture with A and B, compare CSTs with `@core.tree_diff`, and fail on non-empty diffs unless the fixture is explicitly newline-residue-classified.
- [ ] Port D2a: for every edit sequence, apply incremental edits to B and compare against B full parse after each edit.
- [ ] Port D2b: preserve projection identity comparison with the same leaf extractor as the spike; report mismatches as `WrongModelStop` unless tied to the accepted newline residue.
- [ ] Keep reuse cripple toggling in the oracle harness only; do not add it back to `Expr`.
- [ ] Run `cd examples/lambda && moon check`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Run `moon info && moon fmt`; expect PASS.
- [ ] Commit: `git add examples/lambda/src/spike && git commit -m "Revalidate lambda oracle on reified grammar IR"`.

### Task 10: Public Interface And Contract Review

**Files**

- Modify `loom/src/grammar/pkg.generated.mbti`
- Modify `examples/lambda/src/spike/pkg.generated.mbti` if generated by `moon info`
- Modify no source files unless this review finds a contract violation.

**Interfaces**

- Consumes generated interface files from `moon info`.
- Produces a reviewed public API where `grammar` exposes only the minimal contract: `Pred`, `RuleName`, `Expr`, `Alt`, `GrammarIr`, compile errors, compiled grammar inspection needed by tests, and `interpret`.

- [ ] Run `moon info`; expect PASS and generated interface updates.
- [ ] Inspect `loom/src/grammar/pkg.generated.mbti`; verify no `Opaque`, no closure fields in public IR, no analyzing interpreter, and no code emitter.
- [ ] Inspect `loom/src/core/pkg.generated.mbti`; verify it has no import of `dowdiness/loom/grammar`.
- [ ] If `loom/src/core/pkg.generated.mbti` changed, stop and revert only the unintended core import/source change made by this plan; rerun `moon check`.
- [ ] Run `moon fmt`; expect PASS.
- [ ] Run `moon check`; expect PASS.
- [ ] Run `moon test -p dowdiness/loom/grammar`; expect PASS.
- [ ] Run `cd examples/lambda && moon test -p dowdiness/lambda/spike`; expect PASS.
- [ ] Commit: `git add loom/src/grammar examples/lambda/src/spike && git commit -m "Finalize grammar IR contract surface"`.

## Self-Review

- [ ] Spec coverage: confirm tasks implement new `loom/src/grammar/`, generic `[T,K]` IR, dense slot refs, `Pred[T]`, no `Opaque`, removal of `cripple_reuse`, runtime-mark `WrapIfNext`, resolved `Expect` message, three reducible hatches, evidence-gated newline residue, revalidated D1/D2a/D2b, and tree-walking interpreter only.
- [ ] Placeholder scan: search this plan for `TBD`, `TODO`, `similar`, `etc.`, and `placeholder`; replace any vague instruction with concrete code or command text before implementation starts.
- [ ] Type consistency: compare every cited `ParserContext` and `LanguageSpec` signature against `loom/src/core/pkg.generated.mbti`; if the generated interface differs on `origin/main`, update the implementation task before coding.
- [ ] Non-goal scan: verify no task builds an authoring grammar format, AST derivation, Layer-1 codegen, RawKind registry fix, analyzing/table-driven interpreter, code emitter, block-reparse parity, or incremental-relex parity.
- [ ] Documentation protocol: this plan adds a Markdown file under `docs/superpowers/plans/`; the implementation PR must update `docs/README.md` unless the maintainer explicitly waives that separate index change.
