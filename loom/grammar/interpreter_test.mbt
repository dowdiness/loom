// Shared test token/kind pair for the interpreter test suite. Defined once
// here; reuse_test.mbt and counted_repeat_test.mbt consume these definitions
// (blackbox tests for a package share one compilation unit).

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
/// Build a LanguageSpec wired to the given reified `parse_root` closure.
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
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(
      TestKind::Root,
      Expr::Emit(TestToken::Int, TestKind::IntToken),
    ),
  }
  let parse_root = interpret(GrammarIr::GrammarIr(rules, root="source"))
  let spec = test_spec(parse_root)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let ctx = @core.ParserContext::new(tokens, "1", spec)
  parse_root(ctx)
  inspect(true, content="true")
}

///|
/// A native mid-`Seq` runs in order with its declarative neighbors: emit Int,
/// run the native (which emits Word as the marker kind), emit the second Int.
test "Native runs in sequence between declarative neighbors" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(
      TestKind::Root,
      Expr::Seq([
        Expr::Emit(TestToken::Int, TestKind::IntToken),
        Expr::Native("mark"),
        Expr::Emit(TestToken::Int, TestKind::IntToken),
      ]),
    ),
  }
  let hook : NativeRule[TestToken, TestKind] = (ctx, _try_parse_rule) => {
    ctx.emit_token(TestKind::WordToken)
  }
  let natives : Map[RuleName, NativeRule[TestToken, TestKind]] = {
    "mark": hook,
  }
  let parse_root = interpret(
    GrammarIr::GrammarIr(rules, root="source"),
    natives~,
  )
  let spec = test_spec(parse_root)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (tree, diagnostics) = @core.parse_with(
    "1 1",
    spec,
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="true")
  match tree.children[0] {
    @seam.CstElement::Node(root) => inspect(root.children.length(), content="3")
    @seam.CstElement::Token(_) => abort("expected the Root node")
  }
}

///|
/// A native re-enters the declarative grammar via `try_parse_rule`, producing the
/// same subtree an equivalent `Ref` would.
test "Native re-enters the grammar through try_parse_rule" {
  let via_native_rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(TestKind::Root, Expr::Native("delegate")),
    "inner": Expr::Emit(TestToken::Int, TestKind::IntToken),
  }
  let mut reentered = false
  let hook : NativeRule[TestToken, TestKind] = (_ctx, try_parse_rule) => {
    reentered = try_parse_rule("inner")
  }
  let natives : Map[RuleName, NativeRule[TestToken, TestKind]] = {
    "delegate": hook,
  }
  let native_parse_root = interpret(
    GrammarIr::GrammarIr(via_native_rules, root="source"),
    natives~,
  )
  let via_ref_rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(TestKind::Root, Expr::Ref("inner")),
    "inner": Expr::Emit(TestToken::Int, TestKind::IntToken),
  }
  let ref_parse_root = interpret(
    GrammarIr::GrammarIr(via_ref_rules, root="source"),
  )
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (native_tree, native_diags) = @core.parse_with(
    "1",
    test_spec(native_parse_root),
    _src => tokens,
    native_parse_root,
  )
  let (ref_tree, ref_diags) = @core.parse_with(
    "1",
    test_spec(ref_parse_root),
    _src => tokens,
    ref_parse_root,
  )
  inspect(reentered, content="true")
  inspect(native_diags.is_empty(), content="true")
  inspect(native_diags == ref_diags, content="true")
  inspect(@core.tree_diff(native_tree, ref_tree).length(), content="0")
}

///|
/// `interpret_compiled` with a registry that does not match the grammar's
/// declared native names degrades to a diagnostic placeholder instead of
/// aborting — the same defensive style as `ManualNewlineAppExpr`.
test "NativeRef with no matching registry entry reports a diagnostic, does not abort" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(TestKind::Root, Expr::Native("missing_at_runtime")),
  }
  let compiled = compile(
    GrammarIr::GrammarIr(rules, root="source"),
    native_names=Set::Set(["missing_at_runtime"]),
  )
  let parse_root : (@core.ParserContext[TestToken, TestKind]) -> Unit = interpret_compiled(
    compiled,
  )
  let tokens = [@core.TokenInfo::new(TestToken::EOF, 0)]
  let (_tree, diagnostics) = @core.parse_with(
    "",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
}

///|
/// A native's `try_parse_rule` with a name that isn't a grammar rule reports a
/// diagnostic AND emits an error placeholder — not just a diagnostic, mirroring
/// the `NativeRef`-registry-miss and `Fail` error paths, so the wrapping node
/// isn't left empty.
test "try_parse_rule with an unknown name reports a diagnostic and emits a placeholder" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(TestKind::Root, Expr::Native("delegate")),
  }
  let hook : NativeRule[TestToken, TestKind] = (_ctx, try_parse_rule) => {
    try_parse_rule("not_a_rule") |> ignore
  }
  let natives : Map[RuleName, NativeRule[TestToken, TestKind]] = {
    "delegate": hook,
  }
  let parse_root = interpret(
    GrammarIr::GrammarIr(rules, root="source"),
    natives~,
  )
  let tokens = [@core.TokenInfo::new(TestToken::EOF, 0)]
  let (tree, diagnostics) = @core.parse_with(
    "",
    test_spec(parse_root),
    _src => tokens,
    parse_root,
  )
  inspect(diagnostics.is_empty(), content="false")
  match tree.children[0] {
    @seam.CstElement::Node(root) => inspect(root.children.length(), content="1")
    @seam.CstElement::Token(_) => abort("expected the Root node")
  }
}

///|
test "interpret resolves HostGuard predicate via guards map in Choice" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(
      TestKind::Root,
      Expr::Choice([
        Alt::{
          starts: Pred::All(
            Pred::IsToken(TestToken::Int),
            Pred::HostGuard("int_is_even"),
          ),
          body: Expr::Seq([
            Expr::Emit(TestToken::Int, TestKind::IntToken),
            Expr::Emit(TestToken::Word, TestKind::WordToken),
          ]),
        },
        Alt::{
          starts: Pred::IsToken(TestToken::Int),
          body: Expr::Emit(TestToken::Int, TestKind::IntToken),
        },
      ]),
    ),
  }
  let mut call_count = 0
  let guards : Map[RuleName, HostGuard[TestToken, TestKind]] = {
    "int_is_even": fn(_ctx) {
      call_count = call_count + 1
      // First call (odd source "1") returns false; second call (even source "2") returns true
      call_count > 1
    },
  }
  let parse_root = interpret(
    GrammarIr::GrammarIr(rules, root="source"),
    guards~,
  )
  let spec = test_spec(parse_root)
  // Token 1 (odd) → second Choice arm (plain Emit, no guard matches)
  let tokens_odd = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (tree_odd, _) = @core.parse_with(
    "1",
    spec,
    _src => tokens_odd,
    parse_root,
  )
  match tree_odd.children[0] {
    @seam.CstElement::Node(root) => inspect(root.children.length(), content="1")
    // Token 1 (odd) → second Choice arm: only one IntToken emitted
    _ => fail("expected Root node")
  }
  // Token 2 (even) → first Choice arm (guard matches, produces IntToken + WordToken)
  let tokens_even = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Word, 1), // second token for the Word emit
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (tree_even, _) = @core.parse_with(
    "2w",
    spec,
    _src => tokens_even,
    parse_root,
  )
  match tree_even.children[0] {
    @seam.CstElement::Node(root) =>
      // Token 2 (even) → first Choice arm: IntToken + WordToken
      inspect(root.children.length(), content="2")
    _ => fail("expected Root node")
  }
}

///|
/// `try_parse_rule` on a top-level `Choice` whose only arm has a failing
/// HostGuard returns false without emitting tokens or diagnostics.
test "try_parse_rule atomic gate skips body when HostGuard returns false" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(TestKind::Root, Expr::Native("gate_caller")),
    "gate_rule": Expr::Choice([
      Alt::{
        starts: Pred::All(
          Pred::IsToken(TestToken::Int),
          Pred::HostGuard("always_false"),
        ),
        body: Expr::Emit(TestToken::Int, TestKind::IntToken),
      },
    ]),
  }
  let guards : Map[RuleName, HostGuard[TestToken, TestKind]] = {
    "always_false": fn(_ctx) { false },
  }
  let mut gate_result = true
  let hook : NativeRule[TestToken, TestKind] = (_ctx, try_parse_rule) => {
    gate_result = try_parse_rule("gate_rule")
  }
  let natives : Map[RuleName, NativeRule[TestToken, TestKind]] = {
    "gate_caller": hook,
  }
  let parse_root = interpret(
    GrammarIr::GrammarIr(rules, root="source"),
    natives~,
    guards~,
  )
  let spec = test_spec(parse_root)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (tree, diagnostics) = @core.parse_with("1", spec, _src => tokens, parse_root)
  inspect(gate_result, content="false")
  inspect(diagnostics.is_empty(), content="true")
  match tree.children[0] {
    @seam.CstElement::Node(root) => inspect(root.children.length(), content="0")
    @seam.CstElement::Token(_) => abort("expected the Root node with no children")
  }
}

///|
test "interpret falls back on second Choice arm when HostGuard returns false" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Node(
      TestKind::Root,
      Expr::Choice([
        Alt::{
          starts: Pred::All(
            Pred::IsToken(TestToken::Int),
            Pred::HostGuard("never_pass"),
          ),
          body: Expr::Emit(TestToken::Int, TestKind::WordToken),
        },
        Alt::{
          starts: Pred::IsToken(TestToken::Int),
          body: Expr::Emit(TestToken::Int, TestKind::IntToken),
        },
      ]),
    ),
  }
  let guards : Map[RuleName, HostGuard[TestToken, TestKind]] = {
    "never_pass": fn(_ctx) { false },
  }
  let parse_root = interpret(
    GrammarIr::GrammarIr(rules, root="source"),
    guards~,
  )
  let spec = test_spec(parse_root)
  let tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let (tree, _) = @core.parse_with("1", spec, _src => tokens, parse_root)
  match tree.children[0] {
    @seam.CstElement::Node(root) => inspect(root.children.length(), content="1")
    _ => fail("expected Root node")
  }
}
