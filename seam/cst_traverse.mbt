// cst_traverse.mbt — Closure-based traversal methods for CstElement.
//
// Ported from cst-transform/ research module. See cst-transform/REPORT.md
// for performance characteristics.

///|
/// Bottom-up structure-preserving transformation.
///
/// Leaves are mapped by `on_token`; interior nodes by `on_node` which
/// receives the node's kind and an `Array[R]` of already-transformed children.
pub fn[R] CstElement::transform(
  self : CstElement,
  on_token : (CstToken) -> R,
  on_node : (RawKind, Array[R]) -> R,
) -> R {
  match self {
    Token(token) => on_token(token)
    Node(node) => {
      let results = Array::new(capacity=node.children.length())
      for child in node.children {
        results.push(child.transform(on_token, on_node))
      }
      on_node(node.kind, results)
    }
  }
}

///|
/// Monoid catamorphism — folds leaf results with `combine` without
/// allocating an intermediate `Array[R]`.
///
/// **Warning:** `empty` is shared by reference. Use only value-type
/// accumulators (Int, String). For Array collection, use `transform` instead.
pub fn[R] CstElement::fold(
  self : CstElement,
  on_token : (CstToken) -> R,
  combine : (R, R) -> R,
  empty : R,
) -> R {
  match self {
    Token(token) => on_token(token)
    Node(node) =>
      for child in node.children; acc = empty {
        continue combine(acc, child.fold(on_token, combine, empty))
      } nobreak {
        acc
      }
  }
}

///|
/// Fused transform+fold: avoids `Array[R]` allocation.
///
/// Like `transform`, processes children bottom-up. Instead of collecting
/// into an Array, folds inline: `on_child(kind, accumulator, child_result)`.
pub fn[R] CstElement::transform_fold(
  self : CstElement,
  on_token : (CstToken) -> R,
  init : (RawKind) -> R,
  on_child : (RawKind, R, R) -> R,
) -> R {
  match self {
    Token(token) => on_token(token)
    Node(node) =>
      for child in node.children; acc = init(node.kind) {
        continue on_child(
            node.kind,
            acc,
            child.transform_fold(on_token, init, on_child),
          )
      } nobreak {
        acc
      }
  }
}

///|
/// Callback-based depth-first pre-order traversal.
///
/// Calls `f` for every element in the tree. Returns `true` if traversal
/// completed, `false` if `f` returned `false` to request early termination.
pub fn CstElement::each(self : CstElement, f : (CstElement) -> Bool) -> Bool {
  if !f(self) {
    return false
  }
  match self {
    Token(_) => true
    Node(node) => {
      for child in node.children {
        if !child.each(f) {
          return false
        }
      }
      true
    }
  }
}

///|
/// Depth-first pre-order iterator over all elements in the tree.
///
/// Uses an explicit stack. Suitable for stdlib composition
/// (`.filter`, `.find_first`, `.take`, etc.).
pub fn CstElement::iter(self : CstElement) -> Iter[CstElement] {
  let stack : Array[CstElement] = [self]
  Iter::new(() => {
    if stack.is_empty() {
      return None
    }
    // Safety: is_empty() check above guarantees stack is non-empty
    let current = stack.unsafe_pop()
    match current {
      Node(node) => {
        let mut i = node.children.length() - 1
        while i >= 0 {
          stack.push(node.children[i])
          i = i - 1
        }
      }
      Token(_) => ()
    }
    Some(current)
  })
}

///|
/// Bottom-up structure-preserving map: transforms a `CstElement` into
/// another `CstElement`.
///
/// Children are recursively mapped first, then `f` is applied to the
/// reconstructed element. For `Node` elements, a new `CstNode` is built
/// with `CstNode::new` to ensure metadata consistency.
///
/// Pass `trivia_kind`, `error_kind`, `incomplete_kind` for accurate
/// `token_count` and `has_any_error` metadata on reconstructed nodes.
/// Without these, `token_count` counts all leaf tokens (including trivia)
/// and `has_any_error` defaults to `false` at each reconstructed node.
///
/// **Caveat:** If `f` returns a pre-existing subtree (not rebuilt by this
/// traversal), its cached metadata may reflect different classification
/// assumptions. `CstNode::new` trusts child `token_count`/`has_any_error`
/// without re-deriving from leaves, so mixing trees built under different
/// `trivia_kind`/`error_kind` rules produces inconsistent metadata.
pub fn CstElement::map(
  self : CstElement,
  f : (CstElement) -> CstElement,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstElement {
  match self {
    Token(_) => f(self)
    Node(node) => {
      let new_children = Array::new(capacity=node.children.length())
      for child in node.children {
        new_children.push(
          child.map(f, trivia_kind~, error_kind~, incomplete_kind~),
        )
      }
      f(
        CstElement::Node(
          CstNode::new(
            node.kind,
            new_children,
            trivia_kind~,
            error_kind~,
            incomplete_kind~,
          ),
        ),
      )
    }
  }
}

///|
/// Typeclass for DFS search. `check` returns true if the element matches.
/// Statically dispatched — zero closure overhead for predicates.
pub(open) trait Finder {
  check(Self, CstElement) -> Bool
}

///|
/// Statically-dispatched DFS find. Returns the first element where `check` is true.
pub fn[F : Finder] CstElement::find(self : CstElement, f : F) -> CstElement? {
  if F::check(f, self) {
    return Some(self)
  }
  match self {
    Token(_) => None
    Node(node) => {
      for child in node.children {
        match child.find(f) {
          Some(n) => return Some(n)
          None => ()
        }
      }
      None
    }
  }
}
