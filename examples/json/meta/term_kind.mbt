///|
/// Term kind metadata for loomgen generation of the json example.
/// Contains the #loom.term enum defining CST node types that appear in SyntaxKind.
/// This is the single source of truth for CST term-kind metadata; the token enum
/// lives in examples/json/token.mbt (see issue #563 for the layout decision).
///
/// NOT part of any package (this directory has no moon.pkg): json is a single
/// package, so compiling TermKind here would make its constructors ambiguous
/// with SyntaxKind's. Consumed by loomgen at generation time via --term.
/// Variant order mirrors the raw-kind numbering in syntax_kind.mbt (raws 14-22)
/// so a future --seed generation of that file preserves seam RawKind identity
/// (issue #565 step 3).
#loom.term
pub(all) enum TermKind {
  #loom.node
  ObjectNode
  #loom.node
  ArrayNode
  #loom.node
  MemberNode
  #loom.leaf
  StringValue
  #loom.leaf
  NumberValue
  #loom.leaf
  BoolValue
  #loom.leaf
  NullValue
  #loom.errornode
  ErrorNode
  #loom.root
  RootNode
}
