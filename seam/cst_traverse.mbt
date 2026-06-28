// cst_traverse.mbt — Traversal methods for CstElement.
//
// Three tiers, each benchmarked (see docs/performance/2026-03-30-cst-traversal-tiers.md):
//   1. Closure methods: transform, fold, transform_fold, each, iter, map (~1.0–1.35x)
//   2. Finder trait: statically-dispatched DFS search (~1.0x)
//   3. Hand-written: parameterized queries like token_count (~1.0x always)

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
///
/// **Performance:** Closures that capture outer variables (e.g., a
/// `trivia_kinds` for filtering) incur ~2x overhead from upvalue access.
/// For parameterized hot-path folds, prefer hand-written methods like
/// `CstElement::token_count`.
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
/// Equivalent to consuming `self.iter()`. Calls `f` for every element in the
/// tree. Returns `true` if traversal completed, or `false` if `f` returned
/// `false` to request early termination.
pub fn CstElement::each(self : CstElement, f : (CstElement) -> Bool) -> Bool {
  for elem in self.iter() {
    if !f(elem) {
      return false
    }
  }
  true
}

///|
fn push_children_reversed(
  stack : Array[CstElement],
  children : Array[CstElement],
) -> Unit {
  let mut i = children.length() - 1
  while i >= 0 {
    stack.push(children[i])
    i = i - 1
  }
}

///|
fn direct_elements_iter_flat(children : Array[CstElement]) -> Iter[CstElement] {
  let stack : Array[CstElement] = []
  push_children_reversed(stack, children)
  Iter::new(() => {
    while !stack.is_empty() {
      // Safety: is_empty() check above guarantees stack is non-empty.
      let current = stack.unsafe_pop()
      match current {
        Node(node) =>
          if node.kind == repeat_group_kind {
            push_children_reversed(stack, node.children)
          } else {
            return Some(current)
          }
        Token(_) => return Some(current)
      }
    }
    None
  })
}

///|
/// Iterator over the direct visible children of a raw CST node.
///
/// `RepeatGroup` nodes are transparent: their children are yielded in source
/// order as direct visible children, and the `RepeatGroup` wrapper itself is
/// skipped. Non-repeat child nodes are yielded without recursively traversing
/// into them.
///
/// The iterator is single-pass. Request a fresh iterator from the node when you
/// need to traverse the visible children again.
pub fn CstNode::direct_elements_iter(self : CstNode) -> Iter[CstElement] {
  direct_elements_iter_flat(self.children)
}

///|
/// Callback over the direct visible children of a raw CST node.
///
/// Equivalent to consuming `self.direct_elements_iter()`, including its
/// `RepeatGroup` transparency. Returns `true` if traversal completed, or
/// `false` when `f` returned `false` to request early termination.
pub fn CstNode::each(self : CstNode, f : (CstElement) -> Bool) -> Bool {
  for elem in self.direct_elements_iter() {
    if !f(elem) {
      return false
    }
  }
  true
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
    // Safety: is_empty() check above guarantees stack is non-empty.
    let current = stack.unsafe_pop()
    match current {
      Node(node) => push_children_reversed(stack, node.children)
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
/// Pass `trivia_kinds`, `error_kind`, `incomplete_kind` for accurate
/// `token_count` and `has_any_error` metadata on reconstructed nodes.
/// Without these, `token_count` counts all leaf tokens (including trivia)
/// and `has_any_error` defaults to `false` at each reconstructed node.
///
/// **Caveat:** If `f` returns a pre-existing subtree (not rebuilt by this
/// traversal), its cached metadata may reflect different classification
/// assumptions. `CstNode::new` trusts child `token_count`/`has_any_error`
/// without re-deriving from leaves, so mixing trees built under different
/// `trivia_kinds`/`error_kind` rules produces inconsistent metadata.
pub fn CstElement::map(
  self : CstElement,
  f : (CstElement) -> CstElement,
  trivia_kinds? : Array[RawKind]? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstElement {
  match self {
    Token(_) => f(self)
    Node(node) => {
      let new_children = Array::new(capacity=node.children.length())
      for child in node.children {
        new_children.push(
          child.map(f, trivia_kinds~, error_kind~, incomplete_kind~),
        )
      }
      f(
        CstElement::Node(
          CstNode::new(
            node.kind,
            new_children,
            trivia_kinds~,
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
/// Statically dispatched — no closure allocation for predicates.
pub(open) trait Finder {
  fn check(Self, CstElement) -> Bool
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

// ── Hand-written parameterized queries ────────────────────────────────
// Parameterized folds (needing runtime arguments like trivia_kind) can't
// be expressed as stateless Folder traits, and closure fold has 2x overhead
// from captured upvalues. Hand-written recursion is the right tool here.

///|
/// Count non-trivia leaf tokens in the subtree.
///
/// Use this when the tree wasn't built with `trivia_kinds` (otherwise
/// prefer the cached `CstNode.token_count` field which is O(1)).
pub fn CstElement::token_count(
  self : CstElement,
  trivia_kinds : Array[RawKind],
) -> Int {
  match self {
    Token(t) => if trivia_kinds.contains(t.kind) { 0 } else { 1 }
    Node({ children, .. }) =>
      for child in children; acc = 0 {
        continue acc + child.token_count(trivia_kinds)
      } nobreak {
        acc
      }
  }
}
