///|
/// Term kind metadata for loomgen generation of the jsx example.
/// Contains the #loom.term enum defining CST node types that appear in SyntaxKind.
#loom.term
pub(all) enum TermKind {
  #loom.node
  ElementNode
  #loom.node
  FragmentNode
  #loom.node
  AttrNode
  // `{...}` embedded-expression span — wraps BraceOpen, zero or more
  // ExprRawText/ExprStringUnterminated content tokens, and an optional
  // BraceClose (absent when EOF truncates the expression). Needs its own
  // node kind, not a bare token, so fold_node can concatenate the raw
  // content tokens into one JsxNode::ExprSpan(raw) — see the 2026-07-10
  // Task 1.1 design gate, Design B case 4.
  #loom.node
  ExprSpanNode
  #loom.leaf
  TextLeaf
  #loom.errornode
  ErrorNode
  #loom.root
  RootNode
}
