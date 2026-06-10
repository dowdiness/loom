// syntax_visitor.mbt — Positioned traversal over SyntaxNode.

///|
/// Mutable visitor for positioned syntax trees.
///
/// Traversal is source-order and uses the same repeat-group flattening as
/// `SyntaxNode::all_children`: `RepeatGroup` CST nodes are transparent, so
/// callbacks receive visible `SyntaxNode` and `SyntaxToken` values only.
///
/// `enter_node` runs before visible children. Return `false` to skip that
/// node's subtree; skipped nodes do not receive `exit_node`.
pub(open) trait SyntaxMutVisitor {
  fn enter_node(Self, SyntaxNode) -> Bool
  fn exit_node(Self, SyntaxNode) -> Unit
  fn visit_token(Self, SyntaxToken) -> Unit
}

///|
/// Walk `self` with a mutable positioned visitor.
///
/// The root node is visited first, then visible direct children in source
/// order. Interior children recurse depth-first; direct tokens call
/// `visit_token`. `RepeatGroup` nodes are flattened transparently, matching
/// `SyntaxNode::children`, `SyntaxNode::all_children`, and related accessors.
pub fn[V : SyntaxMutVisitor] SyntaxNode::accept_visitor(
  self : SyntaxNode,
  visitor : V,
) -> Unit {
  if !V::enter_node(visitor, self) {
    return
  }
  for elem in self.direct_elements_iter() {
    match elem {
      Node(n) => n.accept_visitor(visitor)
      Token(t) => V::visit_token(visitor, t)
    }
  }
  V::exit_node(visitor, self)
}
