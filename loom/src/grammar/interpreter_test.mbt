// Shared test token/kind pair for the interpreter test suite. Defined once
// here; reuse_test.mbt and counted_repeat_test.mbt consume these definitions
// (blackbox tests for a package share one compilation unit).

///|
enum TestToken {
  Int
  EOF
} derive(Eq, @debug.Debug)

///|
impl Show for TestToken with fn output(self, logger) {
  logger.write_string(
    match self {
      Int => "Int"
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
    EOF => @seam.RawKind(0)
  }
}

///|
enum TestKind {
  Root
  IntToken
  Error
  Incomplete
} derive(Eq, @debug.Debug)

///|
impl @seam.ToRawKind for TestKind with fn to_raw(self) {
  match self {
    Root => @seam.RawKind(10)
    IntToken => @seam.RawKind(11)
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
