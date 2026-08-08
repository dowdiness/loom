///|
test "TokenBuffer::update updates internal state without a return value" {
  let buf = TokenBuffer::new(
    SourceId("token-buffer-source"),
    "ab",
    tokenize_fn=bad_tokenizer,
    eof_token="EOF",
  )
  buf.update(Edit::insert(1, 1), "axb")
  let stored = buf.get_tokens()
  inspect(stored[0].token, content="char")
  inspect(stored[0].len, content="1")
  inspect(buf.get_start(1), content="1")
  inspect(buf.get_end(1), content="2")
}

///|
test "TokenBuffer::new detaches arrays returned by tokenize_fn" {
  let retained = [TokenInfo::new("A", 1), TokenInfo::new("EOF", 0)]
  let buffer = TokenBuffer::new(
    SourceId("token-buffer-callback-input"),
    "a",
    tokenize_fn=_ => retained,
    eof_token="EOF",
  )
  retained[0] = TokenInfo::new("changed", 7)
  inspect(buffer.get_token(0), content="A")
  inspect(buffer.get_start(0), content="0")
  inspect(buffer.get_end(0), content="1")
}

///|
test "TokenBuffer retokenize result detaches callback arrays" {
  let latest : Ref[Array[TokenInfo[String]]] = Ref([])
  let buffer = TokenBuffer::new(
    SourceId("token-buffer-callback-relex"),
    "a",
    tokenize_fn=source => {
      let tokens = [
        TokenInfo::new(source, source.length()),
        TokenInfo::new("EOF", 0),
      ]
      latest.val = tokens
      tokens
    },
    eof_token="EOF",
  )
  let result = (buffer.retokenize_full)("bb")
  latest.val[0] = TokenInfo::new("changed", 7)
  inspect(result.token_at(0).unwrap().token, content="bb")
  inspect(result.token_at(0).unwrap().len, content="2")
  debug_inspect(result.start_at(0), content="Some(0)")
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
      lex_result_from_owned_or_abort(
        [TokenInfo::new("ERR", 1), TokenInfo::new("EOF", 0)],
        [offset, source.length()],
        diagnostics=DiagnosticSet::single(
          lexer_diagnostic_at(
            SourceId("token-buffer-source"),
            "bad bang",
            offset,
            offset + 1,
            "bang",
          ),
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
      lex_result_from_owned_or_abort(
        tokens,
        starts,
        diagnostics=DiagnosticSet::empty(),
      )
    }
  }
}

///|
fn invalid_range_eof_lex(source : String) -> LexResult[String] {
  if source == "axc" {
    return lex_result_from_owned_or_abort(
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
  lex_result_from_owned_or_abort(
    tokens,
    starts,
    diagnostics=DiagnosticSet::empty(),
  )
}

///|
test "TokenBuffer::update preserves explicit LexResult starts from range relex" {
  let buf = TokenBuffer::new_from_lex(
    SourceId("token-buffer-source"),
    "abc",
    lex_fn=explicit_start_lex,
    eof_token="EOF",
  )
  buf.update(Edit::insert(2, 1), "ab!c")
  debug_inspect(
    buf.get_tokens().map(fn(t) { t.token }),
    content="[\"ERR\", \"EOF\"]",
  )
  debug_inspect(buf.get_starts(), content="[2, 4]")
  debug_inspect(buf.get_diagnostics().format(), content="[\"bad bang [2,3]\"]")
}

///|
test "TokenBuffer::update diagnoses invalid trailing range sentinel" {
  let buf = TokenBuffer::new_from_lex(
    SourceId("token-buffer-source"),
    "abc",
    lex_fn=invalid_range_eof_lex,
    eof_token="EOF",
  )
  buf.update(Edit::replace(1, 1, 1), "axc")
  debug_inspect(
    buf.get_diagnostics().format(),
    content="[\"range lexer returned invalid trailing EOF sentinel\"]",
  )
}
