///|
/// Helper: create a leaf token element.
fn tok(kind_val : Int, text : String) -> @seam.CstElement {
  @seam.CstElement::Token(@seam.CstToken::new(@seam.RawKind(kind_val), text))
}

///|
/// Helper: create a node element.
fn nd(kind_val : Int, children : Array[@seam.CstElement]) -> @seam.CstElement {
  @seam.CstElement::Node(@seam.CstNode::new(@seam.RawKind(kind_val), children))
}

///|
/// Trivial algebra: returns "kind:<n>" for leaves, "kind:<n>(<child1>,<child2>,...)" for nodes.
fn test_algebra(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> String,
) -> String {
  let @seam.RawKind(k) = node.kind()
  let child_strs = node.children().map(recurse)
  if child_strs.length() == 0 {
    "kind:" + k.to_string()
  } else {
    "kind:" + k.to_string() + "(" + child_strs.join(",") + ")"
  }
}

///|
test "CstFold: basic fold produces correct result" {
  //   Root(10)
  //   ├── Token(1, "x")
  //   └── Child(20)
  //       └── Token(2, "y")
  let child = nd(20, [tok(2, "y")])
  let root = @seam.CstNode::new(@seam.RawKind(10), [tok(1, "x"), child])
  let syntax = @seam.SyntaxNode::from_cst(root)
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let result = fold.fold(syntax)
  inspect(result, content="kind:10(kind:20)")
}

///|
test "CstFold: second fold reuses cache for unchanged tree" {
  let child = nd(20, [tok(2, "y")])
  let root = @seam.CstNode::new(@seam.RawKind(10), [tok(1, "x"), child])
  let syntax = @seam.SyntaxNode::from_cst(root)
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let _ = fold.fold(syntax)
  // Second fold on same tree — all nodes hit persistent cache
  let result2 = fold.fold(syntax)
  inspect(result2, content="kind:10(kind:20)")
  let stats = fold.get_stats()
  // Root hits cache immediately, returns without visiting children
  inspect(stats.reused, content="1")
  inspect(stats.recomputed, content="0")
}

///|
test "CstFold: incremental fold reuses unchanged subtrees" {
  // Original:  Root(10) -> [Token("a"), Child(20) -> [Token("y")]]
  let child = @seam.CstNode::new(@seam.RawKind(20), [tok(2, "y")])
  let root = @seam.CstNode::new(@seam.RawKind(10), [
    tok(1, "a"),
    @seam.CstElement::Node(child),
  ])
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let _ = fold.fold(@seam.SyntaxNode::from_cst(root))
  // Modified: Root(10) -> [Token("b"), Child(20) -> [Token("y")]]
  // Child(20) is structurally identical (same hash) — should be reused.
  let new_root = @seam.CstNode::new(@seam.RawKind(10), [
    tok(1, "b"),
    @seam.CstElement::Node(child),
  ])
  let result = fold.fold(@seam.SyntaxNode::from_cst(new_root))
  inspect(result, content="kind:10(kind:20)")
  let stats = fold.get_stats()
  // Child(20) reused from cache, Root(10) recomputed
  inspect(stats.reused, content="1")
  inspect(stats.recomputed, content="1")
}

///|
test "CstFold: unvisited children are cache-warmed" {
  // Algebra that skips child nodes intentionally
  let skip_algebra = fn(
    node : @seam.SyntaxNode,
    _recurse : (@seam.SyntaxNode) -> String,
  ) -> String {
    let @seam.RawKind(k) = node.kind()
    "leaf:" + k.to_string() // Never calls recurse
  }
  let child = nd(20, [tok(2, "y")])
  let root = @seam.CstNode::new(@seam.RawKind(10), [tok(1, "x"), child])
  let fold : CstFold[String] = CstFold::new(skip_algebra)
  let _ = fold.fold(@seam.SyntaxNode::from_cst(root))
  let stats = fold.get_stats()
  // Root recomputed, child unvisited but cache-warmed
  inspect(stats.recomputed, content="2")
  inspect(stats.unvisited, content="1")
}
