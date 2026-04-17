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

///|
/// Convert a CST SyntaxNode into a TypedTerm.
/// Preserves lambda type annotations (which Term-based convert() cannot).
pub fn convert_from_cst(n : @seam.SyntaxNode) -> TypedTerm {
  match @syntax.SyntaxKind::from_raw(n.kind()) {
    @syntax.SyntaxKind::SourceFile => convert_source_file(n)
    @syntax.SyntaxKind::IntLiteral => {
      let value = match n.find_token(@syntax.SyntaxKind::IntToken.to_raw()) {
        None => 0
        Some(t) => @string.parse_int(t.text()) catch { _ => 0 }
      }
      TypedTerm::Int(value)
    }
    @syntax.SyntaxKind::VarRef =>
      TypedTerm::Var(n.token_text(@syntax.SyntaxKind::IdentToken.to_raw()))
    @syntax.SyntaxKind::HoleLiteral => TypedTerm::Hole(0)
    @syntax.SyntaxKind::ErrorNode => TypedTerm::Error("error node")
    @syntax.SyntaxKind::LambdaExpr => {
      let param = n.token_text(@syntax.SyntaxKind::IdentToken.to_raw())
      let mut annot_node : @seam.SyntaxNode? = None
      let mut body_node : @seam.SyntaxNode? = None
      for c in n.children() {
        let k = @syntax.SyntaxKind::from_raw(c.kind())
        if k == @syntax.SyntaxKind::TypeAnnot {
          if annot_node is None {
            annot_node = Some(c)
          }
        } else if body_node is None {
          body_node = Some(c)
        }
      }
      let annot = match annot_node {
        None => None
        Some(ann) => {
          let cs = ann.children()
          if cs.length() == 0 {
            Some(TError)
          } else {
            Some(type_of_node(cs[0]))
          }
        }
      }
      let body = match body_node {
        Some(b) => convert_from_cst(b)
        None => TypedTerm::Error("missing lambda body")
      }
      TypedTerm::Lam(param, annot, body)
    }
    _ => TypedTerm::Error("unhandled CST kind")
  }
}

///|
/// Handle a SourceFile: recurse on its single interior child.
/// Module-level multi-def handling lands in a later task.
fn convert_source_file(n : @seam.SyntaxNode) -> TypedTerm {
  let cs = n.children()
  if cs.length() == 0 {
    TypedTerm::Unit
  } else {
    convert_from_cst(cs[0])
  }
}
