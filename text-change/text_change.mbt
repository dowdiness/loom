// Pure contiguous text-change logic shared across crdt, loom, and valtio.
// Keep this module leaf-only: no parser, CRDT, or UI dependencies.

///|
pub(all) enum TextChange {
  ReplaceRange(start~ : Int, delete_len~ : Int, inserted~ : String)
  ReplaceAll(String)
} derive(Eq, Debug)

///|
pub(all) suberror ChangeSetError {
  NegativeSourceLength
  NegativeRange(index~ : Int, start~ : Int, delete_len~ : Int)
  ReplaceAll(index~ : Int)
  Unordered(index~ : Int)
  Overlapping(index~ : Int)
  OutOfBounds(index~ : Int, end~ : Int, source_length~ : Int)
  ResultLengthOverflow(index~ : Int)
} derive(Eq, Debug)

///|
/// An atomic collection of replacements in the original source coordinates.
///
/// The fields are intentionally private: construct a set with `ChangeSet::ChangeSet`
/// so that its ordering and length invariants are always checked.
pub(all) struct ChangeSet {
  priv source_length : Int
  priv result_length : Int
  priv changes : Array[TextChange]
}

///|
/// Validate and construct an atomic set of UTF-16 source-coordinate changes.
pub fn ChangeSet::ChangeSet(
  source_length~ : Int,
  changes~ : Array[TextChange],
) -> ChangeSet raise ChangeSetError {
  if source_length < 0 {
    raise ChangeSetError::NegativeSourceLength
  }
  let mut previous_start : Int? = None
  let mut previous_end = 0
  let mut result_length = source_length
  for index, change in changes {
    match change {
      ReplaceAll(_) => raise ChangeSetError::ReplaceAll(index~)
      ReplaceRange(start~, delete_len~, inserted~) => {
        if start < 0 || delete_len < 0 {
          raise ChangeSetError::NegativeRange(index~, start~, delete_len~)
        }
        if previous_start is Some(previous_start) && start < previous_start {
          raise ChangeSetError::Unordered(index~)
        }
        if start < previous_end {
          raise ChangeSetError::Overlapping(index~)
        }
        if delete_len > @int.MAX_VALUE - start {
          raise ChangeSetError::OutOfBounds(
            index~,
            end=@int.MAX_VALUE,
            source_length~,
          )
        }
        let end = start + delete_len
        if end > source_length {
          raise ChangeSetError::OutOfBounds(index~, end~, source_length~)
        }
        let delta = inserted.length() - delete_len
        if delta > 0 && result_length > @int.MAX_VALUE - delta {
          raise ChangeSetError::ResultLengthOverflow(index~)
        }
        result_length = result_length + delta
        previous_start = Some(start)
        previous_end = end
      }
    }
  }
  {
    source_length,
    result_length,
    changes: changes.filter(change => !change.is_noop()),
  }
}

///|
/// Construct an empty change set for a source of the given UTF-16 length.
pub fn ChangeSet::empty(source_length : Int) -> ChangeSet raise ChangeSetError {
  ChangeSet::ChangeSet(source_length~, changes=[])
}

///|
pub fn ChangeSet::source_length(self : ChangeSet) -> Int {
  self.source_length
}

///|
pub fn ChangeSet::result_length(self : ChangeSet) -> Int {
  self.result_length
}

///|
pub fn ChangeSet::is_empty(self : ChangeSet) -> Bool {
  self.changes.is_empty()
}

///|
/// Visit replacements in validated original-source coordinate order.
///
/// The callback cannot mutate the change set's private storage.
pub fn ChangeSet::each(
  self : ChangeSet,
  visit : (TextChange) -> Unit raise?,
) -> Unit raise? {
  self.changes.each(visit)
}

///|
/// Apply every replacement against the original source coordinates.
pub fn ChangeSet::apply(self : ChangeSet, source : String) -> String? {
  guard source.length() == self.source_length else { return None }
  let builder = StringBuilder(size_hint=self.result_length)
  let mut cursor = 0
  for change in self.changes {
    match change {
      ReplaceRange(start~, delete_len~, inserted~) => {
        guard source.get_view(start=cursor, end=start) is Some(prefix) else {
          return None
        }
        builder.write_stringview(prefix)
        builder.write_string(inserted)
        cursor = start + delete_len
      }
      ReplaceAll(_) => return None
    }
  }
  guard source.get_view(start=cursor) is Some(suffix) else { return None }
  builder.write_stringview(suffix)
  Some(builder.to_string())
}

///|
fn cluster_equal(
  old_text : String,
  old_start : Int,
  old_end : Int,
  new_text : String,
  new_start : Int,
  new_end : Int,
) -> Bool {
  old_text[old_start:old_end].to_owned() ==
  new_text[new_start:new_end].to_owned()
}

///|
fn common_prefix_len(old_text : String, new_text : String) -> Int {
  let old_boundaries = @moji.grapheme_boundaries(old_text)
  let new_boundaries = @moji.grapheme_boundaries(new_text)
  let mut idx = 0
  let mut prefix = 0
  while idx + 1 < old_boundaries.length() && idx + 1 < new_boundaries.length() {
    let old_start = old_boundaries[idx]
    let old_end = old_boundaries[idx + 1]
    let new_start = new_boundaries[idx]
    let new_end = new_boundaries[idx + 1]
    if cluster_equal(old_text, old_start, old_end, new_text, new_start, new_end) {
      prefix = old_end
      idx += 1
    } else {
      break
    }
  }
  prefix
}

///|
fn common_suffix_lens(
  old_text : String,
  new_text : String,
  prefix_len : Int,
) -> (Int, Int) {
  let old_boundaries = @moji.grapheme_boundaries(old_text)
  let new_boundaries = @moji.grapheme_boundaries(new_text)
  let mut old_idx = old_boundaries.length() - 1
  let mut new_idx = new_boundaries.length() - 1
  let mut old_suffix_len = 0
  let mut new_suffix_len = 0
  while old_idx > 0 && new_idx > 0 {
    let old_start = old_boundaries[old_idx - 1]
    let old_end = old_boundaries[old_idx]
    let new_start = new_boundaries[new_idx - 1]
    let new_end = new_boundaries[new_idx]
    if old_start < prefix_len || new_start < prefix_len {
      break
    }
    if cluster_equal(old_text, old_start, old_end, new_text, new_start, new_end) {
      old_suffix_len += old_end - old_start
      new_suffix_len += new_end - new_start
      old_idx -= 1
      new_idx -= 1
    } else {
      break
    }
  }
  (old_suffix_len, new_suffix_len)
}

///|
/// Compute the minimal contiguous text change between two strings.
pub fn compute_text_change(old_text : String, new_text : String) -> TextChange {
  let old_len = old_text.length()
  let new_len = new_text.length()

  let prefix = common_prefix_len(old_text, new_text)
  let (old_suffix_len, new_suffix_len) = common_suffix_lens(
    old_text, new_text, prefix,
  )

  let delete_len = old_len - prefix - old_suffix_len
  let inserted = new_text[prefix:new_len - new_suffix_len].to_owned()
  TextChange::ReplaceRange(start=prefix, delete_len~, inserted~)
}

///|
/// Apply this change to one source String.
///
/// `ReplaceRange` returns `None` for a negative range, an out-of-bounds range,
/// or a range that splits a UTF-16 surrogate pair. `ReplaceAll` returns its
/// complete replacement directly.
pub fn TextChange::apply(self : TextChange, source : String) -> String? {
  match self {
    ReplaceAll(text) => Some(text)
    ReplaceRange(start~, delete_len~, inserted~) => {
      guard start >= 0 && delete_len >= 0 else { return None }
      let removed_end = start + delete_len
      guard removed_end >= start else { return None }
      guard source.get_view(end=start) is Some(prefix) else { return None }
      guard source.get_view(start=removed_end) is Some(suffix) else {
        return None
      }
      let builder = StringBuilder(
        size_hint=source.length() - delete_len + inserted.length(),
      )
      builder
      ..write_stringview(prefix)
      ..write_string(inserted)
      .write_stringview(suffix)
      Some(builder.to_string())
    }
  }
}

///|
pub fn TextChange::is_noop(self : TextChange) -> Bool {
  match self {
    ReplaceRange(delete_len=0, inserted="", ..) => true
    ReplaceRange(_) | ReplaceAll(_) => false
  }
}
