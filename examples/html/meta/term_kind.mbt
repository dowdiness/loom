///|
/// Term kind metadata for loomgen generation of the html example.
/// Contains the #loom.term enum defining CST node types that appear in SyntaxKind.
#loom.term
pub(all) enum TermKind {
  #loom.node
  ElementNode
  #loom.node
  VoidElementNode
  #loom.node
  SelfClosingElementNode
  #loom.node
  DoctypeNode
  #loom.node
  CommentNode
  #loom.node
  AttributeNode
  #loom.leaf
  TextLeaf
  #loom.leaf
  RawTextLeaf
  #loom.errornode
  ErrorNode
  #loom.root
  RootNode
}
