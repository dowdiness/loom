///|
test "TokenBuffer::update returns a defensive copy" {
  let buf = TokenBuffer::new(
    "ab",
    tokenize_fn=bad_tokenizer,
    eof_token="EOF",
  )
  let returned = buf.update(Edit::insert(1, 1), "axb")
  returned[0] = TokenInfo::new("mutated", 99)
  inspect(returned[0].token, content="mutated")
  inspect(returned[0].len, content="99")
  let stored = buf.get_tokens()
  inspect(stored[0].token, content="char")
  inspect(stored[0].len, content="1")
  inspect(buf.get_start(1), content="1")
  inspect(buf.get_end(1), content="2")
}
