///|
/// Language specification for the MoonBit parser skeleton.
let moonbit_spec : @core.LanguageSpec[MoonToken, MoonbitSyntaxKind] = @core.LanguageSpec::new(
  TriviaToken,
  ErrorToken,
  SourceFileNode,
  EOF,
  incomplete_kind=IncompleteToken,
  parse_root=parse_moonbit_root,
  reuse_size_threshold=0,
)

///|
/// Syntax-only Loom grammar handle for the skeleton.
///
/// This is the preferred entry point for reactive CST/diagnostics consumers:
/// it does not require a placeholder AST or `Ast : Eq`.
pub let moonbit_syntax_grammar : @loom.SyntaxGrammar[
  MoonToken,
  MoonbitSyntaxKind,
] = @loom.SyntaxGrammar::new(
  spec=moonbit_spec,
  lex=fn(source) { lex_moonbit(source) },
  incremental_relex_enabled=false,
)

///|
/// AST-folding Loom grammar handle for placeholder smoke tests.
///
/// Future milestones should replace `MoonbitParseShell` and
/// `moonbit_fold_node` with the official AST projection. CST/diagnostics-only
/// consumers should use `moonbit_syntax_grammar` instead.
pub let moonbit_grammar : @loom.Grammar[
  MoonToken,
  MoonbitSyntaxKind,
  MoonbitParseShell,
] = @loom.Grammar::new(
  spec=moonbit_spec,
  lex=fn(source) { lex_moonbit(source) },
  fold_node=moonbit_fold_node,
  incremental_relex_enabled=false,
)
