// traits.mbt — Trait-based static dispatch for zero-cost CST traversal.
//
// MoonBit monomorphizes trait method calls and guarantees single-element
// tuple structs are unboxed. Combined, this produces code identical to
// hand-written recursion.

///|
/// Typeclass for monoid-style folding. `Self` is the result type.
pub(open) trait Folder {
  fold_token(TokenKind, String) -> Self
  fold_combine(Self, Self) -> Self
  fold_empty() -> Self
}

///|
/// Typeclass for fused transform+fold. `Self` is the result type.
pub(open) trait TransformFolder {
  tf_token(TokenKind, String) -> Self
  tf_init(SyntaxKind) -> Self
  tf_child(SyntaxKind, Self, Self) -> Self
}

///|
/// Typeclass for callback-based DFS traversal with early termination.
pub(open) trait Walker {
  walk(Self, GreenNode) -> Bool
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
/// Typeclass for DFS search. `check` returns true if the node matches.
/// Statically dispatched — zero closure overhead for predicates.
pub(open) trait Finder {
  check(Self, GreenNode) -> Bool
}

///|
/// Statically-dispatched DFS find. Returns the first node where `check` is true.
pub fn[F : Finder] GreenNode::find(self : GreenNode, f : F) -> GreenNode? {
  if F::check(f, self) {
    return Some(self)
  }
  match self {
    Leaf(_, _) => None
    Branch(_, children) => {
      for child in children {
        match child.find(f) {
          Some(n) => return Some(n)
          None => ()
        }
      }
      None
    }
  }
}

// ── Concrete implementations (newtypes for zero-cost fold) ──────────

///|
pub(all) struct NodeCount(Int) derive(Show)

///|
pub impl Folder for NodeCount with fold_token(_kind, _text) {
  NodeCount(1)
}

///|
pub impl Folder for NodeCount with fold_combine(self, other) {
  NodeCount(self.0 + other.0)
}

///|
pub impl Folder for NodeCount with fold_empty() {
  NodeCount(0)
}

///|
pub impl TransformFolder for NodeCount with tf_token(_kind, _text) {
  NodeCount(1)
}

///|
pub impl TransformFolder for NodeCount with tf_init(_kind) {
  NodeCount(1)
}

///|
pub impl TransformFolder for NodeCount with tf_child(_kind, acc, child) {
  NodeCount(acc.0 + child.0)
}

///|
pub(all) struct TokenCount(Int) derive(Show)

///|
pub impl Folder for TokenCount with fold_token(_kind, _text) {
  TokenCount(1)
}

///|
pub impl Folder for TokenCount with fold_combine(self, other) {
  TokenCount(self.0 + other.0)
}

///|
pub impl Folder for TokenCount with fold_empty() {
  TokenCount(0)
}

///|
pub impl TransformFolder for TokenCount with tf_token(_kind, _text) {
  TokenCount(1)
}

///|
pub impl TransformFolder for TokenCount with tf_init(_kind) {
  TokenCount(0)
}

///|
pub impl TransformFolder for TokenCount with tf_child(_kind, acc, child) {
  TokenCount(acc.0 + child.0)
}

// ── Finder implementations ──────────────────────────────────────────

///|
/// Zero-cost predicate: finds the first Leaf(Ident, _) node.
pub(all) struct IdentFinder(Unit) derive(Show)

///|
pub impl Finder for IdentFinder with check(_self, node) {
  match node {
    Leaf(Ident, _) => true
    _ => false
  }
}
