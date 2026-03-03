///|
pub(all) enum TextDelta {
  Retain(Int) // advance cursor n bytes — no edit emitted
  Insert(String) // insert text at cursor position
  Delete(Int) // delete n bytes at cursor position
} derive(Show, Eq)

///|
/// Convert a TextDelta sequence to Edits for ImperativeParser.
///
/// The returned Edits are in sequential-application order: each Edit's start
/// is in the coordinate space after all previous Edits have been applied.
/// The caller can iterate and call `parser.edit(edit, updated_source)` for each
/// without additional position adjustment.
///
/// Adjacent Delete+Insert are merged into a single replace Edit — the common
/// CRDT pattern [Retain(n), Delete(m), Insert(s)] produces exactly one Edit.
pub fn to_edits(deltas : Array[TextDelta]) -> Array[Edit] {
  let result : Array[Edit] = []
  let mut cursor_orig = 0
  let mut accumulated_delta = 0
  let mut i = 0
  while i < deltas.length() {
    match deltas[i] {
      Retain(n) => {
        cursor_orig += n
        i += 1
      }
      Delete(n) => {
        let pos = cursor_orig + accumulated_delta
        // Merge Delete+Insert into a replace Edit when adjacent
        if i + 1 < deltas.length() {
          match deltas[i + 1] {
            Insert(s) => {
              result.push(Edit::new(pos, n, s.length()))
              accumulated_delta += s.length() - n
              cursor_orig += n
              i += 2
            }
            _ => {
              result.push(Edit::new(pos, n, 0))
              accumulated_delta -= n
              cursor_orig += n
              i += 1
            }
          }
        } else {
          result.push(Edit::new(pos, n, 0))
          accumulated_delta -= n
          cursor_orig += n
          i += 1
        }
      }
      Insert(s) => {
        result.push(Edit::new(cursor_orig + accumulated_delta, 0, s.length()))
        accumulated_delta += s.length()
        i += 1
      }
    }
  }
  result
}

///|
/// Convert a (old, new) string pair into a minimal TextDelta sequence.
///
/// Finds the longest common prefix and suffix, then emits:
///   [Retain(prefix), Delete(old_mid_len), Insert(new_mid)]
///
/// Handles any single contiguous change (the common CRDT case after merge).
/// For identical strings, returns [Retain(n)] — to_edits converts this to [].
pub fn text_to_delta(old : String, new : String) -> Array[TextDelta] {
  let old_len = old.length()
  let new_len = new.length()
  // Find common prefix length
  let mut prefix = 0
  while prefix < old_len && prefix < new_len && old[prefix] == new[prefix] {
    prefix += 1
  }
  // Find common suffix length (don't overlap with prefix region)
  let mut suffix = 0
  while suffix < old_len - prefix &&
        suffix < new_len - prefix &&
        old[old_len - 1 - suffix] == new[new_len - 1 - suffix] {
    suffix += 1
  }
  let old_mid_len = old_len - prefix - suffix
  // Indices are always valid by construction; try? guards against edge cases
  let new_mid = try new[prefix:new_len - suffix] catch {
    _ => ""
  } noraise {
    view => view.to_string()
  }
  let result : Array[TextDelta] = []
  if prefix > 0 {
    result.push(TextDelta::Retain(prefix))
  }
  if old_mid_len > 0 {
    result.push(TextDelta::Delete(old_mid_len))
  }
  if new_mid.length() > 0 {
    result.push(TextDelta::Insert(new_mid))
  }
  result
}
