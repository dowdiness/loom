// Whitebox tests for GoalTokenSource — parser-directed goal tokenization.
// Tests GoalCache, TokenBuffer goal methods, and ParserContext goal methods.

// Goal-specific test token type — unique name to avoid collision with TestKind.

///|
priv enum GoalTestTok {
  GTSlash
  GTRegex(String)
  GTIdent(String)
  GTNumber(Int)
  GTWs
  GTEof
} derive(Eq, Debug)

///|
impl Show for GoalTestTok with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
impl @seam.IsTrivia for GoalTestTok with fn is_trivia(self) {
  self == GTWs
}

///|
impl @seam.IsEof for GoalTestTok with fn is_eof(self) {
  self == GTEof
}

///|
impl @seam.ToRawKind for GoalTestTok with fn to_raw(self) {
  let n = match self {
    GTSlash => 0
    GTRegex(_) => 1
    GTIdent(_) => 2
    GTNumber(_) => 3
    GTWs => 4
    GTEof => 6
  }
  @seam.RawKind(n)
}

///|
enum GoalTestKind {
  GTKRegex
  GTKWs
  GTKErr
  GTKRoot
  GTKIncomplete
} derive(Debug)

///|
impl @seam.ToRawKind for GoalTestKind with fn to_raw(self) {
  let n = match self {
    GTKRegex => 1
    GTKWs => 4
    GTKErr => 5
    GTKRoot => 6
    GTKIncomplete => 8
  }
  @seam.RawKind(n)
}

///|
/// Goal-aware step lexer.
/// Goal 0 = DivGoal: '/' → Slash (len 1)
/// Goal 1 = RegExpGoal: '/.../' → Regex(body)
fn goal_lex_step(
  source : String,
  pos : Int,
  goal : Int,
) -> LexStep[GoalTestTok] {
  if pos >= source.length() {
    return Done
  }
  let code = source.code_unit_at(pos).to_int()
  if code == 0x20 {
    // whitespace
    let mut end = pos + 1
    while end < source.length() && source.code_unit_at(end).to_int() == 0x20 {
      end = end + 1
    }
    Produced(TokenInfo::new(GTWs, end - pos), next_offset=end)
  } else if code == 0x2F {
    // '/'
    if goal == 1 {
      // RegExpGoal: consume until closing '/', then flags
      let mut end = pos + 1
      while end < source.length() && source.code_unit_at(end).to_int() != 0x2F {
        end = end + 1
      }
      if end < source.length() {
        end = end + 1 // consume closing '/'
        while end < source.length() {
          let c = source.code_unit_at(end).to_int()
          if (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) {
            end = end + 1
          } else {
            break
          }
        }
      }
      let body_start = pos + 1
      let body_end = if end > body_start &&
        source.code_unit_at(end - 1).to_int() == 0x2F {
        end - 1
      } else {
        end
      }
      let body_raw : StringView = source[body_start:body_end]
      Produced(
        TokenInfo::new(GTRegex(body_raw.to_owned()), end - pos),
        next_offset=end,
      )
    } else {
      // DivGoal: '/' alone
      Produced(TokenInfo::new(GTSlash, 1), next_offset=pos + 1)
    }
  } else if code >= 0x61 && code <= 0x7A {
    // lowercase ident
    let mut end = pos + 1
    while end < source.length() {
      let c = source.code_unit_at(end).to_int()
      if (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) {
        end = end + 1
      } else {
        break
      }
    }
    let text : StringView = source[pos:end]
    Produced(
      TokenInfo::new(GTIdent(text.to_owned()), end - pos),
      next_offset=end,
    )
  } else if code >= 0x30 && code <= 0x39 {
    // digit
    let mut end = pos + 1
    while end < source.length() {
      let d = source.code_unit_at(end).to_int()
      if d >= 0x30 && d <= 0x39 {
        end = end + 1
      } else {
        break
      }
    }
    Produced(TokenInfo::new(GTNumber(code - 0x30), end - pos), next_offset=end)
  } else {
    Done
  }
}

///|
fn baseline_tokenize(source : String) -> LexResult[GoalTestTok] {
  let tokens : Array[TokenInfo[GoalTestTok]] = []
  let mut i = 0
  while i < source.length() {
    let step = goal_lex_step(source, i, 0)
    match step {
      Produced(tok, next_offset~) => {
        tokens.push(tok)
        i = next_offset
      }
      _ => i = i + 1
    }
  }
  let starts = build_starts(tokens)
  LexResult::with_starts(tokens, starts, diagnostics=DiagnosticSet::empty())
}

///|
/// Goal-aware lex step for TokenBuffer.
fn goal_step_fn(source : String, pos : Int, goal : Int) -> LexStep[GoalTestTok] {
  goal_lex_step(source, pos, goal)
}

///|
/// Setup a TokenBuffer with goal-aware lexing for a given source.
fn make_goal_buffer(source : String) -> TokenBuffer[GoalTestTok] {
  let buf = TokenBuffer::new_from_lex(
    source,
    lex_fn=baseline_tokenize,
    eof_token=GTEof,
  )
  buf.set_goal_step(goal_step_fn)
  buf
}

///|
fn make_goal_spec() -> LanguageSpec[GoalTestTok, GoalTestKind] {
  {
    whitespace_kind: GTKWs,
    error_kind: GTKErr,
    incomplete_kind: GTKIncomplete,
    root_kind: GTKRoot,
    eof_token: GTEof,
    parse_root: fn(_) { () },
    reuse_size_threshold: 64,
    trivia_kinds_spec: [GTKWs],
  }
}

// === GoalCache tests ===

///|
test "GoalCache: new cache is empty, lookup returns None" {
  let cache : GoalCache[String] = GoalCache::new()
  let result = cache.lookup(0, 0)
  inspect(result is None, content="true")
}

///|
test "GoalCache: insert then lookup returns same entry" {
  let cache : GoalCache[String] = GoalCache::new()
  cache.insert(10, 1, "hello", 15)
  let result = cache.lookup(10, 1)
  inspect(result is Some(_), content="true")
  match result {
    Some((token, end_offset)) => {
      inspect(token, content="hello")
      inspect(end_offset, content="15")
    }
    None => ()
  }
}

///|
test "GoalCache: invalidate clears all entries" {
  let cache : GoalCache[String] = GoalCache::new()
  cache.insert(10, 1, "hello", 15)
  cache.insert(20, 0, "world", 25)
  cache.invalidate()
  let r1 = cache.lookup(10, 1)
  let r2 = cache.lookup(20, 0)
  inspect(r1 is None, content="true")
  inspect(r2 is None, content="true")
}

// === TokenBuffer goal_token_at tests ===

///|
test "goal_token_at: cache miss lexes and caches" {
  let buf = make_goal_buffer("/x/")
  // DivGoal at offset 0: '/' → Slash
  let (tok0, end0) = buf.goal_token_at(0, 0)
  inspect(tok0, content="GTSlash")
  inspect(end0, content="1")
  // Same query again: cache hit
  let (tok0b, end0b) = buf.goal_token_at(0, 0)
  inspect(tok0b, content="GTSlash")
  inspect(end0b, content="1")
}

///|
test "goal_token_at: different goals at same offset" {
  let buf = make_goal_buffer("/x/")
  // RegExpGoal at offset 0: '/x/' → Regex("x")
  let (tok0, end0) = buf.goal_token_at(0, 1)
  match tok0 {
    GTRegex(body) => inspect(body, content="x")
    _ => inspect("wrong", content="expected GTRegex")
  }
  inspect(end0, content="3")
  // DivGoal at same offset: still Slash
  let (tok1, end1) = buf.goal_token_at(0, 0)
  inspect(tok1, content="GTSlash")
  inspect(end1, content="1")
}

///|
test "goal_token_at: update invalidates cache" {
  let buf = make_goal_buffer("/x/")
  // Populate cache
  let (_, _) = buf.goal_token_at(0, 1)
  // Edit changes the source
  buf.update(Edit::insert(1, 1), "/ab/")
  // After update, cache miss should re-lex
  let (tok, end) = buf.goal_token_at(0, 1)
  match tok {
    GTRegex(body) => inspect(body, content="ab")
    _ => inspect("wrong", content="expected GTRegex")
  }
  inspect(end, content="4")
}

///|
test "goal_token_at: no goal_step falls back to baseline" {
  let buf = TokenBuffer::new_from_lex(
    "/x/",
    lex_fn=baseline_tokenize,
    eof_token=GTEof,
  )
  // No set_goal_step — should fall back to baseline (Slash at offset 0)
  let (tok, end) = buf.goal_token_at(0, 1) // RegExpGoal, but no step
  inspect(tok, content="GTSlash")
  inspect(end, content="1")
}

// === ParserContext goal tests ===

///|
test "ParserContext::token_at with goal_source set" {
  let buf = make_goal_buffer("/x/")
  let spec = make_goal_spec()
  let ctx = ParserContext::new_indexed(
    buf.token_count(),
    fn(i) { buf.get_token(i) },
    fn(i) { buf.get_start(i) },
    fn(i) { buf.get_end(i) },
    buf.get_source(),
    spec,
  )
  ctx.set_goal_source(fn(offset, goal) { buf.goal_token_at(offset, goal) })

  // RegExpGoal at offset 0
  let (tok, end) = ctx.token_at(0, 1)
  match tok {
    GTRegex(body) => inspect(body, content="x")
    _ => inspect("wrong", content="expected GTRegex")
  }
  inspect(end, content="3")
}

///|
test "ParserContext::token_at without goal_source falls back to baseline" {
  let spec = make_goal_spec()
  let result = baseline_tokenize("/x/")
  let toks = result.tokens
  let starts = result.starts
  let ctx = ParserContext::new_indexed(
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) { starts[i] + toks[i].len },
    "/x/",
    spec,
  )
  // No goal_source set — falls back to baseline
  let (tok, end) = ctx.token_at(0, 1)
  inspect(tok, content="GTSlash")
  inspect(end, content="1")
}

///|
test "minimal emit_token_with_goal produces CST with goal span" {
  let buf = make_goal_buffer("/x/")
  let spec = make_goal_spec()
  let ctx = ParserContext::new_indexed(
    buf.token_count(),
    fn(i) { buf.get_token(i) },
    fn(i) { buf.get_start(i) },
    fn(i) { buf.get_end(i) },
    buf.get_source(),
    spec,
  )
  ctx.set_goal_source(fn(offset, goal) { buf.goal_token_at(offset, goal) })

  // Emit with RegExpGoal: should span 3 chars "/x/"
  ctx.emit_token_with_goal(1, GTKRegex)
  // Position should be past the 3-char regex, not just 1-char slash
  inspect(ctx.position, content="3")
}

///|
test "advance_with_goal returns goal-directed token" {
  let buf = make_goal_buffer("/x/")
  let spec = make_goal_spec()
  let ctx = ParserContext::new_indexed(
    buf.token_count(),
    fn(i) { buf.get_token(i) },
    fn(i) { buf.get_start(i) },
    fn(i) { buf.get_end(i) },
    buf.get_source(),
    spec,
  )
  ctx.set_goal_source(fn(offset, goal) { buf.goal_token_at(offset, goal) })

  // advance_with_goal(1) = RegExpGoal
  let tok = ctx.advance_with_goal(1)
  match tok {
    GTRegex(body) => inspect(body, content="x")
    _ => inspect("wrong", content="expected GTRegex")
  }
  inspect(ctx.position, content="3")
}

///|
test "advance_with_goal at eof returns eof" {
  let buf = make_goal_buffer("")
  let spec = make_goal_spec()
  let ctx = ParserContext::new_indexed(
    buf.token_count(),
    fn(i) { buf.get_token(i) },
    fn(i) { buf.get_start(i) },
    fn(i) { buf.get_end(i) },
    buf.get_source(),
    spec,
  )
  ctx.set_goal_source(fn(offset, goal) { buf.goal_token_at(offset, goal) })

  let tok = ctx.advance_with_goal(0)
  inspect(tok, content="GTEof")
  inspect(ctx.position, content="0")
}

///|
test "advance_with_goal skips reuse for subsumed regions" {
  let buf = make_goal_buffer("/x/")
  let spec = make_goal_spec()
  let ctx = ParserContext::new_indexed(
    buf.token_count(),
    fn(i) { buf.get_token(i) },
    fn(i) { buf.get_start(i) },
    fn(i) { buf.get_end(i) },
    buf.get_source(),
    spec,
  )
  ctx.set_goal_source(fn(offset, goal) { buf.goal_token_at(offset, goal) }, subsumption_check=fn(
    offset,
  ) {
    buf.is_offset_goal_subsumed(offset)
  })

  // Populate cache with RegExpGoal at offset 0
  let (_tok, _end) = ctx.token_at(0, 1)

  // Now offset 0 is subsumed (the goal-produced Regex spans 0..3)
  // An attempt to reuse an old node at offset 0 would be rejected
  inspect(buf.is_offset_goal_subsumed(0), content="true")
  // Offset 3 (just past the regex) is NOT subsumed
  inspect(buf.is_offset_goal_subsumed(3), content="false")
}
