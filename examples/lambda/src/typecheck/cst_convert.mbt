// cst_convert.mbt — CST (SyntaxNode) → Type conversion.
//
// Converts a type-position CST subtree into a `Type` value, preserving
// type annotations that the Term-based convert() cannot (which always
// emits None annotations).

///|
/// Convert a type-position CST subtree into a `Type`.
/// Returns `TError` for unrecognized kinds or any subtree containing an ErrorNode.
pub fn type_of_node(n : @seam.SyntaxNode) -> Type {
  if has_error_descendant(n) {
    return TError
  }
  match @syntax.SyntaxKind::from_raw(n.kind()) {
    TypeInt => TInt
    TypeUnit => TUnit
    TypeArrow => {
      // TypeArrow has two type children: lhs and rhs.
      let cs = n.children()
      if cs.length() < 2 {
        TError
      } else {
        TArrow(type_of_node(cs[0]), type_of_node(cs[1]))
      }
    }
    _ => TError
  }
}

///|
/// Returns true if `n` or any descendant is an ErrorNode.
fn has_error_descendant(n : @seam.SyntaxNode) -> Bool {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.SyntaxKind::ErrorNode {
    return true
  }
  for c in n.children() {
    if has_error_descendant(c) {
      return true
    }
  }
  false
}
