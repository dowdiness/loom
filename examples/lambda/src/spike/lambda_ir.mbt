///|
/// Hand-authored grammar IR for the lambda language.
///
/// IR coverage note (E1 accounting after Track 2 Seq+Pratt extension):
///   Declarative (5/7): source, expression, binary, application, atom.
///   Escape hatches (2/7):
///     - definition: called directly from parse_top_level_repeat; the
///       soft-newline-before-expression combinator + LeftParen guard +
///       param-list are all in-function logic not yet in the IR.
///     - param_list: ManualParamList — mark/start_at retroactive-wrap
///       dance for the positional grammar cannot be expressed with current
///       combinators.
///
/// Source, Expression: Ref delegation — declarative (zero escape-hatch).
/// Binary: PrattBinary — fully declarative Pratt binary.
/// Application: PrattApp — fully declarative Pratt left-assoc application.
/// Atom: Choice + Seq — fully declarative per-token dispatch.
pub fn lambda_spike_ir(cripple_reuse? : Bool) -> GrammarIr {
  let cr = cripple_reuse.unwrap_or(false)
  GrammarIr::{
    // Dispatched via interpret() → run_expr(ctx, ir, ir.rule(Source)).
    source: Expr::RepeatTopLevel(RuleId::Definition, cr),
    // Not dispatched via IR — parse_definition_ir() is called directly from
    // parse_top_level_repeat. Documented Empty to avoid invisible gap.
    definition: Expr::Empty,
    // Expression = Binary (no if-then-else in spike scope).
    expression: Expr::Ref(RuleId::Binary),
    // Pratt binary: left-associative + and - over applications.
    binary: Expr::PrattBinary(RuleId::Application, @syntax.BinaryExpr, [
      (@token.Plus, @syntax.PlusToken),
      (@token.Minus, @syntax.MinusToken),
    ]),
    // Pratt application: left-associative juxtaposition of atoms.
    application: Expr::PrattApp(
      RuleId::Atom,
      @syntax.AppExpr,
      atom_starts_token,
    ),
    // Atom: token-dispatched choice. BlockExpr uses RepeatWhile for newlines.
    // No arrow-lambda (classified D2a divergence for lambda-literal inputs).
    atom: Expr::Choice([
      Alt::{
        starts: t => t == @token.Integer,
        body: Expr::Node(
          @syntax.IntLiteral,
          Expr::Emit(@token.Integer, @syntax.IntToken),
        ),
      },
      Alt::{
        starts: t => t == @token.Identifier,
        body: Expr::Node(
          @syntax.VarRef,
          Expr::Emit(@token.Identifier, @syntax.IdentToken),
        ),
      },
      Alt::{
        starts: t => t == @token.Hole,
        body: Expr::Node(
          @syntax.HoleLiteral,
          Expr::Emit(@token.Hole, @syntax.HoleToken),
        ),
      },
      Alt::{
        starts: t => t == @token.LBrace,
        body: Expr::Node(
          @syntax.BlockExpr,
          Expr::Seq([
            Expr::Emit(@token.LBrace, @syntax.LBraceToken),
            Expr::RepeatWhile(
              t => t == @token.Newline,
              Expr::Emit(@token.Newline, @syntax.NewlineToken),
            ),
            Expr::Choice([
              Alt::{
                starts: t => t == @token.RBrace,
                body: Expr::EmitError("Empty block expression"),
              },
              Alt::{
                starts: t => t != @token.EOF,
                body: Expr::Seq([
                  // Mirror A's definition loop before the trailing expression.
                  Expr::RepeatWhile(
                    token_starts_definition,
                    Expr::Seq([
                      Expr::ManualDefinition,
                      Expr::RepeatWhile(
                        t => t == @token.Newline,
                        Expr::Emit(@token.Newline, @syntax.NewlineToken),
                      ),
                    ]),
                  ),
                  // Optional trailing expression.
                  Expr::Choice([
                    Alt::{ starts: t => t == @token.RBrace, body: Expr::Empty },
                    Alt::{
                      starts: t => t != @token.EOF,
                      body: Expr::Seq([
                        Expr::Ref(RuleId::Binary),
                        Expr::RepeatWhile(
                          t => t == @token.Newline,
                          Expr::Emit(@token.Newline, @syntax.NewlineToken),
                        ),
                      ]),
                    },
                  ]),
                ]),
              },
            ]),
            Expr::Expect(@token.RBrace, @syntax.RBraceToken, "expected }"),
          ]),
        ),
      },
      Alt::{
        starts: t => t == @token.LeftParen,
        body: Expr::Node(
          @syntax.ParenExpr,
          Expr::Seq([
            Expr::Emit(@token.LeftParen, @syntax.LeftParenToken),
            Expr::Ref(RuleId::Binary),
            Expr::Expect(
              @token.RightParen,
              @syntax.RightParenToken,
              "expected )",
            ),
          ]),
        ),
      },
      Alt::{
        starts: _t => true,
        body: Expr::ErrorUntil(
          spike_is_sync_point, "Unexpected token in expression",
        ),
      },
    ]),
    // Not dispatched via IR — parse_param_list_exact is called directly.
    param_list: Expr::ManualParamList,
  }
}

///|
/// Build a SyntaxGrammar with the spike's NORMALIZED incremental config, so the
/// ONLY difference between A and B is `spec.parse_root`. Both A and B are built
/// through this function.
///
/// VERIFIED confound (grammar.mbt:14-15): A's lambda_grammar uses
/// incremental_relex_enabled=false + block_reparse_spec=Some(...), but
/// SyntaxGrammar::new defaults are true/None — so without normalization,
/// newline edits (relex) and BlockExpr edits (block reparse) would diverge in
/// reuse_count and diagnostics because of PARSER CONFIG, not the grammar IR.
/// We pin both axes OFF: relex=false (matches A; full relex each edit is
/// correct) and block_reparse=None (NOT Some(lambda_block_reparse_spec) — that
/// spec's get_reparser invokes A's hand reparser inside blocks for B too,
/// defeating the test). Block-reparse and incremental-relex-path parity are
/// deferred follow-ups (see plan §NON-GOALS); BlockExpr is not in the minimal
/// spike slice.
pub fn normalized_syntax_grammar(
  spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind],
  lex : (String) -> @core.LexResult[@token.Token],
) -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  @loom.SyntaxGrammar::new(
    spec~,
    lex~,
    incremental_relex_enabled=false,
    block_reparse_spec=None,
  )
}

///|
/// Build B's SyntaxGrammar. B uses the spike's grammar IR interpreted into a
/// parse_root closure. A and B differ ONLY in `spec.parse_root`.
///
/// `incomplete_kind` is deliberately OMITTED to mirror A's lambda_spec exactly
/// (A also omits it). VERIFIED: LanguageSpec::new defaults incomplete_kind to
/// error_kind (@syntax.ErrorToken for lambda), so A and B get identical
/// incomplete_kind. Passing it explicitly would still be equivalent but would
/// break the literal mirror.
pub fn build_b_syntax_grammar(
  cripple_reuse? : Bool,
) -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  let ir = lambda_spike_ir(cripple_reuse=cripple_reuse.unwrap_or(false))
  let parse_root = interpret(ir)
  let b_spec = @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    parse_root~,
    reuse_size_threshold=0,
  )
  normalized_syntax_grammar(b_spec, @lexer.lex)
}
