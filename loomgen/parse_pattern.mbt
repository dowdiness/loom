///|
/// Task #529: private pattern parser for the fail-closed #loom.pattern allowlist.
/// Parse a MoonBit `re`-shaped pattern into a private IR and return the first
/// malformed/unsupported error by position.
enum PatternError {
  Malformed(Int, String)
  Unsupported(Int, String)
}

///|

///|
enum Pattern {
  Empty
  Seq(Array[Pattern])
  Anchor
  Literal
  Escape
  Class
  Group(Pattern)
  Quantified(Pattern, Quantifier)
}

///|

///|
struct PatternParser {
  pattern : String
  length : Int
  mut pos : Int
  mut group_depth : Int
  mut first_malformed : Int?
  mut first_unsupported : Int?
}

///|
fn PatternParser::PatternParser(pattern : String) -> PatternParser {
  {
    pattern,
    length: pattern.length(),
    pos: 0,
    group_depth: 0,
    first_malformed: None,
    first_unsupported: None,
  }
}

///|
fn PatternParser::note_malformed(self : PatternParser, at : Int) -> Unit {
  match self.first_malformed {
    None => self.first_malformed = Some(at)
    Some(pos) => if at < pos { self.first_malformed = Some(at) }
  }
}

///|
fn PatternParser::note_unsupported(self : PatternParser, at : Int) -> Unit {
  match self.first_unsupported {
    None => self.first_unsupported = Some(at)
    Some(pos) => if at < pos { self.first_unsupported = Some(at) }
  }
}

///|
fn PatternParser::peek(self : PatternParser) -> UInt16? {
  if self.pos < self.length {
    Some(self.pattern[self.pos])
  } else {
    None
  }
}

///|
fn PatternParser::bump(self : PatternParser, count : Int) -> Unit {
  self.pos = self.pos + count
}

///|
fn parser_error_reason(
  pattern : String,
  pos : Int,
  unsupported : Bool,
  group_depth : Int,
) -> String {
  if unsupported {
    if pos < pattern.length() && pattern[pos] == '|' {
      return "alternation '|' is not supported; regex alternation is leftmost-match, not longest-match, so a branch that is a prefix of a later branch would under-match and split tokens. Use separate token variants or a character class"
    }
    if pos > 0 &&
      pattern[pos] == '?' &&
      (
        pattern[pos - 1] == '*' ||
        pattern[pos - 1] == '+' ||
        pattern[pos - 1] == '?' ||
        pattern[pos - 1] == '}'
      ) {
      return "lazy quantifier '" +
        pattern[pos - 1:pos + 1].to_owned() +
        "' is not supported; a longest-match lexer requires greedy quantifiers"
    }
    if pos + 1 < pattern.length() && pattern[pos] == '\\' {
      let esc = pattern[pos + 1]
      if esc == 'b' ||
        esc == 'B' ||
        esc == 'A' ||
        esc == 'z' ||
        esc == 'Z' ||
        esc == 'G' {
        return "zero-width assertion escape " +
          pattern[pos:pos + 2].to_owned() +
          " is not supported by the re dialect"
      }
      if esc == 'd' ||
        esc == 'D' ||
        esc == 's' ||
        esc == 'S' ||
        esc == 'w' ||
        esc == 'W' {
        return "character-class escape " +
          pattern[pos:pos + 2].to_owned() +
          " is not supported by the re dialect; use a POSIX class such as [[:digit:]], [[:space:]], or [[:alnum:]]"
      }
    }
    if pos + 1 < pattern.length() &&
      pattern[pos] == '(' &&
      pattern[pos + 1] == '?' {
      return "(?...) groups (non-capturing, flags, or lookaround) are not supported; use a plain group (..)"
    }
    "unsupported pattern"
  } else {
    if pos < pattern.length() {
      match pattern[pos] {
        '[' => return "unterminated character class '['"
        '{' => return "unterminated counted quantifier '{'"
        '\\' => return "pattern ends with an unescaped backslash"
        ')' => return "unbalanced ')'"
        '(' =>
          return "unbalanced '(' (" + group_depth.to_string() + " unclosed)"
        _ => ()
      }
    }
    "malformed pattern"
  }
}

///|
fn parse_pattern(pattern : String) -> Result[Pattern, PatternError] {
  let parser = PatternParser::PatternParser(pattern)
  let tree = parser.parse_top()
  if parser.pos < parser.length {
    parser.note_malformed(parser.pos)
  }
  match parser.first_malformed {
    Some(pos) =>
      Err(
        PatternError::Malformed(
          pos,
          parser_error_reason(pattern, pos, false, parser.group_depth),
        ),
      )
    None =>
      match parser.first_unsupported {
        Some(pos) =>
          Err(
            PatternError::Unsupported(
              pos,
              parser_error_reason(pattern, pos, true, 0),
            ),
          )
        None => Ok(tree)
      }
  }
}

///|
fn PatternParser::parse_top(self : PatternParser) -> Pattern {
  self.parse_alternation(false)
}

///|
fn PatternParser::parse_alternation(
  self : PatternParser,
  in_group : Bool,
) -> Pattern {
  let parts : Array[Pattern] = []
  while true {
    parts.push(self.parse_sequence(in_group))
    match self.peek() {
      Some('|') => {
        self.note_unsupported(self.pos)
        self.bump(1)
      }
      Some(')') =>
        if in_group {
          break
        } else {
          self.note_malformed(self.pos)
          self.bump(1)
        }
      Some(_) => break
      None => break
    }
  }
  if parts.length() == 1 {
    parts[0]
  } else {
    Seq(parts)
  }
}

///|
fn PatternParser::parse_sequence(
  self : PatternParser,
  in_group : Bool,
) -> Pattern {
  let parts : Array[Pattern] = []
  while self.pos < self.length {
    match self.peek() {
      Some('|') => break
      Some(')') => if in_group { break } else { break }
      Some(_) => parts.push(self.parse_atom())
      None => break
    }
  }
  if parts.length() == 0 {
    Empty
  } else if parts.length() == 1 {
    parts[0]
  } else {
    Seq(parts)
  }
}

///|
fn PatternParser::parse_atom(self : PatternParser) -> Pattern {
  let mut node = match self.peek() {
    Some('(') => self.parse_group()
    Some('[') => self.parse_class()
    Some('^') | Some('$') => {
      self.bump(1)
      Anchor
    }
    Some('\\') => self.parse_escape()
    Some('*') | Some('+') | Some('?') | Some('{') | Some('}') => {
      self.note_malformed(self.pos)
      self.bump(1)
      Literal
    }
    Some(_) => {
      self.bump(1)
      Literal
    }
    None => {
      self.note_malformed(self.pos)
      Empty
    }
  }
  node = self.parse_quantifier(node)
  node
}

///|
fn PatternParser::parse_group(self : PatternParser) -> Pattern {
  let open = self.pos
  self.bump(1)
  self.group_depth = self.group_depth + 1

  if self.pos < self.length && self.pattern[self.pos] == '?' {
    self.note_unsupported(open)
    self.bump(1)
  }

  let inner = self.parse_alternation(true)
  if self.pos < self.length && self.pattern[self.pos] == ')' {
    self.bump(1)
    self.group_depth = self.group_depth - 1
  } else {
    self.note_malformed(open)
  }
  Group(inner)
}
