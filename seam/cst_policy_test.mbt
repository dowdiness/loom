///|
test "CstNode public construction copies children and exposes read-only metadata" {
  let policy = CstMetadataPolicy::new([RawKind(2)])
  let children : Array[CstElement] = [
    Token(CstToken::CstToken(RawKind(1), "x")),
  ]
  let node = CstNode::new(RawKind(10), children, policy~)
  children[0] = Token(CstToken::CstToken(RawKind(2), " "))
  assert_eq(node.kind(), RawKind(10))
  assert_eq(node.text_len(), 1)
  assert_eq(node.token_count(), 1)
  assert_false(node.has_any_error())
  assert_eq(node.children().length(), 1)
  assert_eq(node.children()[0].kind(), RawKind(1))
}

///|
fn expect_policy_failure(run : () -> Unit raise) -> Unit raise {
  let mut caught = false
  try run() catch {
    Failure::Failure(_) => caught = true
    _ => fail("expected policy mismatch Failure")
  } noraise {
    _ => ()
  }
  assert_true(caught)
}

///|
test "equivalent policies compose while role-swapped policies fail" {
  let error_kind : RawKind = RawKind(90)
  let incomplete_kind : RawKind = RawKind(91)
  let child_policy = CstMetadataPolicy::new(
    [RawKind(3), RawKind(1), RawKind(3)],
    error_kind=Some(error_kind),
    incomplete_kind=Some(incomplete_kind),
  )
  let equivalent = CstMetadataPolicy::new(
    [RawKind(1), RawKind(3)],
    error_kind=Some(error_kind),
    incomplete_kind=Some(incomplete_kind),
  )
  let swapped = CstMetadataPolicy::new(
    [RawKind(1), RawKind(3)],
    error_kind=Some(incomplete_kind),
    incomplete_kind=Some(error_kind),
  )
  let child = CstNode::new(RawKind(2), [], policy=child_policy)
  let parent = CstNode::new(
    RawKind(1),
    [CstElement::Node(child)],
    policy=equivalent,
  )
  assert_eq(parent.children().length(), 1)
  expect_policy_failure(() => {
    let _ = CstNode::new(RawKind(1), [CstElement::Node(child)], policy=swapped)
  })
  assert_eq(child.kind(), RawKind(2))
}

///|
test "trivia and error classification axes overlap" {
  let signal : RawKind = RawKind(7)
  let policy = CstMetadataPolicy::new([signal], error_kind=Some(signal))
  let node = CstNode::new(
    RawKind(1),
    [CstElement::Token(CstToken::CstToken(signal, "?"))],
    policy~,
  )
  assert_eq(node.token_count(), 0)
  assert_true(node.has_any_error())
}

///|
test "replacement and map preserve the receiver metadata domain" {
  let receiver_policy = CstMetadataPolicy::new([RawKind(8)])
  let foreign_policy = CstMetadataPolicy::new([RawKind(9)])
  let receiver = CstNode::new(
    RawKind(1),
    [CstElement::Token(CstToken::CstToken(RawKind(2), "x"))],
    policy=receiver_policy,
  )
  let equivalent = CstNode::new(
    RawKind(4),
    [],
    policy=CstMetadataPolicy::new([RawKind(8), RawKind(8)]),
  )
  let foreign = CstNode::new(RawKind(3), [], policy=foreign_policy)
  assert_eq(receiver.with_replaced_root(equivalent).kind(), RawKind(4))
  expect_policy_failure(() => {
    let _ = receiver.with_replaced_root(foreign)
  })
  expect_policy_failure(() => {
    let _ = receiver.with_replaced_child(0, CstElement::Node(foreign))
  })
  expect_policy_failure(() => {
    let _ = CstElement::Node(receiver).map(_ => CstElement::Node(foreign))
  })
  assert_eq(receiver.text_len(), 1)
}

///|
test "EventBuffer policy preflight leaves buffer and interners reusable" {
  let source_policy = CstMetadataPolicy::new([RawKind(8)])
  let foreign_policy = CstMetadataPolicy::new([RawKind(9)])
  let reused = CstNode::new(
    RawKind(2),
    [CstElement::Token(CstToken::CstToken(RawKind(3), "x"))],
    policy=source_policy,
  )
  let buffer = EventBuffer::new()
  buffer.push(ParseEvent::Token(RawKind(4), "y"))
  buffer.push(ParseEvent::ReuseNode(reused))
  let interner = Interner::new()
  let node_interner = NodeInterner::new()
  expect_policy_failure(() => {
    let _ = buffer.build_tree(RawKind(1), policy=foreign_policy)
  })
  expect_policy_failure(() => {
    let _ = buffer.build_tree_interned(
      RawKind(1),
      interner,
      policy=foreign_policy,
    )
  })
  expect_policy_failure(() => {
    let _ = buffer.build_tree_fully_interned(
      RawKind(1),
      interner,
      node_interner,
      policy=foreign_policy,
    )
  })
  assert_eq(buffer.length(), 2)
  assert_eq(interner.size(), 0)
  assert_eq(node_interner.size(), 0)
  let recovered = buffer.build_tree_fully_interned(
    RawKind(1),
    interner,
    node_interner,
    policy=source_policy,
  )
  assert_eq(recovered.text_len(), 2)
  assert_true(interner.size() > 0)
  assert_true(node_interner.size() > 0)
}
