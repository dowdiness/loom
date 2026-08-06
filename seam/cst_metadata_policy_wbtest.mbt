///|
test "CstMetadataPolicy normalizes trivia as a set and preserves roles" {
  let error_kind = RawKind(90)
  let incomplete_kind = RawKind(91)
  let left = CstMetadataPolicy::new(
    [RawKind(3), RawKind(1), RawKind(3)],
    error_kind=Some(error_kind),
    incomplete_kind=Some(incomplete_kind),
  )
  let reordered = CstMetadataPolicy::new(
    [RawKind(1), RawKind(3)],
    error_kind=Some(error_kind),
    incomplete_kind=Some(incomplete_kind),
  )
  let swapped = CstMetadataPolicy::new(
    [RawKind(1), RawKind(3)],
    error_kind=Some(incomplete_kind),
    incomplete_kind=Some(error_kind),
  )
  assert_true(policy_equal(left, reordered))
  assert_eq(left.semantic_hash, reordered.semantic_hash)
  assert_false(policy_equal(left, swapped))
}

///|
test "CstMetadataPolicy canonicalizes semantic-empty construction" {
  let shared = CstMetadataPolicy::unclassified()
  let repeated = CstMetadataPolicy::unclassified()
  let constructed = CstMetadataPolicy::new([])
  assert_true(physical_equal(shared, repeated))
  assert_true(physical_equal(shared, constructed))
}
