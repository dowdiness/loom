///| Test incremental re-lex with mode convergence.
///  Uses the mock 2-mode language from mode_lexer_wbtest.mbt.

///|
/// Helper: create a TokenBuffer with mode-aware re-lex for the mock language.
fn create_mock_buffer(source : String) -> TokenBuffer[MockToken] raise LexError {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let state = erase_mode_lexer(lexer, MockToken::EOF)
  let (tokens, starts) = (state.tokenize)(source)
  TokenBuffer::new_with_mode_relex(
    source,
    tokens,
    starts,
    MockToken::EOF,
    state,
  )
}

///|
test "mode relex: edit inside normal region converges immediately" {
  let buffer = create_mock_buffer("hello\"world\"end")
  // Edit: change "hello" to "hi" (replace 5 chars with 2)
  let edit = Edit::new(0, 5, 2)
  buffer.update(edit, "hi\"world\"end")
  inspect(buffer.token_count(), content="6")
  inspect(buffer.get_token(0), content="Text(\"hi\")")
  inspect(buffer.get_token(2), content="StringContent(\"world\")")
}

///|
test "mode relex: insert quote changes mode — propagates" {
  let buffer = create_mock_buffer("hello world")
  // tokens: Text("hello world"), EOF
  // Insert a quote at position 5: "hello\" world"
  let edit = Edit::new(5, 0, 1)
  buffer.update(edit, "hello\" world")
  // Now: Text("hello"), Quote, StringContent(" world"), EOF
  inspect(buffer.get_token(0), content="Text(\"hello\")")
  inspect(buffer.get_token(1), content="Quote")
  inspect(buffer.get_token(2), content="StringContent(\" world\")")
}

///|
test "mode relex: delete quote reverts mode" {
  let buffer = create_mock_buffer("hello\"world\"end")
  // Delete first quote (at position 5, length 1)
  let edit = Edit::new(5, 1, 0)
  buffer.update(edit, "helloworld\"end")
  // Now: Text("helloworld"), Quote, StringContent("end"), EOF
  inspect(buffer.get_token(0), content="Text(\"helloworld\")")
  inspect(buffer.get_token(1), content="Quote")
  inspect(buffer.get_token(2), content="StringContent(\"end\")")
}

///|
/// Verify that TokenBuffer without mode_relex behaves identically.
test "backward compat: TokenBuffer::new still works without mode_relex" {
  let tokenize_fn : (String) -> Array[TokenInfo[MockToken]] raise LexError = s => {
    let lexer : ModeLexer[MockToken, MockMode] = {
      lex_step: mock_lex_step,
      initial_mode: Normal,
    }
    let (tokens, _modes) = tokenize_with_modes(lexer, s, MockToken::EOF)
    tokens
  }
  let buffer = TokenBuffer::new("hello", tokenize_fn~, eof_token=MockToken::EOF)
  inspect(buffer.token_count(), content="2")
  inspect(buffer.get_token(0), content="Text(\"hello\")")
}
