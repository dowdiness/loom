///|
fn is_ascii_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ascii_alpha(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_hex_digit(c : UInt16) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn is_literal_meta_escape(c : UInt16) -> Bool {
  match c {
    '\\'
    | '"'
    | '.'
    | '['
    | ']'
    | '('
    | ')'
    | '{'
    | '}'
    | '*'
    | '+'
    | '?'
    | '|'
    | '^'
    | '$'
    | '-' => true
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
    't' | 'r' | 'n' => self.bump(2)
    _ =>
      if is_literal_meta_escape(esc) {
        self.bump(2)
      } else {
        self.note_unsupported(open)
        self.bump(2)
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
              } else if !is_posix_name(name) || !is_posix_allowed(name) {
                self.note_unsupported(self.pos)
              }
              self.pos = after
              has_content = true
              prev_token = true
              prev_dash = false
            }
            None =>
              match class_posix_name_prefix(self.pattern, self.pos) {
                Some((name, after_name)) =>
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
fn class_posix_class(pattern : String, pos : Int) -> (String, Int)? {
  let mut i = pos + 2
  while i + 1 < pattern.length() {
    if pattern[i] == ']' {
      return None
    }
    if pattern[i] == ':' && pattern[i + 1] == ']' {
      return Some((pattern[pos + 2:i].to_owned(), i + 2))
    }
    i = i + 1
  }
  None
}
