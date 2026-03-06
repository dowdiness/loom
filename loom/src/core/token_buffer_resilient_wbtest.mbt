///|
fn has_bad_char(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    if s.code_unit_at(i).to_int() == 64 {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn bad_tokenizer(s : String) -> Array[TokenInfo[String]] raise LexError {
  if has_bad_char(s) {
    raise LexError("bad char @")
  }
  let result : Array[TokenInfo[String]] = []
  for i = 0; i < s.length(); i = i + 1 {
    result.push(TokenInfo::new("char", i, i + 1))
  }
  result.push(TokenInfo::new("EOF", s.length(), s.length()))
  result
}

///|
test "TokenBuffer::new_resilient: clean input produces normal tokens" {
  let buf = TokenBuffer::new_resilient(
    "abc",
    tokenize_fn=bad_tokenizer,
    eof_token="EOF",
    error_token="ERR",
  )
  inspect(buf.get_tokens().length(), content="4")
}

///|
test "TokenBuffer::new_resilient: bad char produces error token and continues" {
  let buf = TokenBuffer::new_resilient(
    "a@b",
    tokenize_fn=bad_tokenizer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  inspect(tokens.length(), content="4")
  let rendered = tokens
    .map(fn(t) { t.token + "@" + t.start.to_string() + "-" + t.end.to_string() })
    .join(",")
  inspect(rendered, content="char@0-1,ERR@1-2,char@2-3,EOF@3-3")
}

///|
fn quote_sensitive_tokenizer(
  s : String,
) -> Array[TokenInfo[String]] raise LexError {
  if s.length() > 0 &&
    s.code_unit_at(0).to_int() == 34 &&
    s.code_unit_at(s.length() - 1).to_int() != 34 {
    raise LexError("unterminated quote")
  }
  if has_bad_char(s) {
    raise LexError("bad char @")
  }
  let result : Array[TokenInfo[String]] = []
  for i = 0; i < s.length(); i = i + 1 {
    result.push(TokenInfo::new("char", i, i + 1))
  }
  result.push(TokenInfo::new("EOF", s.length(), s.length()))
  result
}

///|
test "TokenBuffer::new_resilient: preserves valid prefix for non-monotonic tokenizer" {
  // Prefix success here is non-monotonic:
  //   "\"a"   -> LexError (unterminated quote)
  //   "\"a\"" -> Ok
  //   "\"a\"@" -> LexError (bad char @)
  let buf = TokenBuffer::new_resilient(
    "\"a\"@",
    tokenize_fn=quote_sensitive_tokenizer,
    eof_token="EOF",
    error_token="ERR",
  )
  let tokens = buf.get_tokens()
  let rendered = tokens
    .map(fn(t) { t.token + "@" + t.start.to_string() + "-" + t.end.to_string() })
    .join(",")
  inspect(rendered, content="char@0-1,char@1-2,char@2-3,ERR@3-4,EOF@4-4")
}
