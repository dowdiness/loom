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
  priv tokens : Array[TokenInfo[T]]
  priv starts : Array[Int]
  priv diagnostics : DiagnosticSet
} derive(Eq, Debug)

///|
/// A lexer adapter violated the structural contract of a token/start result.
/// This describes adapter output, not malformed user source.
pub(all) suberror LexResultError {
  TokenStartCountMismatch(Int, Int)
  NegativeTokenLength(Int, Int)
  NegativeStart(Int, Int)
  DecreasingStart(Int, Int, Int)
  OverlappingToken(Int, Int, Int)
  NegativeConvergence(Int)
} derive(Eq, Debug)

///|
pub fn[T] LexResult::LexResult(
  tokens : Array[TokenInfo[T]],
  diagnostics? : DiagnosticSet = DiagnosticSet::empty(),
) -> LexResult[T] raise LexResultError {
  let tokens = tokens.copy()
  let starts = build_starts(tokens)
  lex_result_from_owned(tokens, starts, diagnostics=diagnostics.copy())
}

///|
pub fn[T] LexResult::with_starts(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics~ : DiagnosticSet,
) -> LexResult[T] raise LexResultError {
  let tokens = tokens.copy()
  let starts = starts.copy()
  lex_result_from_owned(tokens, starts, diagnostics=diagnostics.copy())
}

///|
fn[T] lex_result_from_owned(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics~ : DiagnosticSet,
) -> LexResult[T] raise LexResultError {
  validate_lex_result_starts(tokens, starts)
  { tokens, starts, diagnostics }
}

///|
fn[T] lex_result_from_owned_or_abort(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics~ : DiagnosticSet,
) -> LexResult[T] {
  lex_result_from_owned(tokens, starts, diagnostics~) catch {
    error =>
      abort(
        "internal LexResult producer violated its ownership contract: " +
        @debug.to_string(error),
      )
  }
}

///|
fn[T] lex_result_from_owned_tokens_or_abort(
  tokens : Array[TokenInfo[T]],
  diagnostics~ : DiagnosticSet,
) -> LexResult[T] {
  let starts = build_starts(tokens)
  lex_result_from_owned_or_abort(tokens, starts, diagnostics~)
}

///|
fn[T] lex_result_from_callback_or_abort(
  tokens : Array[TokenInfo[T]],
  diagnostics~ : DiagnosticSet,
) -> LexResult[T] {
  LexResult::LexResult(tokens, diagnostics~) catch {
    error =>
      abort(
        "tokenizer adapter returned an invalid token stream: " +
        @debug.to_string(error),
      )
  }
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
  let located_tokens = located_tokens.copy()
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
    let clamped_start = clamp_lex_offset(located.start, source_len)
    let clamped_end = clamp_lex_offset(located.end, source_len)
    if clamped_start < cursor {
      diagnostics.push(
        lexer_diagnostic(
          "LexResult received overlapping located token span at index " +
          index.to_string() +
          ": start " +
          clamped_start.to_string() +
          " precedes repaired cursor " +
          cursor.to_string(),
        ),
      )
    }
    let start = if clamped_start < cursor { cursor } else { clamped_start }
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
  lex_result_from_owned(tokens, starts, diagnostics~) catch {
    error =>
      abort(
        "LexResult::from_located_tokens produced an invalid repaired result: " +
        @debug.to_string(error),
      )
  }
}

///|
pub fn[T] LexResult::length(self : LexResult[T]) -> Int {
  self.tokens.length()
}

///|
pub fn[T] LexResult::token_at(
  self : LexResult[T],
  index : Int,
) -> TokenInfo[T]? {
  self.tokens.get(index)
}

///|
pub fn[T] LexResult::start_at(self : LexResult[T], index : Int) -> Int? {
  self.starts.get(index)
}

///|
pub fn[T] LexResult::iter(self : LexResult[T]) -> Iter[(TokenInfo[T], Int)] {
  let mut index = 0
  Iter::new(() => {
    if index < self.tokens.length() {
      let pair = (self.tokens[index], self.starts[index])
      index = index + 1
      Some(pair)
    } else {
      None
    }
  })
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
        lexer_diagnostic_at(
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
      lexer_diagnostic(
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
) -> Unit raise LexResultError {
  guard starts.length() == tokens.length() else {
    raise TokenStartCountMismatch(tokens.length(), starts.length())
  }
  for i in 0..<tokens.length() {
    guard tokens[i].len >= 0 else {
      raise NegativeTokenLength(i, tokens[i].len)
    }
    guard starts[i] >= 0 else { raise NegativeStart(i, starts[i]) }
    if i > 0 {
      guard starts[i] >= starts[i - 1] else {
        raise DecreasingStart(i, starts[i - 1], starts[i])
      }
      let previous_end = starts[i - 1] + tokens[i - 1].len
      guard starts[i] >= previous_end else {
        raise OverlappingToken(i, previous_end, starts[i])
      }
    }
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
pub fn lexer_diagnostic(message : String) -> Diagnostic {
  @diagnostic.ToDiagnostic::to_diagnostic(LexError(message))
}

///|
pub fn lexer_diagnostic_at(
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
    origin=DiagnosticOrigin("lexer"),
    severity=DiagnosticSeverity::Error,
    code=Some(DiagnosticCode(code)),
    message~,
    labels~,
    notes~,
  )
}

///|
fn diagnostic_same_key(a : Diagnostic, b : Diagnostic) -> Bool {
  a == b
}

///|
fn parser_diagnostic_same_key(a : Diagnostic, b : Diagnostic) -> Bool {
  // Parser replay can refresh a diagnostic without changing the logical error.
  a.origin() == b.origin() &&
  a.severity() == b.severity() &&
  a.code() == b.code() &&
  a.message() == b.message() &&
  a.labels() == b.labels() &&
  a.fixes() == b.fixes()
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
fn text_range_relex_disposition(
  range : TextRange,
  edit : Edit,
) -> RelexDiagnosticDisposition {
  let old_start = edit.start
  let old_end = edit.old_end()
  if old_start == old_end &&
    (range.start().value() >= old_end || range.end().value() > old_end) {
    RelexShift
  } else if old_start < old_end &&
    range.start().value() < old_end &&
    range.end().value() > old_start {
    RelexDrop
  } else if range.start().value() >= old_end {
    RelexShift
  } else {
    RelexPreserve
  }
}

///|
fn diagnostic_relex_disposition(
  diagnostic : Diagnostic,
  source_edit : SourceEdit,
) -> RelexDiagnosticDisposition {
  diagnostic
  .labels()
  .fold(init=RelexPreserve, (disposition, label) => {
    if label.span().source_id() == source_edit.source_id {
      combine_relex_disposition(
        disposition,
        text_range_relex_disposition(label.span().range(), source_edit.edit),
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
        lexer_diagnostic(
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
        match diagnostic_relex_disposition(diagnostic, source_edit) {
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
        lexer_diagnostic(
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
pub impl @diagnostic.ToDiagnostic for LexError with fn to_diagnostic(self) {
  let LexError(message) = self
  Diagnostic(
    origin=DiagnosticOrigin("lexer"),
    severity=DiagnosticSeverity::Error,
    code=Some(DiagnosticCode("lex-error")),
    message~,
  )
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
