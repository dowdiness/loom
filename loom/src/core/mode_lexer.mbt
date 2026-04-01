///|
/// Mode-aware lexer. Each step takes a mode and returns
///  the token plus the next mode.
pub(all) struct ModeLexer[T, M] {
  lex_step : (String, Int, M) -> (LexStep[T], M)
  initial_mode : M
}

///|
/// Tokenize a full input with mode tracking.
///  Returns parallel arrays: tokens and mode-at-each-token.
///  The mode array records the mode BEFORE each token was lexed.
///  Appends EOF sentinel as the last element (matching tokenize_via_steps contract).
pub fn[T, M] tokenize_with_modes(
  lexer : ModeLexer[T, M],
  input : String,
  eof_token : T,
) -> (Array[TokenInfo[T]], Array[M]) raise LexError {
  let tokens : Array[TokenInfo[T]] = []
  let modes : Array[M] = []
  let mut pos = 0
  let mut mode = lexer.initial_mode
  while true {
    let (step, next_mode) = (lexer.lex_step)(input, pos, mode)
    match step {
      Produced(tok, next_offset~) => {
        if next_offset <= pos {
          raise LexError(
            "mode lexer made no progress at position " + pos.to_string(),
          )
        }
        modes.push(mode)
        tokens.push(TokenInfo::new(tok.token, next_offset - pos))
        mode = next_mode
        pos = next_offset
      }
      Invalid(message~, ..) => raise LexError(message)
      Incomplete(expected~, ..) => raise LexError(expected)
      Done => {
        modes.push(mode)
        tokens.push(TokenInfo::new(eof_token, 0))
        break
      }
    }
  }
  (tokens, modes)
}

///|
/// Type-erased closure bundle for mode-aware tokenization.
/// Hides M — Grammar only sees T.
///
///   tokenize — full retokenize (initial parse and fallback)
///   relex_from — convergence-based partial re-lex; also splices the
///     internal modes array, so the caller only deals with tokens.
///     params: (new_source, start_offset, start_tok_idx, old_token_count, old_starts, edit_delta)
///     returns: (replacement_tokens, converged_at_old_tok_idx)
pub struct ModeRelexState[T] {
  tokenize : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError
  relex_from : (String, Int, Int, Int, Array[Int], Int) -> (
    Array[TokenInfo[T]],
    Int,
  ) raise LexError
}

///|
/// Erase the mode type M, producing a type-erased closure that Grammar
/// can store without knowing M.
/// M : Eq is required for convergence checking during incremental re-lex.
pub fn[T, M : Eq] erase_mode_lexer(
  lexer : ModeLexer[T, M],
  eof_token : T,
) -> ModeRelexState[T] {
  // Internal modes array — tracks the mode BEFORE each token.
  // Parallel to the token array in TokenBuffer.
  let modes_ref : Ref[Array[M]] = Ref::new([])
  let tokenize = fn(
    source : String,
  ) -> (Array[TokenInfo[T]], Array[Int]) raise LexError {
    let (tokens, modes) = tokenize_with_modes(lexer, source, eof_token)
    modes_ref.val = modes
    let starts = build_starts(tokens)
    (tokens, starts)
  }
  // Convergence-based partial re-lex.
  // Re-lexes from the mode at start_tok_idx until mode + position converge
  // with the old state. Also splices the modes array internally so the
  // caller (TokenBuffer::update) never needs to touch modes.
  let relex_from = fn(
    source : String,
    start_offset : Int,
    start_tok_idx : Int,
    old_token_count : Int,
    old_starts : Array[Int],
    edit_delta : Int,
  ) -> (Array[TokenInfo[T]], Int) raise LexError {
    let old_modes = modes_ref.val
    let mut mode = if start_tok_idx < old_modes.length() {
      old_modes[start_tok_idx]
    } else {
      lexer.initial_mode
    }
    let mut pos = start_offset
    let new_tokens : Array[TokenInfo[T]] = []
    let new_modes : Array[M] = []
    let mut old_idx = start_tok_idx
    while true {
      let (step, next_mode) = (lexer.lex_step)(source, pos, mode)
      match step {
        Produced(tok, next_offset~) => {
          if next_offset <= pos {
            raise LexError(
              "mode lexer made no progress at position " + pos.to_string(),
            )
          }
          new_tokens.push(TokenInfo::new(tok.token, next_offset - pos))
          new_modes.push(mode)
          mode = next_mode
          pos = next_offset
          old_idx = old_idx + 1
          // Convergence: mode matches AND position aligns with old state.
          // The lexer is deterministic given (text, mode), so all subsequent
          // tokens will be identical — safe to stop and reuse the suffix.
          if old_idx < old_modes.length() &&
            next_mode == old_modes[old_idx] &&
            pos == old_starts[old_idx] + edit_delta {
            break
          }
        }
        Invalid(message~, ..) => raise LexError(message)
        Incomplete(expected~, ..) => raise LexError(expected)
        Done => {
          // Don't emit EOF token — the caller always appends it.
          // DO record the mode so the splice below keeps modes correct.
          new_modes.push(mode)
          old_idx = old_token_count
          break
        }
      }
    }
    // Splice modes array: replace old_modes[start_tok_idx..old_idx) with new_modes.
    let delete_count = old_idx - start_tok_idx
    let result : Array[M] = Array::new(
      capacity=old_modes.length() - delete_count + new_modes.length(),
    )
    for i = 0; i < start_tok_idx; i = i + 1 {
      result.push(old_modes[i])
    }
    for i = 0; i < new_modes.length(); i = i + 1 {
      result.push(new_modes[i])
    }
    for i = old_idx; i < old_modes.length(); i = i + 1 {
      result.push(old_modes[i])
    }
    modes_ref.val = result
    (new_tokens, old_idx)
  }
  { tokenize, relex_from }
}
