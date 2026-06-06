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
/// Single Loom grammar handle for the skeleton.
///
/// Future milestones should refine `parse_moonbit_root` and `moonbit_fold_node`
/// behind this value rather than changing downstream call sites.
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
