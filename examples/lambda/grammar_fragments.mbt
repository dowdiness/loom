///|
/// Hand-authored fragment bodies for the generated lambda GrammarIr (#611).
///
/// `"SourceFile"` overrides the generated `Node(SourceFile, …)` wrapper
/// (merge loop replaces it), producing the same bare-body GrammarIr as the
/// spike's hand-authored `lambda_grammar_ir()`. All other rules are
/// unprefixed keys resolved by `Ref()` targets inside the fragment bodies.
fn lambda_atom_starts() -> @grammar.Pred[@token.Token] {
  @grammar.Pred::OneOf([
    @token.LeftParen,
    @token.LBrace,
    @token.Identifier,
    @token.Integer,
    @token.Hole,
  ])
}

///|
fn lambda_expression_starts() -> @grammar.Pred[@token.Token] {
  @grammar.Pred::OneOf([
    @token.If,
    @token.LeftParen,
    @token.LBrace,
    @token.Hole,
    @token.Identifier,
    @token.Integer,
  ])
}

///|
fn lambda_sync_points() -> @grammar.Pred[@token.Token] {
  @grammar.Pred::OneOf([
    @token.Newline,
    @token.RightParen,
    @token.LBrace,
    @token.RBrace,
    @token.Semicolon,
    @token.Lambda,
    @token.Let,
    @token.Fn,
    @token.FatArrow,
    @token.If,
    @token.Then,
    @token.Else,
    @token.EOF,
  ])
}

///|
/// Default fragment bodies for the lambda grammar (mirrors spike's
/// `lambda_grammar_ir()` rule bodies exactly).
pub fn default_grammar_fragments() -> Map[
  String,
  @grammar.Expr[@token.Token, @syntax.SyntaxKind],
] {
  let block_delimiter_msg = "Expected ';' or newline between definitions"
  {
    "SourceFile": @grammar.Expr::Seq([
      @grammar.Expr::RepeatTopLevel(
        "definition",
        starts=@grammar.Pred::OneOf([@token.Fn, @token.Let]),
        delim=@grammar.Pred::IsToken(@token.Newline),
        delim_kind=@syntax.NewlineToken,
        between_msg="Expected newline between top-level definitions",
        after_msg="Expected newline after top-level definition",
      ),
      @grammar.Expr::Choice([
        @grammar.Alt::{
          starts: @grammar.Pred::IsToken(@token.EOF),
          body: @grammar.Expr::Empty,
        },
        @grammar.Alt::{
          starts: @grammar.Pred::Any,
          body: @grammar.Expr::ManualNewlineAppExpr,
        },
      ]),
      @grammar.Expr::RepeatWhile(
        @grammar.Pred::IsToken(@token.Newline),
        @grammar.Expr::Emit(@token.Newline, @syntax.NewlineToken),
      ),
      @grammar.Expr::Choice([
        @grammar.Alt::{
          starts: @grammar.Pred::IsToken(@token.EOF),
          body: @grammar.Expr::Empty,
        },
        @grammar.Alt::{
          starts: @grammar.Pred::Any,
          body: @grammar.Expr::ErrorNodeUntil(
            @syntax.ErrorNode,
            @grammar.Pred::IsToken(@token.EOF),
            "unexpected tokens after expression",
          ),
        },
      ]),
    ]),
    "definition": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.Let),
        body: @grammar.Expr::Node(
          @syntax.LetDef,
          @grammar.Expr::Seq([
            @grammar.Expr::Emit(@token.Let, @syntax.LetKeyword),
            @grammar.Expr::EmitOr(
              @token.Identifier,
              @syntax.IdentToken,
              "expected name after 'let'",
            ),
            @grammar.Expr::DiagnoseIf(
              @grammar.Pred::IsToken(@token.LeftParen),
              "'let' declarations do not take parameter lists; use 'fn'",
            ),
            @grammar.Expr::ExpectSkip(
              @grammar.Pred::IsToken(@token.Newline),
              @syntax.NewlineToken,
              @token.Eq,
              @syntax.EqToken,
            ),
            @grammar.Expr::ConsumeGated(
              @grammar.Pred::IsToken(@token.Newline),
              @syntax.NewlineToken,
              lambda_expression_starts(),
            ),
            @grammar.Expr::Ref("expression"),
          ]),
        ),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.Fn),
        body: @grammar.Expr::Node(
          @syntax.LetDef,
          @grammar.Expr::Seq([
            @grammar.Expr::Emit(@token.Fn, @syntax.FnKeyword),
            @grammar.Expr::EmitOr(
              @token.Identifier,
              @syntax.IdentToken,
              "Expected function name after 'fn'",
            ),
            @grammar.Expr::Choice([
              @grammar.Alt::{
                starts: @grammar.Pred::IsToken(@token.LeftParen),
                body: @grammar.Expr::Ref("param_list"),
              },
              @grammar.Alt::{
                starts: @grammar.Pred::Any,
                body: @grammar.Expr::Fail(
                  "Expected parameter list after function name",
                ),
              },
            ]),
            @grammar.Expr::Choice([
              @grammar.Alt::{
                starts: @grammar.Pred::IsToken(@token.LBrace),
                body: @grammar.Expr::Ref("atom"),
              },
              @grammar.Alt::{
                starts: @grammar.Pred::Any,
                body: @grammar.Expr::Fail("Expected function body"),
              },
            ]),
          ]),
        ),
      },
    ]),
    "expression": @grammar.Expr::Ref("binary"),
    "binary": @grammar.Expr::PrattBinary(
      "application",
      @syntax.BinaryExpr,
      [(@token.Plus, @syntax.PlusToken), (@token.Minus, @syntax.MinusToken)],
      skip=Some((@grammar.Pred::IsToken(@token.Newline), @syntax.NewlineToken)),
    ),
    "application": @grammar.Expr::PrattApp(
      "atom",
      @syntax.AppExpr,
      lambda_atom_starts(),
    ),
    "atom": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.Integer),
        body: @grammar.Expr::Node(
          @syntax.IntLiteral,
          @grammar.Expr::Emit(@token.Integer, @syntax.IntToken),
        ),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.Identifier),
        body: @grammar.Expr::Node(
          @syntax.VarRef,
          @grammar.Expr::Emit(@token.Identifier, @syntax.IdentToken),
        ),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.Hole),
        body: @grammar.Expr::Node(
          @syntax.HoleLiteral,
          @grammar.Expr::Emit(@token.Hole, @syntax.HoleToken),
        ),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.LBrace),
        body: @grammar.Expr::Node(
          @syntax.BlockExpr,
          @grammar.Expr::Seq([
            @grammar.Expr::Emit(@token.LBrace, @syntax.LBraceToken),
            @grammar.Expr::RepeatWhile(
              @grammar.Pred::IsToken(@token.Newline),
              @grammar.Expr::Emit(@token.Newline, @syntax.NewlineToken),
            ),
            @grammar.Expr::Choice([
              @grammar.Alt::{
                starts: @grammar.Pred::IsToken(@token.RBrace),
                body: @grammar.Expr::EmitError("Empty block expression"),
              },
              @grammar.Alt::{
                starts: @grammar.Pred::Not(@grammar.Pred::IsToken(@token.EOF)),
                body: @grammar.Expr::Seq([
                  @grammar.Expr::RepeatWhile(
                    @grammar.Pred::OneOf([@token.Fn, @token.Let]),
                    @grammar.Expr::Seq([
                      @grammar.Expr::Ref("definition"),
                      @grammar.Expr::RequireSep(
                        [
                          (@token.Newline, @syntax.NewlineToken),
                          (@token.Semicolon, @syntax.SemicolonToken),
                        ],
                        @grammar.Pred::OneOf([@token.RBrace, @token.EOF]),
                        @grammar.Pred::Any,
                        msg_alt=block_delimiter_msg,
                        msg_else=block_delimiter_msg,
                      ),
                    ]),
                  ),
                  @grammar.Expr::Choice([
                    @grammar.Alt::{
                      starts: @grammar.Pred::IsToken(@token.RBrace),
                      body: @grammar.Expr::Empty,
                    },
                    @grammar.Alt::{
                      starts: @grammar.Pred::Not(
                        @grammar.Pred::IsToken(@token.EOF),
                      ),
                      body: @grammar.Expr::ManualNewlineAppExpr,
                    },
                  ]),
                ]),
              },
            ]),
            @grammar.Expr::ExpectSkip(
              @grammar.Pred::IsToken(@token.Newline),
              @syntax.NewlineToken,
              @token.RBrace,
              @syntax.RBraceToken,
            ),
          ]),
        ),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.LeftParen),
        body: @grammar.Expr::Node(
          @syntax.ParenExpr,
          @grammar.Expr::Seq([
            @grammar.Expr::Emit(@token.LeftParen, @syntax.LeftParenToken),
            @grammar.Expr::Ref("binary"),
            @grammar.Expr::ExpectSkip(
              @grammar.Pred::IsToken(@token.Newline),
              @syntax.NewlineToken,
              @token.RightParen,
              @syntax.RightParenToken,
            ),
          ]),
        ),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::Any,
        body: @grammar.Expr::ErrorUntil(
          lambda_sync_points(),
          "Unexpected token in expression",
        ),
      },
    ]),
    "param_list": @grammar.Expr::WrapIfNext(
      @syntax.ParamList,
      @grammar.Pred::IsToken(@token.LeftParen),
      @grammar.Expr::Seq([
        @grammar.Expr::Emit(@token.LeftParen, @syntax.LeftParenToken),
        @grammar.Expr::Choice([
          @grammar.Alt::{
            starts: @grammar.Pred::IsToken(@token.RightParen),
            body: @grammar.Expr::Empty,
          },
          @grammar.Alt::{
            starts: @grammar.Pred::IsToken(@token.Identifier),
            body: @grammar.Expr::Seq([
              @grammar.Expr::Emit(@token.Identifier, @syntax.IdentToken),
              @grammar.Expr::RepeatWhile(
                @grammar.Pred::IsToken(@token.Comma),
                @grammar.Expr::Seq([
                  @grammar.Expr::Emit(@token.Comma, @syntax.CommaToken),
                  @grammar.Expr::Choice([
                    @grammar.Alt::{
                      starts: @grammar.Pred::IsToken(@token.Identifier),
                      body: @grammar.Expr::Emit(
                        @token.Identifier,
                        @syntax.IdentToken,
                      ),
                    },
                    @grammar.Alt::{
                      starts: @grammar.Pred::IsToken(@token.RightParen),
                      body: @grammar.Expr::EmitError(
                        "Trailing comma in parameter list",
                      ),
                    },
                    @grammar.Alt::{
                      starts: @grammar.Pred::Any,
                      body: @grammar.Expr::Fail("Expected parameter name"),
                    },
                  ]),
                ]),
              ),
            ]),
          },
          @grammar.Alt::{
            starts: @grammar.Pred::Any,
            body: @grammar.Expr::Fail("Expected parameter name"),
          },
        ]),
        @grammar.Expr::ExpectSkip(
          @grammar.Pred::IsToken(@token.Newline),
          @syntax.NewlineToken,
          @token.RightParen,
          @syntax.RightParenToken,
        ),
      ]),
    ),
  }
}
