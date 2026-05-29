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
  walk_children_flat(
    self.cst.children,
    self,
    self.offset,
    fn(child, parent, pos) {
      SyntaxNode::new(child, Some(parent), pos).accept_visitor(visitor)
    },
    fn(tok, pos) { V::visit_token(visitor, SyntaxToken::new(tok, pos)) },
  )
  |> ignore
  V::exit_node(visitor, self)
}
