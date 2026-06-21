///|
/// build_tree wraps parse_root output in SourceFile automatically, so
/// source must NOT add Node(SourceFile, …). Match A's parse_lambda_root shape
/// which also emits content without an explicit start_node/finish_node.
fn minimal_expr_ir() -> GrammarIr {
  GrammarIr::{
    source: Expr::Ref(RuleId::Expression),
    definition: Expr::Empty,
    expression: Expr::Ref(RuleId::Binary),
    binary: Expr::Ref(RuleId::Application),
    application: Expr::Ref(RuleId::Atom),
    atom: Expr::Choice([
      Alt::{
        starts: fn(t) { t == @token.Integer },
        body: Expr::Node(
          @syntax.IntLiteral,
          Expr::Emit(@token.Integer, @syntax.IntToken),
        ),
      },
      Alt::{
        starts: fn(t) { t == @token.Identifier },
        body: Expr::Node(
          @syntax.VarRef,
          Expr::Emit(@token.Identifier, @syntax.IdentToken),
        ),
      },
    ]),
    param_list: Expr::Empty,
  }
}

///|
fn build_expr_grammar(
  ir : GrammarIr,
) -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  let spec = @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    parse_root=interpret(ir),
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
test "pratt: application produces AppExpr matching A" {
  let source = "f y"
  let (a_cst, _) = @lambda.parse_cst(source)
  let ir = minimal_expr_ir()
  let b_grammar = build_expr_grammar(ir)
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "pratt: binary produces BinaryExpr matching A" {
  let source = "a + b - c"
  let (a_cst, _) = @lambda.parse_cst(source)
  let ir = minimal_expr_ir()
  let b_grammar = build_expr_grammar(ir)
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}
