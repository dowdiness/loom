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
/// Type-erased mode-lexer factory. Grammar stores this immutable value.
///
/// `tokenize` is detached and never retains a snapshot. `new_session` creates
/// the mutable state owned by one TokenBuffer.
pub struct ModeRelexFactory[T] {
  tokenize : (String) -> LexResult[T]
  new_session : () -> ModeRelexState[T]
}

///|
/// Per-TokenBuffer mutable mode snapshot for convergence-based re-lexing.
pub struct ModeRelexState[T] {
  tokenize : (String) -> LexResult[T]
  relex_from : (String, Int, Int, Int, Array[Int], Int, Int) -> ModeRelexResult[
    T,
  ]
}

///|
/// Replacement token chunk produced by mode-aware incremental re-lexing.
/// `starts` are absolute source offsets and are parallel to `tokens`.
/// `converged_at_old_token` is the old token index where unchanged suffix
/// reuse can resume.
pub struct ModeRelexResult[T] {
  tokens : Array[TokenInfo[T]]
  starts : Array[Int]
  diagnostics : DiagnosticSet
  converged_at_old_token : Int
}

///|
priv struct ModeRelexInternal[T, M] {
  chunk : ModeRelexResult[T]
  modes : Array[M]
}

///|
priv struct ModeRecoveredStep[M] {
  pos : Int
  mode : M
  consumed_token : Bool
  stop : Bool
}

///|
fn[T, M] push_recovered_mode_step(
  source : String,
  pos : Int,
  mode : M,
  step : LexStep[T],
  next_mode : M,
  error_token : T,
  error_token_from_message : ((String) -> T)?,
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  modes : Array[M],
  diagnostics : DiagnosticSet,
) -> ModeRecoveredStep[M] {
  let len = source.length()
  match step {
    Produced(tok, next_offset~) => {
      starts.push(pos)
      modes.push(mode)
      let end = if next_offset <= pos {
        let end = next_char_offset(source, pos)
        diagnostics.push(
          Diagnostic::lexer_error_at(
            "mode lexer made no progress at position " + pos.to_string(),
            pos,
            end,
            "lex-no-progress",
          ),
        )
        end
      } else {
        next_offset
      }
      tokens.push(TokenInfo::new(tok.token, end - pos))
      { pos: end, mode: next_mode, consumed_token: true, stop: false }
    }
    Invalid(at~, width~, message~) => {
      let error_start = clamp_offset(if at > pos { at } else { pos }, len)
      let end = lex_step_recovery_offset(source, pos, at, width)
      starts.push(error_start)
      modes.push(mode)
      diagnostics.push(
        Diagnostic::lexer_error_at(message, error_start, end, "lex-invalid"),
      )
      tokens.push(
        TokenInfo::new(
          recoverable_error_token(
            error_token, error_token_from_message, message,
          ),
          end - error_start,
        ),
      )
      { pos: end, mode: next_mode, consumed_token: true, stop: false }
    }
    Incomplete(at~, expected~) => {
      let error_start = clamp_offset(if at > pos { at } else { pos }, len)
      starts.push(error_start)
      modes.push(mode)
      diagnostics.push(
        Diagnostic::lexer_error_at(
          "incomplete token; expected " + expected,
          error_start,
          len,
          "lex-incomplete",
        ),
      )
      let width = if error_start < len { len - error_start } else { 0 }
      tokens.push(
        TokenInfo::new(
          recoverable_error_token(
            error_token, error_token_from_message, expected,
          ),
          width,
        ),
      )
      { pos: len, mode: next_mode, consumed_token: true, stop: true }
    }
    Done => { pos, mode, consumed_token: false, stop: true }
  }
}

///|
/// Tokenize a full input with mode tracking and recoverable structured
/// diagnostics. Invalid steps emit an error token, advance by the same
/// Unicode-safe recovery law as PrefixLexer, and continue with the step's
/// returned next mode.
fn[T, M] tokenize_with_modes_recovering(
  lexer : ModeLexer[T, M],
  input : String,
  eof_token : T,
  error_token : T,
  error_token_from_message? : ((String) -> T)? = None,
) -> (LexResult[T], Array[M]) {
  let tokens : Array[TokenInfo[T]] = []
  let starts : Array[Int] = []
  let modes : Array[M] = []
  let diagnostics = DiagnosticSet::empty()
  let mut pos = 0
  let mut mode = lexer.initial_mode
  while true {
    let (step, next_mode) = (lexer.lex_step)(input, pos, mode)
    let recovered = push_recovered_mode_step(
      input, pos, mode, step, next_mode, error_token, error_token_from_message, tokens,
      starts, modes, diagnostics,
    )
    pos = recovered.pos
    mode = recovered.mode
    if recovered.stop {
      break
    }
  }
  starts.push(input.length())
  modes.push(mode)
  tokens.push(TokenInfo::new(eof_token, 0))
  (LexResult::with_starts(tokens, starts, diagnostics~), modes)
}

///|
/// Tokenize recoverably without retaining a mode snapshot.
///
/// Use this for detached work such as isolated block reparsing. Incremental
/// mode snapshots belong to the `ModeRelexState` installed in a TokenBuffer.
pub fn[T, M] tokenize_mode_lexer_recovering(
  lexer : ModeLexer[T, M],
  input : String,
  eof_token : T,
  error_token~ : T,
  error_token_from_message? : ((String) -> T)? = None,
) -> LexResult[T] {
  let (result, _) = tokenize_with_modes_recovering(
    lexer,
    input,
    eof_token,
    error_token,
    error_token_from_message~,
  )
  result
}

///|

///|
fn[M : Eq] mode_relex_converged(
  old_idx : Int,
  old_modes : Array[M],
  old_starts : Array[Int],
  edit_delta : Int,
  mode : M,
  pos : Int,
) -> Bool {
  old_idx < old_modes.length() &&
  old_idx < old_starts.length() &&
  mode == old_modes[old_idx] &&
  pos == old_starts[old_idx] + edit_delta
}

///|
fn[T, M : Eq] mode_relex_recovering(
  lexer : ModeLexer[T, M],
  source : String,
  start_offset : Int,
  start_tok_idx : Int,
  old_token_count : Int,
  old_starts : Array[Int],
  edit_delta : Int,
  new_damage_end : Int,
  old_modes : Array[M],
  error_token : T,
  error_token_from_message : ((String) -> T)?,
) -> ModeRelexInternal[T, M] {
  let mut mode = if start_tok_idx < old_modes.length() {
    old_modes[start_tok_idx]
  } else {
    lexer.initial_mode
  }
  let mut pos = start_offset
  let tokens : Array[TokenInfo[T]] = []
  let starts : Array[Int] = []
  let modes : Array[M] = []
  let diagnostics = DiagnosticSet::empty()
  let mut old_idx = start_tok_idx
  while true {
    let (step, next_mode) = (lexer.lex_step)(source, pos, mode)
    let recovered = push_recovered_mode_step(
      source, pos, mode, step, next_mode, error_token, error_token_from_message,
      tokens, starts, modes, diagnostics,
    )
    pos = recovered.pos
    mode = recovered.mode
    if recovered.consumed_token {
      old_idx = old_idx + 1
    }
    if recovered.stop {
      modes.push(mode)
      old_idx = old_token_count
      break
    }
    if pos > new_damage_end &&
      mode_relex_converged(
        old_idx, old_modes, old_starts, edit_delta, mode, pos,
      ) {
      break
    }
  }
  {
    chunk: { tokens, starts, diagnostics, converged_at_old_token: old_idx },
    modes,
  }
}

///|
fn[T, M : Eq] new_mode_relex_session(
  lexer : ModeLexer[T, M],
  eof_token : T,
  error_token : T,
  error_token_from_message : ((String) -> T)?,
) -> ModeRelexState[T] {
  // Internal modes array — tracks the mode BEFORE each token.
  // Parallel to the token array in one TokenBuffer.
  let modes_ref : Ref[Array[M]] = Ref([])
  let tokenize = fn(source : String) -> LexResult[T] {
    let (result, modes) = tokenize_with_modes_recovering(
      lexer,
      source,
      eof_token,
      error_token,
      error_token_from_message~,
    )
    modes_ref.val = modes
    result
  }
  let relex_from = fn(
    source : String,
    start_offset : Int,
    start_tok_idx : Int,
    old_token_count : Int,
    old_starts : Array[Int],
    edit_delta : Int,
    new_damage_end : Int,
  ) -> ModeRelexResult[T] {
    let old_modes = modes_ref.val
    let internal = mode_relex_recovering(
      lexer, source, start_offset, start_tok_idx, old_token_count, old_starts, edit_delta,
      new_damage_end, old_modes, error_token, error_token_from_message,
    )
    let chunk = internal.chunk
    let old_idx = chunk.converged_at_old_token
    let delete_count = old_idx - start_tok_idx
    let result : Array[M] = Array::new(
      capacity=old_modes.length() - delete_count + internal.modes.length(),
    )
    for i = 0; i < start_tok_idx; i = i + 1 {
      result.push(old_modes[i])
    }
    for i = 0; i < internal.modes.length(); i = i + 1 {
      result.push(internal.modes[i])
    }
    for i = old_idx; i < old_modes.length(); i = i + 1 {
      result.push(old_modes[i])
    }
    modes_ref.val = result
    chunk
  }
  { tokenize, relex_from }
}

///|
/// Erase the mode type M into an immutable factory.
///
/// Each `new_session` call owns a distinct mode snapshot. Grammar may safely
/// share this factory across parser instances and detached lexing operations.
pub fn[T, M : Eq] erase_mode_lexer(
  lexer : ModeLexer[T, M],
  eof_token : T,
  error_token~ : T,
  error_token_from_message? : ((String) -> T)? = None,
) -> ModeRelexFactory[T] {
  let tokenize = fn(source : String) {
    tokenize_mode_lexer_recovering(
      lexer,
      source,
      eof_token,
      error_token~,
      error_token_from_message~,
    )
  }
  let new_session = fn() {
    new_mode_relex_session(
      lexer, eof_token, error_token, error_token_from_message,
    )
  }
  { tokenize, new_session }
}
