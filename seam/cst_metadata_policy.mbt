///|
/// Immutable classification contract for cached CST metadata.
///
/// Trivia kinds are stored as a canonical sorted set. Error and incomplete
/// kinds are role-bearing slots and therefore remain distinct.
pub struct CstMetadataPolicy {
  priv trivia_kinds : Array[RawKind]
  priv error_kind : RawKind?
  priv incomplete_kind : RawKind?
  priv semantic_hash : Int
}

///|
fn hash_optional_kind(hash : Int, kind : RawKind?) -> Int {
  match kind {
    None => combine_hash(hash, 0)
    Some(RawKind(value)) => combine_hash(combine_hash(hash, 1), value)
  }
}

///|
fn compute_policy_hash(
  trivia_kinds : Array[RawKind],
  error_kind : RawKind?,
  incomplete_kind : RawKind?,
) -> Int {
  let mut hash = combine_hash(1129534544, trivia_kinds.length())
  for raw_kind in trivia_kinds {
    let RawKind(kind) = raw_kind
    hash = combine_hash(hash, kind)
  }
  hash = hash_optional_kind(combine_hash(hash, 1), error_kind)
  hash_optional_kind(combine_hash(hash, 2), incomplete_kind)
}

///|
fn canonical_trivia_kinds(trivia_kinds : Array[RawKind]) -> Array[RawKind] {
  let sorted = trivia_kinds.copy()
  sorted.sort()
  let canonical : Array[RawKind] = Array::new(capacity=sorted.length())
  for kind in sorted {
    if canonical.is_empty() || canonical[canonical.length() - 1] != kind {
      canonical.push(kind)
    }
  }
  canonical
}

///|
let unclassified_policy : CstMetadataPolicy = {
  trivia_kinds: [],
  error_kind: None,
  incomplete_kind: None,
  semantic_hash: compute_policy_hash([], None, None),
}

///|
/// Create an immutable CST metadata policy.
///
/// The input trivia array is copied, sorted, and deduplicated. A semantically
/// empty policy canonicalizes to the package-level unclassified value.
pub fn CstMetadataPolicy::new(
  trivia_kinds : Array[RawKind],
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstMetadataPolicy {
  let canonical = canonical_trivia_kinds(trivia_kinds)
  if canonical.is_empty() && error_kind is None && incomplete_kind is None {
    return unclassified_policy
  }
  {
    trivia_kinds: canonical,
    error_kind,
    incomplete_kind,
    semantic_hash: compute_policy_hash(canonical, error_kind, incomplete_kind),
  }
}

///|
/// Return the shared language-agnostic metadata policy.
pub fn CstMetadataPolicy::unclassified() -> CstMetadataPolicy {
  unclassified_policy
}

///|
fn policy_equal(left : CstMetadataPolicy, right : CstMetadataPolicy) -> Bool {
  if physical_equal(left, right) {
    return true
  }
  if left.semantic_hash != right.semantic_hash ||
    left.error_kind != right.error_kind ||
    left.incomplete_kind != right.incomplete_kind ||
    left.trivia_kinds.length() != right.trivia_kinds.length() {
    return false
  }
  for index in 0..<left.trivia_kinds.length() {
    if left.trivia_kinds[index] != right.trivia_kinds[index] {
      return false
    }
  }
  true
}

///|
fn CstMetadataPolicy::is_trivia(
  self : CstMetadataPolicy,
  kind : RawKind,
) -> Bool {
  self.trivia_kinds.contains(kind)
}

///|
fn CstMetadataPolicy::is_error_signal(
  self : CstMetadataPolicy,
  kind : RawKind,
) -> Bool {
  (match self.error_kind {
    Some(error_kind) => kind == error_kind
    None => false
  }) ||
  (match self.incomplete_kind {
    Some(incomplete_kind) => kind == incomplete_kind
    None => false
  })
}
