// Shared test token/kind pair for the interpreter test suite. Definitions are
// also consumed by the other grammar package tests.

///|
enum TestToken {
  Int
  Word
  Skip
  Expected
  EOF
} derive(Eq, @debug.Debug)

///|
impl Show for TestToken with fn output(self, logger) {
  logger.write_string(
    match self {
      Int => "Int"
      Word => "Word"
      Skip => "Skip"
      Expected => "Expected"
      EOF => "EOF"
    },
  )
}

///|
impl @seam.IsTrivia for TestToken with fn is_trivia(_self) {
  false
}

///|
impl @seam.IsEof for TestToken with fn is_eof(self) {
  self == TestToken::EOF
}

///|
impl @seam.ToRawKind for TestToken with fn to_raw(self) {
  match self {
    Int => @seam.RawKind(1)
    Word => @seam.RawKind(2)
    Skip => @seam.RawKind(3)
    Expected => @seam.RawKind(4)
    EOF => @seam.RawKind(0)
  }
}

///|
enum TestKind {
  Root
  IntToken
  WordToken
  WordNode
  SkipKind
  ExpectedKind
  Error
  Incomplete
} derive(Eq, @debug.Debug)

///|
impl @seam.ToRawKind for TestKind with fn to_raw(self) {
  match self {
    Root => @seam.RawKind(10)
    IntToken => @seam.RawKind(11)
    WordToken => @seam.RawKind(14)
    WordNode => @seam.RawKind(15)
    SkipKind => @seam.RawKind(16)
    ExpectedKind => @seam.RawKind(17)
    Error => @seam.RawKind(12)
    Incomplete => @seam.RawKind(13)
  }
}

///|
fn test_spec(
  parse_root : (@core.ParserContext[TestToken, TestKind]) -> Unit,
) -> @core.LanguageSpec[TestToken, TestKind] {
  @core.LanguageSpec::new(
    TestKind::Root,
    TestKind::Error,
    TestKind::Root,
    TestToken::EOF,
    incomplete_kind=TestKind::Incomplete,
    parse_root~,
  )
}

///|
test "interpret emits a token through LanguageSpec parse_root" {
  let ir = GrammarIr::GrammarIr(
    {
      "source": Expr::Node(
        TestKind::Root,
        Expr::Emit(TestToken::Int, TestKind::IntToken),
      ),
    },
    root="source",
  )
  let parse_root = interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_tree, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "Native runs in sequence between declarative neighbors" {
  let ir = GrammarIr::GrammarIr(
    {
      "source": Expr::Node(
        TestKind::Root,
        Expr::Seq([
          Expr::Emit(TestToken::Int, TestKind::IntToken),
          Expr::Native("mark"),
          Expr::Emit(TestToken::Int, TestKind::IntToken),
        ]),
      ),
    },
    root="source",
  )
  let natives : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "mark": fn(_caps) {
      fn(ctx, _dispatcher) { ctx.emit_token(TestKind::WordToken) }
    },
  }
  let parse_root = interpret(ir, natives~)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (tree, diagnostics) = @core.parse_with(
    "1 1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
  match tree.children[0] {
    @seam.CstElement::Node(root) => inspect(root.children.length(), content="3")
    _ => fail("expected Root node")
  }
}

///|
test "native capability dispatches a declared Choice" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(TestKind::Root, Expr::Native("delegate")),
    "inner": Expr::Choice([
      Alt::{
        starts: Pred::IsToken(TestToken::Int),
        body: Expr::Emit(TestToken::Int, TestKind::IntToken),
      },
    ]),
  }
  let factories : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "delegate": caps => {
      let target = caps.require("inner")
      fn(ctx, dispatcher) { ignore(dispatcher.try_rule(ctx, target)) }
    },
  }
  let parse_root = interpret(
    GrammarIr::GrammarIr(rules, root="source"),
    natives=factories,
    native_rule_refs={ "delegate": Set::Set(["inner"]) },
  )
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (tree, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
  match tree.children[0] {
    @seam.CstElement::Node(root) => inspect(root.children.length(), content="1")
    _ => fail("expected Root node")
  }
}

///|
test "valid nonmatching native capability returns false without diagnostics" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(TestKind::Root, Expr::Native("delegate")),
    "inner": Expr::Choice([
      Alt::{
        starts: Pred::IsToken(TestToken::Word),
        body: Expr::Emit(TestToken::Word, TestKind::WordToken),
      },
    ]),
  }
  let mut matched = true
  let factories : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "delegate": caps => {
      let target = caps.require("inner")
      fn(ctx, dispatcher) { matched = dispatcher.try_rule(ctx, target) }
    },
  }
  let parse_root = interpret(
    GrammarIr::GrammarIr(rules, root="source"),
    natives=factories,
    native_rule_refs={ "delegate": Set::Set(["inner"]) },
  )
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_tree, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(matched, content="false")
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "HostGuard lowers and evaluates in Choice" {
  let ir = GrammarIr::GrammarIr(
    {
      "source": Expr::Node(
        TestKind::Root,
        Expr::Choice([
          Alt::{
            starts: Pred::All(
              Pred::IsToken(TestToken::Int),
              Pred::HostGuard("allow"),
            ),
            body: Expr::Emit(TestToken::Int, TestKind::WordToken),
          },
          Alt::{
            starts: Pred::IsToken(TestToken::Int),
            body: Expr::Emit(TestToken::Int, TestKind::IntToken),
          },
        ]),
      ),
    },
    root="source",
  )
  let guards : Map[RuleName, HostGuard[TestToken, TestKind]] = {
    "allow": fn(_ctx) { false },
  }
  let parse_root = interpret(ir, guards~)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (tree, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
  match tree.children[0] {
    @seam.CstElement::Node(root) =>
      match root.children[0] {
        @seam.CstElement::Token(token) =>
          inspect(token.kind, content="RawKind(11)")
        _ => fail("expected emitted token")
      }
    _ => fail("expected Root node")
  }
}

///|
test "negated HostGuard evaluates in a Choice predicate" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    {
      "source": Expr::Node(
        TestKind::Root,
        Expr::Choice([
          Alt::{
            starts: Pred::Not(Pred::HostGuard("deny")),
            body: Expr::Emit(TestToken::Int, TestKind::WordToken),
          },
        ]),
      ),
    },
    root="source",
  )
  let guards : Map[RuleName, HostGuard[TestToken, TestKind]] = {
    "deny": _ctx => false,
  }
  let parse_root = interpret(ir, guards~)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (tree, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
  match tree.children[0] {
    @seam.CstElement::Node(root) =>
      match root.children[0] {
        @seam.CstElement::Token(token) =>
          inspect(token.kind, content="RawKind(14)")
        _ => fail("expected emitted token")
      }
    _ => fail("expected Root node")
  }
}

///|
test "bind rejects missing and unexpected handlers before parsing" {
  let native_ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    { "source": Expr::Native("mark") },
    root="source",
  )
  let compiled_native = compile(native_ir, native_names=Set::Set(["mark"]))
  let missing = try {
    let _ = bind(compiled_native)
    None
  } catch {
    e => Some(e)
  }
  match missing {
    Some(GrammarBindError::MissingNative("mark")) => ()
    _ => fail("expected missing native bind error")
  }
  let extra : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "unexpected": fn(_caps) { fn(_ctx, _dispatcher) {  } },
  }
  let unexpected = try {
    let _ = bind(
      compile(GrammarIr::GrammarIr({ "source": Expr::Empty }, root="source")),
      natives=extra,
    )
    None
  } catch {
    e => Some(e)
  }
  match unexpected {
    Some(GrammarBindError::UnexpectedNative("unexpected")) => ()
    _ => fail("expected unexpected native bind error")
  }
  let guard_ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    { "source": Expr::Empty },
    root="source",
  )
  let compiled_guard = compile(guard_ir, guard_names=Set::Set(["allow"]))
  let missing_guard = try {
    let _ = bind(compiled_guard)
    None
  } catch {
    e => Some(e)
  }
  match missing_guard {
    Some(GrammarBindError::MissingGuard("allow")) => ()
    _ => fail("expected missing guard bind error")
  }
  let extra_guard : Map[RuleName, HostGuard[TestToken, TestKind]] = {
    "unexpected_guard": _ctx => true,
  }
  let unexpected_guard = try {
    let _ = bind(compile(guard_ir), guards=extra_guard)
    None
  } catch {
    e => Some(e)
  }
  match unexpected_guard {
    Some(GrammarBindError::UnexpectedGuard("unexpected_guard")) => ()
    _ => fail("expected unexpected guard bind error")
  }
}

///|
test "RepeatWhile runtime guard reports an opaque native with no progress" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    { "source": Expr::RepeatWhile(Pred::Any, Expr::Native("noop")) },
    root="source",
  )
  let factories : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "noop": _caps => fn(_ctx, _dispatcher) {  },
  }
  let parse_root = interpret(ir, natives=factories)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
}

///|
test "RepeatTopLevel runtime guard reports an opaque native with no progress" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    {
      "source": Expr::RepeatTopLevel(
        "item",
        starts=Pred::Any,
        delim=Pred::Not(Pred::Any),
        delim_kind=TestKind::SkipKind,
        between_msg="expected separator",
        after_msg="unexpected item",
      ),
      "item": Expr::Native("noop"),
    },
    root="source",
  )
  let factories : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "noop": _caps => fn(_ctx, _dispatcher) {  },
  }
  let parse_root = interpret(ir, natives=factories)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.length(), content="1")
  inspect(
    diagnostics.items()[0].message,
    content="grammar: RepeatTopLevel body made no progress",
  )
}

///|
test "runtime cycle guard stops unknown recursive re-entry" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    { "source": Expr::Seq([Expr::Native("noop"), Expr::Ref("source")]) },
    root="source",
  )
  let factories : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "noop": _caps => fn(_ctx, _dispatcher) {  },
  }
  let parse_root = interpret(ir, natives=factories)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
}

///|
test "runtime cycle guard permits recursive re-entry after token progress" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    {
      "source": Expr::Choice([
        Alt::{
          starts: Pred::IsToken(TestToken::Int),
          body: Expr::Seq([
            Expr::Emit(TestToken::Int, TestKind::IntToken),
            Expr::Ref("source"),
          ]),
        },
        Alt::{ starts: Pred::IsToken(TestToken::EOF), body: Expr::Empty },
      ]),
    },
    root="source",
  )
  let parse_root = interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "ErrorUntil treats the stop token as a normal boundary" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    {
      "source": Expr::ErrorUntil(
        Pred::IsToken(TestToken::Expected),
        "unexpected input",
      ),
    },
    root="source",
  )
  let parse_root = interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Expected, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_, diagnostics) = @core.parse_with(
    ")",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "ErrorUntil is silent at EOF" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    {
      "source": Expr::ErrorUntil(
        Pred::IsToken(TestToken::Expected),
        "unexpected input",
      ),
    },
    root="source",
  )
  let parse_root = interpret(ir)
  let tokens = [@core.TokenInfo::new(TestToken::EOF, 0)]
  let (_, diagnostics) = @core.parse_with(
    "",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "required EmitOr diagnoses a missing item at a stop token" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    {
      "source": Expr::Seq([
        Expr::EmitOr(TestToken::Int, TestKind::IntToken, "expected expression"),
        Expr::ErrorUntil(Pred::IsToken(TestToken::Expected), "unexpected input"),
        Expr::Emit(TestToken::Expected, TestKind::ExpectedKind),
      ]),
    },
    root="source",
  )
  let parse_root = interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Expected, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_, diagnostics) = @core.parse_with(
    ")",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.length(), content="1")
}

///|
test "required EmitOr diagnoses a missing item at EOF" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    {
      "source": Expr::EmitOr(
        TestToken::Int,
        TestKind::IntToken,
        "expected expression",
      ),
    },
    root="source",
  )
  let parse_root = interpret(ir)
  let tokens = [@core.TokenInfo::new(TestToken::EOF, 0)]
  let (_, diagnostics) = @core.parse_with(
    "",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.length(), content="1")
}

///|
test "runtime cycle guard stops recursive native dispatch" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    {
      "source": Expr::Native("delegate"),
      "choice": Expr::Choice([
        Alt::{ starts: Pred::Any, body: Expr::Ref("source") },
      ]),
    },
    root="source",
  )
  let factories : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "delegate": caps => {
      let target = caps.require("choice")
      fn(ctx, dispatcher) { ignore(dispatcher.try_rule(ctx, target)) }
    },
  }
  let parse_root = interpret(ir, natives=factories, native_rule_refs={
    "delegate": Set::Set(["choice"]),
  })
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
}

///|
test "PrattApp runtime guard reports an empty atom" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    {
      "source": Expr::PrattApp("empty", TestKind::WordNode, Pred::Any),
      "empty": Expr::Empty,
    },
    root="source",
  )
  let parse_root = interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_, diagnostics) = @core.parse_with(
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
}

///|
test "native factory cannot acquire an undeclared capability" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    { "source": Expr::Native("delegate"), "inner": Expr::Choice([]) },
    root="source",
  )
  let factories : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "delegate": caps => {
      let _ = caps.require("not_declared")
      fn(_ctx, _dispatcher) {  }
    },
  }
  let compiled = compile(ir, native_names=Set::Set(["delegate"]), native_rule_refs={
    "delegate": Set::Set(["inner"]),
  })
  let result = try {
    let _ = bind(compiled, natives=factories)
    None
  } catch {
    e => Some(e)
  }
  match result {
    Some(GrammarBindError::CapabilityRejected("not_declared")) => ()
    _ => fail("expected capability rejection during bind")
  }
}

///|
/// Characterization: convenience and explicit setup have equivalent behavior.
test "interpret and compile -> bind preserve native and HostGuard behavior" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(TestKind::Root, Expr::Native("delegate")),
    "close_boundary": Expr::Choice([
      Alt::{
        starts: Pred::HostGuard("allow_close"),
        body: Expr::Emit(TestToken::Word, TestKind::WordToken),
      },
    ]),
  }
  let ir = GrammarIr::GrammarIr(rules, root="source")
  let native_rule_refs : Map[RuleName, Set[RuleName]] = {
    "delegate": Set::Set(["close_boundary"]),
  }
  let factories : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "delegate": caps => {
      let target = caps.require("close_boundary")
      fn(ctx, dispatcher) { ignore(dispatcher.try_rule(ctx, target)) }
    },
  }
  let guards : Map[RuleName, HostGuard[TestToken, TestKind]] = {
    "allow_close": fn(_ctx) { true },
  }
  let direct = interpret(ir, natives=factories, guards~, native_rule_refs~)
  let compiled = compile(
    ir,
    native_names=Set::Set(["delegate"]),
    guard_names=Set::Set(["allow_close"]),
    native_rule_refs~,
  )
  let explicit = bind(compiled, natives=factories, guards~).parse_root()
  let tokens = [
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (direct_tree, direct_diags) = @core.parse_with(
    "w",
    test_spec(direct),
    _src => tokens,
    direct,
  )
  let (explicit_tree, explicit_diags) = @core.parse_with(
    "w",
    test_spec(explicit),
    _src => tokens,
    explicit,
  )
  inspect(@core.tree_diff(direct_tree, explicit_tree).length(), content="0")
  inspect(direct_diags == explicit_diags, content="true")
}

///|
/// Characterization: each binding owns its fresh native registry.
test "compiled grammar accepts fresh native registries per parse" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    { "source": Expr::Node(TestKind::Root, Expr::Native("mark")) },
    root="source",
  )
  let compiled = compile(ir, native_names=Set::Set(["mark"]))
  let first : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "mark": fn(_caps) {
      fn(ctx, _dispatcher) { ctx.emit_token(TestKind::IntToken) }
    },
  }
  let second : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "mark": fn(_caps) {
      fn(ctx, _dispatcher) { ctx.emit_token(TestKind::WordToken) }
    },
  }
  let first_parse = bind(compiled, natives=first).parse_root()
  let second_parse = bind(compiled, natives=second).parse_root()
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (first_tree, first_diags) = @core.parse_with(
    "i",
    test_spec(first_parse),
    _src => tokens,
    first_parse,
  )
  let (second_tree, second_diags) = @core.parse_with(
    "i",
    test_spec(second_parse),
    _src => tokens,
    second_parse,
  )
  inspect(first_diags.is_empty(), content="true")
  inspect(second_diags.is_empty(), content="true")
  match first_tree.children[0] {
    @seam.CstElement::Node(root) =>
      match root.children[0] {
        @seam.CstElement::Token(token) =>
          inspect(token.kind, content="RawKind(11)")
        _ => fail("expected first parse token")
      }
    _ => fail("expected first Root node")
  }
  match second_tree.children[0] {
    @seam.CstElement::Node(root) =>
      match root.children[0] {
        @seam.CstElement::Token(token) =>
          inspect(token.kind, content="RawKind(14)")
        _ => fail("expected second parse token")
      }
    _ => fail("expected second Root node")
  }
}

///|
/// Characterization: binding factories do not execute parser callbacks.
test "compiled execution defers native callbacks until parsing" {
  let ir : GrammarIr[TestToken, TestKind] = GrammarIr::GrammarIr(
    { "source": Expr::Node(TestKind::Root, Expr::Native("mark")) },
    root="source",
  )
  let compiled = compile(ir, native_names=Set::Set(["mark"]))
  let mut native_calls = 0
  let factories : Map[RuleName, NativeFactory[TestToken, TestKind]] = {
    "mark": fn(_caps) {
      fn(ctx, _dispatcher) {
        native_calls += 1
        ctx.emit_token(TestKind::IntToken)
      }
    },
  }
  let parse_root = bind(compiled, natives=factories).parse_root()
  inspect(native_calls, content="0")
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (_tree, diagnostics) = @core.parse_with(
    "i",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(native_calls, content="1")
  inspect(diagnostics.is_empty(), content="true")
}
