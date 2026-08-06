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
/// Read-only access to the old token-start offsets for one re-lex invocation.
///
/// A callback may retain this value, but cannot recover or mutate the backing
/// array. `start_at` aborts when `index` is outside `[0, length())` because an
/// invalid token index is a caller defect and continuing would corrupt re-lex.
pub struct OldTokenStarts(Array[Int])

///|
fn OldTokenStarts::from_owned(starts : Array[Int]) -> OldTokenStarts {
  OldTokenStarts(starts)
}

///|
/// Construct a detached read-only offset capability.
/// The input array is copied so later caller mutation cannot affect it.
pub fn OldTokenStarts::new(starts : Array[Int]) -> OldTokenStarts {
  OldTokenStarts(starts.copy())
}

///|
#inline
pub fn OldTokenStarts::length(self : OldTokenStarts) -> Int {
  self.0.length()
}

///|
#inline
pub fn OldTokenStarts::start_at(self : OldTokenStarts, index : Int) -> Int {
  self.0[index]
}

///|
/// Type-erased mode-lexer factory. Grammar stores this immutable value.
/// Each operation creates or initializes a distinct session.
pub struct ModeRelexFactory[T] {
  priv new_session_fn : (SourceId) -> ModeRelexState[T]
  priv initialize_session : ((SourceId, String) -> (
    ModeRelexState[T],
    LexResult[T],
  ))?
}

///|
/// Per-TokenBuffer mutable mode snapshot for convergence-based re-lexing.
pub struct ModeRelexState[T] {
  priv tokenize_fn : (String) -> LexResult[T]
  priv relex_from_fn : (String, Int, Int, Int, OldTokenStarts, Int, Int) -> ModeRelexResult[
    T,
  ] raise LexResultError
}

///|
pub fn[T] ModeRelexState::new(
  tokenize~ : (String) -> LexResult[T],
  relex_from~ : (String, Int, Int, Int, OldTokenStarts, Int, Int) -> ModeRelexResult[
    T,
  ] raise LexResultError,
) -> ModeRelexState[T] {
  { tokenize_fn: tokenize, relex_from_fn: relex_from }
}

///|
pub fn[T] ModeRelexState::tokenize(
  self : ModeRelexState[T],
  source : String,
) -> LexResult[T] {
  (self.tokenize_fn)(source)
}

///|
#inline
pub fn[T] ModeRelexState::relex_from(
  self : ModeRelexState[T],
  source : String,
  start_offset : Int,
  start_tok_idx : Int,
  old_token_count : Int,
  old_starts : OldTokenStarts,
  edit_delta : Int,
  new_damage_end : Int,
) -> ModeRelexResult[T] raise LexResultError {
  (self.relex_from_fn)(
    source, start_offset, start_tok_idx, old_token_count, old_starts, edit_delta,
    new_damage_end,
  )
}

///|
pub fn[T] ModeRelexFactory::new(
  new_session~ : (SourceId) -> ModeRelexState[T],
) -> ModeRelexFactory[T] {
  { new_session_fn: new_session, initialize_session: None }
}

///|
pub fn[T] ModeRelexFactory::new_session(
  self : ModeRelexFactory[T],
  source_id : SourceId,
) -> ModeRelexState[T] {
  (self.new_session_fn)(source_id)
}

///|
pub fn[T] ModeRelexFactory::tokenize(
  self : ModeRelexFactory[T],
  source_id : SourceId,
  source : String,
) -> LexResult[T] {
  self.new_session(source_id).tokenize(source)
}

///|
/// Create and initialize one session when the factory owns canonical full
/// tokenization. Legacy factories return `None` so callers preserve their
/// separate grammar-lexer path and any diagnostics it adds.
fn[T] ModeRelexFactory::new_session_with_initial(
  self : ModeRelexFactory[T],
  source_id : SourceId,
  source : String,
) -> (ModeRelexState[T], LexResult[T])? {
  match self.initialize_session {
    Some(initialize) => Some(initialize(source_id, source))
    None => None
  }
}

///|
/// Replacement token chunk produced by mode-aware incremental re-lexing.
/// `starts` are absolute source offsets and are parallel to `tokens`.
/// `converged_at_old_token` is the old token index where unchanged suffix
/// reuse can resume.
pub struct ModeRelexResult[T] {
  priv tokens : Array[TokenInfo[T]]
  priv starts : Array[Int]
  priv diagnostics : DiagnosticSet
  priv converged_at_old_token : Int
}

///|
fn[T] validate_mode_relex_result(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  converged_at_old_token : Int,
) -> Unit raise LexResultError {
  guard tokens.length() == starts.length() else {
    raise TokenStartCountMismatch(tokens.length(), starts.length())
  }
  guard converged_at_old_token >= 0 else {
    raise NegativeConvergence(converged_at_old_token)
  }
  for i in 0..<tokens.length() {
    guard tokens[i].len >= 0 else {
      raise NegativeTokenLength(i, tokens[i].len)
    }
    guard starts[i] >= 0 else { raise NegativeStart(i, starts[i]) }
    if i > 0 {
      guard starts[i] >= starts[i - 1] else {
        raise DecreasingStart(i, starts[i - 1], starts[i])
      }
      let previous_end = starts[i - 1] + tokens[i - 1].len
      guard starts[i] >= previous_end else {
        raise OverlappingToken(i, previous_end, starts[i])
      }
    }
  }
}

///|
/// Construct an alias-safe replacement chunk from a custom mode relexer.
pub fn[T] ModeRelexResult::new(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics : DiagnosticSet,
  converged_at_old_token~ : Int,
) -> ModeRelexResult[T] raise LexResultError {
  let tokens = tokens.copy()
  let starts = starts.copy()
  let diagnostics = diagnostics.copy()
  validate_mode_relex_result(tokens, starts, converged_at_old_token)
  { tokens, starts, diagnostics, converged_at_old_token }
}

///|
#inline
fn[T] mode_relex_result_owned(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics : DiagnosticSet,
  converged_at_old_token : Int,
) -> ModeRelexResult[T] {
  { tokens, starts, diagnostics, converged_at_old_token }
}

///|
pub fn[T] ModeRelexResult::tokens(
  self : ModeRelexResult[T],
) -> Array[TokenInfo[T]] {
  self.tokens.copy()
}

///|
pub fn[T] ModeRelexResult::starts(self : ModeRelexResult[T]) -> Array[Int] {
  self.starts.copy()
}

///|
pub fn[T] ModeRelexResult::diagnostics(
  self : ModeRelexResult[T],
) -> DiagnosticSet {
  self.diagnostics.copy()
}

///|
pub fn[T] ModeRelexResult::converged_at_old_token(
  self : ModeRelexResult[T],
) -> Int {
  self.converged_at_old_token
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
  source_id : SourceId,
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
          lexer_diagnostic_at(
            source_id,
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
        lexer_diagnostic_at(source_id, message, error_start, end, "lex-invalid"),
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
        lexer_diagnostic_at(
          source_id,
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
  source_id : SourceId,
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
      source_id, input, pos, mode, step, next_mode, error_token, error_token_from_message,
      tokens, starts, modes, diagnostics,
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
  source_id : SourceId,
  lexer : ModeLexer[T, M],
  input : String,
  eof_token : T,
  error_token~ : T,
  error_token_from_message? : ((String) -> T)? = None,
) -> LexResult[T] {
  let (result, _) = tokenize_with_modes_recovering(
    source_id,
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
#inline
fn[M : Eq] mode_relex_converged(
  old_idx : Int,
  old_modes : Array[M],
  old_starts : OldTokenStarts,
  edit_delta : Int,
  mode : M,
  pos : Int,
) -> Bool {
  old_idx < old_modes.length() &&
  old_idx < old_starts.length() &&
  mode == old_modes[old_idx] &&
  pos == old_starts.start_at(old_idx) + edit_delta
}

///|
fn[T, M : Eq] mode_relex_recovering(
  source_id : SourceId,
  lexer : ModeLexer[T, M],
  source : String,
  start_offset : Int,
  start_tok_idx : Int,
  old_token_count : Int,
  old_starts : OldTokenStarts,
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
      source_id, source, pos, mode, step, next_mode, error_token, error_token_from_message,
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
    chunk: mode_relex_result_owned(tokens, starts, diagnostics, old_idx),
    modes,
  }
}

///|
fn[T, M : Eq] new_mode_relex_session(
  source_id : SourceId,
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
      source_id,
      lexer,
      source,
      eof_token,
      error_token,
      error_token_from_message~,
    )
    modes_ref.val = modes
    result
  }
  let relex_from : (String, Int, Int, Int, OldTokenStarts, Int, Int) -> ModeRelexResult[
    T,
  ] raise LexResultError = fn(
    source : String,
    start_offset : Int,
    start_tok_idx : Int,
    old_token_count : Int,
    old_starts : OldTokenStarts,
    edit_delta : Int,
    new_damage_end : Int,
  ) -> ModeRelexResult[T] {
    let old_modes = modes_ref.val
    let internal = mode_relex_recovering(
      source_id, lexer, source, start_offset, start_tok_idx, old_token_count, old_starts,
      edit_delta, new_damage_end, old_modes, error_token, error_token_from_message,
    )
    let chunk = internal.chunk
    let old_idx = chunk.converged_at_old_token
    let delete_count = old_idx - start_tok_idx
    // This session exclusively owns old_modes. Equal-cardinality replacement
    // preserves every suffix index, so only the converged damage slice changes.
    if internal.modes.length() == delete_count {
      for i = 0; i < internal.modes.length(); i = i + 1 {
        old_modes[start_tok_idx + i] = internal.modes[i]
      }
    } else {
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
    }
    chunk
  }
  ModeRelexState::new(tokenize~, relex_from~)
}

///|
/// Erase the mode type M into an immutable factory using a fresh lexer shell
/// for each detached tokenization and parser session.
///
/// Use this overload when `ModeLexer::lex_step` closes over mutable derived
/// state such as a source-local index. The builder is called once by each
/// `tokenize` operation and once by each `new_session` call. Grammar may safely
/// share the returned factory without sharing those lexer-owned resources.
/// When installed on a Grammar, its full lexer must be semantically identical
/// to this factory's `tokenize`; parser initialization uses the session result
/// directly so it does not build the same derived state twice.
pub fn[T, M : Eq] erase_mode_lexer_factory(
  new_lexer : () -> ModeLexer[T, M],
  eof_token : T,
  error_token~ : T,
  error_token_from_message? : ((String) -> T)? = None,
) -> ModeRelexFactory[T] {
  let new_session = fn(source_id : SourceId) {
    let lexer = new_lexer()
    new_mode_relex_session(
      source_id, lexer, eof_token, error_token, error_token_from_message,
    )
  }
  let initialize_session = fn(source_id : SourceId, source : String) {
    let state = new_session(source_id)
    let initial = state.tokenize(source)
    (state, initial)
  }
  { new_session_fn: new_session, initialize_session: Some(initialize_session) }
}

///|
/// Erase the mode type M into an immutable factory.
///
/// Each `new_session` call owns a distinct mode snapshot. Grammar may safely
/// share this factory when the supplied lexer is itself immutable. Use
/// `erase_mode_lexer_factory` when the lexer closes over mutable resources that
/// must be owned by one detached tokenization or parser session.
pub fn[T, M : Eq] erase_mode_lexer(
  lexer : ModeLexer[T, M],
  eof_token : T,
  error_token~ : T,
  error_token_from_message? : ((String) -> T)? = None,
) -> ModeRelexFactory[T] {
  erase_mode_lexer_factory(
    () => lexer,
    eof_token,
    error_token~,
    error_token_from_message~,
  )
}
