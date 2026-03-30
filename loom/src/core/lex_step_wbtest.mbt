// Contract and unit tests for step-based lexing.

// -- Test lexer: produces one char-token per code unit --

///|
fn char_step_lexer(source : String, start : Int) -> LexStep[String] {
  if start >= source.length() {
    return Done
  }
  let end = start + 1
  Produced(TokenInfo::new("char", 1), next_offset=end)
}

// -- Test lexer: reports Invalid for '@' characters --

///|
fn char_with_error_lexer(source : String, start : Int) -> LexStep[String] {
  if start >= source.length() {
    return Done
  }
  if source.code_unit_at(start).to_int() == 64 {
    // '@' = 64
    return Invalid(at=start, width=1, message="bad char @")
  }
  let end = start + 1
  Produced(TokenInfo::new("char", 1), next_offset=end)
}

// -- Test lexer: reports Incomplete for unterminated quote --

///|
fn incomplete_lexer(source : String, start : Int) -> LexStep[String] {
  if start >= source.length() {
    return Done
  }
  // '"' = 34
  if source.code_unit_at(start).to_int() == 34 {
    return Incomplete(at=start, expected="closing quote")
  }
  let end = start + 1
  Produced(TokenInfo::new("char", 1), next_offset=end)
}

// -- Test lexer: Invalid with width=0 (must be corrected to 1) --

///|
fn zero_width_invalid_lexer(source : String, start : Int) -> LexStep[String] {
  if start >= source.length() {
    return Done
  }
  if source.code_unit_at(start).to_int() == 64 {
    return Invalid(at=start, width=0, message="zero-width invalid")
  }
  let end = start + 1
  Produced(TokenInfo::new("char", 1), next_offset=end)
}

// -- Test lexer: Produced with next_offset == start (violates progress) --

///|
fn no_progress_lexer(source : String, start : Int) -> LexStep[String] {
  if start >= source.length() {
    return Done
  }
  Produced(TokenInfo::new("stuck", 0), next_offset=start)
}

// -- Test lexer: reports stale token lengths despite correct next_offset --

///|
fn stale_len_lexer(source : String, start : Int) -> LexStep[String] {
  if start >= source.length() {
    return Done
  }
  let end = start + 1
  Produced(TokenInfo::new("char", 99), next_offset=end)
}

// -- Test lexer: reports an error after a valid prefix in the same step --

///|
fn late_invalid_lexer(source : String, start : Int) -> LexStep[String] {
  if start >= source.length() {
    return Done
  }
  if start == 0 {
    return Invalid(at=2, width=1, message="bad char !")
  }
  let end = start + 1
  Produced(TokenInfo::new("char", 1), next_offset=end)
}

// -- Contract helper: verify lex_step laws for a given source --

///|
/// Verify that a PrefixLexer satisfies the core laws for a given source.
/// Returns (token_count, error_count) on success, or aborts with a message.
fn verify_lex_contract(
  lexer : PrefixLexer[String],
  source : String,
) -> (Int, Int) {
  let len = source.length()
  let mut pos = 0
  let mut token_count = 0
  let mut error_count = 0
  let max_iterations = len + 1 // Safety: at most len+1 steps
  let mut iteration = 0
  while pos < len {
    if iteration >= max_iterations {
      abort("contract violation: exceeded max iterations (infinite loop)")
    }
    let step = (lexer.lex_step)(source, pos)
    // Law 1: Determinism — same input must produce same result
    let step2 = (lexer.lex_step)(source, pos)
    match (step, step2) {
      (Produced(t1, next_offset=n1), Produced(t2, next_offset=n2)) =>
        if !(t1 == t2 && n1 == n2) {
          abort("contract violation: non-deterministic Produced")
        }
      (
        Invalid(at=a1, width=w1, message=m1),
        Invalid(at=a2, width=w2, message=m2),
      ) =>
        if !(a1 == a2 && w1 == w2 && m1 == m2) {
          abort("contract violation: non-deterministic Invalid")
        }
      (Incomplete(at=a1, expected=e1), Incomplete(at=a2, expected=e2)) =>
        if !(a1 == a2 && e1 == e2) {
          abort("contract violation: non-deterministic Incomplete")
        }
      (Done, Done) => ()
      _ => abort("contract violation: non-deterministic step variant")
    }
    match step {
      Produced(_, next_offset~) => {
        // Law 2: Progress
        if next_offset <= pos {
          abort(
            "contract violation: Produced next_offset <= start (\{next_offset} <= \{pos})",
          )
        }
        token_count = token_count + 1
        pos = next_offset
      }
      Invalid(at~, width~, ..) => {
        // Law 3: Stability — at cannot precede the current position
        if at < pos {
          abort("contract violation: Invalid.at (\{at}) < current pos (\{pos})")
        }
        // Law 2: Progress — width >= 1
        if width < 1 {
          abort("contract violation: Invalid.width < 1 (\{width})")
        }
        error_count = error_count + 1
        pos = at + width
      }
      Incomplete(..) => {
        error_count = error_count + 1
        break
      }
      Done => break
    }
    iteration = iteration + 1
  }
  (token_count, error_count)
}

// ============ Contract Tests ============

///|
test "contract: char_step_lexer satisfies all laws" {
  let lexer : PrefixLexer[String] = { lex_step: char_step_lexer }
  let (tokens, errors) = verify_lex_contract(lexer, "hello")
  inspect(tokens, content="5")
  inspect(errors, content="0")
}

///|
test "contract: char_with_error_lexer satisfies all laws" {
  let lexer : PrefixLexer[String] = { lex_step: char_with_error_lexer }
  let (tokens, errors) = verify_lex_contract(lexer, "a@b@c")
  inspect(tokens, content="3")
  inspect(errors, content="2")
}

///|
test "contract: incomplete_lexer satisfies laws" {
  let lexer : PrefixLexer[String] = { lex_step: incomplete_lexer }
  let (tokens, errors) = verify_lex_contract(lexer, "ab\"cd")
  inspect(tokens, content="2")
  inspect(errors, content="1")
}

///|
test "contract: empty source satisfies laws" {
  let lexer : PrefixLexer[String] = { lex_step: char_step_lexer }
  let (tokens, errors) = verify_lex_contract(lexer, "")
  inspect(tokens, content="0")
  inspect(errors, content="0")
}

// ============ Test Helpers ============

///|
fn render_tokens(tokens : Array[TokenInfo[String]]) -> String {
  let mut offset = 0
  tokens
  .map(t => {
    let start = offset
    let end = offset + t.len
    offset = end
    t.token + "@" + start.to_string() + "-" + end.to_string()
  })
  .join(",")
}

///|
fn render_buffer_spans(buf : TokenBuffer[String]) -> String {
  let tokens = buf.get_tokens()
  let rendered : Array[String] = []
  for i = 0; i < tokens.length(); i = i + 1 {
    rendered.push(
      tokens[i].token +
      "@" +
      buf.get_start(i).to_string() +
      "-" +
      buf.get_end(i).to_string(),
    )
  }
  rendered.join(",")
}

// ============ new_from_steps Unit Tests ============

///|
test "new_from_steps: clean input produces normal tokens + EOF" {
  let lexer : PrefixLexer[String] = { lex_step: char_step_lexer }
  let buf = TokenBuffer::new_from_steps(
    "abc",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  inspect(tokens.length(), content="4")
  let rendered = render_tokens(tokens)
  inspect(rendered, content="char@0-1,char@1-2,char@2-3,EOF@3-3")
}

///|
test "new_from_steps: empty source produces only EOF" {
  let lexer : PrefixLexer[String] = { lex_step: char_step_lexer }
  let buf = TokenBuffer::new_from_steps(
    "",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  inspect(tokens.length(), content="1")
  inspect(tokens[0].token, content="EOF")
}

///|
test "new_from_steps: error token for Invalid" {
  let lexer : PrefixLexer[String] = { lex_step: char_with_error_lexer }
  let buf = TokenBuffer::new_from_steps(
    "a@b",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  let rendered = render_tokens(tokens)
  inspect(rendered, content="char@0-1,ERR@1-2,char@2-3,EOF@3-3")
}

///|
test "new_from_steps: multi-error input" {
  let lexer : PrefixLexer[String] = { lex_step: char_with_error_lexer }
  let buf = TokenBuffer::new_from_steps(
    "@a@@b",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  let rendered = render_tokens(tokens)
  inspect(rendered, content="ERR@0-1,char@1-2,ERR@2-3,ERR@3-4,char@4-5,EOF@5-5")
}

///|
test "new_from_steps: Incomplete emits error token to EOF" {
  let lexer : PrefixLexer[String] = { lex_step: incomplete_lexer }
  let buf = TokenBuffer::new_from_steps(
    "ab\"cd",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  let rendered = render_tokens(tokens)
  // 'a', 'b' are normal, then Incomplete at pos 2 emits ERR@2-5
  inspect(rendered, content="char@0-1,char@1-2,ERR@2-5,EOF@5-5")
}

///|
test "new_from_steps: zero-width Invalid corrected to width 1" {
  let lexer : PrefixLexer[String] = { lex_step: zero_width_invalid_lexer }
  let buf = TokenBuffer::new_from_steps(
    "a@b",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  let rendered = render_tokens(tokens)
  // width=0 is corrected to 1, so error token covers @1-2
  inspect(rendered, content="char@0-1,ERR@1-2,char@2-3,EOF@3-3")
}

///|
test "new_from_steps: no-progress Produced is corrected" {
  let lexer : PrefixLexer[String] = { lex_step: no_progress_lexer }
  let buf = TokenBuffer::new_from_steps(
    "ab",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  // Defensive correction: each step advances by 1 despite next_offset=start
  inspect(tokens.length(), content="3")
}

///|
test "new_from_steps: Produced token len is normalized from consumed span" {
  let lexer : PrefixLexer[String] = { lex_step: stale_len_lexer }
  let buf = TokenBuffer::new_from_steps(
    "abc",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let rendered = render_tokens(buf.get_tokens())
  inspect(rendered, content="char@0-1,char@1-2,char@2-3,EOF@3-3")
}

///|
test "new_from_steps_strict: Produced token len is normalized from consumed span" {
  let lexer : PrefixLexer[String] = { lex_step: stale_len_lexer }
  let buf = TokenBuffer::new_from_steps_strict("abc", lexer, eof_token="EOF")
  let rendered = render_tokens(buf.get_tokens())
  inspect(rendered, content="char@0-1,char@1-2,char@2-3,EOF@3-3")
}

///|
test "new_from_steps: late Invalid preserves exact error offset" {
  let lexer : PrefixLexer[String] = { lex_step: late_invalid_lexer }
  let buf = TokenBuffer::new_from_steps(
    "ab!c",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let rendered = render_buffer_spans(buf)
  inspect(rendered, content="ERR@2-3,char@3-4,EOF@4-4")
}

///|
test "new_from_steps: update preserves late Invalid offsets" {
  let lexer : PrefixLexer[String] = { lex_step: late_invalid_lexer }
  let buf = TokenBuffer::new_from_steps(
    "ab!c",
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  buf.update(Edit::replace(0, 2, 2), "xy!z")
  let rendered = render_buffer_spans(buf)
  inspect(rendered, content="ERR@2-3,char@3-4,EOF@4-4")
}

///|
test "lex_all: collects all steps" {
  let lexer : PrefixLexer[String] = { lex_step: char_with_error_lexer }
  let steps = lexer.lex_all("a@b", 0)
  // 3 steps: Produced(char), Invalid(@), Produced(char) — loop exits at EOF
  inspect(steps.length(), content="3")
}

// ============ QuickCheck Property Tests ============

///|
fn next_seed(seed : Int) -> Int {
  let a = 1103515245
  let c = 12345
  let m = 2147483647
  (seed * a + c) % m
}

///|
/// Build a random source string with occasional '@' chars for error testing.
fn build_lex_source(seed : Int) -> String {
  let pool = ["a", "b", "c", "1", "2", " ", "@", "x", "y", "(", ")"]
  let buf = StringBuilder::new()
  let count = seed.abs() % 30 + 1
  let mut s = seed
  let pool_len = pool.length()
  for _i = 0; _i < count; _i = _i + 1 {
    s = next_seed(s)
    let idx = s.abs() % pool_len
    buf.write_string(pool[idx])
  }
  buf.to_string()
}

///|
/// Property: new_from_steps always terminates and produces tokens ending with EOF.
fn prop_step_terminates_with_eof(seed : Int) -> Bool {
  let source = build_lex_source(seed)
  let lexer : PrefixLexer[String] = { lex_step: char_with_error_lexer }
  let buf = TokenBuffer::new_from_steps(
    source,
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  if tokens.length() == 0 {
    return false
  }
  tokens[tokens.length() - 1].token == "EOF"
}

///|
/// Property: step-based tokens cover the entire source with no gaps or overlaps.
fn prop_step_tokens_cover_source(seed : Int) -> Bool {
  let source = build_lex_source(seed)
  let lexer : PrefixLexer[String] = { lex_step: char_with_error_lexer }
  let buf = TokenBuffer::new_from_steps(
    source,
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  let len = source.length()
  // Check all non-EOF tokens cover [0, len) contiguously via prefix sum
  let mut offset = 0
  for i = 0; i < tokens.length() - 1; i = i + 1 {
    let t = tokens[i]
    if t.len <= 0 {
      return false
    }
    offset = offset + t.len
  }
  // Total length of non-EOF tokens should equal source length
  offset == len
}

///|
/// Property: step-based result matches char-by-char full lex for clean inputs.
fn prop_step_matches_full_for_clean(seed : Int) -> Bool {
  let source = build_lex_source(seed.abs())
  // Remove '@' to get a clean input
  let buf = StringBuilder::new()
  for i = 0; i < source.length(); i = i + 1 {
    let cu = source.code_unit_at(i).to_int()
    if cu != 64 {
      buf.write_char(cu.unsafe_to_char())
    }
  }
  let clean = buf.to_string()
  if clean.length() == 0 {
    return true
  }
  let lexer : PrefixLexer[String] = { lex_step: char_step_lexer }
  let buf = TokenBuffer::new_from_steps(
    clean,
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  // Should have exactly clean.length() char tokens + 1 EOF
  tokens.length() == clean.length() + 1
}

///|
/// Property: determinism — building from steps twice gives same result.
fn prop_step_deterministic(seed : Int) -> Bool {
  let source = build_lex_source(seed)
  let lexer : PrefixLexer[String] = { lex_step: char_with_error_lexer }
  let buf1 = TokenBuffer::new_from_steps(
    source,
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let buf2 = TokenBuffer::new_from_steps(
    source,
    lexer,
    eof_token="EOF",
    error_token="ERR",
  )
  let t1 = buf1.get_tokens()
  let t2 = buf2.get_tokens()
  if t1.length() != t2.length() {
    return false
  }
  for i = 0; i < t1.length(); i = i + 1 {
    if !(t1[i] == t2[i]) {
      return false
    }
  }
  true
}

///|
test "property: step-based tokenization always terminates with EOF" {
  @qc.quick_check_fn(prop_step_terminates_with_eof)
}

///|
test "property: step-based tokens cover source contiguously" {
  @qc.quick_check_fn(prop_step_tokens_cover_source)
}

///|
test "property: step-based matches full lex for clean inputs" {
  @qc.quick_check_fn(prop_step_matches_full_for_clean)
}

///|
test "property: step-based tokenization is deterministic" {
  @qc.quick_check_fn(prop_step_deterministic)
}
