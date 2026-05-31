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
priv enum PendingProjectionIdentityChange {
  NoProjectionIdentityChange
  ExactProjectionIdentityEdit(Edit, String)
  ProjectionIdentitySourceDiff
}

///|
/// Tracks the last successful projection identity baseline across malformed
/// intermediate input.
///
/// The tracker owns only identity-realignment state. Parser diagnostics,
/// projection diagnostics, semantic documents, and lowering results remain
/// language-owned. `realign_success` is preview-only; call `commit_success`
/// only after parser diagnostics, projection, and semantic lowering all succeed.
pub struct ProjectionIdentityTracker[Id] {
  priv mut baseline : ProjectionIdentityBaseline[Id]?
  priv mut pending : PendingProjectionIdentityChange
}

///|
/// Create an empty projection identity tracker.
pub fn[Id] ProjectionIdentityTracker::new() -> ProjectionIdentityTracker[Id] {
  { baseline: None, pending: NoProjectionIdentityChange }
}

///|
/// Create a projection identity tracker seeded from an existing last-good
/// baseline.
pub fn[Id] ProjectionIdentityTracker::from_baseline(
  baseline : ProjectionIdentityBaseline[Id],
) -> ProjectionIdentityTracker[Id] {
  { baseline: Some(baseline), pending: NoProjectionIdentityChange }
}

///|
/// Return the current last-good projection identity baseline, if one exists.
pub fn[Id] ProjectionIdentityTracker::baseline(
  self : ProjectionIdentityTracker[Id],
) -> ProjectionIdentityBaseline[Id]? {
  self.baseline
}

///|
/// Record an input that failed parser diagnostics, CST projection, or semantic
/// lowering.
///
/// Pass `source_before_edit` and `edit` only when `edit` is relative to the
/// tracker's current last-good baseline source. The pending baseline edit is
/// validated against the next successful source before use, so malformed text
/// may carry additional syntax damage. Later failed or recovery edits compose
/// with the pending baseline-relative edit when they exactly match the parser's
/// malformed source; missing or non-composable edits degrade to source-diff
/// fallback for the next successful projection.
pub fn[Id] ProjectionIdentityTracker::record_failed_input(
  self : ProjectionIdentityTracker[Id],
  current_source : String,
  source_before_edit? : String,
  edit? : Edit,
) -> Unit {
  self.record_failed_input_with_optional_edit(
    current_source, source_before_edit, edit,
  )
}

///|
/// Value-shaped counterpart to `record_failed_input` for callers that already
/// carry optional edit state.
pub fn[Id] ProjectionIdentityTracker::record_failed_input_with_optional_edit(
  self : ProjectionIdentityTracker[Id],
  current_source : String,
  source_before_edit : String?,
  edit : Edit?,
) -> Unit {
  self.pending = self.pending_after_failed_input(
    current_source, source_before_edit, edit,
  )
}

///|
/// Realign `next_leaves` against the retained last-good baseline without
/// mutating the tracker.
///
/// If no baseline exists yet, every returned leaf receives a fresh ID from
/// `allocate`. If a failed input was recorded, the retained pending change wins
/// when it matches `next_source`; a direct `edit` is only used when it composes
/// from the pending malformed source into `next_source`. Otherwise `edit` is
/// used when supplied and source-diff fallback is used when omitted.
pub fn[Id] ProjectionIdentityTracker::realign_success(
  self : ProjectionIdentityTracker[Id],
  next_source : String,
  next_leaves : Array[ProjectionLeaf],
  allocate : (ProjectionLeaf) -> Id,
  edit? : Edit,
) -> Array[StableProjectionLeaf[Id]] {
  self.realign_success_with_optional_edit(
    next_source, next_leaves, allocate, edit,
  )
}

///|
/// Value-shaped counterpart to `realign_success` for callers that already carry
/// optional edit state.
pub fn[Id] ProjectionIdentityTracker::realign_success_with_optional_edit(
  self : ProjectionIdentityTracker[Id],
  next_source : String,
  next_leaves : Array[ProjectionLeaf],
  allocate : (ProjectionLeaf) -> Id,
  edit : Edit?,
) -> Array[StableProjectionLeaf[Id]] {
  match self.baseline {
    None => allocate_all_projection_leaves(next_leaves, allocate)
    Some(baseline) =>
      realign_projection_identities_with_optional_edit(
        baseline,
        next_source,
        next_leaves,
        allocate,
        self.edit_for_success(baseline.source(), next_source, edit),
      )
  }
}

///|
/// Advance the last-good baseline after a successful parse, projection, and
/// semantic lowering.
///
/// This is the only tracker operation that mutates the retained baseline or
/// clears a pending failed-input change.
pub fn[Id] ProjectionIdentityTracker::commit_success(
  self : ProjectionIdentityTracker[Id],
  next_source : String,
  stable_leaves : Array[StableProjectionLeaf[Id]],
) -> Unit {
  self.baseline = Some(
    ProjectionIdentityBaseline::new(next_source, stable_leaves),
  )
  self.pending = NoProjectionIdentityChange
}

///|
fn[Id] ProjectionIdentityTracker::pending_after_failed_input(
  self : ProjectionIdentityTracker[Id],
  current_source : String,
  source_before_edit : String?,
  edit : Edit?,
) -> PendingProjectionIdentityChange {
  match self.baseline {
    None => ProjectionIdentitySourceDiff
    Some(baseline) =>
      match self.pending {
        NoProjectionIdentityChange =>
          pending_baseline_edit_from_source(
            baseline.source(),
            current_source,
            source_before_edit,
            edit,
          )
        ExactProjectionIdentityEdit(pending_edit, pending_source) =>
          pending_after_additional_exact_edit(
            baseline.source(),
            pending_edit,
            pending_source,
            current_source,
            source_before_edit,
            edit,
          )
        ProjectionIdentitySourceDiff => ProjectionIdentitySourceDiff
      }
  }
}

///|
fn[Id] ProjectionIdentityTracker::edit_for_success(
  self : ProjectionIdentityTracker[Id],
  baseline_source : String,
  next_source : String,
  edit : Edit?,
) -> Edit? {
  match self.pending {
    NoProjectionIdentityChange =>
      match edit {
        Some(e) if edit_matches_sources(baseline_source, next_source, e) =>
          Some(e)
        _ => None
      }
    ExactProjectionIdentityEdit(pending_edit, pending_source) =>
      if edit_matches_sources(baseline_source, next_source, pending_edit) {
        Some(pending_edit)
      } else {
        match edit {
          Some(e) if edit_matches_sources(pending_source, next_source, e) =>
            compose_projection_identity_edits(
              baseline_source, pending_edit, pending_source, e, next_source,
            )
          _ => None
        }
      }
    ProjectionIdentitySourceDiff => None
  }
}

///|
fn pending_baseline_edit_from_source(
  expected_source_before_edit : String,
  current_source : String,
  source_before_edit : String?,
  edit : Edit?,
) -> PendingProjectionIdentityChange {
  match (source_before_edit, edit) {
    (Some(before), Some(e)) if before == expected_source_before_edit &&
      edit_has_valid_old_range(before, e) =>
      ExactProjectionIdentityEdit(e, current_source)
    _ => ProjectionIdentitySourceDiff
  }
}

///|
fn pending_after_additional_exact_edit(
  baseline_source : String,
  pending_edit : Edit,
  pending_source : String,
  current_source : String,
  source_before_edit : String?,
  edit : Edit?,
) -> PendingProjectionIdentityChange {
  match
    pending_baseline_edit_from_source(
      baseline_source, current_source, source_before_edit, edit,
    ) {
    ExactProjectionIdentityEdit(e, source) =>
      ExactProjectionIdentityEdit(e, source)
    _ =>
      match (source_before_edit, edit) {
        (Some(before), Some(e)) if before == pending_source &&
          edit_matches_sources(pending_source, current_source, e) =>
          match
            compose_projection_identity_edits(
              baseline_source, pending_edit, pending_source, e, current_source,
            ) {
            Some(composed) =>
              ExactProjectionIdentityEdit(composed, current_source)
            None => ProjectionIdentitySourceDiff
          }
        _ =>
          if pending_source == current_source {
            ExactProjectionIdentityEdit(pending_edit, pending_source)
          } else {
            ProjectionIdentitySourceDiff
          }
      }
  }
}

///|
fn compose_projection_identity_edits(
  baseline_source : String,
  first : Edit,
  middle_source : String,
  second : Edit,
  next_source : String,
) -> Edit? {
  guard edit_has_valid_old_range(baseline_source, first) else { return None }
  guard edit_matches_sources(middle_source, next_source, second) else {
    return None
  }
  let baseline_len = baseline_source.length()
  let second_old_start = clamp_projection_identity_position(
    position_before_projection_identity_edit(first, second.start),
    baseline_len,
  )
  let second_old_end = clamp_projection_identity_position(
    position_before_projection_identity_edit(first, second.old_end()),
    baseline_len,
  )
  let start = if first.start < second_old_start {
    first.start
  } else {
    second_old_start
  }
  let old_end = if first.old_end() > second_old_end {
    first.old_end()
  } else {
    second_old_end
  }
  guard old_end >= start else { return None }
  let old_len = old_end - start
  let new_len = old_len + next_source.length() - baseline_source.length()
  guard new_len >= 0 else { return None }
  let composed = Edit::new(start, old_len, new_len)
  if edit_matches_sources(baseline_source, next_source, composed) {
    Some(composed)
  } else {
    None
  }
}

///|
fn position_before_projection_identity_edit(
  edit : Edit,
  position_after_edit : Int,
) -> Int {
  if position_after_edit <= edit.start {
    position_after_edit
  } else if position_after_edit >= edit.new_end() {
    position_after_edit - edit.delta()
  } else {
    edit.old_end()
  }
}

///|
fn clamp_projection_identity_position(position : Int, source_len : Int) -> Int {
  if position < 0 {
    0
  } else if position > source_len {
    source_len
  } else {
    position
  }
}

///|
fn edit_matches_sources(
  old_source : String,
  next_source : String,
  edit : Edit,
) -> Bool {
  let old_len = old_source.length()
  let next_len = next_source.length()
  let old_end = edit.old_end()
  let new_end = edit.new_end()
  edit_has_valid_old_range(old_source, edit) &&
  new_end <= next_len &&
  old_len + edit.delta() == next_len &&
  source_prefix_matches(old_source, next_source, edit.start) &&
  source_suffix_matches(old_source, next_source, old_end, new_end)
}

///|
fn edit_has_valid_old_range(old_source : String, edit : Edit) -> Bool {
  edit.start >= 0 &&
  edit.deleted_length() >= 0 &&
  edit.inserted_length() >= 0 &&
  edit.old_end() <= old_source.length()
}

///|
fn source_prefix_matches(
  old_source : String,
  next_source : String,
  end : Int,
) -> Bool {
  let mut i = 0
  while i < end {
    if old_source[i] != next_source[i] {
      return false
    }
    i += 1
  }
  true
}

///|
fn source_suffix_matches(
  old_source : String,
  next_source : String,
  old_start : Int,
  next_start : Int,
) -> Bool {
  let old_len = old_source.length()
  let suffix_len = old_len - old_start
  let mut i = 0
  while i < suffix_len {
    if old_source[old_start + i] != next_source[next_start + i] {
      return false
    }
    i += 1
  }
  true
}

///|
fn[Id] allocate_all_projection_leaves(
  leaves : Array[ProjectionLeaf],
  allocate : (ProjectionLeaf) -> Id,
) -> Array[StableProjectionLeaf[Id]] {
  let result : Array[StableProjectionLeaf[Id]] = Array::new(
    capacity=leaves.length(),
  )
  for leaf in leaves {
    result.push(fresh_stable_projection_leaf(leaf, allocate))
  }
  result
}

///|
/// Stateful allocator for projection-owned string IDs.
///
/// The caller supplies `make_id`, so Loom does not impose a public ID schema.
/// `make_id(key, occurrence)` should produce a deterministic candidate ID for
/// that key/occurrence pair and should eventually produce an unused ID as
/// `occurrence` increases. The allocator tracks IDs it has returned and, when
/// seeded from a baseline, IDs that were already preserved from the previous
/// successful projection.
pub struct ProjectionStringIdAllocator {
  priv used : Map[String, Bool]
  priv counters : Map[String, Int]
  priv make_id : (String, Int) -> String
}

///|
/// Create an unseeded string-ID allocator.
pub fn ProjectionStringIdAllocator::new(
  make_id : (String, Int) -> String,
) -> ProjectionStringIdAllocator {
  { used: {}, counters: {}, make_id }
}

///|
/// Create a string-ID allocator seeded with IDs from `baseline`.
///
/// Fresh IDs allocated by the result skip every ID already present in the
/// baseline, avoiding collisions with prefix/suffix IDs preserved by
/// `realign_projection_identities`.
pub fn ProjectionStringIdAllocator::from_baseline(
  baseline : ProjectionIdentityBaseline[String],
  make_id : (String, Int) -> String,
) -> ProjectionStringIdAllocator {
  let allocator = ProjectionStringIdAllocator::new(make_id)
  for leaf in baseline.leaves() {
    allocator.used[leaf.id] = true
  }
  allocator
}

///|
/// Allocate a fresh string ID for `leaf.key`.
pub fn ProjectionStringIdAllocator::allocate(
  self : ProjectionStringIdAllocator,
  leaf : ProjectionLeaf,
) -> String {
  self.allocate_key(leaf.key)
}

///|
fn ProjectionStringIdAllocator::allocate_key(
  self : ProjectionStringIdAllocator,
  key : String,
) -> String {
  let mut occurrence = match self.counters.get(key) {
    Some(value) => value
    None => 0
  }
  let mut id = (self.make_id)(key, occurrence)
  while self.used.contains(id) {
    occurrence += 1
    id = (self.make_id)(key, occurrence)
  }
  self.counters[key] = occurrence + 1
  self.used[id] = true
  id
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
/// Realign domain items against a projection identity baseline.
///
/// `to_leaf` extracts the source range and stable key from each item.
/// `with_id` zips the preserved or fresh ID back onto the original item. This
/// delegates to `realign_projection_identities`, so duplicate-key prefix/suffix
/// preservation and changed-window allocation match the lower-level helper.
pub fn[Item, Id, StableItem] realign_projection_items(
  baseline : ProjectionIdentityBaseline[Id],
  next_source : String,
  items : Array[Item],
  to_leaf : (Item) -> ProjectionLeaf,
  with_id : (Item, Id) -> StableItem,
  allocate : (ProjectionLeaf) -> Id,
  edit? : Edit,
) -> Array[StableItem] {
  realign_projection_items_with_optional_edit(
    baseline, next_source, items, to_leaf, with_id, allocate, edit,
  )
}

///|
/// Realign domain items against a projection identity baseline, accepting the
/// edit as an `Edit?` value.
pub fn[Item, Id, StableItem] realign_projection_items_with_optional_edit(
  baseline : ProjectionIdentityBaseline[Id],
  next_source : String,
  items : Array[Item],
  to_leaf : (Item) -> ProjectionLeaf,
  with_id : (Item, Id) -> StableItem,
  allocate : (ProjectionLeaf) -> Id,
  edit : Edit?,
) -> Array[StableItem] {
  let leaves = items.map(to_leaf)
  let stable = realign_projection_identities_with_optional_edit(
    baseline, next_source, leaves, allocate, edit,
  )
  let result : Array[StableItem] = Array::new(capacity=items.length())
  for i = 0; i < items.length(); i = i + 1 {
    result.push(with_id(items[i], stable[i].id))
  }
  result
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
