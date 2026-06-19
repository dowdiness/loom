///|
pub(all) enum UnorderedListMarker {
  Dash
  Star
  Plus
} derive(Eq, Debug)

///|
fn UnorderedListMarker::text(self : UnorderedListMarker) -> String {
  match self {
    Dash => "-"
    Star => "*"
    Plus => "+"
  }
}

///|
fn unordered_list_marker_from_text(text : String) -> UnorderedListMarker? {
  match text {
    ['-', ..] => Some(Dash)
    ['*', ..] => Some(Star)
    ['+', ..] => Some(Plus)
    _ => None
  }
}

///|
pub(all) enum OrderedListDelimiter {
  Period
  Paren
} derive(Eq, Debug)

///|
fn OrderedListDelimiter::text(self : OrderedListDelimiter) -> String {
  match self {
    Period => "."
    Paren => ")"
  }
}

///|
pub struct OrderedListMarker {
  priv start : Int
  priv delimiter : OrderedListDelimiter
} derive(Eq, Debug)

///|
pub fn OrderedListMarker::OrderedListMarker(
  start~ : Int,
  delimiter~ : OrderedListDelimiter,
) -> OrderedListMarker {
  guard start >= 0 && start < 1000000000 else {
    abort("ordered list marker start must have 1-9 decimal digits")
  }
  { start, delimiter }
}

///|
pub fn OrderedListMarker::start(self : OrderedListMarker) -> Int {
  self.start
}

///|
pub fn OrderedListMarker::delimiter(
  self : OrderedListMarker,
) -> OrderedListDelimiter {
  self.delimiter
}

///|
pub fn OrderedListMarker::text(self : OrderedListMarker) -> String {
  self.start.to_string() + self.delimiter.text()
}

///|
fn is_decimal_digit(ch : Char) -> Bool {
  match ch {
    '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' => true
    _ => false
  }
}

///|
fn count_ordered_marker_digits(text : String, pos : Int) -> Int {
  let mut n = 0
  while pos + n < text.length() && n < 9 {
    match char_at(text, pos + n) {
      Some(ch) if is_decimal_digit(ch) => n = n + 1
      _ => break
    }
  }
  n
}

///|
fn ordered_list_marker_from_text(text : String) -> OrderedListMarker? {
  let digits = count_ordered_marker_digits(text, 0)
  guard digits > 0 else { return None }
  let delimiter = match char_at(text, digits) {
    Some('.') => Period
    Some(')') => Paren
    _ => return None
  }
  let start = @string.parse_int(text[:digits].to_owned()) catch {
    _ => return None
  }
  Some(OrderedListMarker(start~, delimiter~))
}

///|
pub(all) enum Token {
  HeadingMarker(Int) // "# " = 1, "## " = 2, etc. (includes trailing space)
  ListMarker // "- " or "* " or "+ " (includes trailing space)
  OrderedListMarker(OrderedListMarker) // "1. " or "1) " (includes trailing space)
  CodeFenceOpen(Int, String) // backtick count, info string
  CodeFenceClose // closing fence
  BlankLine // empty or whitespace-only line
  Star // *
  StarStar // **
  Backtick // `
  LeftBracket // [
  RightBracket // ]
  LeftParen // (
  RightParen // )
  Text(String) // plain text run (includes inter-word spaces)
  CodeText(String) // line of code block content
  Newline // \n
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      HeadingMarker(n) => "#".repeat(n) + " "
      ListMarker => "- "
      OrderedListMarker(marker) => marker.text() + " "
      CodeFenceOpen(n, info) => "`".repeat(n) + info
      CodeFenceClose => "```"
      BlankLine => ""
      Star => "*"
      StarStar => "**"
      Backtick => "`"
      LeftBracket => "["
      RightBracket => "]"
      LeftParen => "("
      RightParen => ")"
      Text(s) => s
      CodeText(s) => s
      Newline => "\n"
      Error(msg) => "<error: " + msg + ">"
      EOF => ""
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with fn is_trivia(_self) {
  false
}

///|
pub impl @seam.IsEof for Token with fn is_eof(self) {
  self == EOF
}

///|
/// Maps Token to the same RawKind as the corresponding SyntaxKind.
/// Payload-carrying variants (HeadingMarker, CodeFenceOpen, Text, CodeText)
/// collapse to their kind — text is available via token_text_at at the framework level.
pub impl @seam.ToRawKind for Token with fn to_raw(self) {
  @seam.RawKind(
    match self {
      HeadingMarker(_) => 0 // HeadingMarkerToken
      ListMarker => 1 // ListMarkerToken
      OrderedListMarker(_) => 28 // OrderedListMarkerToken
      CodeFenceOpen(_, _) => 2 // CodeFenceOpenToken
      CodeFenceClose => 3 // CodeFenceCloseToken
      BlankLine => 4 // BlankLineToken
      Star => 5 // StarToken
      StarStar => 6 // StarStarToken
      Backtick => 7 // BacktickToken
      LeftBracket => 8 // LeftBracketToken
      RightBracket => 9 // RightBracketToken
      LeftParen => 10 // LeftParenToken
      RightParen => 11 // RightParenToken
      Text(_) => 12 // TextToken
      CodeText(_) => 13 // CodeTextToken
      Newline => 14 // NewlineToken
      Error(_) => 15 // ErrorToken
      EOF => 16 // EofToken
    },
  )
}
