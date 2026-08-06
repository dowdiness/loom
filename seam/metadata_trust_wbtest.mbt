///|
fn error_policy(error_kind : RawKind) -> CstMetadataPolicy {
  CstMetadataPolicy::new([], error_kind=Some(error_kind))
}

///|
fn make_error_bearing_node(
  error_kind : RawKind,
  policy : CstMetadataPolicy,
) -> CstNode raise Failure {
  let error_token = CstElement::Token(CstToken::CstToken(error_kind, "?"))
  CstNode::new(RawKind(1), [error_token], policy~)
}

///|
test "metadata policy: map preserves receiver classification" {
  let error_kind = RawKind(99)
  let policy = error_policy(error_kind)
  let original = make_error_bearing_node(error_kind, policy)
  let rebuilt = CstElement::Node(original).map(element => element)
  guard rebuilt is CstElement::Node(node) else { fail("expected node") }
  assert_true(node.has_any_error)
  assert_true(policy_equal(node.policy, policy))
}

///|
test "metadata policy: child replacement preserves receiver classification" {
  let error_kind = RawKind(99)
  let policy = error_policy(error_kind)
  let error_token = CstElement::Token(CstToken::CstToken(error_kind, "?"))
  let clean_token = CstElement::Token(CstToken::CstToken(RawKind(2), "x"))
  let parent = CstNode::new(RawKind(5), [error_token, clean_token], policy~)
  let replacement = CstElement::Token(CstToken::CstToken(RawKind(2), "y"))
  let rebuilt = parent.with_replaced_child(1, replacement)
  assert_true(rebuilt.has_any_error)
  assert_true(policy_equal(rebuilt.policy, policy))
}
