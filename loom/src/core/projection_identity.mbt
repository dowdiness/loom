///|
/// A user-facing semantic leaf extracted from a successful CST projection.
///
/// `start` and `end` are UTF-16 code-unit offsets in the source used for the
/// projection. `key` is a domain-chosen equality key such as a token text plus
/// semantic family. It is used only as a safety check when carrying old IDs
/// across an edit.
pub struct ProjectionLeaf {
  start : Int
  end : Int
  key : String
} derive(Eq, Debug)

///|
pub fn ProjectionLeaf::new(
  start : Int,
  end : Int,
  key : String,
) -> ProjectionLeaf {
  { start, end, key }
}

///|
/// A projected semantic leaf paired with its domain-owned stable identity.
///
/// The `id` type is generic so downstream authoring layers can keep public IDs
/// in their own shape instead of exposing Loom internals.
pub struct StableProjectionLeaf[Id] {
  start : Int
  end : Int
  key : String
  id : Id
} derive(Eq, Debug)

///|
pub fn[Id] StableProjectionLeaf::new(
  start : Int,
  end : Int,
  key : String,
  id : Id,
) -> StableProjectionLeaf[Id] {
  { start, end, key, id }
}

///|
/// Edit window used for semantic identity realignment.
///
/// Old leaves ending at or before `old_start` form the reusable prefix. Old
/// leaves starting at or after `old_end` form the reusable suffix. New leaves in
/// the corresponding prefix/suffix windows inherit old IDs when their keys still
/// match; leaves inside the new window receive fresh IDs.
struct ProjectionIdentityWindow {
  old_start : Int
  old_end : Int
  new_start : Int
  new_end : Int
} derive(Eq, Debug)

///|
fn ProjectionIdentityWindow::new(
  old_start : Int,
  old_end : Int,
  new_start : Int,
  new_end : Int,
) -> ProjectionIdentityWindow {
  { old_start, old_end, new_start, new_end }
}

///|
/// Build a projection identity window from an editor-provided edit span.
fn ProjectionIdentityWindow::from_edit(edit : Edit) -> ProjectionIdentityWindow {
  ProjectionIdentityWindow::new(
    edit.start,
    edit.old_end(),
    edit.start,
    edit.new_end(),
  )
}

///|
/// Build a projection identity window by diffing two source baselines.
///
/// This is the fallback path for `set_source` or for recovery after malformed
/// intermediate input when no edit span relative to the last-good semantic
/// baseline is available.
fn ProjectionIdentityWindow::from_sources(
  old_source : String,
  new_source : String,
) -> ProjectionIdentityWindow {
  let change = @shared_text_change.compute_text_change(old_source, new_source)
  ProjectionIdentityWindow::new(
    change.start,
    change.start + change.delete_len,
    change.start,
    change.start + change.inserted.length(),
  )
}

///|
/// Last successful semantic projection baseline used for stable-ID recovery.
///
/// Keep this baseline only after parser diagnostics and projection/lowering both
/// succeed. If later input is malformed, retain the old baseline and realign the
/// next successful projection against it.
pub struct ProjectionIdentityBaseline[Id] {
  priv source : String
  priv leaves : Array[StableProjectionLeaf[Id]]
} derive(Eq, Debug)

///|
pub fn[Id] ProjectionIdentityBaseline::new(
  source : String,
  leaves : Array[StableProjectionLeaf[Id]],
) -> ProjectionIdentityBaseline[Id] {
  { source, leaves: leaves.copy() }
}

///|
pub fn[Id] ProjectionIdentityBaseline::source(
  self : ProjectionIdentityBaseline[Id],
) -> String {
  self.source
}

///|
pub fn[Id] ProjectionIdentityBaseline::leaves(
  self : ProjectionIdentityBaseline[Id],
) -> Array[StableProjectionLeaf[Id]] {
  self.leaves.copy()
}

///|
/// Realign `next_leaves` against this last-good baseline and return a new
/// baseline for the successful projection.
pub fn[Id] ProjectionIdentityBaseline::advance(
  self : ProjectionIdentityBaseline[Id],
  next_source : String,
  next_leaves : Array[ProjectionLeaf],
  allocate : (ProjectionLeaf) -> Id,
  edit? : Edit,
) -> ProjectionIdentityBaseline[Id] {
  self.advance_with_optional_edit(next_source, next_leaves, allocate, edit)
}

///|
/// Realign `next_leaves` against this last-good baseline using an `Edit?`
/// value and return a new baseline for the successful projection.
///
/// This is the value-shaped counterpart to `advance`, for callers that already
/// carry `Edit?` state across parse/projection recovery.
pub fn[Id] ProjectionIdentityBaseline::advance_with_optional_edit(
  self : ProjectionIdentityBaseline[Id],
  next_source : String,
  next_leaves : Array[ProjectionLeaf],
  allocate : (ProjectionLeaf) -> Id,
  edit : Edit?,
) -> ProjectionIdentityBaseline[Id] {
  ProjectionIdentityBaseline::new(
    next_source,
    realign_projection_identities_with_optional_edit(
      self, next_source, next_leaves, allocate, edit,
    ),
  )
}

///|
/// Preserve stable IDs for unchanged prefix/suffix leaves around an edit window.
///
/// Pass `edit=editor_edit` when the edit is relative to the baseline's source.
/// Omit it to fall back to a minimal source diff between the baseline and
/// `next_source`. The `allocate` callback is invoked only for leaves inside the
/// changed window or for unexpected key mismatches in the reusable prefix/suffix.
pub fn[Id] realign_projection_identities(
  baseline : ProjectionIdentityBaseline[Id],
  next_source : String,
  next_leaves : Array[ProjectionLeaf],
  allocate : (ProjectionLeaf) -> Id,
  edit? : Edit,
) -> Array[StableProjectionLeaf[Id]] {
  realign_projection_identities_with_optional_edit(
    baseline, next_source, next_leaves, allocate, edit,
  )
}

///|
/// Preserve stable IDs for unchanged prefix/suffix leaves around an edit
/// window, accepting the edit as an `Edit?` value.
///
/// Pass `Some(editor_edit)` when the edit is relative to the baseline's source.
/// Pass `None` to fall back to a minimal source diff between the baseline and
/// `next_source`.
pub fn[Id] realign_projection_identities_with_optional_edit(
  baseline : ProjectionIdentityBaseline[Id],
  next_source : String,
  next_leaves : Array[ProjectionLeaf],
  allocate : (ProjectionLeaf) -> Id,
  edit : Edit?,
) -> Array[StableProjectionLeaf[Id]] {
  let window = match edit {
    Some(e) => ProjectionIdentityWindow::from_edit(e)
    None => ProjectionIdentityWindow::from_sources(baseline.source, next_source)
  }
  realign_projection_identities_in_window(
    baseline.leaves,
    next_leaves,
    allocate,
    window,
  )
}

///|
fn[Id] realign_projection_identities_in_window(
  previous : Array[StableProjectionLeaf[Id]],
  next : Array[ProjectionLeaf],
  allocate : (ProjectionLeaf) -> Id,
  window : ProjectionIdentityWindow,
) -> Array[StableProjectionLeaf[Id]] {
  let old_prefix_count = count_old_prefix(previous, window.old_start)
  let new_prefix_count = count_new_prefix(next, window.new_start)
  let mut prefix_count = if old_prefix_count < new_prefix_count {
    old_prefix_count
  } else {
    new_prefix_count
  }
  if prefix_count > previous.length() {
    prefix_count = previous.length()
  }
  if prefix_count > next.length() {
    prefix_count = next.length()
  }

  let old_suffix_count = count_old_suffix(previous, window.old_end)
  let new_suffix_count = count_new_suffix(next, window.new_end)
  let mut suffix_count = if old_suffix_count < new_suffix_count {
    old_suffix_count
  } else {
    new_suffix_count
  }
  if suffix_count > previous.length() - prefix_count {
    suffix_count = previous.length() - prefix_count
  }
  if suffix_count > next.length() - prefix_count {
    suffix_count = next.length() - prefix_count
  }

  let new_suffix_start = next.length() - suffix_count
  let old_suffix_start = previous.length() - suffix_count

  let result : Array[StableProjectionLeaf[Id]] = Array::new(
    capacity=next.length(),
  )
  for i = 0; i < next.length(); i = i + 1 {
    if i < prefix_count {
      result.push(align_or_allocate(previous[i], next[i], allocate))
    } else if i >= new_suffix_start {
      let old_index = old_suffix_start + (i - new_suffix_start)
      result.push(align_or_allocate(previous[old_index], next[i], allocate))
    } else {
      result.push(fresh_stable_projection_leaf(next[i], allocate))
    }
  }
  result
}

///|
fn[Id] count_old_prefix(
  leaves : Array[StableProjectionLeaf[Id]],
  old_start : Int,
) -> Int {
  let mut count = 0
  while count < leaves.length() && leaves[count].end <= old_start {
    count += 1
  }
  count
}

///|
fn count_new_prefix(leaves : Array[ProjectionLeaf], new_start : Int) -> Int {
  let mut count = 0
  while count < leaves.length() && leaves[count].end <= new_start {
    count += 1
  }
  count
}

///|
fn[Id] count_old_suffix(
  leaves : Array[StableProjectionLeaf[Id]],
  old_end : Int,
) -> Int {
  let mut count = 0
  let mut i = leaves.length()
  while i > 0 && leaves[i - 1].start >= old_end {
    count += 1
    i -= 1
  }
  count
}

///|
fn count_new_suffix(leaves : Array[ProjectionLeaf], new_end : Int) -> Int {
  let mut count = 0
  let mut i = leaves.length()
  while i > 0 && leaves[i - 1].start >= new_end {
    count += 1
    i -= 1
  }
  count
}

///|
fn[Id] align_or_allocate(
  old_leaf : StableProjectionLeaf[Id],
  new_leaf : ProjectionLeaf,
  allocate : (ProjectionLeaf) -> Id,
) -> StableProjectionLeaf[Id] {
  if old_leaf.key == new_leaf.key {
    StableProjectionLeaf::new(
      new_leaf.start,
      new_leaf.end,
      new_leaf.key,
      old_leaf.id,
    )
  } else {
    fresh_stable_projection_leaf(new_leaf, allocate)
  }
}

///|
fn[Id] fresh_stable_projection_leaf(
  leaf : ProjectionLeaf,
  allocate : (ProjectionLeaf) -> Id,
) -> StableProjectionLeaf[Id] {
  StableProjectionLeaf::new(leaf.start, leaf.end, leaf.key, allocate(leaf))
}
