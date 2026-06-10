// syntax_node_bench_wbtest.mbt — Benchmarks for SyntaxNode position queries.
//
// Guards the token_at_offset hot path (IDE hover/completion): interior hit
// (early exit), boundary Between (bounded scan), and out-of-range miss
// (full scan, worst case).
//
// Run: cd seam && moon bench --release

///|
/// Build a tree of `depth` levels; each node carries `tokens_per_node`
/// width-2 tokens ("ab") followed by `fanout` child subtrees.
/// With width-2 tokens, odd offsets are strict-interior and even offsets
/// are token boundaries.
fn make_position_tree(
  depth : Int,
  tokens_per_node : Int,
  fanout : Int,
) -> CstNode {
  let children : Array[CstElement] = []
  for i = 0; i < tokens_per_node; i = i + 1 {
    children.push(CstElement::Token(CstToken::CstToken(RawKind(9), "ab")))
  }
  if depth > 1 {
    for i = 0; i < fanout; i = i + 1 {
      children.push(
        CstElement::Node(make_position_tree(depth - 1, tokens_per_node, fanout)),
      )
    }
  }
  CstNode::new(RawKind(21), children)
}

///|
test "bench: token_at_offset interior hit mid-tree" (b : @bench.T) {
  let root = SyntaxNode::from_cst(make_position_tree(6, 10, 2))
  let mid_interior = root.end() / 2 + 1 // odd → strict interior
  b.bench(fn() { b.keep(root.token_at_offset(mid_interior)) })
}

///|
test "bench: token_at_offset boundary Between mid-tree" (b : @bench.T) {
  let root = SyntaxNode::from_cst(make_position_tree(6, 10, 2))
  let mid_boundary = root.end() / 2 // even → between two tokens
  b.bench(fn() { b.keep(root.token_at_offset(mid_boundary)) })
}

///|
test "bench: token_at_offset out-of-range miss (full scan)" (b : @bench.T) {
  let root = SyntaxNode::from_cst(make_position_tree(6, 10, 2))
  let beyond = root.end() + 5
  b.bench(fn() { b.keep(root.token_at_offset(beyond)) })
}
