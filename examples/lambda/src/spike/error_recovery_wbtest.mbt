///|
fn error_recovery_grammar() -> GrammarIr {
  GrammarIr::{
    source: Expr::RepeatTopLevel(
      RuleId::Definition,
      token_starts_definition,
      false,
    ),
    definition: Expr::ManualDefinition,
    expression: Expr::Ref(RuleId::Binary),
    binary: Expr::PrattBinary(RuleId::Application, @syntax.BinaryExpr, [
      (@token.Plus, @syntax.PlusToken),
      (@token.Minus, @syntax.MinusToken),
    ]),
    application: Expr::PrattApp(
      RuleId::Atom,
      @syntax.AppExpr,
      atom_starts_token,
    ),
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
      // Catch-all: error node when no atom matches (mirrors A's parse_atom `_` arm).
      Alt::{
        starts: fn(_) { true },
        body: Expr::ErrorUntil(spike_is_sync_point, "Unexpected token"),
      },
    ]),
    param_list: Expr::Empty,
  }
}

///|
fn build_error_recovery_grammar() -> @loom.SyntaxGrammar[
  @token.Token,
  @syntax.SyntaxKind,
] {
  let spec = @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    parse_root=interpret(error_recovery_grammar()),
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
test "task7: missing name 'let = 1' CST matches A" {
  let source = "let = 1"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_error_recovery_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "task7: missing value 'let x =' CST matches A" {
  let source = "let x ="
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_error_recovery_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
test "task7: incomplete binary 'let x = 1 +' CST matches A" {
  let source = "let x = 1 +"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b_grammar = build_error_recovery_grammar()
  let (b_cst, _) = b_grammar.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}
