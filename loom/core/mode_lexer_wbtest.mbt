///|
/// Mock 2-mode language: Normal and String.
///  `"` toggles between modes.
///  Normal mode: Text tokens for non-quote chars.
///  String mode: StringContent tokens for non-quote chars.
///  `"` always produces a Quote token in either mode.
priv enum MockMode {
  Normal
  StringMode
} derive(Eq, Debug)

///|
impl Show for MockMode with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
priv enum MockToken {
  Text(String)
  StringContent(String)
  Error(String)
  Quote
  EOF
} derive(Eq, Debug)

///|
impl Show for MockToken with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

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
        Normal => Text(text.to_owned())
        StringMode => StringContent(text.to_owned())
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
  let state = erase_mode_lexer(
    lexer,
    MockToken::EOF,
    error_token=Error("error"),
    error_token_from_message=Some(msg => Error(msg)),
  )
  let result = state.tokenize(
    SourceId("mode-lexer-source"),
    "hello\"world\"end",
  )
  let tokens = result.tokens()
  let starts = result.starts()
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

///|
test "erase_mode_lexer_factory owns one lexer shell per operation" {
  let construction_count : Ref[Int] = Ref(0)
  let new_lexer = fn() {
    construction_count.val = construction_count.val + 1
    (
      { lex_step: mock_lex_step, initial_mode: Normal } :
      ModeLexer[MockToken, MockMode])
  }
  let factory = erase_mode_lexer_factory(
    new_lexer,
    MockToken::EOF,
    error_token=Error("error"),
  )
  assert_eq(construction_count.val, 0)
  ignore(factory.tokenize(SourceId("detached-a"), "alpha"))
  ignore(factory.tokenize(SourceId("detached-b"), "beta"))
  assert_eq(construction_count.val, 2)
  let session_a = factory.new_session(SourceId("session-a"))
  let session_b = factory.new_session(SourceId("session-b"))
  assert_eq(construction_count.val, 4)
  ignore(session_a.tokenize("alpha"))
  ignore(session_b.tokenize("beta"))
  assert_eq(construction_count.val, 4)
}

///|
fn mock_recovering_lex_step(
  input : String,
  pos : Int,
  mode : MockMode,
) -> (LexStep[MockToken], MockMode) {
  if pos >= input.length() {
    return (Done, mode)
  }
  match mock_char_at(input, pos) {
    Some('!') => (Invalid(at=pos, width=1, message="bang"), StringMode)
    Some('?') => (Incomplete(at=pos, expected="closing marker"), mode)
    _ => mock_lex_step(input, pos, mode)
  }
}

///|
test "tokenize_with_modes_recovering records diagnostics and next mode" {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_recovering_lex_step,
    initial_mode: Normal,
  }
  let (result, modes) = tokenize_with_modes_recovering(
    SourceId("mode-lexer-recovery-source"),
    lexer,
    "!x",
    MockToken::EOF,
    Error("error"),
    error_token_from_message=Some(msg => Error(msg)),
  )
  let tokens = result.tokens()
  let starts = result.starts()
  debug_inspect(result.diagnostics().format(), content="[\"bang [0,1]\"]")
  inspect(tokens[0].token, content="Error(\"bang\")")
  inspect(tokens[1].token, content="StringContent(\"x\")")
  inspect(tokens[2].token, content="EOF")
  inspect(starts[0], content="0")
  inspect(starts[1], content="1")
  inspect(modes[0], content="Normal")
  inspect(modes[1], content="StringMode")
}

///|
test "tokenize_with_modes_recovering records incomplete diagnostic" {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_recovering_lex_step,
    initial_mode: Normal,
  }
  let (result, _modes) = tokenize_with_modes_recovering(
    SourceId("mode-lexer-recovery-source"),
    lexer,
    "?tail",
    MockToken::EOF,
    Error("error"),
    error_token_from_message=Some(msg => Error(msg)),
  )
  let tokens = result.tokens()
  debug_inspect(
    result.diagnostics().format(),
    content="[\"incomplete token; expected closing marker [0,5]\"]",
  )
  inspect(tokens[0].token, content="Error(\"closing marker\")")
  inspect(tokens[0].len, content="5")
  inspect(tokens[1].token, content="EOF")
}

///|
/// Property: tokenize_with_modes produces the same tokens as manually
///  stepping through lex_step with mode threading.
///  Uses quickcheck to generate random strings containing quotes and text.
test "property: tokenize_with_modes consistent with step replay" {
  @qc.quick_check_fn(fn(input : String) -> Bool {
    let lexer : ModeLexer[MockToken, MockMode] = {
      lex_step: mock_lex_step,
      initial_mode: Normal,
    }
    let (tokens, modes) = tokenize_with_modes(lexer, input, MockToken::EOF) catch {
      _ => return true // skip inputs that cause lex errors
    }
    // Manual replay
    let mut pos = 0
    let mut mode : MockMode = Normal
    let mut i = 0
    while pos < input.length() {
      let (step, next_mode) = mock_lex_step(input, pos, mode)
      match step {
        Produced(tok, next_offset~) => {
          if tokens[i].token != tok.token {
            return false
          }
          if modes[i] != mode {
            return false
          }
          mode = next_mode
          pos = next_offset
          i = i + 1
        }
        _ => break
      }
    }
    // EOF sentinel
    tokens[i].token == MockToken::EOF
  })
}

///|
/// A separate vocabulary exercises two meanings of the same quote delimiter.
priv enum MixedMode {
  Normal
  AfterNotationHead
  AfterOpaqueHead
  ExpectNotationQuote
  ExpectOpaqueQuote
  NotationString
  OpaqueString
} derive(Eq, Debug)

///|
impl Show for MixedMode with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
priv enum MixedToken {
  HeadS
  HeadSection
  OpenParen
  CloseParen
  Space(String)
  Quote
  NotationWord(String)
  NotationSpace
  NotationColon
  OpaqueRaw(String)
  EOF
} derive(Eq, Debug)

///|
impl Show for MixedToken with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn mixed_source() -> String {
  "s(\"bd sd\") section(\"verse: 1\")"
}

///|
/// Choose the next quote context from lexical facts already consumed.
fn mixed_lex_step(
  input : String,
  pos : Int,
  mode : MixedMode,
) -> (LexStep[MixedToken], MixedMode) {
  if pos >= input.length() {
    return (Done, mode)
  }
  let cursor = LexCursor::new(input, pos)
  match mode {
    Normal => {
      if cursor.starts_with("section") {
        ignore(cursor.consume_string("section"))
        return (cursor.produced(HeadSection), AfterOpaqueHead)
      }
      if cursor.starts_with("s") {
        ignore(cursor.consume_string("s"))
        return (cursor.produced(HeadS), AfterNotationHead)
      }
      match cursor.peek() {
        Some(' ') => {
          ignore(cursor.take_while(fn(ch) { ch == ' ' }))
          let text = input
            .view(start_offset=pos, end_offset=cursor.position())
            .to_owned()
          (cursor.produced(Space(text)), Normal)
        }
        Some(')') => {
          ignore(cursor.advance_char())
          (cursor.produced(CloseParen), Normal)
        }
        _ => (cursor.invalid("unexpected normal token"), Normal)
      }
    }
    AfterNotationHead =>
      if cursor.consume_char('(') {
        (cursor.produced(OpenParen), ExpectNotationQuote)
      } else {
        (cursor.invalid("expected notation opener"), Normal)
      }
    AfterOpaqueHead =>
      if cursor.consume_char('(') {
        (cursor.produced(OpenParen), ExpectOpaqueQuote)
      } else {
        (cursor.invalid("expected opaque opener"), Normal)
      }
    ExpectNotationQuote =>
      if cursor.consume_char('"') {
        (cursor.produced(Quote), NotationString)
      } else {
        (cursor.invalid("expected notation quote"), Normal)
      }
    ExpectOpaqueQuote =>
      if cursor.consume_char('"') {
        (cursor.produced(Quote), OpaqueString)
      } else {
        (cursor.invalid("expected opaque quote"), Normal)
      }
    NotationString =>
      match cursor.peek() {
        Some('"') => {
          ignore(cursor.advance_char())
          (cursor.produced(Quote), Normal)
        }
        Some(' ') => {
          ignore(cursor.take_while(fn(ch) { ch == ' ' }))
          (cursor.produced(NotationSpace), NotationString)
        }
        Some(':') => {
          ignore(cursor.advance_char())
          (cursor.produced(NotationColon), NotationString)
        }
        Some(_) => {
          ignore(
            cursor.take_while(fn(ch) { ch != ' ' && ch != '"' && ch != ':' }),
          )
          let text = input
            .view(start_offset=pos, end_offset=cursor.position())
            .to_owned()
          (cursor.produced(NotationWord(text)), NotationString)
        }
        None => (Done, NotationString)
      }
    OpaqueString =>
      match cursor.peek() {
        Some('"') => {
          ignore(cursor.advance_char())
          (cursor.produced(Quote), Normal)
        }
        Some(_) => {
          ignore(cursor.take_while(fn(ch) { ch != '"' }))
          let text = input
            .view(start_offset=pos, end_offset=cursor.position())
            .to_owned()
          (cursor.produced(OpaqueRaw(text)), OpaqueString)
        }
        None => (Done, OpaqueString)
      }
  }
}

///|
test "mixed contexts use the same quote with distinct content modes" {
  let lexer : ModeLexer[MixedToken, MixedMode] = {
    lex_step: mixed_lex_step,
    initial_mode: Normal,
  }
  let (tokens, modes) = tokenize_with_modes(lexer, mixed_source(), EOF)
  inspect(tokens.length(), content="16")
  inspect(tokens[0].token, content="HeadS")
  inspect(tokens[1].token, content="OpenParen")
  inspect(tokens[2].token, content="Quote")
  inspect(tokens[3].token, content="NotationWord(\"bd\")")
  inspect(tokens[4].token, content="NotationSpace")
  inspect(tokens[5].token, content="NotationWord(\"sd\")")
  inspect(tokens[6].token, content="Quote")
  inspect(tokens[7].token, content="CloseParen")
  inspect(tokens[8].token, content="Space(\" \")")
  inspect(tokens[9].token, content="HeadSection")
  inspect(tokens[10].token, content="OpenParen")
  inspect(tokens[11].token, content="Quote")
  inspect(tokens[12].token, content="OpaqueRaw(\"verse: 1\")")
  inspect(tokens[13].token, content="Quote")
  inspect(tokens[14].token, content="CloseParen")
  inspect(tokens[15].token, content="EOF")
  inspect(modes[2], content="ExpectNotationQuote")
  inspect(modes[3], content="NotationString")
  inspect(modes[5], content="NotationString")
  inspect(modes[6], content="NotationString")
  inspect(modes[11], content="ExpectOpaqueQuote")
  inspect(modes[12], content="OpaqueString")
  inspect(modes[13], content="OpaqueString")
  inspect(modes[15], content="Normal")
}

///|
test "mixed contexts detached tokenization preserves snapshots and spans" {
  let lexer : ModeLexer[MixedToken, MixedMode] = {
    lex_step: mixed_lex_step,
    initial_mode: Normal,
  }
  let (typed_tokens, _typed_modes) = tokenize_with_modes(
    lexer,
    mixed_source(),
    EOF,
  )
  let factory = erase_mode_lexer(lexer, EOF, error_token=OpaqueRaw("error"))
  let result = factory.tokenize(
    SourceId("mode-lexer-mixed-source"),
    mixed_source(),
  )
  inspect(result.tokens() == typed_tokens, content="true")
  inspect(result.starts()[0], content="0")
  inspect(result.starts()[1], content="1")
  inspect(result.starts()[2], content="2")
  inspect(result.starts()[3], content="3")
  inspect(result.starts()[4], content="5")
  inspect(result.starts()[5], content="6")
  inspect(result.starts()[6], content="8")
  inspect(result.starts()[7], content="9")
  inspect(result.starts()[8], content="10")
  inspect(result.starts()[9], content="11")
  inspect(result.starts()[10], content="18")
  inspect(result.starts()[11], content="19")
  inspect(result.starts()[12], content="20")
  inspect(result.starts()[13], content="28")
  inspect(result.starts()[14], content="29")
  inspect(result.starts()[15], content="30")
  inspect(result.tokens()[12].token, content="OpaqueRaw(\"verse: 1\")")
  inspect(result.tokens()[12].len, content="8")
}
