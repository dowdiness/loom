// cst_traits_wbtest.mbt — Tests and benchmarks for trait-based traversal.

///|
fn make_trait_test_tree() -> CstElement {
  let foo = CstToken::new(RawKind(9), "foo")
  let ws = CstToken::new(RawKind(11), " ")
  let one = CstToken::new(RawKind(10), "1")
  let plus = CstToken::new(RawKind(12), "+")
  let two = CstToken::new(RawKind(10), "2")
  let eof = CstToken::new(RawKind(13), "")
  let bin_expr = CstNode::new(RawKind(21), [
    CstElement::Token(one),
    CstElement::Token(plus),
    CstElement::Token(two),
  ])
  let root = CstNode::new(RawKind(20), [
    CstElement::Token(foo),
    CstElement::Token(ws),
    CstElement::Node(bin_expr),
    CstElement::Token(eof),
  ])
  CstElement::Node(root)
}

// ── TextLen (Folder) ──────────────────────────────────────────────────

///|
test "accept_fold[TextLen]: matches CstNode.text_len" {
  let tree = make_trait_test_tree()
  let result : TextLen = tree.accept_fold()
  // "foo" + " " + "1" + "+" + "2" + "" = 7
  inspect(result, content="TextLen(7)")
  // Verify matches cached metadata
  match tree {
    Node(n) => inspect(result.0 == n.text_len, content="true")
    _ => ()
  }
}

///|
test "accept_fold[TextLen]: single token" {
  let tok = CstToken::new(RawKind(9), "hello")
  let elem = CstElement::Token(tok)
  let result : TextLen = elem.accept_fold()
  inspect(result, content="TextLen(5)")
}

///|
test "accept_fold[TextLen]: empty node" {
  let node = CstNode::new(RawKind(20), [])
  let elem = CstElement::Node(node)
  let result : TextLen = elem.accept_fold()
  inspect(result, content="TextLen(0)")
}

// ── NodeCount (TransformFolder) ───────────────────────────────────────

///|
test "accept_transform_fold[NodeCount]: counts all elements" {
  let tree = make_trait_test_tree()
  let result : NodeCount = tree.accept_transform_fold()
  // 2 branch nodes + 6 tokens = 8
  inspect(result, content="NodeCount(8)")
}

///|
test "accept_transform_fold[NodeCount]: single token" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let result : NodeCount = elem.accept_transform_fold()
  inspect(result, content="NodeCount(1)")
}

///|
test "accept_transform_fold[NodeCount]: empty node counts itself" {
  let node = CstNode::new(RawKind(20), [])
  let elem = CstElement::Node(node)
  let result : NodeCount = elem.accept_transform_fold()
  inspect(result, content="NodeCount(1)")
}

// ── Benchmarks ────────────────────────────────────────────────────────

///|
/// Build a large tree for benchmarking: depth levels, branching children per node.
fn generate_large_cst(depth : Int, branching : Int) -> CstElement {
  if depth <= 0 {
    CstElement::Token(CstToken::new(RawKind(9), "leaf"))
  } else {
    let children = Array::new(capacity=branching)
    for i = 0; i < branching; i = i + 1 {
      children.push(generate_large_cst(depth - 1, branching))
      let _ = i
    }
    CstElement::Node(CstNode::new(RawKind(20), children))
  }
}

///|
fn hand_written_text_len(elem : CstElement) -> Int {
  match elem {
    Token(t) => t.text.length()
    Node(node) =>
      for child in node.children; acc = 0 {
        continue acc + hand_written_text_len(child)
      } nobreak {
        acc
      }
  }
}

///|
fn hand_written_node_count(elem : CstElement) -> Int {
  match elem {
    Token(_) => 1
    Node(node) =>
      for child in node.children; acc = 1 {
        continue acc + hand_written_node_count(child)
      } nobreak {
        acc
      }
  }
}

///|
test "bench: text_len hand-written" (b : @bench.T) {
  let tree = generate_large_cst(8, 4)
  b.bench(() => {
    let _ = hand_written_text_len(tree)
  })
}

///|
test "bench: text_len via accept_fold[TextLen]" (b : @bench.T) {
  let tree = generate_large_cst(8, 4)
  b.bench(() => {
    let _ : TextLen = tree.accept_fold()
  })
}

///|
test "bench: text_len via closure fold" (b : @bench.T) {
  let tree = generate_large_cst(8, 4)
  b.bench(() => {
    let _ = tree.fold(t => t.text.length(), (a, b) => a + b, 0)
  })
}

///|
test "bench: node_count hand-written" (b : @bench.T) {
  let tree = generate_large_cst(8, 4)
  b.bench(() => {
    let _ = hand_written_node_count(tree)
  })
}

///|
test "bench: node_count via accept_transform_fold[NodeCount]" (b : @bench.T) {
  let tree = generate_large_cst(8, 4)
  b.bench(() => {
    let _ : NodeCount = tree.accept_transform_fold()
  })
}

///|

///|
test "bench: node_count via closure transform_fold" (b : @bench.T) {
  let tree = generate_large_cst(8, 4)
  b.bench(() => {
    let _ = tree.transform_fold(_token => 1, _kind => 1, (_kind, acc, child) => {
      acc + child
    })
  })
}

// ── Token count with trivia filter (parameterized fold) ───────────────
// Folder trait CANNOT express this (no way to thread trivia_kind).
// CstElement::token_count is hand-written for zero overhead.

///|
test "token_count: filters trivia" {
  let tree = make_trait_test_tree()
  let ws_kind = RawKind(11)
  // 6 total tokens - 1 whitespace = 5
  inspect(tree.token_count(ws_kind), content="5")
}

///|
test "token_count: single token non-trivia" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  inspect(elem.token_count(RawKind(11)), content="1")
}

///|
test "token_count: single token trivia" {
  let tok = CstToken::new(RawKind(11), " ")
  let elem = CstElement::Token(tok)
  inspect(elem.token_count(RawKind(11)), content="0")
}

///|
test "bench: token_count (trivia filter) via CstElement::token_count" (
  b : @bench.T,
) {
  let tree = generate_large_cst(8, 4)
  let trivia_kind = RawKind(11)
  b.bench(() => {
    let _ = tree.token_count(trivia_kind)
  })
}
