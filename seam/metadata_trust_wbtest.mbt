///|
/// Metadata-trust invariant tests.
///
/// `CstNode::new` computes `has_any_error` / `token_count` by *trusting* each
/// child Node's cached metadata and *re-classifying* token children against the
/// `error_kind` / `incomplete_kind` / `trivia_kinds` passed to this call (see
/// cst_node.mbt and the caveat in cst_traverse.mbt). The invariant: every
/// reconstruction path must thread the *same* classification kinds the subtree
/// was originally built with, or the recomputed metadata silently diverges.
///
/// These tests pin that invariant for both reconstruction paths (`map` and
/// `with_replaced_child`), each paired with a positive control proving the test
/// would catch a regression: both paths default their kinds to `None`, so an
/// un-threaded reconstruction of a node carrying a direct error *token* must lose
/// the error bit. If a control ever stops failing, that detector is broken.

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
/// Build a 2-child parent whose error lives in a *direct error token* (index 0),
/// not a wrapped error node. This is what makes `with_replaced_child` actually
/// exercise the threading invariant: `CstNode::new` *trusts* a child node's
/// cached `has_any_error` regardless of the kinds passed, so an error wrapped in
/// a child node would keep the bit set even with threading dropped (tautology).
/// A direct error token, by contrast, is re-classified against *this* call's
/// `error_kind` — so the bit survives reconstruction only if the kind is threaded.
fn make_error_token_parent(error_raw : RawKind) -> CstNode {
  let error_token = CstElement::Token(CstToken::CstToken(error_raw, "?"))
  let clean_child = CstElement::Token(CstToken::CstToken(RawKind(2), "x"))
  CstNode::new(
    RawKind(5),
    [error_token, clean_child],
    error_kind=Some(error_raw),
  )
}

///|
test "metadata-trust: with_replaced_child threading preserves has_any_error" {
  let err = RawKind(99)
  let parent = make_error_token_parent(err)
  assert_true(parent.has_any_error)

  // Replace the CLEAN sibling (index 1), threading the same error_kind → the
  // surviving error TOKEN (index 0) is re-classified as an error → bit preserved.
  let new_clean = CstElement::Token(CstToken::CstToken(RawKind(2), "y"))
  let rebuilt = parent.with_replaced_child(1, new_clean, error_kind=Some(err))
  assert_true(rebuilt.has_any_error)
}

///|
/// Positive control for the replacement path: replacing a sibling WITHOUT
/// threading `error_kind` (it defaults to `None`) re-classifies the surviving
/// error token as non-error and drops the bit. Proves the test above exercises
/// the threading mechanism rather than a trusted child-node short-circuit — if
/// this ever stops failing, `with_replaced_child` coverage has gone blind.
test "metadata-trust: un-threaded with_replaced_child loses the error bit (footgun control)" {
  let err = RawKind(99)
  let parent = make_error_token_parent(err)
  assert_true(parent.has_any_error)

  // error_kind defaults to None → the surviving error token is no longer an
  // error → recomputed has_any_error is false.
  let new_clean = CstElement::Token(CstToken::CstToken(RawKind(2), "y"))
  let rebuilt = parent.with_replaced_child(1, new_clean)
  assert_false(rebuilt.has_any_error)
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
