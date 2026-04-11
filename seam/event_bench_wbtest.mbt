// event_bench_wbtest.mbt — Benchmarks for build_tree / build_tree_interned
// with ReuseNode events, measuring rebuild_subtree and re_intern_tokens_only.
//
// Run: cd seam && moon bench --release

///|
/// Build a reusable subtree: a node with N tokens.
fn make_reuse_subtree(size : Int) -> CstNode {
  let children : Array[CstElement] = Array::new(capacity=size)
  for i = 0; i < size; i = i + 1 {
    children.push(
      CstElement::Token(CstToken::new(RawKind(9), "tok" + i.to_string())),
    )
  }
  CstNode::new(RawKind(21), children)
}

///|
/// Build events that reuse a subtree N times within a root.
fn make_reuse_events(subtree : CstNode, reuse_count : Int) -> Array[ParseEvent] {
  let events : Array[ParseEvent] = []
  for i = 0; i < reuse_count; i = i + 1 {
    events.push(ParseEvent::ReuseNode(subtree))
    let _ = i
  }
  events
}

///|
test "bench: build_tree with ReuseNode (rebuild_subtree)" (b : @bench.T) {
  let subtree = make_reuse_subtree(100)
  let events = make_reuse_events(subtree, 50)
  let root_kind = RawKind(20)
  let trivia_kind = Some(RawKind(11))
  b.bench(fn() {
    let _ = try! build_tree(
      events,
      root_kind,
      trivia_kind~,
      error_kind=Some(RawKind(99)),
      incomplete_kind=Some(RawKind(98)),
    )
  })
}

///|
test "bench: build_tree_interned with ReuseNode (re_intern_tokens_only)" (
  b : @bench.T,
) {
  let subtree = make_reuse_subtree(100)
  let events = make_reuse_events(subtree, 50)
  let root_kind = RawKind(20)
  let trivia_kind = Some(RawKind(11))
  b.bench(fn() {
    let _ = try! build_tree_interned(
      events,
      root_kind,
      Interner::new(),
      trivia_kind~,
      error_kind=Some(RawKind(99)),
      incomplete_kind=Some(RawKind(98)),
    )
  })
}
