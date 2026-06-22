///|
/// Lambda grammar authored as a generic `@grammar.GrammarIr` value (loomgen
/// IR-contract, Task 7). This replaces the spike-local closure IR
/// (`lambda_spike_ir`): predicates are reified `@grammar.Pred` data, rule
/// references are open string names, and the four lambda escape hatches are
/// reduced to the grown vocabulary (spec §5.3) — `ManualDefinition`,
/// `ManualParamList`, and `ManualBlockDelimiterCheck` are gone, expressed with
/// `Node`/`Seq`/`Choice`/`EmitOr`/`DiagnoseIf`/`ExpectSkip`/`ConsumeGated`/
/// `Fail`/`RequireSep`/`WrapIfNext`/`ErrorNodeUntil`.
///
/// `ManualNewlineAppExpr` is the lone residue (§5.1): it is kept as a node and
/// handled by the spike-local probe interpreter, NOT by `@grammar.interpret`
/// (which placeholders it). The probe carries the recursive newline-application
/// mode and the reuse-cripple toggle that a static `@grammar` value cannot.
///
/// Every spike `Expect(_, _, msg)` routed through `spike_expect`
/// (consume-soft-newlines-then-expect), so it reifies to `ExpectSkip` over
/// `Newline`; the unused `msg` is intentionally dropped (spec §3.1).

///|
/// Tokens that may open an application atom (mirrors `atom_starts_token`).
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
/// Tokens that may open an expression after a soft newline (mirrors
/// `spike_starts_expression`); gates `let x =\n<expr>`.
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
/// Error-recovery sync points (mirrors `spike_is_sync_point`).
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
/// The reified lambda grammar. Root rule is `source`.
pub fn lambda_grammar_ir() -> @grammar.GrammarIr[
  @token.Token,
  @syntax.SyntaxKind,
] {
  let block_delimiter_msg = "Expected ';' or newline between definitions"
  let rules : Map[String, @grammar.Expr[@token.Token, @syntax.SyntaxKind]] = {
    // Top level: delimited definition repeat, then an optional trailing
    // newline-application expression, then trailing-garbage recovery. The
    // RepeatTopLevel node owns the leading-delimiter consume, the reuse loop,
    // and the between/after delimiter diagnostics; the Seq tail mirrors
    // parse_top_level_repeat's post-loop trailing-expr + garbage handling.
    "source": @grammar.Expr::Seq([
      @grammar.Expr::RepeatTopLevel(
        "definition",
        starts=@grammar.Pred::OneOf([@token.Fn, @token.Let]),
        delim=@grammar.Pred::IsToken(@token.Newline),
        delim_kind=@syntax.NewlineToken,
        between_msg="Expected newline between top-level definitions",
        after_msg="Expected newline after top-level definition",
      ),
      // Trailing expression (newline-application mode) unless at EOF.
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
      // Consume delimiter newlines after the trailing expression.
      @grammar.Expr::RepeatWhile(
        @grammar.Pred::IsToken(@token.Newline),
        @grammar.Expr::Emit(@token.Newline, @syntax.NewlineToken),
      ),
      // Trailing-token error recovery: open an ErrorNode over the garbage,
      // EOF-guarded so it never opens an empty node.
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
    // One definition: let-binding or fn-definition.
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
    // Expression = binary (no if-then-else in the spike scope).
    "expression": @grammar.Expr::Ref("binary"),
    // Pratt binary: left-associative + and - over applications.
    "binary": @grammar.Expr::PrattBinary("application", @syntax.BinaryExpr, [
      (@token.Plus, @syntax.PlusToken),
      (@token.Minus, @syntax.MinusToken),
    ]),
    // Pratt application: left-associative juxtaposition of atoms.
    "application": @grammar.Expr::PrattApp(
      "atom",
      @syntax.AppExpr,
      lambda_atom_starts(),
    ),
    // Atom: token-dispatched choice.
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
                  // Definition loop, mirroring A's block delimiter check.
                  @grammar.Expr::RepeatWhile(
                    @grammar.Pred::OneOf([@token.Fn, @token.Let]),
                    @grammar.Expr::Seq([
                      @grammar.Expr::Ref("definition"),
                      @grammar.Expr::RequireSep(
                        @grammar.Pred::IsToken(@token.Newline),
                        @syntax.NewlineToken,
                        @grammar.Pred::OneOf([@token.RBrace, @token.EOF]),
                        @grammar.Pred::Any,
                        msg_alt=block_delimiter_msg,
                        msg_else=block_delimiter_msg,
                      ),
                    ]),
                  ),
                  // Optional trailing expression (newline-application mode).
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
    // Parameter list: retroactively wrapped in ParamList when '(' opens it.
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
  @grammar.GrammarIr::GrammarIr(rules, root="source")
}
