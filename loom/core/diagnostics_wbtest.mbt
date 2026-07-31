///|
fn test_offset(value : Int) -> TextOffset {
  try TextOffset(value) catch {
    _ => abort("expected valid offset")
  } noraise {
    offset => offset
  }
}

///|
fn test_range(start : Int, end : Int) -> TextRange {
  try TextRange::from_offsets(start, end) catch {
    _ => abort("expected valid range")
  } noraise {
    range => range
  }
}

///|
fn test_source(value : String) -> SourceId {
  SourceId(value)
}

///|
fn test_span(source_id : SourceId, start : Int, end : Int) -> SourceSpan {
  SourceSpan(source_id, test_range(start, end))
}

///|
fn test_label(
  style : LabelStyle,
  source_id : SourceId,
  start : Int,
  end : Int,
  message? : String? = None,
) -> DiagnosticLabel {
  DiagnosticLabel(style, test_span(source_id, start, end), message)
}

///|
fn source_diagnostic(
  message : String,
  source_id : SourceId,
  start : Int,
  end : Int,
  kind : Int,
) -> Diagnostic {
  let span = test_span(source_id, start, end)
  Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    code=Some(DiagnosticCode("parse.expected")),
    message~,
    labels=[DiagnosticLabel(LabelStyle::Primary, span, None)],
    token=Some(TokenEvidence(@seam.RawKind(kind), span)),
  )
}

///|
fn test_shift(
  set : DiagnosticSet,
  delta : Int,
  after : TextOffset,
) -> DiagnosticSet {
  try set.offset_by(test_source("test"), delta, after) catch {
    _ => abort("expected valid diagnostic offset")
  } noraise {
    set => set
  }
}

///|
fn test_diagnostic(
  message : String,
  start : Int,
  end : Int,
  kind : Int,
) -> Diagnostic {
  let span = test_span(test_source("test"), start, end)
  Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    code=Some(DiagnosticCode("parse.expected")),
    message~,
    labels=[DiagnosticLabel(LabelStyle::Primary, span, None)],
    token=Some(TokenEvidence(@seam.RawKind(kind), span)),
  )
}

///|
test "TextOffset and TextRange expose validated values" {
  let range = test_range(2, 5)
  inspect(range.start().value(), content="2")
  inspect(range.end().value(), content="5")
  inspect(range.length(), content="3")
}

///|
test "TextOffset and TextRange reject invalid inputs without aborting" {
  try TextOffset(-3) catch {
    NegativeTextOffset(value) => inspect(value, content="-3")
    _ => abort("expected offset error")
  } noraise {
    _ => abort("expected invalid offset")
  }
  try TextRange(test_offset(5), test_offset(2)) catch {
    InvalidTextRange(start, end) =>
      debug_inspect([start, end], content="[5, 2]")
    _ => abort("expected range error")
  } noraise {
    _ => abort("expected invalid range")
  }
}

///|
test "Diagnostic lexer_error_at reports invalid ranges as notes" {
  let diagnostic = Diagnostic::lexer_error_at(
    test_source("test"),
    "invalid",
    5,
    2,
    "bad-range",
  )
  inspect(diagnostic.format(), content="invalid")
  inspect(diagnostic.labels().length(), content="0")
  debug_inspect(
    diagnostic.notes(),
    content="[\"invalid lexer diagnostic range [5,2]: InvalidTextRange(5, 2)\"]",
  )
}

///|
test "Diagnostic formats raw offsets and line columns" {
  let diagnostic = test_diagnostic("expected value", 1, 5, 7)
  inspect(diagnostic.format(), content="expected value [1,5]")
  let index = LineIndex::new("ab\ncd")
  inspect(
    diagnostic.format_with_line_col(index),
    content="expected value [0:1,1:2]",
  )
}

///|
test "Diagnostic without primary range formats as message only" {
  let diagnostic = Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=Error,
    message="invalid token",
  )
  inspect(diagnostic.format(), content="invalid token")
  inspect(
    diagnostic.format_with_line_col(LineIndex::new("abc")),
    content="invalid token",
  )
}

///|
test "DiagnosticSet returns a defensive copy" {
  let set = DiagnosticSet::single(test_diagnostic("first", 0, 1, 1))
  let items = set.items()
  items.push(test_diagnostic("second", 2, 3, 2))
  inspect(items.length(), content="2")
  inspect(set.length(), content="1")
}

///|
test "DiagnosticSet offset_by zero returns an independent copy" {
  let set = DiagnosticSet::single(test_diagnostic("first", 0, 1, 1))
  let shifted = test_shift(set, 0, test_offset(0))
  shifted.push(test_diagnostic("second", 2, 3, 2))
  inspect(shifted.length(), content="2")
  inspect(set.length(), content="1")
}

///|
test "DiagnosticSet deduplicates exact duplicates" {
  let set = DiagnosticSet::empty()
  let diagnostic1 = test_diagnostic("expected", 1, 2, 7)
  let diagnostic2 = test_diagnostic("expected", 1, 2, 7)
  set.push(diagnostic1)
  set.push(diagnostic2)
  inspect(set.length(), content="1")
}

///|
test "DiagnosticSet preserves diagnostics with different token evidence" {
  let set = DiagnosticSet::empty()
  set.push(test_diagnostic("expected", 1, 2, 7))
  set.push(test_diagnostic("expected", 1, 2, 8))
  inspect(set.length(), content="2")
}

///|
test "DiagnosticSet formatting preserves order" {
  let set = DiagnosticSet::empty()
  set.push(test_diagnostic("first", 0, 1, 1))
  set.push(test_diagnostic("second", 3, 4, 2))
  debug_inspect(set.format(), content="[\"first [0,1]\", \"second [3,4]\"]")
}

///|
test "DiagnosticSet offset_by shifts ranges at or after boundary" {
  let set = DiagnosticSet::empty()
  set.push(test_diagnostic("before", 0, 1, 1))
  set.push(test_diagnostic("after", 3, 4, 2))
  let shifted = test_shift(set, 10, test_offset(2))
  debug_inspect(
    shifted.format(),
    content="[\"before [0,1]\", \"after [13,14]\"]",
  )
  match shifted.items()[1].token() {
    Some(token) => inspect(token.span().range().start().value(), content="13")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex shifts zero-width insertion boundary diagnostics" {
  let set = DiagnosticSet::single(test_diagnostic("eof", 2, 2, 1))
  let shifted = set.after_relex(
    SourceEdit(test_source("test"), Edit::insert(2, 3)),
    failure_context="test",
  )
  debug_inspect(shifted.format(), content="[\"eof [5,5]\"]")
  match shifted.items()[0].token() {
    Some(token) => inspect(token.span().range().start().value(), content="5")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex shifts ranges spanning insertion boundary" {
  let set = DiagnosticSet::single(test_diagnostic("span", 0, 2, 1))
  let shifted = set.after_relex(
    SourceEdit(test_source("test"), Edit::insert(1, 3)),
    failure_context="test",
  )
  debug_inspect(shifted.format(), content="[\"span [0,5]\"]")
  match shifted.items()[0].token() {
    Some(token) => inspect(token.span().range().end().value(), content="5")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex preserves ranges ending at insertion boundary" {
  let set = DiagnosticSet::single(test_diagnostic("before", 0, 2, 1))
  let shifted = set.after_relex(
    SourceEdit(test_source("test"), Edit::insert(2, 3)),
    failure_context="test",
  )
  debug_inspect(shifted.format(), content="[\"before [0,2]\"]")
  match shifted.items()[0].token() {
    Some(token) => inspect(token.span().range().end().value(), content="2")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex shifts secondary positional evidence" {
  let source = test_source("test")
  let primary = test_span(source, 0, 1)
  let diagnostic = Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=Error,
    message="secondary",
    labels=[
      DiagnosticLabel(LabelStyle::Primary, primary, None),
      test_label(LabelStyle::Secondary, source, 4, 5, message=Some("label")),
    ],
    token=Some(TokenEvidence(@seam.RawKind(9), test_span(source, 6, 7))),
  )
  let shifted = DiagnosticSet::single(diagnostic).after_relex(
    SourceEdit(source, Edit::replace(2, 4, 7)),
    failure_context="test",
  )
  let item = shifted.items()[0]
  inspect(item.labels()[0].span().range().start().value(), content="0")
  inspect(item.labels()[1].span().range().start().value(), content="7")
  match item.token() {
    Some(token) => inspect(token.span().range().start().value(), content="9")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex drops diagnostics with secondary stale evidence" {
  let source = test_source("test")
  let diagnostic = Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=Error,
    message="secondary",
    labels=[
      test_label(LabelStyle::Primary, source, 0, 1),
      test_label(LabelStyle::Secondary, source, 3, 4, message=Some("label")),
    ],
  )
  let shifted = DiagnosticSet::single(diagnostic).after_relex(
    SourceEdit(source, Edit::replace(2, 5, 8)),
    failure_context="test",
  )
  inspect(shifted.length(), content="0")
}

///|
test "DiagnosticSet after_relex reports invalid relex boundary" {
  let set = DiagnosticSet::single(test_diagnostic("before", 0, 1, 1))
  let shifted = set.after_relex(
    SourceEdit(test_source("test"), Edit::replace(0, -1, 2)),
    failure_context="test",
  )
  debug_inspect(
    shifted.format(),
    content="[\"failed to update lexer diagnostics after test: NegativeTextOffset(-1)\"]",
  )
}

///|
test "DiagnosticSet after_relex reports invalid shifted diagnostics" {
  let set = DiagnosticSet::single(test_diagnostic("before", 0, 1, 1))
  let shifted = set.after_relex(
    SourceEdit(test_source("test"), Edit::new(0, 0, -2)),
    failure_context="test",
  )
  debug_inspect(
    shifted.format(),
    content="[\"failed to shift lexer diagnostic after test: NegativeTextOffset(-2)\"]",
  )
}

///|
test "DiagnosticSet offset_by preserves invalid offset errors" {
  let set = DiagnosticSet::single(test_diagnostic("before", 0, 1, 1))
  try set.offset_by(test_source("test"), -10, test_offset(0)) catch {
    NegativeTextOffset(value) => inspect(value, content="-10")
    _ => abort("expected offset error")
  } noraise {
    _ => abort("expected invalid shifted offset")
  }
}

///|
test "LexResult with_starts records mismatched token and start arrays" {
  let result = LexResult::with_starts(
    [TokenInfo::new("A", 1)],
    [],
    diagnostics=DiagnosticSet::empty(),
  )
  debug_inspect(
    result.diagnostics().format(),
    content="[\"LexResult requires `starts` and `tokens` to be parallel\"]",
  )
}

///|
test "LexResult with_starts records negative start offsets" {
  let result = LexResult::with_starts(
    [TokenInfo::new("A", 1)],
    [-1],
    diagnostics=DiagnosticSet::empty(),
  )
  debug_inspect(
    result.diagnostics().format(),
    content="[\"LexResult received a negative start offset at index 0\"]",
  )
}

///|
test "LexResult with_starts records invalid start invariants" {
  let result = LexResult::with_starts(
    [TokenInfo::new("A", 2), TokenInfo::new("B", 1)],
    [0, 1],
    diagnostics=DiagnosticSet::empty(),
  )
  debug_inspect(
    result.diagnostics().format(),
    content="[\"LexResult received overlapping token spans at index 1\"]",
  )
}

///|
test "LexResult constructor validates generated starts" {
  let result = LexResult([TokenInfo::new("A", -1)])
  debug_inspect(
    result.diagnostics().format(),
    content="[\"LexResult received a negative token length at index 0\"]",
  )
}

///|
test "LexResult from_located_tokens fills blank gaps" {
  let result = LexResult::from_located_tokens(
    test_source("test"),
    "let x",
    [LocatedToken("LET", start=0, end=3), LocatedToken("IDENT", start=4, end=5)],
    gap_token=fn(_text, _start, _end) { "WS" },
  )
  let summary = result
    .tokens()
    .map(fn(info) { info.token + ":" + info.len.to_string() })
  debug_inspect(summary, content="[\"LET:3\", \"WS:1\", \"IDENT:1\"]")
  debug_inspect(result.starts(), content="[0, 3, 4]")
  inspect(result.diagnostics().is_empty(), content="true")
}

///|
test "LexResult from_located_tokens reports nonblank gaps" {
  let result = LexResult::from_located_tokens(
    test_source("test"),
    "ab",
    [LocatedToken("A", start=0, end=1)],
    gap_error_token=fn(_text, _start, _end) { "ERR" },
  )
  let summary = result
    .tokens()
    .map(fn(info) { info.token + ":" + info.len.to_string() })
  debug_inspect(summary, content="[\"A:1\", \"ERR:1\"]")
  debug_inspect(result.starts(), content="[0, 1]")
  debug_inspect(
    result.diagnostics().format(),
    content="[\"unlexed source gap [1,2]\"]",
  )
}

///|
test "LexResult from_located_tokens preserves zero-width tokens" {
  let result = LexResult::from_located_tokens(test_source("test"), "ab", [
    LocatedToken("A", start=0, end=1),
    LocatedToken("ASI", start=1, end=1),
    LocatedToken("B", start=1, end=2),
  ])
  let summary = result
    .tokens()
    .map(fn(info) { info.token + ":" + info.len.to_string() })
  debug_inspect(summary, content="[\"A:1\", \"ASI:0\", \"B:1\"]")
  debug_inspect(result.starts(), content="[0, 1, 1]")
}

///|
test "LexResult from_located_tokens preserves supplied diagnostics" {
  let diagnostics = DiagnosticSet::single(
    Diagnostic::lexer_error_at(
      test_source("test"),
      "external lexer error",
      0,
      1,
      "external",
    ),
  )
  let result = LexResult::from_located_tokens(
    test_source("test"),
    "a",
    [LocatedToken("A", start=0, end=1)],
    diagnostics~,
  )
  debug_inspect(
    result.diagnostics().format(),
    content="[\"external lexer error [0,1]\"]",
  )
}

///|
test "LexResult from_located_tokens diagnoses invalid external spans" {
  let negative_start = LexResult::from_located_tokens(
    test_source("test"),
    "a",
    [LocatedToken("A", start=-1, end=1)],
  )
  debug_inspect(negative_start.starts(), content="[0]")
  debug_inspect(
    negative_start.diagnostics().format(),
    content=(
      #|["LexResult received invalid located token span at index 0: [-1,1] for source length 1"]
    ),
  )
  let reversed = LexResult::from_located_tokens(
    test_source("test"),
    "abc",
    [LocatedToken("B", start=2, end=1)],
    diagnose_nonblank_gaps=false,
  )
  let summary = reversed
    .tokens()
    .map(fn(info) { info.token + ":" + info.len.to_string() })
  debug_inspect(summary, content="[\"B:0\"]")
  debug_inspect(
    reversed.diagnostics().format(),
    content=(
      #|["LexResult received invalid located token span at index 0: [2,1] for source length 3"]
    ),
  )
}

///|
test "source-aware labels preserve style span and message" {
  let source = test_source("file-a")
  let label = test_label(
    LabelStyle::Secondary,
    source,
    1,
    3,
    message=Some("related declaration"),
  )
  debug_inspect(label.style(), content="Secondary")
  inspect(label.span().source_id().value(), content="file-a")
  inspect(label.span().range().start().value(), content="1")
  inspect(label.span().range().end().value(), content="3")
  debug_inspect(label.message(), content="Some(\"related declaration\")")
}

///|
test "source-scoped offset shifts only labels in the edited source" {
  let source_a = test_source("a")
  let source_b = test_source("b")
  let diagnostic = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    message="two sources",
    labels=[
      test_label(LabelStyle::Primary, source_a, 4, 5),
      test_label(LabelStyle::Secondary, source_b, 4, 5),
    ],
  )
  let shifted = try
    DiagnosticSet::single(diagnostic).offset_by(source_a, 3, test_offset(4))
  catch {
    _ => abort("expected valid source-scoped shift")
  } noraise {
    set => set
  }
  let labels = shifted.items()[0].labels()
  inspect(labels[0].span().range().start().value(), content="7")
  inspect(labels[1].span().range().start().value(), content="4")
}

///|
test "source-scoped offset preserves token evidence when no edited-source label shifts" {
  let source_a = test_source("a")
  let source_b = test_source("b")
  let source_c = test_source("c")
  let diagnostic = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Hint,
    message="token alone does not select shift",
    labels=[
      test_label(LabelStyle::Primary, source_b, 4, 5),
      test_label(LabelStyle::Secondary, source_c, 7, 8),
    ],
    token=Some(TokenEvidence(@seam.RawKind(5), test_span(source_a, 4, 5))),
  )
  let shifted = try
    DiagnosticSet::single(diagnostic).offset_by(source_a, 3, test_offset(4))
  catch {
    _ => abort("expected valid source-scoped offset")
  } noraise {
    set => set
  }
  inspect(shifted.items()[0] == diagnostic, content="true")
}

///|
test "source A relex does not shift or drop source B labels" {
  let source_a = test_source("a")
  let source_b = test_source("b")
  let diagnostic = Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=Warning,
    message="belongs to b",
    labels=[test_label(LabelStyle::Primary, source_b, 2, 3)],
  )
  let updated = DiagnosticSet::single(diagnostic).after_relex(
    SourceEdit(source_a, Edit::replace(2, 4, 7)),
    failure_context="test",
  )
  inspect(updated.length(), content="1")
  let label = updated.items()[0].labels()[0]
  inspect(label.span().source_id().value(), content="b")
  inspect(label.span().range().start().value(), content="2")
  inspect(label.span().range().end().value(), content="3")
}

///|
test "same-source relex shifts labels and preserves style messages and token evidence" {
  let source_a = test_source("a")
  let primary = test_span(source_a, 4, 5)
  let diagnostic = Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=Error,
    message="shift",
    labels=[
      DiagnosticLabel(LabelStyle::Primary, primary, Some("primary message")),
      test_label(
        LabelStyle::Secondary,
        source_a,
        6,
        7,
        message=Some("secondary message"),
      ),
    ],
    token=Some(TokenEvidence(@seam.RawKind(9), primary)),
  )
  let updated = DiagnosticSet::single(diagnostic).after_relex(
    SourceEdit(source_a, Edit::replace(2, 4, 7)),
    failure_context="test",
  )
  let item = updated.items()[0]
  let labels = item.labels()
  debug_inspect(labels[0].style(), content="Primary")
  debug_inspect(labels[0].message(), content="Some(\"primary message\")")
  inspect(labels[0].span().range().start().value(), content="7")
  debug_inspect(labels[1].style(), content="Secondary")
  debug_inspect(labels[1].message(), content="Some(\"secondary message\")")
  inspect(labels[1].span().range().start().value(), content="9")
  match item.token() {
    Some(token) => {
      inspect(token.span().source_id().value(), content="a")
      inspect(token.span().range().start().value(), content="7")
    }
    None => abort("expected token evidence")
  }
}

///|
test "overlap with any same-source label drops the whole diagnostic" {
  let source_a = test_source("a")
  let source_b = test_source("b")
  let diagnostic = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    message="related cause became stale",
    labels=[
      test_label(LabelStyle::Primary, source_b, 8, 9),
      test_label(LabelStyle::Secondary, source_a, 3, 4),
    ],
  )
  let updated = DiagnosticSet::single(diagnostic).after_relex(
    SourceEdit(source_a, Edit::replace(2, 5, 7)),
    failure_context="test",
  )
  inspect(updated.length(), content="0")
}

///|
test "source-scoped relex keeps half-open insertion boundaries" {
  let source_a = test_source("a")
  let before = source_diagnostic("before", source_a, 0, 2, 1)
  let at = source_diagnostic("at", source_a, 2, 2, 2)
  let spanning = source_diagnostic("spanning", source_a, 0, 3, 3)
  let set = DiagnosticSet::empty()
  set.push(before)
  set.push(at)
  set.push(spanning)
  let updated = set.after_relex(
    SourceEdit(source_a, Edit::insert(2, 3)),
    failure_context="test",
  )
  inspect(
    updated.items()[0].labels()[0].span().range().end().value(),
    content="2",
  )
  inspect(
    updated.items()[1].labels()[0].span().range().start().value(),
    content="5",
  )
  inspect(
    updated.items()[2].labels()[0].span().range().end().value(),
    content="6",
  )
}

///|
test "multiple primary labels and sources remain explicit and distinct" {
  let source_a = test_source("a")
  let source_b = test_source("b")
  let labels = [
    test_label(LabelStyle::Primary, source_a, 1, 2, message=Some("a primary")),
    test_label(LabelStyle::Primary, source_b, 1, 2, message=Some("b primary")),
  ]
  let diagnostic = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    message="multi-primary",
    labels~,
  )
  let stored = diagnostic.labels()
  inspect(stored.length(), content="2")
  inspect(stored[0].span().source_id().value(), content="a")
  inspect(stored[1].span().source_id().value(), content="b")
}

///|
test "diagnostic arrays are defensively copied at construction and access" {
  let source = test_source("a")
  let labels = [test_label(LabelStyle::Primary, source, 0, 1)]
  let notes = ["first note"]
  let diagnostic = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    message="owned arrays",
    labels~,
    notes~,
  )
  labels.push(test_label(LabelStyle::Secondary, source, 2, 3))
  notes.push("second note")
  let exposed_labels = diagnostic.labels()
  let exposed_notes = diagnostic.notes()
  exposed_labels.push(test_label(LabelStyle::Secondary, source, 4, 5))
  exposed_notes.push("third note")
  inspect(diagnostic.labels().length(), content="1")
  inspect(diagnostic.notes().length(), content="1")
}

///|
test "equal numeric ranges in different sources do not deduplicate" {
  let set = DiagnosticSet::empty()
  set.push(source_diagnostic("same", test_source("a"), 1, 2, 7))
  set.push(source_diagnostic("same", test_source("b"), 1, 2, 7))
  inspect(set.length(), content="2")
}

///|
test "source identity remains distinct from producer identity" {
  let source_id = test_source("parser")
  let diagnostic = Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=Info,
    message="distinct domains",
    labels=[test_label(LabelStyle::Primary, source_id, 0, 0)],
  )
  inspect(diagnostic.source().name(), content="lexer")
  inspect(diagnostic.labels()[0].span().source_id().value(), content="parser")
}

///|
test "diagnostics can have no primary or labels" {
  let diagnostic = Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=Error,
    message="locationless",
  )
  inspect(diagnostic.labels().length(), content="0")
  inspect(diagnostic.format(), content="locationless")
}

///|
test "overlap with a same-source primary drops the whole diagnostic" {
  let source_a = test_source("a")
  let source_b = test_source("b")
  let diagnostic = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    message="primary became stale",
    labels=[
      test_label(LabelStyle::Primary, source_a, 3, 4),
      test_label(LabelStyle::Secondary, source_b, 8, 9),
    ],
  )
  let updated = DiagnosticSet::single(diagnostic).after_relex(
    SourceEdit(source_a, Edit::replace(2, 5, 7)),
    failure_context="test",
  )
  inspect(updated.length(), content="0")
}

///|
test "diagnostics with only B and C labels remain exactly unchanged by an A edit" {
  let source_a = test_source("a")
  let source_b = test_source("b")
  let source_c = test_source("c")
  let token_span = test_span(source_a, 3, 4)
  let diagnostic = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Hint,
    code=Some(DiagnosticCode("cross-source")),
    message="no labels in a",
    labels=[
      test_label(LabelStyle::Primary, source_b, 3, 4),
      test_label(LabelStyle::Secondary, source_c, 7, 8, message=Some("context")),
    ],
    notes=["keep"],
    token=Some(TokenEvidence(@seam.RawKind(5), token_span)),
  )
  let updated = DiagnosticSet::single(diagnostic).after_relex(
    SourceEdit(source_a, Edit::replace(2, 5, 7)),
    failure_context="test",
  )
  inspect(updated.items()[0] == diagnostic, content="true")
}

///|
test "property: edits affect only the selected source among two to four sources" {
  let seeds : Array[Int] = @quickcheck.samples(64)
  for seed in seeds {
    let magnitude = if seed < 0 { -(seed + 1) } else { seed }
    let source_count = 2 + magnitude % 3
    let edited_index = magnitude / 3 % source_count
    let sources = Array::makei(source_count, i => {
      test_source("source-" + i.to_string())
    })
    let labels = Array::makei(source_count, i => {
      test_label(
        if i == 0 {
          LabelStyle::Primary
        } else {
          LabelStyle::Secondary
        },
        sources[i],
        6 + i,
        7 + i,
        message=Some("label-" + i.to_string()),
      )
    })
    let diagnostic = Diagnostic(
      source=DiagnosticSource::parser(),
      severity=Error,
      message="property",
      labels~,
    )
    let updated = DiagnosticSet::single(diagnostic).after_relex(
      SourceEdit(sources[edited_index], Edit::insert(5, 3)),
      failure_context="property",
    )
    let actual = updated.items()[0].labels()
    for i in 0..<source_count {
      let expected_start = if i == edited_index { 9 + i } else { 6 + i }
      guard actual[i].span().source_id() == sources[i] &&
        actual[i].span().range().start().value() == expected_start &&
        actual[i].style() == labels[i].style() &&
        actual[i].message() == labels[i].message() else {
        abort(
          "source-scoped property failed for seed " +
          seed.to_string() +
          " at label " +
          i.to_string(),
        )
      }
    }
  }
}
