///|
/// Task #529: private pattern parser for the fail-closed #loom.pattern allowlist.
/// Parse a MoonBit `re`-shaped pattern into a private IR and return the first
/// malformed/unsupported error by position.
enum PatternError {
  Malformed(Int, String)
  Unsupported(Int, String)
}

///|
suberror CountError {
  OutOfRange
  Reversed
}

///|
struct Count {
  value : Int
}

///|
struct CountRange {
  min : Count
  max : Count
}

///|
enum RepeatBounds {
  Exact(Count)
  AtLeast(Count)
  Range(CountRange)
}

///|
enum QuantifierKind {
  ZeroOrMore
  OneOrMore
  Optional
  Counted(RepeatBounds)
}

///|
struct Quantifier {
  kind : QuantifierKind
}

///|
fn Quantifier::Quantifier(kind : QuantifierKind) -> Quantifier {
  { kind, }
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
  Quantified(Pattern, Quantifier)
}

///|
fn Count::Count(value : Int) -> Count raise CountError {
  guard value >= 0 && value <= counted_quantifier_limit() else {
    raise OutOfRange
  }
  { value, }
}

///|
fn checked_count(value : Int) -> Count? {
  try Count(value) catch {
    _ => None
  } noraise {
    count => Some(count)
  }
}

///|
fn Count::to_int(self : Count) -> Int {
  self.value
}

///|
fn CountRange::CountRange(
  min : Count,
  max : Count,
) -> CountRange raise CountError {
  let range = { min, max }
  guard range.min.to_int() <= range.max.to_int() else { raise Reversed }
  range
}

///|
fn RepeatBounds::exact(value : Int) -> RepeatBounds? {
  match checked_count(value) {
    Some(count) => Some(Exact(count))
    None => None
  }
}

///|
fn RepeatBounds::at_least(value : Int) -> RepeatBounds? {
  match checked_count(value) {
    Some(count) => Some(AtLeast(count))
    None => None
  }
}

///|
fn RepeatBounds::range(min : Int, max : Int) -> RepeatBounds? {
  match (checked_count(min), checked_count(max)) {
    (Some(min), Some(max)) =>
      try CountRange(min, max) catch {
        _ => None
      } noraise {
        bounds => Some(Range(bounds))
      }
    _ => None
  }
}

///|
fn RepeatBounds::min(self : RepeatBounds) -> Int {
  match self {
    Exact(min) | AtLeast(min) => min.to_int()
    Range(bounds) => bounds.min.to_int()
  }
}

///|
fn Quantifier::is_nullable(self : Quantifier) -> Bool {
  match self.kind {
    ZeroOrMore | Optional => true
    OneOrMore => false
    Counted(bounds) => bounds.min() == 0
  }
}

///|
fn Pattern::is_nullable(self : Pattern) -> Bool {
  match self {
    Empty => true
    Seq(parts) => {
      let mut all = true
      for part in parts {
        if !part.is_nullable() {
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
    Quantified(inner, quantifier) =>
      quantifier.is_nullable() || inner.is_nullable()
  }
}

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
fn PatternParser::parse_quantifier(
  self : PatternParser,
  node : Pattern,
) -> Pattern {
  let quantized = match self.peek() {
    Some('*') => {
      self.bump(1)
      Quantified(node, Quantifier(ZeroOrMore))
    }
    Some('+') => {
      self.bump(1)
      Quantified(node, Quantifier(OneOrMore))
    }
    Some('?') => {
      self.bump(1)
      Quantified(node, Quantifier(Optional))
    }
    Some('{') => self.parse_counted(node)
    _ => node
  }
  match self.peek() {
    Some('?') => {
      let pos = self.pos
      self.bump(1)
      self.note_unsupported(pos)
    }
    _ => ()
  }
  quantized
}

///|
/// MoonBit `re` rejects counted bounds above 256 (native compile probe).
fn counted_quantifier_limit() -> Int {
  256
}

///|
fn decimal_to_int(pattern : String, start : Int, end : Int) -> Int {
  let mut value = 0
  let mut i = start
  while i < end {
    value = value * 10 + (pattern[i].to_int() - '0'.to_int())
    i = i + 1
  }
  value
}

///|
fn decimal_leq(
  pattern : String,
  left_start : Int,
  left_end : Int,
  right_start : Int,
  right_end : Int,
) -> Bool {
  let mut left = left_start
  while left < left_end && pattern[left] == '0' {
    left = left + 1
  }
  let mut right = right_start
  while right < right_end && pattern[right] == '0' {
    right = right + 1
  }
  let left_length = left_end - left
  let right_length = right_end - right
  if left_length != right_length {
    return left_length < right_length
  }
  let mut i = 0
  while i < left_length {
    if pattern[left + i] != pattern[right + i] {
      return pattern[left + i] < pattern[right + i]
    }
    i = i + 1
  }
  true
}

///|
fn decimal_leq_limit(
  pattern : String,
  start : Int,
  end : Int,
  limit : String,
) -> Bool {
  let mut value = start
  while value < end && pattern[value] == '0' {
    value = value + 1
  }
  let value_length = end - value
  if value_length != limit.length() {
    return value_length < limit.length()
  }
  let mut i = 0
  while i < value_length {
    if pattern[value + i] != limit[i] {
      return pattern[value + i] < limit[i]
    }
    i = i + 1
  }
  true
}

///|
fn PatternParser::scan_decimal_end(self : PatternParser, from : Int) -> Int {
  let mut end = from
  while end < self.length && is_ascii_digit(self.pattern[end]) {
    end = end + 1
  }
  end
}

///|
fn PatternParser::recover_counted(
  self : PatternParser,
  node : Pattern,
  open : Int,
  from : Int,
) -> Pattern {
  self.note_malformed(open)
  self.pos = from
  while self.pos < self.length && self.pattern[self.pos] != '}' {
    self.pos = self.pos + 1
  }
  if self.pos < self.length {
    self.pos = self.pos + 1
  }
  node
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
    return self.recover_counted(node, open, self.pos)
  }

  let min_start = self.pos
  let min_end = self.scan_decimal_end(min_start)
  if min_start == min_end ||
    !decimal_leq_limit(
      self.pattern,
      min_start,
      min_end,
      counted_quantifier_limit().to_string(),
    ) {
    return self.recover_counted(node, open, min_end)
  }
  let min = decimal_to_int(self.pattern, min_start, min_end)
  if min_end >= self.length {
    self.note_malformed(open)
    self.pos = min_end
    return node
  }

  if self.pattern[min_end] == '}' {
    self.pos = min_end + 1
    let result = match RepeatBounds::exact(min) {
      Some(bounds) => Quantified(node, Quantifier(Counted(bounds)))
      None => {
        self.note_malformed(open)
        node
      }
    }
    return result
  }
  if self.pattern[min_end] != ',' {
    return self.recover_counted(node, open, min_end)
  }

  let max_start = min_end + 1
  if max_start >= self.length {
    self.note_malformed(open)
    self.pos = max_start
    return node
  }
  if self.pattern[max_start] == '}' {
    self.pos = max_start + 1
    let result = match RepeatBounds::at_least(min) {
      Some(bounds) => Quantified(node, Quantifier(Counted(bounds)))
      None => {
        self.note_malformed(open)
        node
      }
    }
    return result
  }
  if !is_ascii_digit(self.pattern[max_start]) {
    return self.recover_counted(node, open, max_start)
  }

  let max_end = self.scan_decimal_end(max_start)
  if max_end >= self.length || self.pattern[max_end] != '}' {
    return self.recover_counted(node, open, max_end)
  }
  if !decimal_leq_limit(
      self.pattern,
      max_start,
      max_end,
      counted_quantifier_limit().to_string(),
    ) ||
    !decimal_leq(self.pattern, min_start, min_end, max_start, max_end) {
    self.pos = max_end + 1
    self.note_malformed(open)
    return node
  }

  let max = decimal_to_int(self.pattern, max_start, max_end)
  self.pos = max_end + 1
  let result = match RepeatBounds::range(min, max) {
    Some(bounds) => Quantified(node, Quantifier(Counted(bounds)))
    None => {
      self.note_malformed(open)
      node
    }
  }
  result
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
