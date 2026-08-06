///|
/// Helper: create a leaf token element.
fn tok(kind_val : Int, text : String) -> @seam.CstElement {
  @seam.CstElement::Token(
    @seam.CstToken::CstToken(@seam.RawKind(kind_val), text),
  )
}

///|
/// Helper: create a node element.
fn nd(
  kind_val : Int,
  children : Array[@seam.CstElement],
) -> @seam.CstElement raise Failure {
  @seam.CstElement::Node(
    @seam.CstNode::new_unclassified(@seam.RawKind(kind_val), children),
  )
}

///|
/// White-box retention signal. This intentionally stays out of the public API.
fn[Ast] CstFold::cache_entry_count(self : CstFold[Ast]) -> Int {
  self.cache.keys().count()
}

///|
fn[Ast] CstFold::cached_key_equal_to(
  self : CstFold[Ast],
  expected : @seam.CstNode,
) -> @seam.CstNode? {
  for key in self.cache.keys() {
    if key == expected {
      return Some(key)
    }
  }
  None
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
fn source_text_algebra(
  node : @seam.SyntaxNode,
  _recurse : (@seam.SyntaxNode) -> String,
) -> String {
  node.text()
}

///|
test "CstFold: basic fold produces correct result" {
  //   Root(10)
  //   ├── Token(1, "x")
  //   └── Child(20)
  //       └── Token(2, "y")
  let child = nd(20, [tok(2, "y")])
  let root = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    tok(1, "x"),
    child,
  ])
  let syntax = @seam.SyntaxNode::from_cst(root)
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let result = fold.fold(syntax)
  inspect(result, content="kind:10(kind:20)")
}

///|
test "CstFold: second fold reuses cache for unchanged tree" {
  let child = nd(20, [tok(2, "y")])
  let root = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    tok(1, "x"),
    child,
  ])
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
  let child = @seam.CstNode::new_unclassified(@seam.RawKind(20), [tok(2, "y")])
  let root = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    tok(1, "a"),
    @seam.CstElement::Node(child),
  ])
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let _ = fold.fold(@seam.SyntaxNode::from_cst(root))
  // Modified: Root(10) -> [Token("b"), Child(20) -> [Token("y")]]
  // Child(20) is structurally identical — should be reused.
  let new_root = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
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
  let root = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    tok(1, "x"),
    child,
  ])
  let fold : CstFold[String] = CstFold::new(skip_algebra)
  let _ = fold.fold(@seam.SyntaxNode::from_cst(root))
  let stats = fold.get_stats()
  // Root recomputed, child unvisited but cache-warmed
  inspect(stats.recomputed, content="2")
  inspect(stats.unvisited, content="1")
}

///|
test "CstFold: cache retention stays bounded across distinct roots" {
  let fold : CstFold[String] = CstFold::new(source_text_algebra)
  let edit_generations = cst_fold_compaction_interval * 4 + 7
  for i = 0; i < edit_generations; i = i + 1 {
    let source = "value-" + i.to_string()
    let root = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
      tok(1, source),
    ])
    let result = fold.fold(@seam.SyntaxNode::from_cst(root))
    assert_eq(result, source)
  }
  inspect(
    fold.cache_entry_count() <= cst_fold_compaction_interval,
    content="true",
  )
}

///|
test "CstFold: compaction releases a historical source-backed root" {
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let historical = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    tok(1, "historical-source"),
  ])
  let _ = fold.fold(@seam.SyntaxNode::from_cst(historical))
  inspect(fold.cache.contains(historical), content="true")
  for i = 1; i < cst_fold_compaction_interval; i = i + 1 {
    let current = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
      tok(1, "current-" + i.to_string()),
    ])
    let _ = fold.fold(@seam.SyntaxNode::from_cst(current))
  }
  inspect(fold.cache.contains(historical), content="false")
}

///|
test "CstFold: compaction refreshes reachable CST source backing" {
  let historical_source = "old:stable"
  let current_source = "new:stable"
  let historical = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    @seam.CstElement::Token(
      @seam.CstToken::CstToken(
        @seam.RawKind(1),
        historical_source.view(start_offset=4, end_offset=10),
      ),
    ),
  ])
  let current = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    @seam.CstElement::Token(
      @seam.CstToken::CstToken(
        @seam.RawKind(1),
        current_source.view(start_offset=4, end_offset=10),
      ),
    ),
  ])
  inspect(historical == current, content="true")
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let _ = fold.fold(@seam.SyntaxNode::from_cst(historical))
  for generation = 1
      generation < cst_fold_compaction_interval
      generation = generation + 1 {
    let _ = fold.fold(@seam.SyntaxNode::from_cst(current))
  }
  match fold.cached_key_equal_to(current) {
    Some(cached) =>
      match cached.first_token(fn(_kind) { false }) {
        Some(token) =>
          inspect(
            physical_equal(token.unsafe_backing_source(), current_source),
            content="true",
          )
        None => abort("expected cached source-backed token")
      }
    None => abort("expected reachable cache entry")
  }
}

///|
test "CstFold: root-hit compaction preserves deep adjacent reuse" {
  let grandchild = @seam.CstNode::new_unclassified(@seam.RawKind(30), [
    tok(3, "stable"),
  ])
  let child = @seam.CstNode::new_unclassified(@seam.RawKind(20), [
    tok(2, "before"),
    @seam.CstElement::Node(grandchild),
  ])
  let root = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    @seam.CstElement::Node(child),
  ])
  let syntax = @seam.SyntaxNode::from_cst(root)
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let _ = fold.fold(syntax)
  for generation = 1
      generation < cst_fold_compaction_interval
      generation = generation + 1 {
    let _ = fold.fold(syntax)
  }
  let _ = fold.fold(syntax)
  let root_hit_stats = fold.get_stats()
  inspect(root_hit_stats.reused, content="1")
  inspect(root_hit_stats.recomputed, content="0")
  let edited_child = @seam.CstNode::new_unclassified(@seam.RawKind(20), [
    tok(2, "after"),
    @seam.CstElement::Node(grandchild),
  ])
  let edited_root = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    @seam.CstElement::Node(edited_child),
  ])
  let _ = fold.fold(@seam.SyntaxNode::from_cst(edited_root))
  let stats = fold.get_stats()
  inspect(stats.reused, content="1")
  inspect(stats.recomputed, content="2")
}

///|
test "CstFold: structurally distinct nodes occupy distinct cache entries" {
  let first = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    tok(1, "first"),
  ])
  let second = @seam.CstNode::new_unclassified(@seam.RawKind(10), [
    tok(1, "second"),
  ])
  inspect(first == second, content="false")
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let _ = fold.fold(@seam.SyntaxNode::from_cst(first))
  let _ = fold.fold(@seam.SyntaxNode::from_cst(second))
  let stats = fold.get_stats()
  inspect(stats.reused, content="0")
  inspect(stats.recomputed, content="1")
  inspect(fold.cache_entry_count(), content="2")
}
