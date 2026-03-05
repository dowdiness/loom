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
/// Shared tokenizer core. When ~layout=false (default), \n/\r are folded into
/// Whitespace runs. When ~layout=true, \n and \r\n are emitted as Newline
/// tokens (non-trivia delimiters for the source-file grammar).
fn tokenize_helper(
  input : String,
  pos : Int,
  acc : Array[@core.TokenInfo[@token.Token]],
  layout? : Bool,
) -> Array[@core.TokenInfo[@token.Token]] raise @core.LexError {
  let layout = layout.unwrap_or(false)
  if pos >= input.length() {
    acc.push(@core.TokenInfo::new(@token.EOF, pos, pos))
    acc
  } else {
    let c = input.code_unit_at(pos).to_char()
    match c {
      Some('\n') if layout => {
        acc.push(@core.TokenInfo::new(@token.Newline, pos, pos + 1))
        tokenize_helper(input, pos + 1, acc, layout~)
      }
      Some('\r') if layout => {
        let end = if pos + 1 < input.length() &&
          input.code_unit_at(pos + 1).to_char() == Some('\n') {
          pos + 2
        } else {
          pos + 1
        }
        acc.push(@core.TokenInfo::new(@token.Newline, pos, end))
        tokenize_helper(input, end, acc, layout~)
      }
      Some(' ') | Some('\t') | Some('\n') | Some('\r') => {
        // Consume a run of whitespace (layout=false folds \n here too)
        let ws_start = pos
        let mut ws_end = pos + 1
        while ws_end < input.length() {
          match input.code_unit_at(ws_end).to_char() {
            Some(' ') | Some('\t') | Some('\n') | Some('\r') if not(layout) =>
              ws_end = ws_end + 1
            Some(' ') | Some('\t') if layout => ws_end = ws_end + 1
            _ => break
          }
        }
        acc.push(@core.TokenInfo::new(@token.Whitespace, ws_start, ws_end))
        tokenize_helper(input, ws_end, acc, layout~)
      }
      Some('λ') | Some('\\') => {
        acc.push(@core.TokenInfo::new(@token.Lambda, pos, pos + 1))
        tokenize_helper(input, pos + 1, acc, layout~)
      }
      Some('.') => {
        acc.push(@core.TokenInfo::new(@token.Dot, pos, pos + 1))
        tokenize_helper(input, pos + 1, acc, layout~)
      }
      Some('(') => {
        acc.push(@core.TokenInfo::new(@token.LeftParen, pos, pos + 1))
        tokenize_helper(input, pos + 1, acc, layout~)
      }
      Some(')') => {
        acc.push(@core.TokenInfo::new(@token.RightParen, pos, pos + 1))
        tokenize_helper(input, pos + 1, acc, layout~)
      }
      Some('+') => {
        acc.push(@core.TokenInfo::new(@token.Plus, pos, pos + 1))
        tokenize_helper(input, pos + 1, acc, layout~)
      }
      Some('-') => {
        acc.push(@core.TokenInfo::new(@token.Minus, pos, pos + 1))
        tokenize_helper(input, pos + 1, acc, layout~)
      }
      Some('=') => {
        acc.push(@core.TokenInfo::new(@token.Eq, pos, pos + 1))
        tokenize_helper(input, pos + 1, acc, layout~)
      }
      Some(c) =>
        if is_alphabet(c.to_int()) {
          let (new_pos, identifier) = read_identifier(input, pos, "")
          let token = match identifier {
            "if" => @token.Token::If
            "then" => @token.Token::Then
            "else" => @token.Token::Else
            "let" => @token.Token::Let
            "in" => @token.Token::In
            _ => @token.Token::Identifier(identifier)
          }
          acc.push(@core.TokenInfo::new(token, pos, new_pos))
          tokenize_helper(input, new_pos, acc, layout~)
        } else if is_numeric(c.to_int()) {
          let (new_pos, number) = read_number(input, pos, 0)
          acc.push(@core.TokenInfo::new(@token.Integer(number), pos, new_pos))
          tokenize_helper(input, new_pos, acc, layout~)
        } else {
          raise @core.LexError(c.to_string())
        }
      None =>
        raise @core.LexError(
          "Error to read character at position \{pos}",
        )
    }
  }
}

///|
/// Tokenize the input string into an array of tokens with position information
pub fn tokenize(
  input : String,
) -> Array[@core.TokenInfo[@token.Token]] raise @core.LexError {
  tokenize_helper(input, 0, [])
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
  let result : Array[@core.TokenInfo[@token.Token]] = []
  for token_info in tokens {
    match token_info.token {
      @token.EOF => ()
      _ =>
        result.push(
          @core.TokenInfo::new(
            token_info.token,
            token_info.start + start,
            token_info.end + start,
          ),
        )
    }
  }
  result
}

///|
/// Layout-aware tokenizer: like tokenize but emits Newline tokens for \n/\r\n
/// (separate from Whitespace for spaces/tabs). Used by the source-file grammar
/// so that newlines act as definition delimiters.
pub fn tokenize_layout(
  input : String,
) -> Array[@core.TokenInfo[@token.Token]] raise @core.LexError {
  tokenize_helper(input, 0, [], layout=true)
}
