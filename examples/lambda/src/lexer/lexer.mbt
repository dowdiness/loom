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
fn read_identifier(input : String, pos : Int, acc : String) -> (Int, String) {
  if pos >= input.length() {
    (pos, acc)
  } else {
    let code = input.code_unit_at(pos).to_int()
    if is_alphabet(code) || is_numeric(code) {
      match code.to_char() {
        Some(ch) => read_identifier(input, pos + 1, acc + ch.to_string())
        None => (pos, acc)
      }
    } else {
      (pos, acc)
    }
  }
}

///|
fn read_number(input : String, pos : Int, acc : Int) -> (Int, Int) {
  if pos >= input.length() {
    (pos, acc)
  } else {
    let code = input.code_unit_at(pos).to_int()
    if is_numeric(code) {
      let digit = code - 48
      read_number(input, pos + 1, acc * 10 + digit)
    } else {
      (pos, acc)
    }
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
  if pos >= input.length() {
    return Done
  }
  let c = input.code_unit_at(pos).to_char()
  match c {
    Some('\n') if layout =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Newline, 1),
        next_offset=pos + 1,
      )
    Some('\r') if layout => {
      let end = if pos + 1 < input.length() &&
        input.code_unit_at(pos + 1).to_char() == Some('\n') {
        pos + 2
      } else {
        pos + 1
      }
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Newline, end - pos),
        next_offset=end,
      )
    }
    Some(' ') | Some('\t') | Some('\n') | Some('\r') => {
      let ws_start = pos
      let mut ws_end = pos + 1
      while ws_end < input.length() {
        match input.code_unit_at(ws_end).to_char() {
          Some(' ') | Some('\t') | Some('\n') | Some('\r') if !layout =>
            ws_end = ws_end + 1
          Some(' ') | Some('\t') if layout => ws_end = ws_end + 1
          _ => break
        }
      }
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Whitespace, ws_end - ws_start),
        next_offset=ws_end,
      )
    }
    Some('λ') | Some('\\') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Lambda, 1),
        next_offset=pos + 1,
      )
    Some('.') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Dot, 1),
        next_offset=pos + 1,
      )
    Some('(') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.LeftParen, 1),
        next_offset=pos + 1,
      )
    Some(')') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.RightParen, 1),
        next_offset=pos + 1,
      )
    Some('+') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Plus, 1),
        next_offset=pos + 1,
      )
    Some('-') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Minus, 1),
        next_offset=pos + 1,
      )
    Some('=') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Eq, 1),
        next_offset=pos + 1,
      )
    Some('{') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.LBrace, 1),
        next_offset=pos + 1,
      )
    Some('}') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.RBrace, 1),
        next_offset=pos + 1,
      )
    Some(',') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Comma, 1),
        next_offset=pos + 1,
      )
    Some(';') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Semicolon, 1),
        next_offset=pos + 1,
      )
    Some('_') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Hole, 1),
        next_offset=pos + 1,
      )
    Some(c) if is_alphabet(c.to_int()) => {
      let (new_pos, identifier) = read_identifier(input, pos, "")
      let token = match identifier {
        "if" => @token.Token::If
        "then" => @token.Token::Then
        "else" => @token.Token::Else
        "let" => @token.Token::Let
        "in" => @token.Token::In
        _ => @token.Token::Identifier(identifier)
      }
      @core.LexStep::Produced(
        @core.TokenInfo::new(token, new_pos - pos),
        next_offset=new_pos,
      )
    }
    Some(c) if is_numeric(c.to_int()) => {
      let (new_pos, number) = read_number(input, pos, 0)
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Integer(number), new_pos - pos),
        next_offset=new_pos,
      )
    }
    None =>
      @core.LexStep::Invalid(
        at=pos,
        width=1,
        message="Error to read character at position \{pos}",
      )
    Some(ch) =>
      @core.LexStep::Invalid(
        at=pos,
        width=1,
        message="unexpected character: \{ch.to_string()} at position \{pos}",
      )
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
  let slice = input[start:end] catch {
      _ => raise @core.LexError("Invalid slice")
    }
  let tokens = tokenize(slice.to_string())
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
