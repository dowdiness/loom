// JSON language specification for the generic parser infrastructure.

///|
/// LanguageSpec for JSON grammar.
/// reuse_size_threshold=0: all nodes eligible for reuse. MemberNode uses ctx.node()
/// so individual object members can be reused during incremental parsing.
let json_spec : @core.LanguageSpec[Token, SyntaxKind] = @core.LanguageSpec::new(
  WhitespaceToken,
  ErrorToken,
  RootNode,
  EOF,
  parse_root=parse_json_root,
  reuse_size_threshold=0,
)
