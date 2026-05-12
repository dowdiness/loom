// Parse data types: token information, diagnostics, and lex errors.

///|
/// Generic position-independent token. T is the language-specific token type.
/// Positions are stored externally in TokenBuffer's `starts` array.
pub struct TokenInfo[T] {
  token : T
  len : Int // length in code units
} derive(Debug, Eq)

///|
/// Structured result of lexing a source string.
///
/// `tokens` remain position-independent. `starts` records the source offset of
/// each token and must be parallel to `tokens`.
pub struct LexResult[T] {
  tokens : Array[TokenInfo[T]]
  starts : Array[Int]
  diagnostics : DiagnosticSet
} derive(Eq, Debug)

///|
pub fn[T] LexResult::LexResult(
  tokens : Array[TokenInfo[T]],
  diagnostics? : DiagnosticSet = DiagnosticSet::empty(),
) -> LexResult[T] {
  { tokens, starts: build_starts(tokens), diagnostics }
}

///|
pub fn[T] LexResult::with_starts(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics~ : DiagnosticSet,
) -> LexResult[T] {
  { tokens, starts, diagnostics }
}

///|
pub fn[T] LexResult::tokens(self : LexResult[T]) -> Array[TokenInfo[T]] {
  self.tokens.copy()
}

///|
pub fn[T] LexResult::starts(self : LexResult[T]) -> Array[Int] {
  self.starts.copy()
}

///|
pub fn[T] LexResult::diagnostics(self : LexResult[T]) -> DiagnosticSet {
  self.diagnostics.copy()
}

///|
/// Type-safe UTF-16 code-unit offset into a source string.
pub struct TextOffset {
  priv value : Int
} derive(Eq, Debug, Hash, Compare)

///|
pub(all) suberror DiagnosticBuildError {
  NegativeTextOffset(Int)
  InvalidTextRange(Int, Int)
} derive(Debug)

///|
pub fn TextOffset::TextOffset(value : Int) -> TextOffset raise DiagnosticBuildError {
  guard value >= 0 else { raise NegativeTextOffset(value) }
  { value, }
}

///|
pub fn TextOffset::value(self : TextOffset) -> Int {
  self.value
}

///|
pub fn TextOffset::offset_by(
  self : TextOffset,
  delta : Int,
) -> TextOffset raise DiagnosticBuildError {
  TextOffset(self.value + delta)
}

///|
fn TextOffset::offset_if_at_or_after(
  self : TextOffset,
  delta : Int,
  after : TextOffset,
) -> TextOffset raise DiagnosticBuildError {
  if self.value >= after.value {
    self.offset_by(delta)
  } else {
    self
  }
}

///|
/// Half-open UTF-16 code-unit source range `[start, end)`.
pub struct TextRange {
  priv start : TextOffset
  priv end : TextOffset
} derive(Eq, Debug, Hash, Compare)

///|
pub fn TextRange::TextRange(
  start : TextOffset,
  end : TextOffset,
) -> TextRange raise DiagnosticBuildError {
  guard end.value >= start.value else {
    raise InvalidTextRange(start.value, end.value)
  }
  { start, end }
}

///|
pub fn TextRange::from_offsets(
  start : Int,
  end : Int,
) -> TextRange raise DiagnosticBuildError {
  TextRange(TextOffset(start), TextOffset(end))
}

///|
pub fn TextRange::start(self : TextRange) -> TextOffset {
  self.start
}

///|
pub fn TextRange::end(self : TextRange) -> TextOffset {
  self.end
}

///|
pub fn TextRange::length(self : TextRange) -> Int {
  self.end.value - self.start.value
}

///|
pub fn TextRange::offset_by(
  self : TextRange,
  delta : Int,
  after : TextOffset,
) -> TextRange raise DiagnosticBuildError {
  if delta == 0 {
    return self
  }
  TextRange(
    self.start.offset_if_at_or_after(delta, after),
    self.end.offset_if_at_or_after(delta, after),
  )
}

///|
fn format_line_col(pos : LineCol) -> String {
  pos.line.to_string() + ":" + pos.column.to_string()
}

///|
pub enum DiagnosticSeverity {
  Error
  Warning
  Info
  Hint
} derive(Eq, Debug)

///|
pub fn DiagnosticSeverity::all() -> Array[DiagnosticSeverity] {
  [Error, Warning, Info, Hint]
}

///|
pub struct DiagnosticSource {
  priv name : String
} derive(Eq, Debug, Hash)

///|
pub fn DiagnosticSource::DiagnosticSource(name : String) -> DiagnosticSource {
  { name, }
}

///|
pub fn DiagnosticSource::parser() -> DiagnosticSource {
  DiagnosticSource("parser")
}

///|
pub fn DiagnosticSource::lexer() -> DiagnosticSource {
  DiagnosticSource("lexer")
}

///|
pub fn DiagnosticSource::name(self : DiagnosticSource) -> String {
  self.name
}

///|
pub struct DiagnosticCode {
  priv value : String
} derive(Eq, Debug, Hash)

///|
pub fn DiagnosticCode::DiagnosticCode(value : String) -> DiagnosticCode {
  { value, }
}

///|
pub fn DiagnosticCode::value(self : DiagnosticCode) -> String {
  self.value
}

///|
pub struct TokenEvidence {
  kind : @seam.RawKind
  range : TextRange
} derive(Eq, Debug)

///|
pub fn TokenEvidence::offset_by(
  self : TokenEvidence,
  delta : Int,
  after : TextOffset,
) -> TokenEvidence raise DiagnosticBuildError {
  { kind: self.kind, range: self.range.offset_by(delta, after) }
}

///|
pub struct DiagnosticLabel {
  range : TextRange
  message : String?
} derive(Eq, Debug)

///|
pub fn DiagnosticLabel::offset_by(
  self : DiagnosticLabel,
  delta : Int,
  after : TextOffset,
) -> DiagnosticLabel raise DiagnosticBuildError {
  { range: self.range.offset_by(delta, after), message: self.message }
}

///|
/// Token-erased diagnostic record for parser, lexer, and editor consumers.
pub struct Diagnostic {
  source : DiagnosticSource
  severity : DiagnosticSeverity
  code : DiagnosticCode?
  message : String
  primary : TextRange?
  labels : Array[DiagnosticLabel]
  notes : Array[String]
  token : TokenEvidence?
} derive(Eq, Debug)

///|
pub fn Diagnostic::Diagnostic(
  source~ : DiagnosticSource,
  severity~ : DiagnosticSeverity,
  message~ : String,
  code? : DiagnosticCode? = None,
  primary? : TextRange? = None,
  labels? : Array[DiagnosticLabel] = [],
  notes? : Array[String] = [],
  token? : TokenEvidence? = None,
) -> Diagnostic {
  { source, severity, code, message, primary, labels, notes, token }
}

///|
pub fn Diagnostic::lexer_error(message : String) -> Diagnostic {
  Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=DiagnosticSeverity::Error,
    code=Some(DiagnosticCode("lex-error")),
    message~,
  )
}

///|
pub fn Diagnostic::lexer_error_at(
  message : String,
  start : Int,
  end : Int,
  code : String,
) -> Diagnostic {
  let range_result : Result[TextRange, DiagnosticBuildError] = try? TextRange::from_offsets(
    start,
    end,
  )
  let (range, notes) = match range_result {
    Ok(range) => (Some(range), [])
    Err(err) =>
      (
        None,
        [
          "invalid lexer diagnostic range [" +
          start.to_string() +
          "," +
          end.to_string() +
          "]: " +
          @debug.to_string(err),
        ],
      )
  }
  Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=DiagnosticSeverity::Error,
    code=Some(DiagnosticCode(code)),
    message~,
    primary=range,
    notes~,
  )
}

///|
pub fn Diagnostic::line_range(
  self : Diagnostic,
  index : LineIndex,
) -> LineRange? {
  match self.primary {
    Some(range) => Some(index.line_range(range.start.value, range.end.value))
    None => None
  }
}

///|
pub fn Diagnostic::format(self : Diagnostic) -> String {
  match self.primary {
    Some(range) =>
      self.message +
      " [" +
      range.start.value.to_string() +
      "," +
      range.end.value.to_string() +
      "]"
    None => self.message
  }
}

///|
pub fn Diagnostic::format_with_line_col(
  self : Diagnostic,
  index : LineIndex,
) -> String {
  match self.line_range(index) {
    Some(range) =>
      self.message +
      " [" +
      format_line_col(range.start) +
      "," +
      format_line_col(range.end) +
      "]"
    None => self.message
  }
}

///|
pub fn Diagnostic::offset_by(
  self : Diagnostic,
  delta : Int,
  after : TextOffset,
) -> Diagnostic raise DiagnosticBuildError {
  if delta == 0 {
    return self
  }
  let primary = match self.primary {
    Some(range) => Some(range.offset_by(delta, after))
    None => None
  }
  let labels : Array[DiagnosticLabel] = []
  for label in self.labels {
    labels.push(label.offset_by(delta, after))
  }
  let token = match self.token {
    Some(token) => Some(token.offset_by(delta, after))
    None => None
  }
  {
    source: self.source,
    severity: self.severity,
    code: self.code,
    message: self.message,
    primary,
    labels,
    notes: self.notes.copy(),
    token,
  }
}

///|
fn diagnostic_same_key(a : Diagnostic, b : Diagnostic) -> Bool {
  a.source == b.source &&
  a.severity == b.severity &&
  a.code == b.code &&
  a.message == b.message &&
  a.primary == b.primary
}

///|
pub struct DiagnosticSet {
  priv items : Array[Diagnostic]
} derive(Eq, Debug)

///|
pub fn DiagnosticSet::empty() -> DiagnosticSet {
  { items: [] }
}

///|
pub fn DiagnosticSet::single(diagnostic : Diagnostic) -> DiagnosticSet {
  { items: [diagnostic] }
}

///|
pub fn DiagnosticSet::items(self : DiagnosticSet) -> Array[Diagnostic] {
  self.items.copy()
}

///|
pub fn DiagnosticSet::copy(self : DiagnosticSet) -> DiagnosticSet {
  { items: self.items.copy() }
}

///|
pub fn[A] DiagnosticSet::map(
  self : DiagnosticSet,
  f : (Diagnostic) -> A,
) -> Array[A] {
  self.items.map(f)
}

///|
pub fn DiagnosticSet::push(
  self : DiagnosticSet,
  diagnostic : Diagnostic,
) -> Unit {
  for i, existing in self.items.iter2() {
    if diagnostic_same_key(existing, diagnostic) {
      self.items[i] = diagnostic
      return
    }
  }
  self.items.push(diagnostic)
}

///|
pub fn DiagnosticSet::extend(
  self : DiagnosticSet,
  other : DiagnosticSet,
) -> Unit {
  for diagnostic in other.items {
    self.push(diagnostic)
  }
}

///|
pub fn DiagnosticSet::is_empty(self : DiagnosticSet) -> Bool {
  self.items.length() == 0
}

///|
pub fn DiagnosticSet::length(self : DiagnosticSet) -> Int {
  self.items.length()
}

///|
pub fn DiagnosticSet::truncate(self : DiagnosticSet, length : Int) -> Unit {
  let target = if length < 0 {
    0
  } else if length > self.items.length() {
    self.items.length()
  } else {
    length
  }
  while self.items.length() > target {
    ignore(self.items.pop())
  }
}

///|
pub fn DiagnosticSet::format(self : DiagnosticSet) -> Array[String] {
  let result : Array[String] = []
  for diagnostic in self.items {
    result.push(diagnostic.format())
  }
  result
}

///|
pub fn DiagnosticSet::format_with_line_col(
  self : DiagnosticSet,
  index : LineIndex,
) -> Array[String] {
  let result : Array[String] = []
  for diagnostic in self.items {
    result.push(diagnostic.format_with_line_col(index))
  }
  result
}

///|
pub fn DiagnosticSet::offset_by(
  self : DiagnosticSet,
  delta : Int,
  after : TextOffset,
) -> DiagnosticSet raise DiagnosticBuildError {
  if delta == 0 {
    return self
  }
  let result = DiagnosticSet::empty()
  for diagnostic in self.items {
    result.push(diagnostic.offset_by(delta, after))
  }
  result
}

///|
/// Lex error raised by a tokenize_fn when the source contains unrecognizable input.
/// Generic replacement for language-specific tokenization error types.
pub(all) suberror LexError {
  LexError(String)
}

///|
/// Construct a TokenInfo. Use this from outside the core package.
pub fn[T] TokenInfo::new(token : T, len : Int) -> TokenInfo[T] {
  { token, len }
}

///|
priv struct ReusedErrorSpan {
  start : Int
  end : Int
}
