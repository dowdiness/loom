// Step-based lexing contract — progress-guaranteed, deterministic recovery.
//
// Core Laws:
// 1. Deterministic: same (source, start) -> same LexStep.
// 2. Progress: Produced.next_offset > start (unless EOF); Invalid advances by max(width, 1).
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
        pos = if next_offset <= pos { pos + 1 } else { next_offset }
      Invalid(at~, width~, ..) => {
        let w = if width > 0 { width } else { 1 }
        let candidate = clamp_offset(at + w, len)
        pos = if candidate > pos { candidate } else { pos + 1 }
      }
      Incomplete(..) | Done => break
    }
  }
  result
}
