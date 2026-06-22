// Incremental-node interpreter tests. TestToken / TestKind / test_spec are
// defined in interpreter_test.mbt (shared blackbox compilation unit).

///|
/// A wired WrapIfNext emits no diagnostic; the Task-4 placeholder would, so
/// this asserts the incremental node is actually interpreted (red → green).
test "WrapIfNext wraps a matching prefix without spurious diagnostics" {
  let expr : Expr[TestToken, TestKind] = Expr::WrapIfNext(
    TestKind::Root,
    Pred::IsToken(TestToken::Int),
    Expr::Emit(TestToken::Int, TestKind::IntToken),
  )
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = { "source": expr }
  let parse_root = interpret(GrammarIr::GrammarIr(rules, root="source"))
  let spec = test_spec(parse_root)
  let lex = _src => {
    [
      @core.TokenInfo::new(TestToken::Int, 1),
      @core.TokenInfo::new(TestToken::EOF, 0),
    ]
  }
  let (_, diagnostics) = @core.parse_with("1", spec, lex, parse_root)
  inspect(diagnostics.is_empty(), content="true")
}
