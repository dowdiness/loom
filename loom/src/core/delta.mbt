///|
pub(all) enum TextDelta {
  Retain(Int) // advance cursor n bytes — no edit emitted
  Insert(String) // insert text at cursor position
  Delete(Int) // delete n bytes at cursor position
} derive(Debug, Eq)

///|
pub impl Show for TextDelta with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

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
/// Convert a shared contiguous TextChange into loom's TextDelta representation.
fn text_change_to_delta(
  change : @shared_text_change.TextChange,
) -> Array[TextDelta] {
  let result : Array[TextDelta] = []
  if change.start > 0 {
    result.push(TextDelta::Retain(change.start))
  }
  if change.delete_len > 0 {
    result.push(TextDelta::Delete(change.delete_len))
  }
  if change.inserted.length() > 0 {
    result.push(TextDelta::Insert(change.inserted))
  }
  result
}

///|
/// Convert a (old, new) string pair into a minimal TextDelta sequence.
pub fn text_to_delta(old : String, new : String) -> Array[TextDelta] {
  text_change_to_delta(@shared_text_change.compute_text_change(old, new))
}
