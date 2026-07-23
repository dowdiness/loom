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
/// Skip literal space characters only; CommonMark tabs expand to four-column
/// indentation and are not interchangeable with optional 0–3 space prefixes in
/// the setext/ATX source-slice helpers that use this.
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
fn parse_marker_line(
  text : StringView,
  is_marker : (Char) -> Bool,
  min_count~ : Int,
  allow_internal_whitespace~ : Bool,
) -> (Char, Int)? {
  let (marker, count, valid) = for
    ch in text
    marker = (None : Char?),
    count = 0,
    valid = true,
    indent = 0,
    trailing_whitespace = false {
    // `indent` only tracks leading literal spaces before the first marker;
    // a leading tab is a 4-column indent and therefore not part of the
    // 0–3-space marker prefix handled here. Once `count > 0`, marker validation
    // ignores it. `trailing_whitespace` distinguishes trailing whitespace from
    // thematic-break marker separators.
    if !valid {
      continue marker, count, valid, indent, trailing_whitespace
    }
    match ch {
      ' ' | '\t' =>
        if count > 0 {
          continue marker, count, true, 0, true
        } else if ch == ' ' && indent < 3 {
          continue marker, count, true, indent + 1, false
        } else {
          continue marker, count, false, indent, trailing_whitespace
        }
      marker_ch if is_marker(marker_ch) =>
        if trailing_whitespace && !allow_internal_whitespace {
          continue marker, count, false, 0, trailing_whitespace
        } else {
          match marker {
            Some(existing) if existing != marker_ch =>
              continue marker, count, false, 0, false
            _ => continue Some(marker_ch), count + 1, true, 0, false
          }
        }
      _ => continue marker, count, false, indent, trailing_whitespace
    }
  } nobreak {
    (marker, count, valid)
  }
  guard valid && count >= min_count else { return None }
  marker.map(marker => (marker, count))
}

///|
fn is_valid_thematic_break_markers(text : StringView) -> Bool {
  parse_marker_line(
    text,
    marker => {
      match marker {
        '-' | '_' | '*' => true
        _ => false
      }
    },
    min_count=3,
    allow_internal_whitespace=true,
  )
  is Some(_)
}

///|
fn parse_setext_underline_depth(text : StringView) -> Int? {
  match
    parse_marker_line(
      text,
      marker => {
        match marker {
          '=' | '-' => true
          _ => false
        }
      },
      min_count=1,
      allow_internal_whitespace=false,
    ) {
    Some(('=', _)) => Some(1)
    Some(('-', _)) => Some(2)
    _ => None
  }
}

///|
fn strip_backslash_escapes(text : String) -> String {
  let buf = StringBuilder::new()
  let mut pending_backslash = false
  for ch in text {
    if pending_backslash {
      if ch.is_ascii_punctuation() {
        buf.write_char(ch)
      } else {
        buf.write_char('\\')
        buf.write_char(ch)
      }
      pending_backslash = false
    } else if ch == '\\' {
      pending_backslash = true
    } else {
      buf.write_char(ch)
    }
  }
  if pending_backslash {
    buf.write_char('\\')
  }
  buf.to_string()
}

///|
test "backslash escapes strip only ASCII punctuation" {
  inspect(strip_backslash_escapes(""), content="")
  inspect(strip_backslash_escapes("\\"), content="\\")
  inspect(strip_backslash_escapes("\\\\"), content="\\")
  inspect(strip_backslash_escapes("\\="), content="=")
  inspect(strip_backslash_escapes("\\-"), content="-")
  inspect(strip_backslash_escapes("\\*"), content="*")
  inspect(strip_backslash_escapes("\\_"), content="_")
  inspect(strip_backslash_escapes("\\["), content="[")
  inspect(strip_backslash_escapes("\\`"), content="`")
  inspect(strip_backslash_escapes("\\#\\*"), content="#*")
  inspect(strip_backslash_escapes("\\## foo"), content="## foo")
  inspect(strip_backslash_escapes("\\> foo"), content="> foo")
  inspect(strip_backslash_escapes("Foo\\\n----"), content="Foo\\\n----")
  inspect(
    strip_backslash_escapes("\\A\\3\\φ\\«\\"),
    content="\\A\\3\\φ\\«\\",
  )
  inspect(strip_backslash_escapes("\\φ"), content="\\φ")
  inspect(strip_backslash_escapes("\\«"), content="\\«")
}

///|
test "setext underline markers reject internal whitespace" {
  guard parse_setext_underline_depth("= =".view()) is None else {
    fail("setext underline must reject spaced equals markers")
  }
  guard parse_setext_underline_depth("--- -".view()) is None else {
    fail("setext underline must reject spaced dash markers")
  }
  guard parse_setext_underline_depth("   ----      ".view()) is Some(2) else {
    fail("setext underline must accept trailing spaces")
  }
  assert_true(is_valid_thematic_break_markers("--- -".view()))
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
  ListMarker(UnorderedListMarker) // "- " or "* " or "+ " (includes trailing space)
  OrderedListMarker(OrderedListMarker) // "1. " or "1) " (includes trailing space)
  BlockQuoteMarker // ">" plus optional following space, with up to three leading spaces
  ThematicBreak(String)
  CodeFenceOpen(Int, String) // backtick count, info string
  CodeFenceClose // closing fence
  HtmlBlockOpen(String) // opening line of an HTML block
  HtmlText(String) // line of HTML block content
  BlankLine // empty or whitespace-only line
  Star // *
  StarStar // **
  Backtick // `
  LeftBracket // [
  RightBracket // ]
  LeftParen // (
  RightParen // )
  Text(String) // plain text run (includes inter-word spaces)
  CodeText(String) // line of fenced code block content
  Indentation(String) // exact leading spaces/tabs of a nonblank physical line
  Newline // \n
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      HeadingMarker(n) => "#".repeat(n) + " "
      ListMarker(marker) => marker.text() + " "
      OrderedListMarker(marker) => marker.text() + " "
      BlockQuoteMarker => "> "
      ThematicBreak(text) => text
      CodeFenceOpen(n, info) => "`".repeat(n) + info
      CodeFenceClose => "```"
      HtmlBlockOpen(s) => s
      HtmlText(s) => s
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
      Indentation(s) => s
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
      ListMarker(_) => 1 // ListMarkerToken
      OrderedListMarker(_) => 29 // OrderedListMarkerToken
      BlockQuoteMarker => 31 // BlockQuoteMarkerToken
      ThematicBreak(_) => 33 // ThematicBreakToken
      CodeFenceOpen(_, _) => 2 // CodeFenceOpenToken
      CodeFenceClose => 3 // CodeFenceCloseToken
      HtmlBlockOpen(_) => 35 // HtmlBlockOpenToken
      HtmlText(_) => 36 // HtmlTextToken
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
      Indentation(_) => 14 // IndentationToken
      Newline => 15 // NewlineToken
      Error(_) => 16 // ErrorToken
      EOF => 17 // EofToken
    },
  )
}

///|
test "tokens map to their corresponding syntax raw kind" {
  let cases : Array[(Token, SyntaxKind)] = [
    (HeadingMarker(1), HeadingMarkerToken),
    (ListMarker(Dash), ListMarkerToken),
    (
      OrderedListMarker(OrderedListMarker(start=1, delimiter=Period)),
      OrderedListMarkerToken,
    ),
    (BlockQuoteMarker, BlockQuoteMarkerToken),
    (ThematicBreak("---"), ThematicBreakToken),
    (CodeFenceOpen(3, ""), CodeFenceOpenToken),
    (CodeFenceClose, CodeFenceCloseToken),
    (HtmlBlockOpen("<div>"), HtmlBlockOpenToken),
    (HtmlText("text"), HtmlTextToken),
    (BlankLine, BlankLineToken),
    (Star, StarToken),
    (StarStar, StarStarToken),
    (Backtick, BacktickToken),
    (LeftBracket, LeftBracketToken),
    (RightBracket, RightBracketToken),
    (LeftParen, LeftParenToken),
    (RightParen, RightParenToken),
    (Text("text"), TextToken),
    (CodeText("code"), CodeTextToken),
    (Indentation("  "), IndentationToken),
    (Newline, NewlineToken),
    (Error("error"), ErrorToken),
    (EOF, EofToken),
  ]
  for pair in cases {
    let (token, kind) = pair
    assert_eq(token.to_raw(), kind.to_raw())
  }
}
