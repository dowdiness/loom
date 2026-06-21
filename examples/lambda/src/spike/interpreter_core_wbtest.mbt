///|
test "interpreter smoke: parse single integer literal via IR" {
  let ir = GrammarIr::{
    source: Expr::Node(
      @syntax.SourceFile,
      Expr::Node(
        @syntax.IntLiteral,
        Expr::Emit(@token.Integer, @syntax.IntToken),
      ),
    ),
    definition: Expr::Empty,
    expression: Expr::Empty,
    binary: Expr::Empty,
    application: Expr::Empty,
    atom: Expr::Empty,
    param_list: Expr::Empty,
  }
  let spec = @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    parse_root=interpret(ir),
    reuse_size_threshold=0,
  )
  let grammar = @loom.SyntaxGrammar::new(
    spec~,
    lex=@lexer.lex,
    incremental_relex_enabled=false,
    block_reparse_spec=None,
  )
  let (cst, diag) = grammar.parse_cst("1")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax.children().length() >= 1, content="true")
  inspect(diag.is_empty(), content="true")
}
