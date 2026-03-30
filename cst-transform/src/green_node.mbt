// green_node.mbt — Simplified CST types and traversal methods.

///|
pub(all) enum TokenKind {
  Ident
  Number
  LParen
  RParen
  Plus
  Minus
  Star
  Slash
  Eq
  Let
  Fn_
  Whitespace
  Newline
  Eof
} derive(Eq, Show, Hash, Compare)

///|
pub(all) enum SyntaxKind {
  SourceFile
  FnDef
  LetStmt
  BinaryExpr
  CallExpr
  ParenExpr
  ArgList
  Literal
  Name
  Error
} derive(Eq, Show, Hash, Compare)

///|
pub(all) enum GreenNode {
  Leaf(TokenKind, String)
  Branch(SyntaxKind, Array[GreenNode])
} derive(Eq, Show)

// ── Closure-based methods ───────────────────────────────────────────

///|
/// Structure-preserving transformation (hylo_rose equivalent).
///
/// Recursively transforms a `GreenNode` bottom-up: leaves are mapped by
/// `on_token`, interior nodes by `on_node` which receives the already-
/// transformed children as `Array[R]`.
pub fn[R] GreenNode::transform(
  self : GreenNode,
  on_token : (TokenKind, String) -> R,
  on_node : (SyntaxKind, Array[R]) -> R,
) -> R {
  match self {
    Leaf(kind, text) => on_token(kind, text)
    Branch(kind, children) => {
      let results = Array::new(capacity=children.length())
      for child in children {
        results.push(child.transform(on_token, on_node))
      }
      on_node(kind, results)
    }
  }
}

///|
/// View-based transform: uses a shared stack + `ArrayView[R]` to avoid
/// per-branch `Array[R]` allocation.
///
/// One `Array[R]` is allocated upfront as a stack. Each branch's child results
/// are pushed onto the stack, a view is taken, `on_node` receives the view,
/// then the stack is truncated back. Zero per-branch allocation.
pub fn[R] GreenNode::transform_view(
  self : GreenNode,
  on_token : (TokenKind, String) -> R,
  on_node : (SyntaxKind, ArrayView[R]) -> R,
) -> R {
  let stack : Array[R] = Array::new(capacity=64)
  fn go(node : GreenNode) -> R {
    match node {
      Leaf(kind, text) => on_token(kind, text)
      Branch(kind, children) => {
        let base = stack.length()
        for child in children {
          stack.push(go(child))
        }
        let view = stack.view(start=base, end=stack.length())
        let result = on_node(kind, view)
        // Pop children results off the stack
        while stack.length() > base {
          let _ = stack.unsafe_pop()
        }
        result
      }
    }
  }
  go(self)
}

///|
/// Monoid catamorphism — folds children with `combine` without allocating
/// an intermediate `Array[R]`.
///
/// Each leaf is mapped by `on_token`. For interior nodes, child results are
/// accumulated left-to-right via `combine`, starting from `empty`.
pub fn[R] GreenNode::fold(
  self : GreenNode,
  on_token : (TokenKind, String) -> R,
  combine : (R, R) -> R,
  empty : R,
) -> R {
  match self {
    Leaf(kind, text) => on_token(kind, text)
    Branch(_, children) =>
      for child in children; acc = empty {
        continue combine(acc, child.fold(on_token, combine, empty))
      } nobreak {
        acc
      }
  }
}

///|
/// Fused transform+fold: avoids `Array[R]` allocation entirely.
///
/// Like `transform`, recursively processes children bottom-up. But instead of
/// collecting child results into an `Array[R]`, it folds them inline using
/// `on_child(kind, accumulator, child_result) -> accumulator`.
pub fn[R] GreenNode::transform_fold(
  self : GreenNode,
  on_token : (TokenKind, String) -> R,
  init : (SyntaxKind) -> R,
  on_child : (SyntaxKind, R, R) -> R,
) -> R {
  match self {
    Leaf(kind, text) => on_token(kind, text)
    Branch(kind, children) =>
      for child in children; acc = init(kind) {
        continue on_child(
            kind,
            acc,
            child.transform_fold(on_token, init, on_child),
          )
      } nobreak {
        acc
      }
  }
}

///|
/// CPS variant of `transform` — avoids allocating `Array[R]` for children.
///
/// Instead of collecting child results into an array, `on_children` receives
/// a callback-based stream: `each_child` calls `emit` once per child result.
pub fn[R] GreenNode::transform_cps(
  self : GreenNode,
  on_token : (TokenKind, String) -> R,
  on_children : (SyntaxKind, ((R) -> Unit) -> Unit) -> R,
) -> R {
  match self {
    Leaf(kind, text) => on_token(kind, text)
    Branch(kind, children) =>
      on_children(kind, emit => {
        for child in children {
          emit(child.transform_cps(on_token, on_children))
        }
      })
  }
}

///|
/// Structure-preserving map: transforms a `GreenNode` into another `GreenNode`.
///
/// Applies `f` bottom-up: children are recursively mapped first, then `f` is
/// applied to the reconstructed node (leaf or branch with new children).
pub fn GreenNode::map(
  self : GreenNode,
  f : (GreenNode) -> GreenNode,
) -> GreenNode {
  match self {
    Leaf(_, _) => f(self)
    Branch(kind, children) => {
      let new_children = Array::new(capacity=children.length())
      for child in children {
        new_children.push(child.map(f))
      }
      f(Branch(kind, new_children))
    }
  }
}

///|
/// Callback-based depth-first pre-order traversal.
///
/// Calls `f` for every node in the tree. Returns `true` if traversal completed,
/// `false` if `f` returned `false` to request early termination.
pub fn GreenNode::each(self : GreenNode, f : (GreenNode) -> Bool) -> Bool {
  if not(f(self)) {
    return false
  }
  match self {
    Leaf(_, _) => true
    Branch(_, children) => {
      for child in children {
        if not(child.each(f)) {
          return false
        }
      }
      true
    }
  }
}

///|
/// Depth-first pre-order iterator over all nodes in a `GreenNode` tree.
///
/// Uses an explicit stack to produce one element per call to the returned thunk.
pub fn GreenNode::iter(self : GreenNode) -> Iter[GreenNode] {
  let stack : Array[GreenNode] = [self]
  Iter::new(() => {
    if stack.is_empty() {
      return None
    }
    let current = stack.pop().unwrap()
    match current {
      Branch(_, children) => {
        let mut i = children.length() - 1
        while i >= 0 {
          stack.push(children[i])
          i = i - 1
        }
      }
      Leaf(_, _) => ()
    }
    Some(current)
  })
}
