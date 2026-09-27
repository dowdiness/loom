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
  let ir = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Node(
        TestKind::Root,
        @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
      ),
    },
    root="source",
  )
  let parse_root = @grammar.interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-interpret-token-source")
  let (_tree, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "Native runs in sequence between declarative neighbors" {
  let ir = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Node(
        TestKind::Root,
        @grammar.Expr::Seq([
          @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
          @grammar.Expr::Native("mark"),
          @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
        ]),
      ),
    },
    root="source",
  )
  let natives : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "mark": fn(_caps) {
      fn(ctx, _dispatcher) { ctx.emit_token(TestKind::WordToken) }
    },
  }
  let parse_root = @grammar.interpret(ir, natives~)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-native-sequence-source")
  let (tree, diagnostics) = @core.parse_with(
    source_id,
    "1 1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
  match tree.children()[0] {
    @seam.CstElement::Node(root) =>
      inspect(root.children().length(), content="3")
    _ => fail("expected Root node")
  }
}

///|
test "native capability dispatches a declared Choice" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::Node(
      TestKind::Root,
      @grammar.Expr::Native("delegate"),
    ),
    "inner": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(TestToken::Int),
        body: @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
      },
    ]),
  }
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "delegate": caps => {
      let target = caps.require("inner")
      fn(ctx, dispatcher) { ignore(dispatcher.try_rule(ctx, target)) }
    },
  }
  let parse_root = @grammar.interpret(
    @grammar.GrammarIr::GrammarIr(rules, root="source"),
    natives=factories,
    native_rule_refs={ "delegate": Set::Set(["inner"]) },
  )
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-native-choice-source")
  let (tree, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
  match tree.children()[0] {
    @seam.CstElement::Node(root) =>
      inspect(root.children().length(), content="1")
    _ => fail("expected Root node")
  }
}

///|
test "valid nonmatching native capability returns false without diagnostics" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::Node(
      TestKind::Root,
      @grammar.Expr::Native("delegate"),
    ),
    "inner": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(TestToken::Word),
        body: @grammar.Expr::Emit(TestToken::Word, TestKind::WordToken),
      },
    ]),
  }
  let mut matched = true
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "delegate": caps => {
      let target = caps.require("inner")
      fn(ctx, dispatcher) { matched = dispatcher.try_rule(ctx, target) }
    },
  }
  let parse_root = @grammar.interpret(
    @grammar.GrammarIr::GrammarIr(rules, root="source"),
    natives=factories,
    native_rule_refs={ "delegate": Set::Set(["inner"]) },
  )
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-native-nonmatching-source")
  let (_tree, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(matched, content="false")
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "HostGuard lowers and evaluates both Choice outcomes" {
  let ir = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Node(
        TestKind::Root,
        @grammar.Expr::Choice([
          @grammar.Alt::{
            starts: @grammar.Pred::All(
              @grammar.Pred::IsToken(TestToken::Int),
              @grammar.Pred::HostGuard("allow"),
            ),
            body: @grammar.Expr::Emit(TestToken::Int, TestKind::WordToken),
          },
          @grammar.Alt::{
            starts: @grammar.Pred::IsToken(TestToken::Int),
            body: @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
          },
        ]),
      ),
    },
    root="source",
  )
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-host-guard-source")
  let parse_kind = allow => {
    let guards : Map[@grammar.RuleName, @grammar.HostGuard[TestToken, TestKind]] = {
      "allow": _ctx => allow,
    }
    let parse_root = @grammar.interpret(ir, guards~)
    let (tree, diagnostics) = @core.parse_with(
      source_id,
      "1",
      test_spec(parse_root),
      _src => tokens,
      parse_root,
    )
    guard diagnostics.is_empty() else { fail("unexpected diagnostics") }
    guard tree.children()[0] is @seam.CstElement::Node(root) else {
      fail("expected Root node")
    }
    guard root.children()[0] is @seam.CstElement::Token(token) else {
      fail("expected emitted token")
    }
    token.kind
  }
  inspect(parse_kind(false), content="RawKind(11)")
  inspect(parse_kind(true), content="RawKind(14)")
}

///|
test "negated HostGuard evaluates in a Choice predicate" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Node(
        TestKind::Root,
        @grammar.Expr::Choice([
          @grammar.Alt::{
            starts: @grammar.Pred::Not(@grammar.Pred::HostGuard("deny")),
            body: @grammar.Expr::Emit(TestToken::Int, TestKind::WordToken),
          },
        ]),
      ),
    },
    root="source",
  )
  let guards : Map[@grammar.RuleName, @grammar.HostGuard[TestToken, TestKind]] = {
    "deny": _ctx => false,
  }
  let parse_root = @grammar.interpret(ir, guards~)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-negated-host-guard-source")
  let (tree, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
  match tree.children()[0] {
    @seam.CstElement::Node(root) =>
      match root.children()[0] {
        @seam.CstElement::Token(token) =>
          inspect(token.kind, content="RawKind(14)")
        _ => fail("expected emitted token")
      }
    _ => fail("expected Root node")
  }
}

///|
test "bind rejects missing and unexpected handlers before parsing" {
  let native_ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    { "source": @grammar.Expr::Native("mark") },
    root="source",
  )
  let compiled_native = @grammar.compile(
    native_ir,
    native_names=Set::Set(["mark"]),
  )
  let missing = try {
    let _ = @grammar.bind(compiled_native)
    None
  } catch {
    e => Some(e)
  }
  match missing {
    Some(@grammar.GrammarBindError::MissingNative("mark")) => ()
    _ => fail("expected missing native bind error")
  }
  let extra : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = { "unexpected": fn(_caps) { fn(_ctx, _dispatcher) {  } } }
  let unexpected = try {
    let _ = @grammar.bind(
      @grammar.compile(
        @grammar.GrammarIr::GrammarIr(
          { "source": @grammar.Expr::Empty },
          root="source",
        ),
      ),
      natives=extra,
    )
    None
  } catch {
    e => Some(e)
  }
  match unexpected {
    Some(@grammar.GrammarBindError::UnexpectedNative("unexpected")) => ()
    _ => fail("expected unexpected native bind error")
  }
  let guard_ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    { "source": @grammar.Expr::Empty },
    root="source",
  )
  let compiled_guard = @grammar.compile(
    guard_ir,
    guard_names=Set::Set(["allow"]),
  )
  let missing_guard = try {
    let _ = @grammar.bind(compiled_guard)
    None
  } catch {
    e => Some(e)
  }
  match missing_guard {
    Some(@grammar.GrammarBindError::MissingGuard("allow")) => ()
    _ => fail("expected missing guard bind error")
  }
  let extra_guard : Map[
    @grammar.RuleName,
    @grammar.HostGuard[TestToken, TestKind],
  ] = { "unexpected_guard": _ctx => true }
  let unexpected_guard = try {
    let _ = @grammar.bind(@grammar.compile(guard_ir), guards=extra_guard)
    None
  } catch {
    e => Some(e)
  }
  match unexpected_guard {
    Some(@grammar.GrammarBindError::UnexpectedGuard("unexpected_guard")) => ()
    _ => fail("expected unexpected guard bind error")
  }
}

///|
test "RepeatWhile runtime guard reports an opaque native with no progress" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::RepeatWhile(
        @grammar.Pred::Any,
        @grammar.Expr::Native("noop"),
      ),
    },
    root="source",
  )
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = { "noop": _caps => fn(_ctx, _dispatcher) {  } }
  let parse_root = @grammar.interpret(ir, natives=factories)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-repeat-while-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
}

///|
test "RepeatTopLevel runtime guard reports an opaque native with no progress" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::RepeatTopLevel(
        "item",
        starts=@grammar.Pred::Any,
        delim=@grammar.Pred::Not(@grammar.Pred::Any),
        delim_kind=TestKind::SkipKind,
        between_msg="expected separator",
        after_msg="unexpected item",
      ),
      "item": @grammar.Expr::Native("noop"),
    },
    root="source",
  )
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = { "noop": _caps => fn(_ctx, _dispatcher) {  } }
  let parse_root = @grammar.interpret(ir, natives=factories)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-repeat-top-level-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.length(), content="1")
  inspect(
    diagnostics.items()[0].message(),
    content="grammar: RepeatTopLevel body made no progress",
  )
}

///|
test "runtime cycle guard stops unknown recursive re-entry" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Seq([
        @grammar.Expr::Native("noop"),
        @grammar.Expr::Ref("source"),
      ]),
    },
    root="source",
  )
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = { "noop": _caps => fn(_ctx, _dispatcher) {  } }
  let parse_root = @grammar.interpret(ir, natives=factories)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-runtime-cycle-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
}

///|
test "runtime cycle guard permits recursive re-entry after token progress" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Choice([
        @grammar.Alt::{
          starts: @grammar.Pred::IsToken(TestToken::Int),
          body: @grammar.Expr::Seq([
            @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
            @grammar.Expr::Ref("source"),
          ]),
        },
        @grammar.Alt::{
          starts: @grammar.Pred::IsToken(TestToken::EOF),
          body: @grammar.Expr::Empty,
        },
      ]),
    },
    root="source",
  )
  let parse_root = @grammar.interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-runtime-cycle-progress-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "ErrorUntil treats the stop token as a normal boundary" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::ErrorUntil(
        @grammar.Pred::IsToken(TestToken::Expected),
        "unexpected input",
      ),
    },
    root="source",
  )
  let parse_root = @grammar.interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Expected, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-error-until-boundary-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    ")",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "ErrorUntil is silent at EOF" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::ErrorUntil(
        @grammar.Pred::IsToken(TestToken::Expected),
        "unexpected input",
      ),
    },
    root="source",
  )
  let parse_root = @grammar.interpret(ir)
  let tokens = [@core.TokenInfo::new(TestToken::EOF, 0)]
  let source_id = @core.SourceId("grammar-error-until-eof-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    "",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "required EmitOr diagnoses a missing item at a stop token" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Seq([
        @grammar.Expr::EmitOr(
          TestToken::Int,
          TestKind::IntToken,
          "expected expression",
        ),
        @grammar.Expr::ErrorUntil(
          @grammar.Pred::IsToken(TestToken::Expected),
          "unexpected input",
        ),
        @grammar.Expr::Emit(TestToken::Expected, TestKind::ExpectedKind),
      ]),
    },
    root="source",
  )
  let parse_root = @grammar.interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Expected, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-emit-or-stop-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    ")",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.length(), content="1")
}

///|
test "required EmitOr diagnoses a missing item at EOF" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::EmitOr(
        TestToken::Int,
        TestKind::IntToken,
        "expected expression",
      ),
    },
    root="source",
  )
  let parse_root = @grammar.interpret(ir)
  let tokens = [@core.TokenInfo::new(TestToken::EOF, 0)]
  let source_id = @core.SourceId("grammar-emit-or-eof-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    "",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.length(), content="1")
}

///|
test "runtime cycle guard stops recursive native dispatch" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Native("delegate"),
      "choice": @grammar.Expr::Choice([
        @grammar.Alt::{
          starts: @grammar.Pred::Any,
          body: @grammar.Expr::Ref("source"),
        },
      ]),
    },
    root="source",
  )
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "delegate": caps => {
      let target = caps.require("choice")
      fn(ctx, dispatcher) { ignore(dispatcher.try_rule(ctx, target)) }
    },
  }
  let parse_root = @grammar.interpret(ir, natives=factories, native_rule_refs={
    "delegate": Set::Set(["choice"]),
  })
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-native-dispatch-cycle-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
}

///|
test "PrattApp runtime guard reports an empty atom" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::PrattApp(
        "empty",
        TestKind::WordNode,
        @grammar.Pred::Any,
      ),
      "empty": @grammar.Expr::Empty,
    },
    root="source",
  )
  let parse_root = @grammar.interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-pratt-app-empty-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
}

///|
test "native factory cannot acquire an undeclared capability" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Native("delegate"),
      "inner": @grammar.Expr::Choice([]),
    },
    root="source",
  )
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "delegate": caps => {
      let _ = caps.require("not_declared")
      fn(_ctx, _dispatcher) {  }
    },
  }
  let compiled = @grammar.compile(ir, native_names=Set::Set(["delegate"]), native_rule_refs={
    "delegate": Set::Set(["inner"]),
  })
  let result = try {
    let _ = @grammar.bind(compiled, natives=factories)
    None
  } catch {
    e => Some(e)
  }
  match result {
    Some(@grammar.GrammarBindError::CapabilityRejected("not_declared")) => ()
    _ => fail("expected capability rejection during bind")
  }
}

///|
/// Characterization: convenience and explicit setup have equivalent behavior.
test "interpret and compile -> bind preserve native and HostGuard behavior" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::Node(
      TestKind::Root,
      @grammar.Expr::Native("delegate"),
    ),
    "close_boundary": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::HostGuard("allow_close"),
        body: @grammar.Expr::Emit(TestToken::Word, TestKind::WordToken),
      },
    ]),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let native_rule_refs : Map[@grammar.RuleName, Set[@grammar.RuleName]] = {
    "delegate": Set::Set(["close_boundary"]),
  }
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "delegate": caps => {
      let target = caps.require("close_boundary")
      fn(ctx, dispatcher) { ignore(dispatcher.try_rule(ctx, target)) }
    },
  }
  let guards : Map[@grammar.RuleName, @grammar.HostGuard[TestToken, TestKind]] = {
    "allow_close": fn(_ctx) { true },
  }
  let direct = @grammar.interpret(
    ir,
    natives=factories,
    guards~,
    native_rule_refs~,
  )
  let compiled = @grammar.compile(
    ir,
    native_names=Set::Set(["delegate"]),
    guard_names=Set::Set(["allow_close"]),
    native_rule_refs~,
  )
  let explicit = @grammar.bind(compiled, natives=factories, guards~).parse_root()
  let tokens = [
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-bind-equivalence-source")
  let (direct_tree, direct_diags) = @core.parse_with(
    source_id,
    "w",
    test_spec(direct),
    _src => tokens,
    direct,
  )
  let (explicit_tree, explicit_diags) = @core.parse_with(
    source_id,
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
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Node(
        TestKind::Root,
        @grammar.Expr::Native("mark"),
      ),
    },
    root="source",
  )
  let compiled = @grammar.compile(ir, native_names=Set::Set(["mark"]))
  let first : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "mark": fn(_caps) {
      fn(ctx, _dispatcher) { ctx.emit_token(TestKind::IntToken) }
    },
  }
  let second : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "mark": fn(_caps) {
      fn(ctx, _dispatcher) { ctx.emit_token(TestKind::WordToken) }
    },
  }
  let first_parse = @grammar.bind(compiled, natives=first).parse_root()
  let second_parse = @grammar.bind(compiled, natives=second).parse_root()
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-fresh-native-registry-source")
  let (first_tree, first_diags) = @core.parse_with(
    source_id,
    "i",
    test_spec(first_parse),
    _src => tokens,
    first_parse,
  )
  let (second_tree, second_diags) = @core.parse_with(
    source_id,
    "i",
    test_spec(second_parse),
    _src => tokens,
    second_parse,
  )
  inspect(first_diags.is_empty(), content="true")
  inspect(second_diags.is_empty(), content="true")
  match first_tree.children()[0] {
    @seam.CstElement::Node(root) =>
      match root.children()[0] {
        @seam.CstElement::Token(token) =>
          inspect(token.kind, content="RawKind(11)")
        _ => fail("expected first parse token")
      }
    _ => fail("expected first Root node")
  }
  match second_tree.children()[0] {
    @seam.CstElement::Node(root) =>
      match root.children()[0] {
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
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Node(
        TestKind::Root,
        @grammar.Expr::Native("mark"),
      ),
    },
    root="source",
  )
  let compiled = @grammar.compile(ir, native_names=Set::Set(["mark"]))
  let mut native_calls = 0
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "mark": fn(_caps) {
      fn(ctx, _dispatcher) {
        native_calls += 1
        ctx.emit_token(TestKind::IntToken)
      }
    },
  }
  let parse_root = @grammar.bind(compiled, natives=factories).parse_root()
  inspect(native_calls, content="0")
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-deferred-native-source")
  let (_tree, diagnostics) = @core.parse_with(
    source_id,
    "i",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(native_calls, content="1")
  inspect(diagnostics.is_empty(), content="true")
}

///|
/// The cycle guard must be visible to the host. A dispatch stopped without
/// consuming input has to report "did not match" so the native runs its own
/// recovery, instead of trusting a rule that never parsed.
test "native dispatch reports the cycle guard as an unmatched rule" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::Native("delegate"),
      "choice": @grammar.Expr::Choice([
        @grammar.Alt::{
          starts: @grammar.Pred::Any,
          body: @grammar.Expr::Native("delegate"),
        },
      ]),
    },
    root="source",
  )
  let results : Array[Bool] = []
  let factories : Map[
    @grammar.RuleName,
    @grammar.NativeFactory[TestToken, TestKind],
  ] = {
    "delegate": caps => {
      let target = caps.require("choice")
      (ctx, dispatcher) => results.push(dispatcher.try_rule(ctx, target))
    },
  }
  let parse_root = @grammar.interpret(ir, natives=factories, native_rule_refs={
    "delegate": Set::Set(["choice"]),
  })
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-cycle-guard-dispatch-source")
  let (_, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  // The inner dispatch re-entered `choice` at the same cursor and was stopped;
  // the outer dispatch did run its alternative.
  inspect(results.length(), content="2")
  inspect(results[0], content="false")
  inspect(results[1], content="true")
  inspect(diagnostics.is_empty(), content="false")
}

///|
/// Reaches the guard *inside* the PrattApp repetition, which the empty-atom
/// test above does not: the first atom consumes, so the wrap is entered, and
/// only a later atom stops consuming. This is the site that can actually spin —
/// the head check runs once, this one runs in a loop — and it is the site whose
/// `before` is shadowed, so a missing snapshot here compiles and loops forever.
test "PrattApp runtime guard stops a repeated atom that stops consuming" {
  let ir : @grammar.GrammarIr[TestToken, TestKind] = @grammar.GrammarIr::GrammarIr(
    {
      "source": @grammar.Expr::PrattApp(
        "atom",
        TestKind::WordNode,
        @grammar.Pred::Any,
      ),
      "atom": @grammar.Expr::Choice([
        @grammar.Alt::{
          starts: @grammar.Pred::IsToken(TestToken::Int),
          body: @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
        },
      ]),
    },
    root="source",
  )
  let parse_root = @grammar.interpret(ir)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let source_id = @core.SourceId("grammar-pratt-app-repeat-source")
  let (tree, diagnostics) = @core.parse_with(
    source_id,
    "1",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  // The WordNode wrap proves the head atom consumed and the repetition was
  // entered, so the diagnostic can only have come from the guard inside the
  // loop, not from the head check.
  guard tree.children()[0] is @seam.CstElement::Node(wrapped) else {
    fail("expected the PrattApp wrap node")
  }
  inspect(wrapped.kind(), content="RawKind(15)")
  inspect(diagnostics.length(), content="1")
  inspect(
    diagnostics.items()[0].message(),
    content="grammar: PrattApp atom made no progress",
  )
}
