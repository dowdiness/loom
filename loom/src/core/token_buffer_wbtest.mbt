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
