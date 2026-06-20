// Generic parser infrastructure — AST view contract

///|
/// Marker trait for typed SyntaxNode view types.
///
/// Every view type in your language package should implement this trait
/// and also provide a `pub fn ViewType::cast(n : @seam.SyntaxNode) -> Self?`
/// static function (can't be in the trait — MoonBit traits require self
/// as first parameter).
///
/// Example:
///   pub struct LambdaExprView { node : @seam.SyntaxNode }
///   pub impl AstView for LambdaExprView with syntax_node(self) { self.node }
///   pub fn LambdaExprView::cast(n : @seam.SyntaxNode) -> LambdaExprView? { ... }
pub(open) trait AstView {
  /// Return the underlying raw SyntaxNode.
  fn syntax_node(Self) -> @seam.SyntaxNode
}
