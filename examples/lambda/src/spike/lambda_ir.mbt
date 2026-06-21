///|
/// Hand-authored grammar IR for the lambda language.
///
/// IR coverage note (E2 accounting):
/// - `source` and `atom` are the only rules dispatched through the IR via
///   `run_expr`. All other rules are invoked directly by the hardcoded
///   interpreter functions (`parse_definition_ir`, `parse_binary_ir`,
///   `parse_top_level_repeat`). This is an E2 escape-hatch finding:
///   the declarative IR model covers only 2 of 7 rules for lambda.
/// - `atom`: ManualAtom (E2 lambda-specific — LeftParen/LBrace/error handling).
/// - `param_list`: ManualParamList (E2 lambda-specific — mark/start_at dance).
/// - `definition`: Empty (never dispatched via IR; called directly).
/// - `expression`, `binary`, `application`: Ref variants (special-cased or
///   never dispatched via IR in this spike).
pub fn lambda_spike_ir(cripple_reuse? : Bool) -> GrammarIr {
  let cr = cripple_reuse.unwrap_or(false)
  GrammarIr::{
    // Dispatched via interpret() → run_expr(ctx, ir, ir.rule(Source)).
    source: Expr::RepeatTopLevel(RuleId::Definition, cr),
    // Not dispatched via IR — parse_definition_ir() is called directly from
    // parse_top_level_repeat. Documented Empty to avoid invisible gap.
    definition: Expr::Empty,
    // Simplified: no if-then-else in spike. parse_top_level_repeat calls
    // parse_binary_ir directly for trailing expression.
    expression: Expr::Ref(RuleId::Binary),
    // Special-cased in run_expr → parse_binary_ir(ctx, ir).
    binary: Expr::Ref(RuleId::Binary),
    // Special-cased in run_expr → parse_application_ir(ctx, ir).
    application: Expr::Ref(RuleId::Application),
    // Dispatched via run_expr in parse_application_ir.
    atom: Expr::ManualAtom,
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
    parse_root=parse_root,
    reuse_size_threshold=0,
  )
  normalized_syntax_grammar(b_spec, @lexer.lex)
}
