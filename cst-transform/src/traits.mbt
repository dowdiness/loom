// traits.mbt — Trait-based static dispatch for CST traversal.
//
// MoonBit monomorphizes trait method calls: `R::method(...)` compiles to
// a direct function call, not an indirect closure dispatch. By encoding
// the transform/fold algebras as traits on the *result type*, we eliminate
// all closure overhead.

///|
/// Typeclass for monoid-style folding. `Self` is the result type.
/// Implement for Int, String, etc. to get zero-overhead tree folds.
pub(open) trait Folder {
  fold_token(TokenKind, String) -> Self
  fold_combine(Self, Self) -> Self
  fold_empty() -> Self
}

///|
/// Typeclass for callback-based DFS traversal with early termination.
/// Return `true` to continue, `false` to stop.
pub(open) trait Walker {
  walk(Self, GreenNode) -> Bool
}

///|
/// Statically-dispatched DFS walk with early termination.
pub fn[W : Walker] GreenNode::accept_walk(self : GreenNode, w : W) -> Bool {
  if not(W::walk(w, self)) {
    return false
  }
  match self {
    Leaf(_, _) => true
    Branch(_, children) => {
      for child in children {
        if not(child.accept_walk(w)) {
          return false
        }
      }
      true
    }
  }
}

///|
/// Typeclass for fused transform+fold. `Self` is the result type.
/// Like Folder but with access to the branch SyntaxKind.
pub(open) trait TransformFolder {
  tf_token(TokenKind, String) -> Self
  tf_init(SyntaxKind) -> Self
  tf_child(SyntaxKind, Self, Self) -> Self
}

///|
/// Statically-dispatched monoid fold. Zero closure overhead.
pub fn[R : Folder] GreenNode::accept_fold(self : GreenNode) -> R {
  match self {
    Leaf(kind, text) => R::fold_token(kind, text)
    Branch(_, children) =>
      for child in children; acc = (R::fold_empty() : R) {
        continue R::fold_combine(acc, child.accept_fold())
      } nobreak {
        acc
      }
  }
}

///|
/// Statically-dispatched fused transform+fold. Zero closure overhead.
pub fn[R : TransformFolder] GreenNode::accept_transform_fold(
  self : GreenNode,
) -> R {
  match self {
    Leaf(kind, text) => R::tf_token(kind, text)
    Branch(kind, children) =>
      for child in children; acc = (R::tf_init(kind) : R) {
        continue R::tf_child(kind, acc, child.accept_transform_fold())
      } nobreak {
        acc
      }
  }
}
