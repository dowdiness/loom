// Generic incremental token buffer for edit-aware lexing.
// T is the language-specific token type.
//
// Contract: tokenize_fn must always append an EOF sentinel as the last element.
// TokenBuffer::update relies on this when re-lexing a range: the last element
// of tokenize_fn(slice) is skipped during offset-adjustment.

///|
pub struct TokenBuffer[T] {
  priv tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError
  priv retokenize_full : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError
  priv incremental_relex_enabled : Bool
  priv eof_token : T
  priv mut tokens : Array[TokenInfo[T]]
  priv mut starts : Array[Int]
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
  let tokens : Array[TokenInfo[T]] = []
  let mut pos = 0
  while true {
    match step_fn(input, pos) {
      Produced(tok, next_offset~) => {
        tokens.push(tok)
        pos = next_offset
      }
      Invalid(message~, ..) => raise LexError(message)
      Incomplete(expected~, ..) => raise LexError(expected)
      Done => {
        tokens.push(TokenInfo::new(eof_token, 0))
        break
      }
    }
  }
  tokens
}

///|
pub fn[T] TokenBuffer::new(
  source : String,
  tokenize_fn~ : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token~ : T,
) -> TokenBuffer[T] raise LexError {
  let tokens = tokenize_fn(source)
  let starts = build_starts(tokens)
  let retokenize_full : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError = s => {
    let tokens = tokenize_fn(s)
    (tokens, build_starts(tokens))
  }
  {
    tokenize_fn,
    retokenize_full,
    incremental_relex_enabled: true,
    eof_token,
    tokens,
    starts,
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
  let tokens = tokenize_resilient(source, tokenize_fn, eof_token, error_token)
  let starts = build_starts(tokens)
  let retokenize_full : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError = s => {
    let tokens = tokenize_resilient(s, tokenize_fn, eof_token, error_token)
    (tokens, build_starts(tokens))
  }
  {
    tokenize_fn,
    retokenize_full,
    incremental_relex_enabled: true,
    eof_token,
    tokens,
    starts,
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
) -> TokenBuffer[T] {
  let (tokens, starts) = tokenize_from_steps_with_starts(
    source, lexer, eof_token, error_token,
  )
  let step_tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError = s => {
    tokenize_from_steps(s, lexer, eof_token, error_token)
  }
  let retokenize_full : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError = s => {
    tokenize_from_steps_with_starts(s, lexer, eof_token, error_token)
  }
  {
    tokenize_fn: step_tokenize_fn,
    retokenize_full,
    incremental_relex_enabled: false,
    eof_token,
    tokens,
    starts,
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
  let tokens = tokenize_from_steps_strict(source, lexer, eof_token)
  let starts = build_starts(tokens)
  let step_tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError = s => {
    tokenize_from_steps_strict(s, lexer, eof_token)
  }
  let retokenize_full : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError = s => {
    let tokens = tokenize_from_steps_strict(s, lexer, eof_token)
    (tokens, build_starts(tokens))
  }
  {
    tokenize_fn: step_tokenize_fn,
    retokenize_full,
    incremental_relex_enabled: false,
    eof_token,
    tokens,
    starts,
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
pub fn[T] TokenBuffer::update(
  self : TokenBuffer[T],
  edit : Edit,
  new_source : String,
) -> Unit raise LexError {
  let old_tokens = self.tokens
  let old_starts = self.starts
  let old_len = old_tokens.length()
  if not(self.incremental_relex_enabled) || old_len == 0 {
    let (tokens, starts) = (self.retokenize_full)(new_source)
    self.tokens = tokens
    self.starts = starts
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
  let replacement_tokens = self.tokenize_range_impl(
    new_source, left_clamped, right_clamped,
  )
  let new_tokens : Array[TokenInfo[T]] = []
  let new_starts : Array[Int] = []
  // Copy unchanged prefix tokens (their positions don't shift).
  for i = 0; i < left_tok_idx; i = i + 1 {
    new_tokens.push(old_tokens[i])
    new_starts.push(old_starts[i])
  }
  // Insert re-lexed replacement tokens with inline prefix-sum (avoids temp array).
  let mut rep_offset = left_clamped
  for i = 0; i < replacement_tokens.length(); i = i + 1 {
    new_tokens.push(replacement_tokens[i])
    new_starts.push(rep_offset)
    rep_offset = rep_offset + replacement_tokens[i].len
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
  self.source = new_source
  self.version = self.version + 1
}

///|
/// Re-lex a range of source. Tokenize the slice.
/// Skips the trailing EOF that tokenize_fn appends by contract (last element).
/// Returned tokens are position-independent; caller computes starts via
/// build_starts and adds the range offset.
fn[T] TokenBuffer::tokenize_range_impl(
  self : TokenBuffer[T],
  source : String,
  start : Int,
  end : Int,
) -> Array[TokenInfo[T]] raise LexError {
  if start < 0 || end < start || end > source.length() {
    raise LexError("Invalid range")
  }
  let slice = source[start:end]
  let slice_tokens = (self.tokenize_fn)(slice.to_string())
  // tokenize_fn contract: EOF is always last — skip it.
  let result : Array[TokenInfo[T]] = []
  for i = 0; i < slice_tokens.length() - 1; i = i + 1 {
    result.push(slice_tokens[i])
  }
  result
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
/// Lex source resiliently: on LexError, insert an error token and continue.
/// **Deprecated:** Used by `new_resilient`. Prefer `tokenize_from_steps`.
fn[T] tokenize_resilient(
  source : String,
  tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token : T,
  error_token : T,
) -> Array[TokenInfo[T]] {
  tokenize_fn(source) catch {
    LexError(_) => {
      let result : Array[TokenInfo[T]] = []
      let mut pos = 0
      while pos < source.length() {
        let remaining : StringView = source[pos:source.length()]
        let rem = remaining.to_string()
        let prefix_len = longest_lexable_prefix_len(rem, tokenize_fn)
        if prefix_len > 0 {
          let prefix : StringView = rem[0:prefix_len]
          let prefix_tokens = tokenize_fn(prefix.to_string()) catch { _ => [] }
          for i = 0; i < prefix_tokens.length() - 1; i = i + 1 {
            result.push(prefix_tokens[i])
          }
          pos = pos + prefix_len
        } else {
          result.push(TokenInfo::new(error_token, 1))
          pos = pos + 1
        }
      }
      result.push(TokenInfo::new(eof_token, 0))
      result
    }
  }
}

///|
/// Step-based tokenization: call lex_step in a loop, emitting tokens for
/// Produced, error tokens for Invalid/Incomplete, and stopping on Done.
fn[T] tokenize_from_steps(
  source : String,
  lexer : PrefixLexer[T],
  eof_token : T,
  error_token : T,
) -> Array[TokenInfo[T]] {
  let (tokens, _) = tokenize_from_steps_with_starts(
    source, lexer, eof_token, error_token,
  )
  tokens
}

///|
/// Step-based tokenization with explicit starts so late Invalid/Incomplete
/// offsets remain representable even when a step reports an error after a
/// valid prefix.
fn[T] tokenize_from_steps_with_starts(
  source : String,
  lexer : PrefixLexer[T],
  eof_token : T,
  error_token : T,
) -> (Array[TokenInfo[T]], Array[Int]) {
  let result : Array[TokenInfo[T]] = []
  let starts : Array[Int] = []
  let len = source.length()
  let mut pos = 0
  while pos < len {
    let step = (lexer.lex_step)(source, pos)
    match step {
      Produced(token_info, next_offset~) => {
        starts.push(pos)
        // Enforce progress: next_offset must be > pos
        if next_offset <= pos {
          result.push(TokenInfo::new(token_info.token, 1))
          // Defensive: skip one code unit to avoid infinite loop
          pos = pos + 1
        } else {
          // Stored token lengths must match consumed span so starts stay in sync.
          result.push(TokenInfo::new(token_info.token, next_offset - pos))
          pos = next_offset
        }
      }
      Invalid(at~, width~, ..) => {
        let effective_width = if width > 0 { width } else { 1 }
        let error_start = clamp_offset(if at > pos { at } else { pos }, len)
        let raw_end = clamp_offset(at + effective_width, len)
        let end = if raw_end > pos { raw_end } else { pos + 1 }
        starts.push(error_start)
        result.push(TokenInfo::new(error_token, end - error_start))
        // Ensure pos never moves backwards (buggy lexer could report at < pos)
        pos = end
      }
      Incomplete(at~, ..) => {
        let error_start = clamp_offset(if at > pos { at } else { pos }, len)
        starts.push(error_start)
        // Emit error token from at to EOF (or zero-width at EOF)
        if error_start < len {
          result.push(TokenInfo::new(error_token, len - error_start))
        } else {
          result.push(TokenInfo::new(error_token, 0))
        }
        break
      }
      Done => break
    }
  }
  starts.push(len)
  result.push(TokenInfo::new(eof_token, 0))
  (result, starts)
}

///|
/// Step-based tokenization in strict mode: report Invalid/Incomplete as LexError.
fn[T] tokenize_from_steps_strict(
  source : String,
  lexer : PrefixLexer[T],
  eof_token : T,
) -> Array[TokenInfo[T]] raise LexError {
  let result : Array[TokenInfo[T]] = []
  let len = source.length()
  let mut pos = 0
  while pos < len {
    let step = (lexer.lex_step)(source, pos)
    match step {
      Produced(token_info, next_offset~) =>
        if next_offset <= pos {
          result.push(TokenInfo::new(token_info.token, 1))
          pos = pos + 1
        } else {
          result.push(TokenInfo::new(token_info.token, next_offset - pos))
          pos = next_offset
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
  result.push(TokenInfo::new(eof_token, 0))
  result
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
  for len = s.length(); len > 0; len = len - 1 {
    let prefix : StringView = s[0:len]
    let ok = try {
      let _ = tokenize_fn(prefix.to_string())
      true
    } catch {
      LexError(_) => false
    }
    if ok {
      return len
    }
  }
  0
}
