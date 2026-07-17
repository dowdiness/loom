///|
/// Task #529: private pattern parser for the fail-closed #loom.pattern allowlist.
/// Parse a MoonBit `re`-shaped pattern into a private IR and return the first
/// malformed/unsupported error by position.
enum PatternError {
  Malformed(Int, String)
  Unsupported(Int, String)
}

///|
fn PatternError::to_string(self : PatternError) -> String {
  match self {
    Malformed(at, reason) => "Malformed(" + at.to_string() + "): " + reason
    Unsupported(at, reason) => "Unsupported(" + at.to_string() + "): " + reason
  }
}

///|
enum Pattern {
  Empty
  Seq(Array[Pattern])
  Anchor
  Literal
  Escape
  Class
  Group(Pattern)
  ZeroOrMore(Pattern)
  OneOrMore(Pattern)
  Optional(Pattern)
  Repeat(Pattern, Int, Int?)
}

///|
fn Pattern::is_nullable(self : Pattern) -> Bool {
  match self {
    Empty => true
    Seq(parts) => {
      let mut all = true
      for p in parts {
        if !p.is_nullable() {
          all = false
          break
        }
      }
      all
    }
    Anchor => true
    Literal => false
    Escape => false
    Class => false
    Group(inner) => inner.is_nullable()
    ZeroOrMore(_) => true
    OneOrMore(inner) => inner.is_nullable()
    Optional(_) => true
    Repeat(inner, min, _) => min == 0 || inner.is_nullable()
  }
}

///|
struct PatternParser {
  pattern : String
  length : Int
  mut pos : Int
  mut first_malformed : Int?
  mut first_unsupported : Int?
}

///|
fn PatternParser::PatternParser(pattern : String) -> PatternParser {
  {
    pattern,
    length: pattern.length(),
    pos: 0,
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
fn is_ascii_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ascii_alpha(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}


///|
fn is_hex_digit(c : UInt16) -> Bool {
  (c >= '0' && c <= '9') ||
    (c >= 'a' && c <= 'f') ||
    (c >= 'A' && c <= 'F')
}

///|
fn is_literal_meta_escape(c : UInt16) -> Bool {
  match c {
    '\\' | '.' | '[' | ']' | '(' | ')' | '{' | '}' | '*' | '+' | '?' | '|' |
    '^' | '$' | '-' => true
    _ => false
  }
}

///|
fn is_posix_name(name : String) -> Bool {
  if name.length() == 0 {
    false
  } else {
    let mut i = 0
    while i < name.length() {
      if !is_ascii_alpha(name[i]) {
        return false
      }
      i = i + 1
    }
    true
  }
}

///|
fn is_posix_allowed(name : String) -> Bool {
  match name {
    "alnum"
    | "alpha"
    | "ascii"
    | "blank"
    | "digit"
    | "lower"
    | "space"
    | "upper"
    | "word"
    | "xdigit" => true
    _ => false
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
    Some(pos) => Err(PatternError::Malformed(pos, "malformed pattern"))
    None =>
      match parser.first_unsupported {
        Some(pos) => Err(PatternError::Unsupported(pos, "unsupported pattern"))
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
fn PatternParser::parse_quantifier(
  self : PatternParser,
  node : Pattern,
) -> Pattern {
  let quantized = match self.peek() {
    Some('*') => {
      self.bump(1)
      ZeroOrMore(node)
    }
    Some('+') => {
      self.bump(1)
      OneOrMore(node)
    }
    Some('?') => {
      self.bump(1)
      Optional(node)
    }
    Some('{') => self.parse_counted(node)
    _ => node
  }

  match self.peek() {
    Some('?') => {
      self.note_unsupported(self.pos)
      self.bump(1)
    }
    _ => ()
  }
  quantized
}

///|
fn PatternParser::parse_counted(
  self : PatternParser,
  node : Pattern,
) -> Pattern {
  let open = self.pos
  self.bump(1)

  if self.pos >= self.length {
    self.note_malformed(open)
    return node
  }

  if !is_ascii_digit(self.pattern[self.pos]) {
    self.note_malformed(open)
    while self.pos < self.length && self.pattern[self.pos] != '}' {
      self.pos = self.pos + 1
    }
    if self.pos < self.length {
      self.pos = self.pos + 1
    }
    return node
  }

  let mut min = 0
  let mut i = self.pos
  while i < self.length && is_ascii_digit(self.pattern[i]) {
    min = min * 10 + (self.pattern[i].to_int() - '0'.to_int())
    i = i + 1
  }
  if i >= self.length {
    self.note_malformed(open)
    self.pos = i
    return node
  }

  if self.pattern[i] == '}' {
    self.pos = i + 1
    return Repeat(node, min, Some(min))
  }

  if self.pattern[i] != ',' {
    self.note_malformed(open)
    self.pos = i
    while self.pos < self.length && self.pattern[self.pos] != '}' {
      self.pos = self.pos + 1
    }
    if self.pos < self.length {
      self.pos = self.pos + 1
    }
    return node
  }

  i = i + 1
  if i >= self.length {
    self.note_malformed(open)
    self.pos = i
    return node
  }

  if self.pattern[i] == '}' {
    self.pos = i + 1
    return Repeat(node, min, None)
  }

  if !is_ascii_digit(self.pattern[i]) {
    self.note_malformed(open)
    self.pos = i
    while self.pos < self.length && self.pattern[self.pos] != '}' {
      self.pos = self.pos + 1
    }
    if self.pos < self.length {
      self.pos = self.pos + 1
    }
    return node
  }

  let mut max = 0
  let mut j = i
  while j < self.length && is_ascii_digit(self.pattern[j]) {
    max = max * 10 + (self.pattern[j].to_int() - '0'.to_int())
    j = j + 1
  }
  if j < self.length && self.pattern[j] == '}' {
    self.pos = j + 1
    return Repeat(node, min, Some(max))
  }

  self.note_malformed(open)
  self.pos = j
  while self.pos < self.length && self.pattern[self.pos] != '}' {
    self.pos = self.pos + 1
  }
  if self.pos < self.length {
    self.pos = self.pos + 1
  }
  node
}

///|
fn PatternParser::parse_escape(self : PatternParser) -> Pattern {
  if self.pos + 1 >= self.length {
    self.note_malformed(self.pos)
    self.bump(1)
    return Escape
  }

  let open = self.pos
  let esc = self.pattern[self.pos + 1]
  if esc == 'x' {
    if self.pos + 3 >= self.length {
      self.note_malformed(open)
      self.bump(self.length - self.pos)
    } else if is_hex_digit(self.pattern[self.pos + 2]) &&
      is_hex_digit(self.pattern[self.pos + 3]) {
      self.bump(4)
    } else {
      self.note_malformed(open)
      self.bump(4)
    }
    return Escape
  }

  match esc {
    'b' | 'B' | 'A' | 'z' | 'Z' | 'G' | 'd' | 'D' | 's' | 'S' | 'w' | 'W' => {
      self.note_unsupported(open)
      self.bump(2)
    }
    _ => {
      if is_literal_meta_escape(esc) {
        self.bump(2)
      } else {
        self.note_unsupported(open)
        self.bump(2)
      }
    }
  }
  Escape
}

///|
fn PatternParser::parse_class(self : PatternParser) -> Pattern {
  let open = self.pos
  self.bump(1)

  let mut has_content = false
  let mut prev_token = false
  let mut prev_dash = false

  if self.pos < self.length && self.pattern[self.pos] == '^' {
    self.bump(1)
  }

  while self.pos < self.length {
    match self.peek() {
      Some(']') => {
        if !has_content {
          self.note_malformed(open)
        }
        self.bump(1)
        return Class
      }
      Some('\\') => {
        let _ = self.parse_escape()
        has_content = true
        prev_token = true
        prev_dash = false
      }
      Some('-') => {
        if !has_content ||
          !prev_token ||
          (self.pos + 1 < self.length && self.pattern[self.pos + 1] == ']') ||
          prev_dash {
          self.note_malformed(self.pos)
        }
        self.bump(1)
        has_content = true
        prev_token = true
        prev_dash = true
      }
      Some('[') =>
        if self.pos + 1 < self.length && self.pattern[self.pos + 1] == ':' {
          match class_posix_class(self.pattern, self.pos) {
            Some((name, after)) => {
              if name.length() == 0 {
                self.note_malformed(self.pos)
              } else if !is_posix_name(name) {
                self.note_unsupported(self.pos)
              } else if !is_posix_allowed(name) {
                self.note_unsupported(self.pos)
              }
              self.pos = after
              has_content = true
              prev_token = true
              prev_dash = false
            }
            None => {
              match class_posix_name_prefix(self.pattern, self.pos) {
                Some((name, after_name)) => {
                  if is_posix_allowed(name) {
                    self.note_malformed(self.pos)
                    self.pos = after_name
                    has_content = true
                    prev_token = true
                    prev_dash = false
                  } else {
                    if !has_content {
                      self.note_malformed(self.pos)
                    }
                    self.bump(1)
                    has_content = true
                    prev_token = true
                    prev_dash = false
                  }
                }
                None => {
                  if !has_content {
                    self.note_malformed(self.pos)
                  }
                  self.bump(1)
                  has_content = true
                  prev_token = true
                  prev_dash = false
                }
              }
            }
          }
        } else {
          self.bump(1)
          has_content = true
          prev_token = true
          prev_dash = false
        }
      Some(_) => {
        self.bump(1)
        has_content = true
        prev_token = true
        prev_dash = false
      }
      None => break
    }
  }

  self.note_malformed(open)
  Class
}

///|
fn class_posix_name_prefix(pattern : String, pos : Int) -> (String, Int)? {
  let mut name_end = pos + 2
  if name_end >= pattern.length() || !is_ascii_alpha(pattern[name_end]) {
    None
  } else {
    while name_end < pattern.length() && is_ascii_alpha(pattern[name_end]) {
      name_end = name_end + 1
    }
    Some((pattern[pos + 2:name_end].to_owned(), name_end))
  }
}

///|
fn PatternParser::parse_group(self : PatternParser) -> Pattern {
  let open = self.pos
  self.bump(1)

  if self.pos < self.length && self.pattern[self.pos] == '?' {
    self.note_unsupported(open)
    self.bump(1)
  }

  let inner = self.parse_alternation(true)
  if self.pos < self.length && self.pattern[self.pos] == ')' {
    self.bump(1)
  } else {
    self.note_malformed(open)
  }
  Group(inner)
}

///|
fn class_posix_class(pattern : String, pos : Int) -> (String, Int)? {
  let mut i = pos + 2
  while i + 1 < pattern.length() {
    if pattern[i] == ':' && pattern[i + 1] == ']' {
      return Some((pattern[pos + 2:i].to_owned(), i + 2))
    }
    i = i + 1
  }
  None
}

