///|
/// Mock 2-mode language: Normal and String.
///  `"` toggles between modes.
///  Normal mode: Text tokens for non-quote chars.
///  String mode: StringContent tokens for non-quote chars.
///  `"` always produces a Quote token in either mode.
priv enum MockMode {
  Normal
  StringMode
} derive(Eq, Show)

///|
priv enum MockToken {
  Text(String)
  StringContent(String)
  Quote
  EOF
} derive(Eq, Show)

///|
fn mock_char_at(input : String, pos : Int) -> Char? {
  input.code_unit_at(pos).to_char()
}

///|
fn mock_lex_step(
  input : String,
  pos : Int,
  mode : MockMode,
) -> (LexStep[MockToken], MockMode) {
  if pos >= input.length() {
    return (Done, mode)
  }
  match mock_char_at(input, pos) {
    Some('"') => {
      let next_mode = match mode {
        Normal => StringMode
        StringMode => Normal
      }
      (Produced(TokenInfo::new(Quote, 1), next_offset=pos + 1), next_mode)
    }
    _ => {
      // Consume run of non-quote characters
      let mut end = pos + 1
      while end < input.length() {
        match mock_char_at(input, end) {
          Some('"') => break
          _ => end = end + 1
        }
      }
      let text : StringView = input[pos:end]
      let token = match mode {
        Normal => Text(text.to_string())
        StringMode => StringContent(text.to_string())
      }
      (Produced(TokenInfo::new(token, end - pos), next_offset=end), mode)
    }
  }
}

///|
test "tokenize_with_modes basic" {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let (tokens, modes) = tokenize_with_modes(
    lexer,
    "hello\"world\"end",
    MockToken::EOF,
  )
  // tokens: Text("hello"), Quote, StringContent("world"), Quote, Text("end"), EOF
  inspect(tokens.length(), content="6")
  inspect(tokens[0].token, content="Text(\"hello\")")
  inspect(tokens[1].token, content="Quote")
  inspect(tokens[2].token, content="StringContent(\"world\")")
  inspect(tokens[3].token, content="Quote")
  inspect(tokens[4].token, content="Text(\"end\")")
  inspect(tokens[5].token, content="EOF")
  // modes: Normal, Normal, StringMode, StringMode, Normal, Normal
  inspect(modes[0], content="Normal")
  inspect(modes[1], content="Normal")
  inspect(modes[2], content="StringMode")
  inspect(modes[3], content="StringMode")
  inspect(modes[4], content="Normal")
  inspect(modes[5], content="Normal")
}

///|
test "tokenize_with_modes empty input" {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let (tokens, modes) = tokenize_with_modes(lexer, "", MockToken::EOF)
  inspect(tokens.length(), content="1")
  inspect(tokens[0].token, content="EOF")
  inspect(modes[0], content="Normal")
}

///|
test "erase_mode_lexer tokenize matches tokenize_with_modes" {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let state = erase_mode_lexer(lexer, MockToken::EOF)
  let (tokens, starts) = (state.tokenize)("hello\"world\"end")
  inspect(tokens.length(), content="6")
  inspect(tokens[0].token, content="Text(\"hello\")")
  inspect(tokens[2].token, content="StringContent(\"world\")")
  // Starts are prefix sums: 0, 5, 6, 11, 12, 15
  inspect(starts[0], content="0")
  inspect(starts[1], content="5")
  inspect(starts[2], content="6")
  inspect(starts[3], content="11")
  inspect(starts[4], content="12")
  inspect(starts[5], content="15")
}
