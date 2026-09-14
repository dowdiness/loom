///|
using @core {type Edit}

///|
pub fn compose_projection_identity_edits(
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
pub fn edit_matches_sources(
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
pub fn edit_has_valid_old_range(old_source : String, edit : Edit) -> Bool {
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
  for i in 0..<end {
    if old_source[i] != next_source[i] {
      return false
    }
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
  let suffix_len = old_source.length() - old_start
  for i in 0..<suffix_len {
    if old_source[old_start + i] != next_source[next_start + i] {
      return false
    }
  }
  true
}
