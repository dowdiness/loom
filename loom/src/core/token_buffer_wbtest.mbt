///|
test "TokenBuffer::update updates internal state without a return value" {
  let buf = TokenBuffer::new("ab", tokenize_fn=bad_tokenizer, eof_token="EOF")
  buf.update(Edit::insert(1, 1), "axb")
  let stored = buf.get_tokens()
  inspect(stored[0].token, content="char")
  inspect(stored[0].len, content="1")
  inspect(buf.get_start(1), content="1")
  inspect(buf.get_end(1), content="2")
}

///|
fn bang_offset(source : String) -> Int? {
  for i = 0; i < source.length(); i = i + 1 {
    if source.code_unit_at(i).to_int() == 33 {
      return Some(i)
    }
  }
  None
}

///|
fn explicit_start_lex(source : String) -> LexResult[String] {
  match bang_offset(source) {
    Some(offset) =>
      LexResult::with_starts(
        [TokenInfo::new("ERR", 1), TokenInfo::new("EOF", 0)],
        [offset, source.length()],
        diagnostics=DiagnosticSet::single(
          Diagnostic::lexer_error_at("bad bang", offset, offset + 1, "bang"),
        ),
      )
    None => {
      let tokens : Array[TokenInfo[String]] = []
      let starts : Array[Int] = []
      for i = 0; i < source.length(); i = i + 1 {
        tokens.push(TokenInfo::new("char", 1))
        starts.push(i)
      }
      tokens.push(TokenInfo::new("EOF", 0))
      starts.push(source.length())
      LexResult::with_starts(tokens, starts, diagnostics=DiagnosticSet::empty())
    }
  }
}

///|
fn invalid_range_eof_lex(source : String) -> LexResult[String] {
  if source == "axc" {
    return LexResult::with_starts(
      [TokenInfo::new("char", 1), TokenInfo::new("char", 1)],
      [0, 1],
      diagnostics=DiagnosticSet::empty(),
    )
  }
  let tokens : Array[TokenInfo[String]] = []
  let starts : Array[Int] = []
  for i = 0; i < source.length(); i = i + 1 {
    tokens.push(TokenInfo::new("char", 1))
    starts.push(i)
  }
  tokens.push(TokenInfo::new("EOF", 0))
  starts.push(source.length())
  LexResult::with_starts(tokens, starts, diagnostics=DiagnosticSet::empty())
}

///|
test "TokenBuffer::update preserves explicit LexResult starts from range relex" {
  let buf = TokenBuffer::new_from_lex(
    "abc",
    lex_fn=explicit_start_lex,
    eof_token="EOF",
  )
  buf.update(Edit::insert(2, 1), "ab!c")
  inspect(buf.get_tokens().map(fn(t) { t.token }), content="[\"ERR\", \"EOF\"]")
  inspect(buf.get_starts(), content="[2, 4]")
  inspect(buf.get_diagnostics().format(), content="[\"bad bang [2,3]\"]")
}

///|
test "TokenBuffer::update diagnoses invalid trailing range sentinel" {
  let buf = TokenBuffer::new_from_lex(
    "abc",
    lex_fn=invalid_range_eof_lex,
    eof_token="EOF",
  )
  buf.update(Edit::replace(1, 1, 1), "axc")
  inspect(
    buf.get_diagnostics().format(),
    content="[\"range lexer returned invalid trailing EOF sentinel\"]",
  )
}
