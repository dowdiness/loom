// Phase 0 baselines for the public CST constructor and the package-owned
// construction seam that Phase 2 will specialize. Keep both rows identical
// except for the helper call.

///|
fn core_ownership_children_32() -> Array[CstElement] {
  let children : Array[CstElement] = []
  for i = 0; i < 32; i = i + 1 {
    children.push(
      CstElement::Token(CstToken::CstToken(RawKind(9), "x" + i.to_string())),
    )
  }
  children
}

///|
fn core_ownership_node_from_owned_children(
  children : Array[CstElement],
) -> CstNode raise Failure {
  // Phase 0 intentionally uses the current no-copy constructor. Phase 2 may
  // change only this call to the package-private owned-child constructor.
  CstNode::new_owned(
    RawKind(20),
    children,
    policy=CstMetadataPolicy::unclassified(),
  )
}

///|
test "core ownership: CST public construction from 32 children" (b : @bench.T) {
  let children = core_ownership_children_32()
  b.bench(fn() { b.keep(try! CstNode::new_unclassified(RawKind(20), children)) })
}

///|
test "core ownership: CST package-owned construction from 32 children" (
  b : @bench.T,
) {
  let children = core_ownership_children_32()
  b.bench(fn() {
    b.keep(try! core_ownership_node_from_owned_children(children))
  })
}
