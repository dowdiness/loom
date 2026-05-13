// Lexer for Lambda Calculus

///|
fn is_big_alphabet(code : Int) -> Bool {
  code >= 65 && code <= 90
}

///|
fn is_small_alphabet(code : Int) -> Bool {
  code >= 97 && code <= 122
}

///|
fn is_alphabet(code : Int) -> Bool {
  is_big_alphabet(code) || is_small_alphabet(code)
}

///|
fn is_numeric(code : Int) -> Bool {
  code >= 48 && code <= 57
}

///|
fn is_identifier_char(ch : Char) -> Bool {
  let code = ch.to_int()
  is_alphabet(code) || is_numeric(code)
}

///|
fn is_numeric_char(ch : Char) -> Bool {
  is_numeric(ch.to_int())
}

///|
fn is_whitespace_char(ch : Char, layout : Bool) -> Bool {
  match ch {
    ' ' | '\t' => true
    '\n' | '\r' => !layout
    _ => false
  }
}

///|
/// Tokenize by stepping through step_lex, raising LexError on Invalid/Incomplete.
fn tokenize_via_steps(
  input : String,
  layout~ : Bool,
) -> Array[@core.TokenInfo[@token.Token]] raise @core.LexError {
  @core.tokenize_via_steps(
    fn(s, p) { step_lex(s, p, layout~) },
    input,
    @token.EOF,
  )
}

///|
/// Step-based lexer: returns one LexStep per call.
/// When ~layout=false (default), newlines fold into whitespace.
/// When ~layout=true, newlines are separate Newline tokens.
fn step_lex(
  input : String,
  pos : Int,
  layout~ : Bool,
) -> @core.LexStep[@token.Token] {
  let cursor = @core.LexCursor::new(input, pos)
  if cursor.is_done() {
    return Done
  }
  match cursor.view() {
    ['\n', .. rest] if layout => {
      cursor.set_view(rest)
      cursor.produced(@token.Newline)
    }
    ['\r', '\n', .. rest] if layout => {
      cursor.set_view(rest)
      cursor.produced(@token.Newline)
    }
    ['\r', .. rest] if layout => {
      cursor.set_view(rest)
      cursor.produced(@token.Newline)
    }
    [ch, ..] if is_whitespace_char(ch, layout) => {
      ignore(cursor.take_while(fn(c) { is_whitespace_char(c, layout) }))
      cursor.produced(@token.Whitespace)
    }
    ['λ', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Lambda)
    }
    ['\\', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Lambda)
    }
    ['.', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Dot)
    }
    ['(', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.LeftParen)
    }
    [')', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.RightParen)
    }
    ['+', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Plus)
    }
    [.. "->", .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Arrow)
    }
    ['-', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Minus)
    }
    ['=', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Eq)
    }
    ['{', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.LBrace)
    }
    ['}', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.RBrace)
    }
    [',', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Comma)
    }
    [';', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Semicolon)
    }
    [':', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Colon)
    }
    ['_', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(@token.Hole)
    }
    [c, ..] if is_alphabet(c.to_int()) => {
      ignore(cursor.take_while(is_identifier_char))
      let text : StringView = input[pos:cursor.position()]
      let token = match text {
        "if" => @token.Token::If
        "then" => @token.Token::Then
        "else" => @token.Token::Else
        "let" => @token.Token::Let
        _ => @token.Token::Identifier
      }
      cursor.produced(token)
    }
    [c, ..] if is_numeric_char(c) => {
      ignore(cursor.take_while(is_numeric_char))
      cursor.produced(@token.Integer)
    }
    _ =>
      match cursor.peek() {
        Some(ch) =>
          @core.LexStep::Invalid(
            at=pos,
            width=1,
            message="unexpected character: \{ch.to_string()} at position \{pos}",
          )
        None =>
          @core.LexStep::Invalid(
            at=pos,
            width=1,
            message="Error to read character at position \{pos}",
          )
      }
  }
}

///|
/// PrefixLexer for the lambda grammar (newlines as separate tokens).
pub fn lambda_step_lexer(
  source : String,
  start : Int,
) -> @core.LexStep[@token.Token] {
  step_lex(source, start, layout=true)
}

///|
/// Tokenize a slice of the input string and return tokens without EOF.
pub fn tokenize_range(
  input : String,
  start : Int,
  end : Int,
) -> Array[@core.TokenInfo[@token.Token]] raise @core.LexError {
  let slice = input[start:end]
  let tokens = tokenize(slice.to_owned())
  // Tokens are position-independent — no offset adjustment needed.
  // Just strip the trailing EOF.
  let result : Array[@core.TokenInfo[@token.Token]] = []
  for token_info in tokens {
    match token_info.token {
      @token.EOF => ()
      _ => result.push(token_info)
    }
  }
  result
}

///|
/// Tokenizer: emits Newline tokens for \n/\r\n (separate from Whitespace for
/// spaces/tabs) so that newlines act as definition delimiters.
pub fn tokenize(
  input : String,
) -> Array[@core.TokenInfo[@token.Token]] raise @core.LexError {
  tokenize_via_steps(input, layout=true)
}

///|
/// Total structured lexer used by the high-level Grammar boundary.
pub fn lex(input : String) -> @core.LexResult[@token.Token] {
  let buffer = @core.TokenBuffer::new_from_steps(
    input,
    @core.PrefixLexer::new(lex_step=lambda_step_lexer),
    eof_token=@token.EOF,
    error_token=@token.Error(""),
    error_token_from_message=Some(fn(msg) { @token.Error(msg) }),
  )
  @core.LexResult::with_starts(
    buffer.get_tokens(),
    buffer.get_starts(),
    diagnostics=buffer.get_diagnostics(),
  )
}
