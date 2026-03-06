// Generic incremental token buffer for edit-aware lexing.
// T is the language-specific token type.
//
// Contract: tokenize_fn must always append an EOF sentinel as the last element.
// TokenBuffer::update relies on this when re-lexing a range: the last element
// of tokenize_fn(slice) is skipped during offset-adjustment.

///|
pub struct TokenBuffer[T] {
  priv tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError
  priv eof_token : T
  mut tokens : Array[TokenInfo[T]]
  mut source : String
  mut version : Int
}

///|
pub fn[T] TokenBuffer::new(
  source : String,
  tokenize_fn~ : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token~ : T,
) -> TokenBuffer[T] raise LexError {
  let tokens = tokenize_fn(source)
  { tokenize_fn, eof_token, tokens, source, version: 0 }
}

///|
/// Construct a TokenBuffer that never raises LexError.
/// On lex failure, inserts an error token for one code unit and retries from
/// the next position.
pub fn[T] TokenBuffer::new_resilient(
  source : String,
  tokenize_fn~ : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token~ : T,
  error_token~ : T,
) -> TokenBuffer[T] {
  let tokens = tokenize_resilient(source, tokenize_fn, eof_token, error_token)
  { tokenize_fn, eof_token, tokens, source, version: 0 }
}

///|
/// Construct a TokenBuffer from a step-based PrefixLexer.
/// Never raises — errors are emitted as error tokens inline.
/// Uses full re-lex on construction; incremental step re-lex is deferred.
pub fn[T] TokenBuffer::new_from_steps(
  source : String,
  lexer : PrefixLexer[T],
  eof_token~ : T,
  error_token~ : T,
) -> TokenBuffer[T] {
  let tokens = tokenize_from_steps(source, lexer, eof_token, error_token)
  // Store a dummy tokenize_fn that aborts — step-based buffers should not
  // fall back to the legacy tokenize path.
  let dummy_tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError = _s => {
    raise LexError("step-based TokenBuffer: legacy tokenize_fn not available")
  }
  { tokenize_fn: dummy_tokenize_fn, eof_token, tokens, source, version: 0 }
}

///|
pub fn[T] TokenBuffer::get_tokens(self : TokenBuffer[T]) -> Array[TokenInfo[T]] {
  self.tokens
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
) -> Array[TokenInfo[T]] raise LexError {
  let old_tokens = self.tokens
  let old_len = old_tokens.length()
  if old_len == 0 {
    let tokens = (self.tokenize_fn)(new_source)
    self.tokens = tokens
    self.source = new_source
    self.version = self.version + 1
    return self.tokens
  }
  let eof_index = old_len - 1
  let mut left_tok_idx = find_left_index(old_tokens, edit.start)
  let mut right_tok_idx = find_right_index(old_tokens, edit.old_end())
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
  let mut left_old_offset = old_tokens[left_tok_idx].start
  if edit.start < left_old_offset {
    left_old_offset = edit.start
  }
  let mut right_old_offset = old_tokens[right_tok_idx].end
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
  for i = 0; i < left_tok_idx; i = i + 1 {
    new_tokens.push(old_tokens[i])
  }
  for token_info in replacement_tokens {
    new_tokens.push(token_info)
  }
  let delta = edit.delta()
  for i = right_tok_idx + 1; i < eof_index; i = i + 1 {
    let t = old_tokens[i]
    new_tokens.push(
      TokenInfo::new(
        t.token,
        clamp_offset(t.start + delta, new_len),
        clamp_offset(t.end + delta, new_len),
      ),
    )
  }
  new_tokens.push(TokenInfo::new(self.eof_token, new_len, new_len))
  self.tokens = new_tokens
  self.source = new_source
  self.version = self.version + 1
  self.tokens
}

///|
/// Re-lex a range of source. Tokenize the slice and offset-adjust results.
/// Skips the trailing EOF that tokenize_fn appends by contract (last element).
fn[T] TokenBuffer::tokenize_range_impl(
  self : TokenBuffer[T],
  source : String,
  start : Int,
  end : Int,
) -> Array[TokenInfo[T]] raise LexError {
  let slice = source[start:end] catch { _ => raise LexError("Invalid range") }
  let slice_tokens = (self.tokenize_fn)(slice.to_string())
  // tokenize_fn contract: EOF is always last — skip it.
  let result : Array[TokenInfo[T]] = []
  for i = 0; i < slice_tokens.length() - 1; i = i + 1 {
    let t = slice_tokens[i]
    result.push(TokenInfo::new(t.token, t.start + start, t.end + start))
  }
  result
}

///|
/// Binary search (lower_bound): first index where tokens[i].end >= pos.
/// Returns len-1 if all tokens end before pos.
fn[T] find_left_index(tokens : Array[TokenInfo[T]], pos : Int) -> Int {
  let len = tokens.length()
  if len == 0 {
    return 0
  }
  let mut lo = 0
  let mut hi = len
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if tokens[mid].end >= pos {
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
/// Binary search (upper_bound - 1): last index where tokens[i].start <= pos.
/// Returns 0 if all tokens start after pos.
fn[T] find_right_index(tokens : Array[TokenInfo[T]], pos : Int) -> Int {
  let len = tokens.length()
  if len == 0 {
    return 0
  }
  let mut lo = 0
  let mut hi = len
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if tokens[mid].start <= pos {
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
        let remaining : StringView = source[pos:source.length()] catch {
            _ => break
          }
        let rem = remaining.to_string()
        let prefix_len = longest_lexable_prefix_len(rem, tokenize_fn)
        if prefix_len > 0 {
          let prefix : StringView = rem[0:prefix_len] catch {
              _ => {
                result.push(TokenInfo::new(error_token, pos, pos + 1))
                pos = pos + 1
                continue
              }
            }
          let prefix_tokens = tokenize_fn(prefix.to_string()) catch { _ => [] }
          for i = 0; i < prefix_tokens.length() - 1; i = i + 1 {
            let t = prefix_tokens[i]
            result.push(TokenInfo::new(t.token, t.start + pos, t.end + pos))
          }
          pos = pos + prefix_len
        } else {
          result.push(TokenInfo::new(error_token, pos, pos + 1))
          pos = pos + 1
        }
      }
      result.push(TokenInfo::new(eof_token, source.length(), source.length()))
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
  let result : Array[TokenInfo[T]] = []
  let len = source.length()
  let mut pos = 0
  while pos < len {
    let step = (lexer.lex_step)(source, pos)
    match step {
      Produced(token_info, next_offset~) => {
        result.push(token_info)
        // Enforce progress: next_offset must be > pos
        if next_offset <= pos {
          // Defensive: skip one code unit to avoid infinite loop
          pos = pos + 1
        } else {
          pos = next_offset
        }
      }
      Invalid(at~, width~, ..) => {
        let effective_width = if width > 0 { width } else { 1 }
        let end = clamp_offset(at + effective_width, len)
        result.push(TokenInfo::new(error_token, at, end))
        pos = end
      }
      Incomplete(at~, ..) => {
        // Emit error token from at to EOF (or zero-width at EOF)
        if at < len {
          result.push(TokenInfo::new(error_token, at, len))
        } else {
          result.push(TokenInfo::new(error_token, len, len))
        }
        break
      }
      Done => break
    }
  }
  result.push(TokenInfo::new(eof_token, len, len))
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
    let prefix : StringView = s[0:len] catch { _ => continue }
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
