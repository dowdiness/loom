// JSON language specification for the generic parser infrastructure.
// Constructed via the loomgen-generated factory in spec.g.mbt (issue #565);
// regenerate with the "Verify spec generation" step command in ci.yml.

///|
/// LanguageSpec for JSON grammar.
/// reuse_size_threshold=0: all nodes eligible for reuse. MemberNode uses ctx.node()
/// so individual object members can be reused during incremental parsing.
let json_spec : @core.LanguageSpec[Token, SyntaxKind] = make_json_spec(
  parse_json_root,
  reuse_size_threshold=0,
)
