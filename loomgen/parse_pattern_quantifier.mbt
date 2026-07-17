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
/// MoonBit `re` rejects counted bounds above 256 (native compile probe).
fn counted_quantifier_limit() -> Int {
  256
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
