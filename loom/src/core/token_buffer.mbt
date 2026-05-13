// Generic incremental token buffer for edit-aware lexing.
// T is the language-specific token type.
//
// Contract: lex/tokenize helpers must always append an EOF sentinel as the
// last element. TokenBuffer::update relies on this when re-lexing a range: the
// last element of the range result is skipped during offset-adjustment.

///|
pub struct TokenBuffer[T] {
  priv retokenize_full : (String) -> LexResult[T] raise LexError
  priv incremental_relex_enabled : Bool
  priv eof_token : T
  priv mut tokens : Array[TokenInfo[T]]
  priv mut starts : Array[Int]
  priv mut diagnostics : DiagnosticSet
  priv mode_relex : ModeRelexState[T]?
  mut source : String
  mut version : Int
}

///|
/// Build a starts array from a token array via prefix sum.
/// Invariant: starts[i+1] == starts[i] + tokens[i].len
pub fn[T] build_starts(tokens : Array[TokenInfo[T]]) -> Array[Int] {
  let starts : Array[Int] = Array::make(tokens.length(), 0)
  let mut offset = 0
  for i = 0; i < tokens.length(); i = i + 1 {
    starts[i] = offset
    offset = offset + tokens[i].len
  }
  starts
}

///|
/// Generic batch tokenization from a step-based lexer.
/// Loops step_fn until Done, collecting TokenInfo results. Appends eof_token.
/// Raises LexError on Invalid or Incomplete steps.
pub fn[T] tokenize_via_steps(
  step_fn : (String, Int) -> LexStep[T],
  input : String,
  eof_token : T,
) -> Array[TokenInfo[T]] raise LexError {
  tokenize_via_steps_result(step_fn, input, eof_token).tokens
}

///|
/// Strict batch tokenization from a step-based lexer with structured result.
/// Invalid/incomplete steps still raise `LexError`; recoverable paths should
/// use `TokenBuffer::new_from_steps`.
pub fn[T] tokenize_via_steps_result(
  step_fn : (String, Int) -> LexStep[T],
  input : String,
  eof_token : T,
) -> LexResult[T] raise LexError {
  let tokens : Array[TokenInfo[T]] = []
  let starts : Array[Int] = []
  let mut pos = 0
  while true {
    match step_fn(input, pos) {
      Produced(tok, next_offset~) => {
        if next_offset <= pos {
          raise LexError(
            "step lexer made no progress at position " + pos.to_string(),
          )
        }
        starts.push(pos)
        tokens.push(TokenInfo::new(tok.token, next_offset - pos))
        pos = next_offset
      }
      Invalid(at~, width~, message~) =>
        raise LexError(
          "step lexer invalid at \{at} (width \{width}): " + message,
        )
      Incomplete(at~, expected~) =>
        raise LexError("step lexer incomplete at \{at}; expected " + expected)
      Done => {
        starts.push(input.length())
        tokens.push(TokenInfo::new(eof_token, 0))
        break
      }
    }
  }
  LexResult::with_starts(tokens, starts, diagnostics=DiagnosticSet::empty())
}

///|
pub fn[T] TokenBuffer::new(
  source : String,
  tokenize_fn~ : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token~ : T,
) -> TokenBuffer[T] raise LexError {
  let tokens = tokenize_fn(source)
  let starts = build_starts(tokens)
  let retokenize_full : (String) -> LexResult[T] raise LexError = s => {
    let tokens = tokenize_fn(s)
    LexResult(tokens)
  }
  {
    retokenize_full,
    incremental_relex_enabled: true,
    eof_token,
    tokens,
    starts,
    diagnostics: DiagnosticSet::empty(),
    mode_relex: None,
    source,
    version: 0,
  }
}

///|
/// Construct a TokenBuffer from a total structured lexer.
pub fn[T] TokenBuffer::new_from_lex(
  source : String,
  lex_fn~ : (String) -> LexResult[T],
  eof_token~ : T,
  incremental_relex_enabled? : Bool = true,
  mode_relex? : ModeRelexState[T]? = None,
) -> TokenBuffer[T] {
  let result = lex_fn(source)
  let retokenize_full : (String) -> LexResult[T] raise LexError = s => {
    lex_fn(s)
  }
  {
    retokenize_full,
    incremental_relex_enabled,
    eof_token,
    tokens: result.tokens,
    starts: result.starts,
    diagnostics: result.diagnostics,
    mode_relex,
    source,
    version: 0,
  }
}

///|
/// Construct a TokenBuffer that never raises LexError.
/// On lex failure, inserts an error token for one code unit and retries from
/// the next position.
#deprecated("Use new_from_steps with a PrefixLexer for explicit error recovery", skip_current_package=true)
pub fn[T] TokenBuffer::new_resilient(
  source : String,
  tokenize_fn~ : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token~ : T,
  error_token~ : T,
) -> TokenBuffer[T] {
  let result = tokenize_resilient_result(
    source, tokenize_fn, eof_token, error_token,
  )
  let retokenize_full : (String) -> LexResult[T] raise LexError = s => {
    tokenize_resilient_result(s, tokenize_fn, eof_token, error_token)
  }
  {
    retokenize_full,
    incremental_relex_enabled: true,
    eof_token,
    tokens: result.tokens,
    starts: result.starts,
    diagnostics: result.diagnostics,
    mode_relex: None,
    source,
    version: 0,
  }
}

///|
/// Compatibility wrapper for packages that still only provide tokenize_fn.
/// Keeps legacy resilient probing behavior without exporting the deprecated
/// constructor at higher layers.
pub fn[T] TokenBuffer::new_resilient_compat(
  source : String,
  tokenize_fn~ : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token~ : T,
  error_token~ : T,
) -> TokenBuffer[T] {
  TokenBuffer::new_resilient(source, tokenize_fn~, eof_token~, error_token~)
}

///|
/// Construct a TokenBuffer from a step-based PrefixLexer.
/// Never raises — errors are emitted as error tokens inline.
/// Uses exact starts from the step stream; updates currently full re-lex so
/// late error offsets remain representable.
pub fn[T] TokenBuffer::new_from_steps(
  source : String,
  lexer : PrefixLexer[T],
  eof_token~ : T,
  error_token~ : T,
  error_token_from_message? : ((String) -> T)? = None,
) -> TokenBuffer[T] {
  let result = tokenize_from_steps_result(
    source, lexer, eof_token, error_token, error_token_from_message~,
  )
  let retokenize_full : (String) -> LexResult[T] raise LexError = s => {
    tokenize_from_steps_result(
      s,
      lexer,
      eof_token,
      error_token,
      error_token_from_message~,
    )
  }
  {
    retokenize_full,
    incremental_relex_enabled: false,
    eof_token,
    tokens: result.tokens,
    starts: result.starts,
    diagnostics: result.diagnostics,
    mode_relex: None,
    source,
    version: 0,
  }
}

///|
/// Construct a TokenBuffer from a step-based PrefixLexer in strict mode.
/// Raises LexError when the step lexer reports Invalid/Incomplete.
/// Updates currently full re-lex to preserve step-lexer offset semantics.
pub fn[T] TokenBuffer::new_from_steps_strict(
  source : String,
  lexer : PrefixLexer[T],
  eof_token~ : T,
) -> TokenBuffer[T] raise LexError {
  let result = tokenize_from_steps_strict_result(source, lexer, eof_token)
  let retokenize_full : (String) -> LexResult[T] raise LexError = s => {
    tokenize_from_steps_strict_result(s, lexer, eof_token)
  }
  {
    retokenize_full,
    incremental_relex_enabled: false,
    eof_token,
    tokens: result.tokens,
    starts: result.starts,
    diagnostics: result.diagnostics,
    mode_relex: None,
    source,
    version: 0,
  }
}

///|
/// Construct a TokenBuffer with mode-aware convergence re-lex support.
/// Uses convergence-based partial re-lex: only re-lexes the damaged region
/// and stops when the lexer mode converges with the old mode array.
pub fn[T] TokenBuffer::new_with_mode_relex(
  source : String,
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  eof_token : T,
  mode_relex : ModeRelexState[T],
) -> TokenBuffer[T] {
  let mode_tokenize = mode_relex.tokenize
  let initial = LexResult::with_starts(
    tokens,
    starts,
    diagnostics=DiagnosticSet::empty(),
  )
  let retokenize_full : (String) -> LexResult[T] raise LexError = s => {
    let (tokens, starts) = mode_tokenize(s)
    LexResult::with_starts(tokens, starts, diagnostics=DiagnosticSet::empty())
  }
  {
    retokenize_full,
    incremental_relex_enabled: true,
    eof_token,
    tokens: initial.tokens,
    starts: initial.starts,
    diagnostics: initial.diagnostics,
    mode_relex: Some(mode_relex),
    source,
    version: 0,
  }
}

///|
/// Return a defensive copy of the token array.
/// Callers cannot desynchronize the internal starts cache by mutating the result.
pub fn[T] TokenBuffer::get_tokens(self : TokenBuffer[T]) -> Array[TokenInfo[T]] {
  self.tokens.copy()
}

///|
/// Return the token at index i (without position information).
pub fn[T] TokenBuffer::get_token(self : TokenBuffer[T], i : Int) -> T {
  self.tokens[i].token
}

///|
/// Return a defensive copy of the token start offsets.
pub fn[T] TokenBuffer::get_starts(self : TokenBuffer[T]) -> Array[Int] {
  self.starts.copy()
}

///|
/// Return lexer diagnostics produced while building or updating this buffer.
pub fn[T] TokenBuffer::get_diagnostics(
  self : TokenBuffer[T],
) -> DiagnosticSet {
  self.diagnostics.copy()
}

///|
/// Return the start code-unit offset of the token at index i.
pub fn[T] TokenBuffer::get_start(self : TokenBuffer[T], i : Int) -> Int {
  self.starts[i]
}

///|
/// Return the end code-unit offset of the token at index i.
pub fn[T] TokenBuffer::get_end(self : TokenBuffer[T], i : Int) -> Int {
  self.starts[i] + self.tokens[i].len
}

///|
/// Return a StringView of the source text for the token at index i.
pub fn[T] TokenBuffer::get_view(self : TokenBuffer[T], i : Int) -> StringView {
  self.source.view(
    start_offset=self.starts[i],
    end_offset=self.starts[i] + self.tokens[i].len,
  )
}

///|
/// Return the number of tokens (including the trailing EOF sentinel).
pub fn[T] TokenBuffer::token_count(self : TokenBuffer[T]) -> Int {
  self.tokens.length()
}

///|
pub fn[T] TokenBuffer::get_source(self : TokenBuffer[T]) -> String {
  self.source
}

///|
pub fn[T] TokenBuffer::get_version(self : TokenBuffer[T]) -> Int {
  self.version
}

///|
pub fn[T : Eq] TokenBuffer::update(
  self : TokenBuffer[T],
  edit : Edit,
  new_source : String,
) -> Unit raise LexError {
  let old_tokens = self.tokens
  let old_starts = self.starts
  let old_len = old_tokens.length()
  if !self.incremental_relex_enabled || old_len == 0 {
    let result = (self.retokenize_full)(new_source)
    self.tokens = result.tokens
    self.starts = result.starts
    self.diagnostics = result.diagnostics
    self.source = new_source
    self.version = self.version + 1
    return
  }
  let eof_index = old_len - 1
  let mut left_tok_idx = find_left_index(old_tokens, old_starts, edit.start)
  let mut right_tok_idx = find_right_index(
    old_tokens,
    old_starts,
    edit.old_end(),
  )
  // Conservative: expand left by one token to catch boundary edits.
  if left_tok_idx > 0 {
    left_tok_idx = left_tok_idx - 1
  }
  // After expand-left, left_tok_idx <= right_tok_idx by construction.
  // If this fires it is a programming error in this function, not bad input.
  if left_tok_idx > right_tok_idx {
    abort("internal: left_tok_idx > right_tok_idx after expand-left")
  }
  if right_tok_idx < eof_index {
    right_tok_idx = right_tok_idx + 1
  }
  // Mode-aware convergence re-lex path.
  // Instead of slicing text and re-lexing without mode context, we re-lex
  // from the correct mode at left_tok_idx and stop when the mode converges
  // with the old mode array. This avoids full retokenize for mode-aware lexers.
  match self.mode_relex {
    Some(state) => {
      let left_clamped = clamp_offset(
        map_start_pos(old_starts[left_tok_idx], edit),
        new_source.length(),
      )
      let delta = edit.delta()
      let (replacement_tokens, converged_right) = (state.relex_from)(
        new_source, left_clamped, left_tok_idx, old_len, old_starts, delta,
      )
      let new_tokens : Array[TokenInfo[T]] = []
      let new_starts : Array[Int] = []
      // Prefix (unchanged)
      for i = 0; i < left_tok_idx; i = i + 1 {
        new_tokens.push(old_tokens[i])
        new_starts.push(old_starts[i])
      }
      // Replacement tokens with inline prefix-sum
      let mut rep_offset = left_clamped
      for i = 0; i < replacement_tokens.length(); i = i + 1 {
        new_tokens.push(replacement_tokens[i])
        new_starts.push(rep_offset)
        rep_offset = rep_offset + replacement_tokens[i].len
      }
      // Suffix (shifted by edit delta)
      let new_len = new_source.length()
      for i = converged_right; i < eof_index; i = i + 1 {
        new_tokens.push(old_tokens[i])
        new_starts.push(clamp_offset(old_starts[i] + delta, new_len))
      }
      // EOF sentinel
      new_tokens.push(TokenInfo::new(self.eof_token, 0))
      new_starts.push(new_len)
      // relex_from already spliced the modes array internally.
      self.tokens = new_tokens
      self.starts = new_starts
      let old_relex_end = if converged_right < old_starts.length() {
        old_starts[converged_right]
      } else {
        self.source.length()
      }
      let shifted_diagnostics = self.diagnostics.after_relex(
        old_starts[left_tok_idx],
        old_relex_end,
        delta,
        failure_context="incremental relex",
      )
      self.diagnostics = shifted_diagnostics
      self.source = new_source
      self.version = self.version + 1
      return
    }
    None => ()
  }
  let mut left_old_offset = old_starts[left_tok_idx]
  if edit.start < left_old_offset {
    left_old_offset = edit.start
  }
  let mut right_old_offset = old_starts[right_tok_idx] +
    old_tokens[right_tok_idx].len
  if edit.old_end() > right_old_offset {
    right_old_offset = edit.old_end()
  }
  let left_new_offset = map_start_pos(left_old_offset, edit)
  let right_new_offset = map_end_pos(right_old_offset, edit)
  let new_len = new_source.length()
  let left_clamped = clamp_offset(left_new_offset, new_len)
  let mut right_clamped = clamp_offset(right_new_offset, new_len)
  if right_clamped < left_clamped {
    right_clamped = left_clamped
  }
  let (
    replacement_tokens,
    replacement_starts,
    replacement_diagnostics,
  ) = self.lex_range_impl(
    new_source, left_clamped, right_clamped,
  )
  let new_tokens : Array[TokenInfo[T]] = []
  let new_starts : Array[Int] = []
  // Copy unchanged prefix tokens (their positions don't shift).
  for i = 0; i < left_tok_idx; i = i + 1 {
    new_tokens.push(old_tokens[i])
    new_starts.push(old_starts[i])
  }
  // Insert re-lexed replacement tokens with lexer-provided starts. Recoverable
  // lexers may report an error after a valid prefix, so starts are not
  // necessarily a prefix sum from left_clamped.
  for i = 0; i < replacement_tokens.length(); i = i + 1 {
    new_tokens.push(replacement_tokens[i])
    new_starts.push(replacement_starts[i])
  }
  // Copy unchanged suffix tokens with shifted positions.
  let delta = edit.delta()
  for i = right_tok_idx + 1; i < eof_index; i = i + 1 {
    let t = old_tokens[i]
    new_tokens.push(t)
    new_starts.push(clamp_offset(old_starts[i] + delta, new_len))
  }
  // EOF sentinel
  new_tokens.push(TokenInfo::new(self.eof_token, 0))
  new_starts.push(new_len)
  self.tokens = new_tokens
  self.starts = new_starts
  let updated_diagnostics = self.diagnostics.after_relex(
    left_old_offset,
    right_old_offset,
    delta,
    failure_context="incremental relex",
  )
  updated_diagnostics.extend(replacement_diagnostics)
  self.diagnostics = updated_diagnostics
  self.source = new_source
  self.version = self.version + 1
}

///|
/// Re-lex a range of source. Lexes the slice and offsets lexer-provided starts
/// into the full source. Skips the trailing EOF that lex helpers append by
/// contract.
fn offset_lex_diagnostics(
  diagnostics : DiagnosticSet,
  offset : Int,
  context : String,
) -> DiagnosticSet {
  let zero_result : Result[TextOffset, DiagnosticBuildError] = try? TextOffset(0)
  match zero_result {
    Ok(zero) =>
      diagnostics.offset_by(offset, zero) catch {
        err =>
          DiagnosticSet::single(
            Diagnostic::lexer_error(
              "failed to offset lexer diagnostics after " +
              context +
              ": " +
              @debug.to_string(err),
            ),
          )
      }
    Err(err) =>
      DiagnosticSet::single(
        Diagnostic::lexer_error(
          "failed to offset lexer diagnostics after " +
          context +
          ": " +
          @debug.to_string(err),
        ),
      )
  }
}

///|
fn[T : Eq] TokenBuffer::lex_range_impl(
  self : TokenBuffer[T],
  source : String,
  start : Int,
  end : Int,
) -> (Array[TokenInfo[T]], Array[Int], DiagnosticSet) raise LexError {
  if start < 0 || end < start || end > source.length() {
    raise LexError("Invalid range")
  }
  let slice = source[start:end]
  let slice_result = (self.retokenize_full)(slice.to_owned())
  // lex result contract: EOF is always last — skip it.
  let result_tokens : Array[TokenInfo[T]] = []
  let result_starts : Array[Int] = []
  if slice_result.tokens.length() == 0 {
    return (
      result_tokens,
      result_starts,
      DiagnosticSet::single(
        Diagnostic::lexer_error("range lexer returned no EOF token"),
      ),
    )
  }
  if slice_result.starts.length() != slice_result.tokens.length() {
    let diagnostics = offset_lex_diagnostics(
      slice_result.diagnostics,
      start,
      "incremental relex range",
    )
    diagnostics.push(
      Diagnostic::lexer_error(
        "range lexer returned non-parallel tokens and starts",
      ),
    )
    return (result_tokens, result_starts, diagnostics)
  }
  let eof_index = slice_result.tokens.length() - 1
  let eof_info = slice_result.tokens[eof_index]
  if eof_info.token != self.eof_token ||
    eof_info.len != 0 ||
    slice_result.starts[eof_index] != slice.length() {
    let diagnostics = offset_lex_diagnostics(
      slice_result.diagnostics,
      start,
      "incremental relex range",
    )
    diagnostics.push(
      Diagnostic::lexer_error(
        "range lexer returned invalid trailing EOF sentinel",
      ),
    )
    return (result_tokens, result_starts, diagnostics)
  }
  for i = 0; i < slice_result.tokens.length() - 1; i = i + 1 {
    result_tokens.push(slice_result.tokens[i])
    result_starts.push(slice_result.starts[i] + start)
  }
  (
    result_tokens,
    result_starts,
    offset_lex_diagnostics(
      slice_result.diagnostics,
      start,
      "incremental relex range",
    ),
  )
}

///|
/// Binary search (lower_bound): first index where end(i) >= pos.
/// end(i) = starts[i] + tokens[i].len
/// Returns len-1 if all tokens end before pos.
fn[T] find_left_index(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  pos : Int,
) -> Int {
  let len = tokens.length()
  if len == 0 {
    return 0
  }
  let mut lo = 0
  let mut hi = len
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if starts[mid] + tokens[mid].len >= pos {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  if lo < len {
    lo
  } else {
    len - 1
  }
}

///|
/// Binary search (upper_bound - 1): last index where starts[i] <= pos.
/// Returns 0 if all tokens start after pos.
fn[T] find_right_index(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  pos : Int,
) -> Int {
  let len = tokens.length()
  if len == 0 {
    return 0
  }
  let mut lo = 0
  let mut hi = len
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if starts[mid] <= pos {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo > 0 {
    lo - 1
  } else {
    0
  }
}

///|
fn map_start_pos(pos : Int, edit : Edit) -> Int {
  if pos <= edit.start {
    pos
  } else if pos >= edit.old_end() {
    pos + edit.delta()
  } else {
    edit.start
  }
}

///|
fn map_end_pos(pos : Int, edit : Edit) -> Int {
  if pos < edit.start {
    pos
  } else if pos >= edit.old_end() {
    pos + edit.delta()
  } else {
    edit.new_end()
  }
}

///|
fn clamp_offset(pos : Int, length : Int) -> Int {
  if pos < 0 {
    0
  } else if pos > length {
    length
  } else {
    pos
  }
}

///|
/// Lex source resiliently with structured diagnostics. On `LexError`, insert
/// an error token for the next Unicode scalar and preserve the lexer message
/// as a diagnostic at that range.
fn[T] tokenize_resilient_result(
  source : String,
  tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token : T,
  error_token : T,
) -> LexResult[T] {
  let full_result : Result[Array[TokenInfo[T]], LexError] = try? tokenize_fn(
    source,
  )
  match full_result {
    Ok(tokens) => LexResult(tokens)
    Err(LexError(first_msg)) => {
      let result : Array[TokenInfo[T]] = []
      let diagnostics = DiagnosticSet::empty()
      let mut pos = 0
      while pos < source.length() {
        let remaining : StringView = source[pos:source.length()]
        let rem = remaining.to_owned()
        let prefix_len = longest_lexable_prefix_len(rem, tokenize_fn)
        if prefix_len > 0 {
          let prefix : StringView = rem[0:prefix_len]
          let prefix_tokens = tokenize_fn(prefix.to_owned()) catch {
            LexError(msg) => {
              diagnostics.push(
                Diagnostic::lexer_error(
                  "resilient lexer prefix replay failed: " + msg,
                ),
              )
              []
            }
          }
          for i = 0; i < prefix_tokens.length() - 1; i = i + 1 {
            result.push(prefix_tokens[i])
          }
          pos = pos + prefix_len
        } else {
          let end = next_char_offset(source, pos)
          let error_result : Result[Array[TokenInfo[T]], LexError] = try? tokenize_fn(
            rem,
          )
          let message = match error_result {
            Ok(_) => first_msg
            Err(LexError(msg)) => msg
          }
          let diagnostic_message = if message == "" { first_msg } else { message }
          diagnostics.push(
            Diagnostic::lexer_error_at(
              diagnostic_message,
              pos,
              end,
              "lex-error",
            ),
          )
          result.push(TokenInfo::new(error_token, end - pos))
          pos = end
        }
      }
      result.push(TokenInfo::new(eof_token, 0))
      LexResult(result, diagnostics~)
    }
  }
}

///|
/// Step-based tokenization with explicit starts so late Invalid/Incomplete
/// offsets remain representable even when a step reports an error after a
/// valid prefix.
fn[T] tokenize_from_steps_result(
  source : String,
  lexer : PrefixLexer[T],
  eof_token : T,
  error_token : T,
  error_token_from_message~ : ((String) -> T)?,
) -> LexResult[T] {
  let result : Array[TokenInfo[T]] = []
  let starts : Array[Int] = []
  let diagnostics = DiagnosticSet::empty()
  let len = source.length()
  let mut pos = 0
  while pos < len {
    let step = (lexer.lex_step)(source, pos)
    match step {
      Produced(token_info, next_offset~) => {
        starts.push(pos)
        // Enforce progress: next_offset must be > pos
        if next_offset <= pos {
          let end = next_char_offset(source, pos)
          diagnostics.push(
            Diagnostic::lexer_error_at(
              "step lexer made no progress at position " + pos.to_string(),
              pos,
              end,
              "lex-no-progress",
            ),
          )
          result.push(TokenInfo::new(token_info.token, end - pos))
          pos = end
        } else {
          // Stored token lengths must match consumed span so starts stay in sync.
          result.push(TokenInfo::new(token_info.token, next_offset - pos))
          pos = next_offset
        }
      }
      Invalid(at~, width~, message~) => {
        let error_start = clamp_offset(if at > pos { at } else { pos }, len)
        let end = lex_step_recovery_offset(source, pos, at, width)
        starts.push(error_start)
        diagnostics.push(
          Diagnostic::lexer_error_at(
            message,
            error_start,
            end,
            "lex-invalid",
          ),
        )
        let token = recoverable_error_token(
          error_token,
          error_token_from_message,
          message,
        )
        result.push(TokenInfo::new(token, end - error_start))
        // Ensure pos never moves backwards (buggy lexer could report at < pos)
        pos = end
      }
      Incomplete(at~, expected~) => {
        let error_start = clamp_offset(if at > pos { at } else { pos }, len)
        starts.push(error_start)
        diagnostics.push(
          Diagnostic::lexer_error_at(
            "incomplete token; expected " + expected,
            error_start,
            len,
            "lex-incomplete",
          ),
        )
        let token = recoverable_error_token(
          error_token,
          error_token_from_message,
          expected,
        )
        // Emit error token from at to EOF (or zero-width at EOF)
        if error_start < len {
          result.push(TokenInfo::new(token, len - error_start))
        } else {
          result.push(TokenInfo::new(token, 0))
        }
        break
      }
      Done => break
    }
  }
  starts.push(len)
  result.push(TokenInfo::new(eof_token, 0))
  LexResult::with_starts(result, starts, diagnostics~)
}

///|
fn[T] tokenize_from_steps_strict_result(
  source : String,
  lexer : PrefixLexer[T],
  eof_token : T,
) -> LexResult[T] raise LexError {
  let result : Array[TokenInfo[T]] = []
  let starts : Array[Int] = []
  let len = source.length()
  let mut pos = 0
  while pos < len {
    let step = (lexer.lex_step)(source, pos)
    match step {
      Produced(token_info, next_offset~) => {
        starts.push(pos)
        if next_offset <= pos {
          raise LexError(
            "step lexer made no progress at position " + pos.to_string(),
          )
        } else {
          result.push(TokenInfo::new(token_info.token, next_offset - pos))
          pos = next_offset
        }
      }
      Invalid(at~, width~, message~) =>
        raise LexError(
          "step lexer invalid at \{at} (width \{width}): " + message,
        )
      Incomplete(at~, expected~) =>
        raise LexError("step lexer incomplete at \{at}; expected " + expected)
      Done => break
    }
  }
  starts.push(len)
  result.push(TokenInfo::new(eof_token, 0))
  LexResult::with_starts(result, starts, diagnostics=DiagnosticSet::empty())
}

///|
fn[T] recoverable_error_token(
  fallback : T,
  from_message : ((String) -> T)?,
  message : String,
) -> T {
  match from_message {
    Some(make_token) => make_token(message)
    None => fallback
  }
}

///|
/// Return the longest prefix length of `s` that tokenizes without LexError.
fn[T] longest_lexable_prefix_len(
  s : String,
  tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError,
) -> Int {
  // Linear descending scan: robust even when tokenize(prefix) success is
  // non-monotone across prefix lengths (e.g. unterminated constructs that
  // become valid only when a later closing delimiter is included).
  let boundaries : Array[Int] = []
  let mut pos = 0
  while pos < s.length() {
    pos = next_char_offset(s, pos)
    boundaries.push(pos)
  }
  for i = boundaries.length(); i > 0; i = i - 1 {
    let len = boundaries[i - 1]
    let prefix : StringView = s[0:len]
    let ok = try {
      let _ = tokenize_fn(prefix.to_owned())
      true
    } catch {
      _ => false
    }
    if ok {
      return len
    }
  }
  0
}
