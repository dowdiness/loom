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
/// Build B's SyntaxGrammar. B compiles the reified `@grammar` lambda IR
/// (`lambda_grammar_ir`) to dense slots and interprets it through the
/// spike-local probe (`b_parse_root`). A and B differ ONLY in `spec.parse_root`.
///
/// `incomplete_kind` is deliberately OMITTED to mirror A's lambda_spec exactly
/// (A also omits it). VERIFIED: LanguageSpec::new defaults incomplete_kind to
/// error_kind (@syntax.ErrorToken for lambda), so A and B get identical
/// incomplete_kind. Passing it explicitly would still be equivalent but would
/// break the literal mirror.
pub fn build_b_syntax_grammar(
  cripple_reuse? : Bool,
) -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] raise @grammar.GrammarCompileError {
  let ir = lambda_grammar_ir()
  let compiled = @grammar.compile(ir)
  let parse_root = b_parse_root(compiled, cripple_reuse.unwrap_or(false))
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
