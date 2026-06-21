///|
fn let_grammar() -> GrammarIr {
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
    param_list: Expr::Empty,
  }
}

///|
fn build_let_grammar() -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  let spec = @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    parse_root=interpret(let_grammar()),
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
test "task5: two let defs get repeat-group reuse after editing second def" {
  let source = "let x = 1\nlet y = 2"
  let b_grammar = build_let_grammar()
  let parser = @loom.new_syntax_parser(source, b_grammar)
  // Edit: change "2" at position 18 to "3": "let x = 1\nlet y = 3"
  let edit = @core.Edit::new(18, 1, 1)
  let new_source = "let x = 1\nlet y = 3"
  parser.apply_edit(edit, new_source)
  let snapshot = parser.snapshot().read_or_abort()
  inspect(snapshot.reuse_count > 0, content="true")
}
