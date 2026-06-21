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
fn skip_leading_spaces(text : String, pos : Int) -> Int {
  let mut i = pos
  while i < text.length() {
    match char_at(text, i) {
      Some(' ') => i = i + 1
      _ => break
    }
  }
  i
}

///|
fn marker_start_after_optional_indent(text : String, pos : Int) -> Int? {
  let marker_start = skip_leading_spaces(text, pos)
  guard marker_start - pos <= 3 else { return None }
  Some(marker_start)
}

///|
fn unordered_list_marker_from_text(text : String) -> UnorderedListMarker? {
  guard marker_start_after_optional_indent(text, 0) is Some(marker_start) else {
    return None
  }
  match text.view(start_offset=marker_start) {
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
fn thematic_break_marker_text(text : StringView) -> Bool {
  let (count, valid, seen_marker) = for
    ch in text
    marker = (None : Char?),
    count = 0,
    valid = true,
    seen_marker = false,
    indent = 0 {
    if !valid {
      continue marker, count, false, seen_marker, indent
    }
    match ch {
      ' ' =>
        if seen_marker {
          continue marker, count, true, true, indent
        } else if indent < 3 {
          continue marker, count, true, false, indent + 1
        } else {
          continue marker, count, false, false, indent
        }
      '\t' =>
        if seen_marker {
          continue marker, count, true, true, indent
        } else {
          continue marker, count, false, false, indent
        }
      '-' | '_' | '*' =>
        match marker {
          Some(existing) if existing != ch =>
            continue marker, count, false, seen_marker, indent
          _ => continue Some(ch), count + 1, true, true, indent
        }
      _ => continue marker, count, false, seen_marker, indent
    }
  } nobreak {
    (count, valid, seen_marker)
  }
  valid && seen_marker && count >= 3
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
  guard marker_start_after_optional_indent(text, 0) is Some(marker_start) else {
    return None
  }
  let digits = count_ordered_marker_digits(text, marker_start)
  guard digits > 0 else { return None }
  let delimiter_offset = marker_start + digits
  let delimiter = match char_at(text, delimiter_offset) {
    Some('.') => Period
    Some(')') => Paren
    _ => return None
  }
  let start = @string.parse_int(text[marker_start:delimiter_offset].to_owned()) catch {
    _ => return None
  }
  Some(OrderedListMarker(start~, delimiter~))
}

///|
pub(all) enum Token {
  HeadingMarker(Int) // "# " = 1, "## " = 2, etc. (includes trailing space)
  ListMarker // "- " or "* " or "+ " (includes trailing space)
  OrderedListMarker(OrderedListMarker) // "1. " or "1) " (includes trailing space)
  BlockQuoteMarker // ">" plus optional following space, with up to three leading spaces
  ThematicBreak
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
      BlockQuoteMarker => "> "
      ThematicBreak => "---"
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
      BlockQuoteMarker => 30 // BlockQuoteMarkerToken
      ThematicBreak => 32 // ThematicBreakToken
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
