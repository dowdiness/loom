///|
/// Hand-authored CSS GrammarIr for parity test against the loomgen-generated
/// `css_grammar_ir` from `#loom.rule` annotations. The two must be structurally
/// identical so that `@grammar.interpret` produces equivalent parse behavior.
pub fn css_ir() -> @grammar.GrammarIr[@token.Token, @syntax.SyntaxKind] {
  let rules : Map[String, @grammar.Expr[@token.Token, @syntax.SyntaxKind]] = {
    "Stylesheet": @grammar.Expr::Node(
      @syntax.Stylesheet,
      @grammar.Expr::Seq([
        @grammar.Expr::RepeatWhile(
          @grammar.Pred::IsToken(@token.Ident),
          @grammar.Expr::Ref("Rule"),
        ),
        @grammar.Expr::Expect(@token.EOF, @syntax.EofToken),
      ]),
    ),
    "Rule": @grammar.Expr::Node(
      @syntax.Rule,
      @grammar.Expr::Seq([
        @grammar.Expr::Emit(@token.Ident, @syntax.IdentToken),
        @grammar.Expr::Expect(@token.LBrace, @syntax.LBraceToken),
        @grammar.Expr::Ref("Decls"),
        @grammar.Expr::Expect(@token.RBrace, @syntax.RBraceToken),
      ]),
    ),
    "Decls": @grammar.Expr::Node(
      @syntax.Decls,
      @grammar.Expr::Seq([
        @grammar.Expr::RepeatWhile(
          @grammar.Pred::IsToken(@token.Ident),
          @grammar.Expr::Ref("Decl"),
        ),
        @grammar.Expr::ErrorUntil(
          @grammar.Pred::IsToken(@token.RBrace),
          "expected 'RBrace'",
        ),
      ]),
    ),
    "Decl": @grammar.Expr::Node(
      @syntax.Decl,
      @grammar.Expr::Seq([
        @grammar.Expr::EmitOr(
          @token.Ident,
          @syntax.IdentToken,
          "expected 'Ident'",
        ),
        @grammar.Expr::EmitOr(
          @token.Colon,
          @syntax.ColonToken,
          "expected 'Colon'",
        ),
        @grammar.Expr::RepeatWhile(
          @grammar.Pred::OneOf([@token.Ident, @token.Number]),
          @grammar.Expr::Choice([
            @grammar.Alt::{
              starts: @grammar.Pred::IsToken(@token.Ident),
              body: @grammar.Expr::Expect(@token.Ident, @syntax.IdentToken),
            },
            @grammar.Alt::{
              starts: @grammar.Pred::IsToken(@token.Number),
              body: @grammar.Expr::Expect(@token.Number, @syntax.NumberToken),
            },
            @grammar.Alt::{
              starts: @grammar.Pred::Any,
              body: @grammar.Expr::Fail("expected one of: Ident, Number"),
            },
          ]),
        ),
        @grammar.Expr::EmitOr(
          @token.Semicolon,
          @syntax.SemicolonToken,
          "expected 'Semicolon'",
        ),
      ]),
    ),
  }
  @grammar.GrammarIr::GrammarIr(rules, root="Stylesheet")
}
