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

///| Type-erased closure bundle for mode-aware tokenization.
///  Hides M — Grammar only sees T.
///
///  Currently provides full retokenize only. Incremental convergence-based
///  re-lex (partial re-lex with mode propagation) is a future optimization,
///  to be added when profiling shows full retokenize is a bottleneck.
pub struct ModeRelexState[T] {
  /// Tokenize full input. Returns (tokens, starts).
  /// Internally maintains a modes-per-token array for future
  /// incremental re-lex support.
  tokenize : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError
}

///| Erase the mode type M, producing a type-erased closure that Grammar
///  can store without knowing M.
pub fn[T, M] erase_mode_lexer(
  lexer : ModeLexer[T, M],
  eof_token : T,
) -> ModeRelexState[T] {
  // Mutable state captured by closure — modes array maintained for
  // future incremental re-lex (convergence check needs mode at each token).
  let modes_ref : Ref[Array[M]] = Ref::new([])
  let tokenize = fn(source : String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError {
    let (tokens, modes) = tokenize_with_modes(lexer, source, eof_token)
    modes_ref.val = modes
    let starts = build_starts(tokens)
    (tokens, starts)
  }
  { tokenize, }
}
