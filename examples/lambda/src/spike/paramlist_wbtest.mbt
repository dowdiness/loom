///|
fn fn_grammar() -> GrammarIr {
  GrammarIr::{
    source: Expr::RepeatTopLevel(RuleId::Definition, false),
    definition: Expr::Empty,
    expression: Expr::Ref(RuleId::Binary),
    binary: Expr::Ref(RuleId::Application),
    application: Expr::Ref(RuleId::Atom),
    atom: Expr::Choice([
      Alt::{
        starts: fn(t) { t == @token.Integer },
        body: Expr::Node(@syntax.IntLiteral, Expr::Emit(@token.Integer, @syntax.IntToken)),
      },
      Alt::{
        starts: fn(t) { t == @token.Identifier },
        body: Expr::Node(@syntax.VarRef, Expr::Emit(@token.Identifier, @syntax.IdentToken)),
      },
    ]),
    param_list: Expr::ManualParamList,
  }
}

///|
fn build_fn_grammar() -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  let spec = @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    parse_root=interpret(fn_grammar()),
    reuse_size_threshold=0,
  )
  @loom.SyntaxGrammar::new(
    spec~,
    lex=@lexer.lex,
    incremental_relex_enabled=false,
    block_reparse_spec=None,
  )
}

///|
test "task6: fn with single param matches A" {
  let source = "fn f(x) { 1 }"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_fn_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "task6: fn with two params matches A" {
  let source = "fn f(x, y) { 1 }"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_fn_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "task6: fn with trailing comma matches A CST (error in both)" {
  let source = "fn f(x,) { 1 }"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  let b_grammar = build_fn_grammar()
  let (b_cst, b_diag) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
  // Both parsers should emit a "Trailing comma" diagnostic
  inspect(a_diag.items().length() > 0, content="true")
  inspect(b_diag.items().length() > 0, content="true")
}
