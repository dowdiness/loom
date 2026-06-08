///|
/// Metadata-trust invariant tests.
///
/// `CstNode::new` computes `has_any_error` / `token_count` by *trusting* each
/// child Node's cached metadata and *re-classifying* token children against the
/// `error_kind` / `incomplete_kind` / `trivia_kind` passed to this call (see
/// cst_node.mbt and the caveat in cst_traverse.mbt). The invariant: every
/// reconstruction path must thread the *same* classification kinds the subtree
/// was originally built with, or the recomputed metadata silently diverges.
///
/// These tests pin that invariant for the reconstruction paths AND keep a
/// positive control proving the test would catch a regression — `CstElement::map`
/// defaults its kinds to `None`, so an un-threaded reconstruction must lose the
/// error bit. If that control ever stops failing, the detector is broken.

///|
/// Build a node whose only "badness" comes from an error-kind token child, so
/// that `has_any_error` depends entirely on the threaded `error_kind`.
fn make_error_bearing_node(error_raw : RawKind) -> CstNode {
  let err_token = CstElement::Token(CstToken::CstToken(error_raw, "?"))
  CstNode::new(RawKind(1), [err_token], error_kind=Some(error_raw))
}

///|
test "metadata-trust: map threading error_kind preserves has_any_error" {
  let err = RawKind(99)
  let original = make_error_bearing_node(err)
  // Sanity: original is classified as carrying an error.
  assert_true(original.has_any_error)

  // Reconstruct via identity map WITH the kind threaded → invariant preserved.
  let rebuilt = CstElement::Node(original).map(e => e, error_kind=Some(err))
  guard rebuilt is Node(n) else { fail("expected a Node from map") }
  assert_true(n.has_any_error)
}

///|
test "metadata-trust: with_replaced_child threading preserves has_any_error" {
  let err = RawKind(99)
  let error_child = CstElement::Node(make_error_bearing_node(err))
  let clean_child = CstElement::Token(CstToken::CstToken(RawKind(2), "x"))
  // Parent built with two children, the first carrying an error.
  let parent = CstNode::new(
    RawKind(5),
    [error_child, clean_child],
    error_kind=Some(err),
  )
  assert_true(parent.has_any_error)

  // Replace the CLEAN child, threading the same error_kind → the surviving
  // error child's trusted metadata must keep the parent's error bit set.
  let new_clean = CstElement::Token(CstToken::CstToken(RawKind(2), "y"))
  let rebuilt = parent.with_replaced_child(1, new_clean, error_kind=Some(err))
  assert_true(rebuilt.has_any_error)
}

///|
/// Positive control: reconstructing WITHOUT threading the kinds drops the error
/// classification. This documents the latent footgun (`map`'s kinds default to
/// `None`) and proves the tests above are actually exercising the mechanism — if
/// this ever passes (stops losing the bit), the detector has gone blind.
test "metadata-trust: un-threaded map loses the error bit (footgun control)" {
  let err = RawKind(99)
  let original = make_error_bearing_node(err)
  assert_true(original.has_any_error)

  // map with no kinds → error_kind defaults to None → the error token is no
  // longer classified as an error → recomputed has_any_error is false.
  let rebuilt = CstElement::Node(original).map(e => e)
  guard rebuilt is Node(n) else { fail("expected a Node from map") }
  assert_false(n.has_any_error)
}
