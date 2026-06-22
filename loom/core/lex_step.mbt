// Step-based lexing contract — progress-guaranteed, deterministic recovery.
//
// Core Laws:
// 1. Deterministic: same (source, start) -> same LexStep.
// 2. Progress: Produced.next_offset > start (unless EOF); Invalid advances by
//    its positive width, or by one Unicode scalar value when width is invalid.
// 3. Stability: Invalid.at identifies the first irrevocably invalid byte for this step.
// 4. Safety: no infinite loops when repeatedly stepping from 0..EOF.

///|
pub(all) enum LexStep[T] {
  Produced(TokenInfo[T], next_offset~ : Int)
  Invalid(at~ : Int, width~ : Int, message~ : String)
  Incomplete(at~ : Int, expected~ : String)
  Done
}

///|
/// Dictionary-passing wrapper for step-based lexing.
/// Use this instead of a trait because MoonBit traits cannot be
/// generic over arbitrary token type T in the way we need.
pub(all) struct PrefixLexer[T] {
  lex_step : (String, Int) -> LexStep[T]
}

///|
/// Create a PrefixLexer from a stepping function.
pub fn[T] PrefixLexer::new(
  lex_step~ : (String, Int) -> LexStep[T],
) -> PrefixLexer[T] {
  { lex_step, }
}

///|
/// Collect all lex steps from start to EOF by repeatedly calling lex_step.
/// Useful for batch tokenization; the core contract lives in lex_step alone.
pub fn[T] PrefixLexer::lex_all(
  self : PrefixLexer[T],
  source : String,
  start : Int,
) -> Array[LexStep[T]] {
  let result : Array[LexStep[T]] = []
  let len = source.length()
  let mut pos = clamp_offset(start, len)
  while pos < len {
    let step = (self.lex_step)(source, pos)
    result.push(step)
    match step {
      Produced(_, next_offset~) =>
        pos = if next_offset <= pos {
          next_char_offset(source, pos)
        } else {
          next_offset
        }
      Invalid(at~, width~, ..) =>
        pos = lex_step_recovery_offset(source, pos, at, width)
      Incomplete(..) | Done => break
    }
  }
  result
}

///|
/// Return the next offset after a malformed or invalid step report.
fn lex_step_recovery_offset(
  source : String,
  pos : Int,
  at : Int,
  width : Int,
) -> Int {
  let len = source.length()
  let current = clamp_offset(pos, len)
  let error_start = clamp_offset(if at > current { at } else { current }, len)
  let candidate = if width > 0 {
    clamp_offset(at + width, len)
  } else {
    next_char_offset(source, error_start)
  }
  if candidate > current {
    next_safe_char_boundary(source, candidate)
  } else {
    next_char_offset(source, current)
  }
}

///|
/// Return `pos` unless it lands inside a surrogate pair; in that case snap to
/// the next scalar boundary. This keeps recovered token spans slice-safe even
/// when a lexer reports `Invalid(width=1)` for a non-BMP character.
fn next_safe_char_boundary(source : String, pos : Int) -> Int {
  let len = source.length()
  let current = clamp_offset(pos, len)
  if current <= 0 || current >= len {
    return current
  }
  let prev = source.code_unit_at(current - 1).to_int()
  let here = source.code_unit_at(current).to_int()
  if prev >= 0xD800 && prev <= 0xDBFF && here >= 0xDC00 && here <= 0xDFFF {
    current + 1
  } else {
    current
  }
}
