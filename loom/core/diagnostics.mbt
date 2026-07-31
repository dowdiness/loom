// Parse data types: token information, diagnostics, and lex errors.

///|
/// Generic position-independent token. T is the language-specific token type.
/// Positions are stored externally in TokenBuffer's `starts` array.
pub struct TokenInfo[T] {
  token : T
  len : Int // length in code units
} derive(Debug, Eq)

///|
/// Token with explicit UTF-16 source offsets from an external lexer.
///
/// `start` and `end` are code-unit offsets into the source string used to build
/// a `LexResult`. Zero-width tokens are valid when `start == end`.
pub struct LocatedToken[T] {
  priv token : T
  priv start : Int
  priv end : Int
} derive(Debug, Eq)

///|
pub fn[T] LocatedToken::LocatedToken(
  token : T,
  start~ : Int,
  end~ : Int,
) -> LocatedToken[T] {
  { token, start, end }
}

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
  LexResult::with_starts(tokens, build_starts(tokens), diagnostics~)
}

///|
pub fn[T] LexResult::with_starts(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics~ : DiagnosticSet,
) -> LexResult[T] {
  let diagnostics = diagnostics.copy()
  validate_lex_result_starts(tokens, starts, diagnostics)
  { tokens, starts, diagnostics }
}

///|
/// Build a `LexResult` from tokens that already carry source offsets.
///
/// This is the recommended adapter for production lexers that return positioned
/// tokens rather than Loom's position-independent `TokenInfo` stream. Blank
/// gaps are skipped unless `gap_token` is supplied. Non-blank gaps emit a lexer
/// diagnostic by default and can also be represented by `gap_error_token`.
pub fn[T] LexResult::from_located_tokens(
  source_id : SourceId,
  source : String,
  located_tokens : Array[LocatedToken[T]],
  gap_token? : (StringView, Int, Int) -> T,
  gap_error_token? : (StringView, Int, Int) -> T,
  diagnostics? : DiagnosticSet = DiagnosticSet::empty(),
  gap_error_code? : String = "loom.lex.unlexed_gap",
  diagnose_nonblank_gaps? : Bool = true,
) -> LexResult[T] {
  let diagnostics = diagnostics.copy()
  let tokens : Array[TokenInfo[T]] = []
  let starts : Array[Int] = []
  let source_len = source.length()
  let cursor = for located in located_tokens; cursor = 0, index = 0 {
    validate_located_token_span(
      diagnostics,
      index,
      located.start,
      located.end,
      source_len,
    )
    let start = clamp_lex_offset(located.start, source_len)
    let clamped_end = clamp_lex_offset(located.end, source_len)
    let end = if clamped_end < start { start } else { clamped_end }
    if start > cursor {
      push_located_gap(
        source_id, source, tokens, starts, cursor, start, diagnostics, gap_token,
        gap_error_token, gap_error_code, diagnose_nonblank_gaps,
      )
    }
    starts.push(start)
    tokens.push(TokenInfo::new(located.token, end - start))
    continue if end > cursor { end } else { cursor }, index + 1
  } nobreak {
    cursor
  }
  if cursor < source_len {
    push_located_gap(
      source_id, source, tokens, starts, cursor, source_len, diagnostics, gap_token,
      gap_error_token, gap_error_code, diagnose_nonblank_gaps,
    )
  }
  LexResult::with_starts(tokens, starts, diagnostics~)
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
fn[T] push_located_gap(
  source_id : SourceId,
  source : String,
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  start : Int,
  end : Int,
  diagnostics : DiagnosticSet,
  gap_token : ((StringView, Int, Int) -> T)?,
  gap_error_token : ((StringView, Int, Int) -> T)?,
  gap_error_code : String,
  diagnose_nonblank_gaps : Bool,
) -> Unit {
  let gap_text = source.view(start_offset=start, end_offset=end)
  if gap_text.is_blank() {
    match gap_token {
      Some(make_gap_token) => {
        starts.push(start)
        tokens.push(
          TokenInfo::new(make_gap_token(gap_text, start, end), end - start),
        )
      }
      None => ()
    }
  } else {
    if diagnose_nonblank_gaps {
      diagnostics.push(
        Diagnostic::lexer_error_at(
          source_id, "unlexed source gap", start, end, gap_error_code,
        ),
      )
    }
    match gap_error_token {
      Some(make_gap_error_token) => {
        starts.push(start)
        tokens.push(
          TokenInfo::new(
            make_gap_error_token(gap_text, start, end),
            end - start,
          ),
        )
      }
      None => ()
    }
  }
}

///|
fn validate_located_token_span(
  diagnostics : DiagnosticSet,
  index : Int,
  start : Int,
  end : Int,
  source_len : Int,
) -> Unit {
  if start < 0 ||
    end < 0 ||
    end < start ||
    start > source_len ||
    end > source_len {
    diagnostics.push(
      Diagnostic::lexer_error(
        "LexResult received invalid located token span at index " +
        index.to_string() +
        ": [" +
        start.to_string() +
        "," +
        end.to_string() +
        "] for source length " +
        source_len.to_string(),
      ),
    )
  }
}

///|
fn clamp_lex_offset(offset : Int, source_len : Int) -> Int {
  if offset < 0 {
    0
  } else if offset > source_len {
    source_len
  } else {
    offset
  }
}

///|
fn[T] validate_lex_result_starts(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics : DiagnosticSet,
) -> Unit {
  if starts.length() != tokens.length() {
    diagnostics.push(
      Diagnostic::lexer_error(
        "LexResult requires `starts` and `tokens` to be parallel",
      ),
    )
  }
  let count = if starts.length() < tokens.length() {
    starts.length()
  } else {
    tokens.length()
  }
  for i = 0; i < count; i = i + 1 {
    if starts[i] < 0 {
      diagnostics.push(
        Diagnostic::lexer_error(
          "LexResult received a negative start offset at index " + i.to_string(),
        ),
      )
    }
    if tokens[i].len < 0 {
      diagnostics.push(
        Diagnostic::lexer_error(
          "LexResult received a negative token length at index " + i.to_string(),
        ),
      )
    }
    if i > 0 {
      let prev_end = starts[i - 1] + tokens[i - 1].len
      if starts[i] < starts[i - 1] {
        diagnostics.push(
          Diagnostic::lexer_error(
            "LexResult requires non-decreasing starts at index " + i.to_string(),
          ),
        )
      } else if starts[i] < prev_end {
        diagnostics.push(
          Diagnostic::lexer_error(
            "LexResult received overlapping token spans at index " +
            i.to_string(),
          ),
        )
      }
    }
  }
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
pub fn TextOffset::TextOffset(
  value : Int,
) -> TextOffset raise DiagnosticBuildError {
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
/// Stable identity of source text within a diagnostic/provider snapshot.
pub struct SourceId {
  priv value : String
} derive(Eq, Debug, Hash)

///|
pub fn SourceId::SourceId(value : String) -> SourceId {
  { value, }
}

///|
pub fn SourceId::value(self : SourceId) -> String {
  self.value
}

///|
/// Source-qualified half-open UTF-16 code-unit range.
pub struct SourceSpan {
  priv source_id : SourceId
  priv range : TextRange
} derive(Eq, Debug, Hash)

///|
pub fn SourceSpan::SourceSpan(
  source_id : SourceId,
  range : TextRange,
) -> SourceSpan {
  { source_id, range }
}

///|
pub fn SourceSpan::source_id(self : SourceSpan) -> SourceId {
  self.source_id
}

///|
pub fn SourceSpan::range(self : SourceSpan) -> TextRange {
  self.range
}

///|
fn SourceSpan::offset_by(
  self : SourceSpan,
  edited_source : SourceId,
  delta : Int,
  after : TextOffset,
) -> SourceSpan raise DiagnosticBuildError {
  if self.source_id != edited_source || delta == 0 {
    self
  } else {
    SourceSpan(self.source_id, self.range.offset_by(delta, after))
  }
}

///|
/// Source-qualified parser edit used by diagnostic invalidation and replay.
pub struct SourceEdit {
  priv source_id : SourceId
  priv edit : Edit
} derive(Eq, Debug)

///|
pub fn SourceEdit::SourceEdit(source_id : SourceId, edit : Edit) -> SourceEdit {
  { source_id, edit }
}

///|
pub fn SourceEdit::source_id(self : SourceEdit) -> SourceId {
  self.source_id
}

///|
pub fn SourceEdit::edit(self : SourceEdit) -> Edit {
  self.edit
}

///|
pub(all) enum LabelStyle {
  Primary
  Secondary
} derive(Eq, Debug, Hash)

///|
pub struct TokenEvidence {
  priv kind : @seam.RawKind
  priv span : SourceSpan
} derive(Eq, Debug)

///|
pub fn TokenEvidence::TokenEvidence(
  kind : @seam.RawKind,
  span : SourceSpan,
) -> TokenEvidence {
  { kind, span }
}

///|
pub fn TokenEvidence::kind(self : TokenEvidence) -> @seam.RawKind {
  self.kind
}

///|
pub fn TokenEvidence::span(self : TokenEvidence) -> SourceSpan {
  self.span
}

///|
fn TokenEvidence::offset_by(
  self : TokenEvidence,
  edited_source : SourceId,
  delta : Int,
  after : TextOffset,
) -> TokenEvidence raise DiagnosticBuildError {
  TokenEvidence(self.kind, self.span.offset_by(edited_source, delta, after))
}

///|
pub struct DiagnosticLabel {
  priv style : LabelStyle
  priv span : SourceSpan
  priv message : String?
} derive(Eq, Debug)

///|
pub fn DiagnosticLabel::DiagnosticLabel(
  style : LabelStyle,
  span : SourceSpan,
  message : String?,
) -> DiagnosticLabel {
  { style, span, message }
}

///|
pub fn DiagnosticLabel::style(self : DiagnosticLabel) -> LabelStyle {
  self.style
}

///|
pub fn DiagnosticLabel::span(self : DiagnosticLabel) -> SourceSpan {
  self.span
}

///|
pub fn DiagnosticLabel::message(self : DiagnosticLabel) -> String? {
  self.message
}

///|
fn DiagnosticLabel::offset_by(
  self : DiagnosticLabel,
  edited_source : SourceId,
  delta : Int,
  after : TextOffset,
) -> DiagnosticLabel raise DiagnosticBuildError {
  DiagnosticLabel(
    self.style,
    self.span.offset_by(edited_source, delta, after),
    self.message,
  )
}

///|
/// Token-erased diagnostic record for parser, lexer, and editor consumers.
pub struct Diagnostic {
  priv source : DiagnosticSource
  priv severity : DiagnosticSeverity
  priv code : DiagnosticCode?
  priv message : String
  priv labels : Array[DiagnosticLabel]
  priv notes : Array[String]
  priv token : TokenEvidence?
} derive(Eq, Debug)

///|
pub fn Diagnostic::Diagnostic(
  source~ : DiagnosticSource,
  severity~ : DiagnosticSeverity,
  message~ : String,
  code? : DiagnosticCode? = None,
  labels? : Array[DiagnosticLabel] = [],
  notes? : Array[String] = [],
  token? : TokenEvidence? = None,
) -> Diagnostic {
  {
    source,
    severity,
    code,
    message,
    labels: labels.copy(),
    notes: notes.copy(),
    token,
  }
}

///|
pub fn Diagnostic::source(self : Diagnostic) -> DiagnosticSource {
  self.source
}

///|
pub fn Diagnostic::severity(self : Diagnostic) -> DiagnosticSeverity {
  self.severity
}

///|
pub fn Diagnostic::code(self : Diagnostic) -> DiagnosticCode? {
  self.code
}

///|
pub fn Diagnostic::message(self : Diagnostic) -> String {
  self.message
}

///|
pub fn Diagnostic::labels(self : Diagnostic) -> Array[DiagnosticLabel] {
  self.labels.copy()
}

///|
pub fn Diagnostic::notes(self : Diagnostic) -> Array[String] {
  self.notes.copy()
}

///|
pub fn Diagnostic::token(self : Diagnostic) -> TokenEvidence? {
  self.token
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
  source_id : SourceId,
  message : String,
  start : Int,
  end : Int,
  code : String,
) -> Diagnostic {
  let (labels, notes) : (Array[DiagnosticLabel], Array[String]) = try
    TextRange::from_offsets(start, end)
  catch {
    err =>
      (
        [],
        [
          "invalid lexer diagnostic range [" +
          start.to_string() +
          "," +
          end.to_string() +
          "]: " +
          @debug.to_string(err),
        ],
      )
  } noraise {
    range =>
      (
        [
          DiagnosticLabel(
            LabelStyle::Primary,
            SourceSpan(source_id, range),
            None,
          ),
        ],
        [],
      )
  }
  Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=DiagnosticSeverity::Error,
    code=Some(DiagnosticCode(code)),
    message~,
    labels~,
    notes~,
  )
}

///|
fn Diagnostic::single_primary_span(self : Diagnostic) -> SourceSpan? {
  let primary = self.labels.filter(label => label.style == LabelStyle::Primary)
  if primary.length() == 1 {
    Some(primary[0].span)
  } else {
    None
  }
}

///|
pub fn Diagnostic::line_range(
  self : Diagnostic,
  index : LineIndex,
) -> LineRange? {
  match self.single_primary_span() {
    Some(span) =>
      Some(index.line_range(span.range.start.value, span.range.end.value))
    None => None
  }
}

///|
pub fn Diagnostic::format(self : Diagnostic) -> String {
  match self.single_primary_span() {
    Some(span) =>
      self.message +
      " [" +
      span.range.start.value.to_string() +
      "," +
      span.range.end.value.to_string() +
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
  edited_source : SourceId,
  delta : Int,
  after : TextOffset,
) -> Diagnostic raise DiagnosticBuildError {
  if delta == 0 {
    return self
  }
  let labels = self.labels.map(label => {
    label.offset_by(edited_source, delta, after)
  })
  let token = if labels == self.labels {
    self.token
  } else {
    match self.token {
      Some(token) => Some(token.offset_by(edited_source, delta, after))
      None => None
    }
  }
  Diagnostic(
    source=self.source,
    severity=self.severity,
    code=self.code,
    message=self.message,
    labels~,
    notes=self.notes,
    token~,
  )
}

///|
fn diagnostic_same_key(a : Diagnostic, b : Diagnostic) -> Bool {
  a == b
}

///|
fn parser_diagnostic_same_key(a : Diagnostic, b : Diagnostic) -> Bool {
  // Parser replay can refresh token evidence without changing the logical error.
  a.source == b.source &&
  a.severity == b.severity &&
  a.code == b.code &&
  a.message == b.message &&
  a.labels == b.labels
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
  match
    self.items.search_by(existing => diagnostic_same_key(existing, diagnostic)) {
    Some(index) => self.items[index] = diagnostic
    None => self.items.push(diagnostic)
  }
}

///|
fn DiagnosticSet::push_parser_unique(
  self : DiagnosticSet,
  diagnostic : Diagnostic,
) -> Bool {
  match
    self.items.search_by(existing => {
      parser_diagnostic_same_key(existing, diagnostic)
    }) {
    Some(index) => {
      self.items[index] = diagnostic
      false
    }
    None => {
      self.items.push(diagnostic)
      true
    }
  }
}

///|
pub fn DiagnosticSet::add_all(
  self : DiagnosticSet,
  other : DiagnosticSet,
) -> Unit {
  for diagnostic in other.items {
    self.push(diagnostic)
  }
}

///|
pub fn DiagnosticSet::is_empty(self : DiagnosticSet) -> Bool {
  self.items.is_empty()
}

///|
pub fn DiagnosticSet::length(self : DiagnosticSet) -> Int {
  self.items.length()
}

///|
pub fn DiagnosticSet::truncate(self : DiagnosticSet, length : Int) -> Unit {
  let target = length.clamp(min=0, max=self.items.length())
  self.items.truncate(target)
}

///|
pub fn DiagnosticSet::format(self : DiagnosticSet) -> Array[String] {
  self.items.map(Diagnostic::format)
}

///|
pub fn DiagnosticSet::format_with_line_col(
  self : DiagnosticSet,
  index : LineIndex,
) -> Array[String] {
  self.items.map(diagnostic => diagnostic.format_with_line_col(index))
}

///|
pub fn DiagnosticSet::offset_by(
  self : DiagnosticSet,
  edited_source : SourceId,
  delta : Int,
  after : TextOffset,
) -> DiagnosticSet raise DiagnosticBuildError {
  if delta == 0 {
    return self.copy()
  }
  {
    items: self.items.map(diagnostic => {
      diagnostic.offset_by(edited_source, delta, after)
    }),
  }
}

///|
priv enum RelexDiagnosticDisposition {
  RelexPreserve
  RelexShift
  RelexDrop
}

///|
fn combine_relex_disposition(
  current : RelexDiagnosticDisposition,
  next : RelexDiagnosticDisposition,
) -> RelexDiagnosticDisposition {
  match current {
    RelexDrop => RelexDrop
    RelexShift =>
      match next {
        RelexDrop => RelexDrop
        _ => RelexShift
      }
    RelexPreserve => next
  }
}

///|
fn TextRange::relex_disposition(
  self : TextRange,
  edit : Edit,
) -> RelexDiagnosticDisposition {
  let old_start = edit.start
  let old_end = edit.old_end()
  if old_start == old_end &&
    (self.start.value >= old_end || self.end.value > old_end) {
    RelexShift
  } else if old_start < old_end &&
    self.start.value < old_end &&
    self.end.value > old_start {
    RelexDrop
  } else if self.start.value >= old_end {
    RelexShift
  } else {
    RelexPreserve
  }
}

///|
fn Diagnostic::relex_disposition(
  self : Diagnostic,
  source_edit : SourceEdit,
) -> RelexDiagnosticDisposition {
  self.labels.fold(init=RelexPreserve, (disposition, label) => {
    if label.span.source_id == source_edit.source_id {
      combine_relex_disposition(
        disposition,
        label.span.range.relex_disposition(source_edit.edit),
      )
    } else {
      disposition
    }
  })
}

///|
/// Preserve diagnostics outside a successfully re-lexed old range.
/// Diagnostics with an edited-source label inside the old range are stale and
/// dropped; diagnostics with edited-source labels after the old range are
/// shifted. Other-source labels never affect disposition and remain unchanged.
/// For insertion ranges, zero-width labels at the insertion point and ranges
/// crossing it are treated as post-edit evidence; ranges ending at the
/// insertion point remain before the edit.
pub fn DiagnosticSet::after_relex(
  self : DiagnosticSet,
  source_edit : SourceEdit,
  failure_context~ : String,
) -> DiagnosticSet {
  let result = DiagnosticSet::empty()
  try TextOffset(source_edit.edit.old_end()) catch {
    err => {
      result.push(
        Diagnostic::lexer_error(
          "failed to update lexer diagnostics after " +
          failure_context +
          ": " +
          @debug.to_string(err),
        ),
      )
      result
    }
  } noraise {
    after => {
      for diagnostic in self.items {
        match diagnostic.relex_disposition(source_edit) {
          RelexPreserve => result.push(diagnostic)
          RelexShift =>
            result.push_shifted_after_relex(
              diagnostic, source_edit, after, failure_context,
            )
          RelexDrop => ()
        }
      }
      result
    }
  }
}

///|
fn DiagnosticSet::push_shifted_after_relex(
  self : DiagnosticSet,
  diagnostic : Diagnostic,
  source_edit : SourceEdit,
  after : TextOffset,
  failure_context : String,
) -> Unit {
  try
    diagnostic.offset_by(source_edit.source_id, source_edit.edit.delta(), after)
  catch {
    err =>
      self.push(
        Diagnostic::lexer_error(
          "failed to shift lexer diagnostic after " +
          failure_context +
          ": " +
          @debug.to_string(err),
        ),
      )
  } noraise {
    diagnostic => self.push(diagnostic)
  }
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
