// Diagnostic rows for the classified parser path. These stay outside the
// release-profile manifest so the Phase 0 benchmark schema remains symmetric.

///|
test "classified CST: package-owned construction from 32 token children" (
  b : @bench.T,
) {
  let policy = CstMetadataPolicy::new(
    [RawKind(1), RawKind(2), RawKind(3)],
    error_kind=Some(RawKind(4)),
    incomplete_kind=Some(RawKind(5)),
  )
  let children = core_ownership_children_32()
  b.bench(fn() {
    b.keep(try! CstNode::new_owned(RawKind(20), children, policy~))
  })
}

///|
test "classified CST: package-owned construction from 32 node children" (
  b : @bench.T,
) {
  let policy = CstMetadataPolicy::new(
    [RawKind(1), RawKind(2), RawKind(3)],
    error_kind=Some(RawKind(4)),
    incomplete_kind=Some(RawKind(5)),
  )
  let leaf = try! CstNode::new_owned(
    RawKind(21),
    [CstElement::Token(CstToken::CstToken(RawKind(9), "leaf"))],
    policy~,
  )
  let children = Array::make(32, CstElement::Node(leaf))
  b.bench(fn() {
    b.keep(try! CstNode::new_owned(RawKind(20), children, policy~))
  })
}
