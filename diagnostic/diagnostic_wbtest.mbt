///|
fn diagnostic_test_offset(value : Int) -> TextOffset {
  try TextOffset(value) catch {
    _ => abort("expected valid diagnostic offset")
  } noraise {
    offset => offset
  }
}

///|
fn diagnostic_test_range(start : Int, end : Int) -> TextRange {
  try TextRange::from_offsets(start, end) catch {
    _ => abort("expected valid diagnostic range")
  } noraise {
    range => range
  }
}

///|
fn diagnostic_test_label(
  style : LabelStyle,
  source_id : SourceId,
  start : Int,
  end : Int,
  message? : String? = None,
) -> DiagnosticLabel {
  DiagnosticLabel(
    style,
    SourceSpan(source_id, diagnostic_test_range(start, end)),
    message,
  )
}

///|
test "text offsets and ranges validate their boundaries" {
  let range = diagnostic_test_range(2, 5)
  inspect(range.start().value(), content="2")
  inspect(range.end().value(), content="5")
  inspect(range.length(), content="3")
  try TextOffset(-3) catch {
    NegativeTextOffset(value) => inspect(value, content="-3")
    _ => abort("expected offset error")
  } noraise {
    _ => abort("expected invalid offset")
  }
  try TextRange(diagnostic_test_offset(5), diagnostic_test_offset(2)) catch {
    InvalidTextRange(start, end) =>
      debug_inspect([start, end], content="[5, 2]")
    _ => abort("expected range error")
  } noraise {
    _ => abort("expected invalid range")
  }
}

///|
test "diagnostics format offsets and derived line columns" {
  let source_id = SourceId("main")
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Error,
    message="unexpected token",
    labels=[diagnostic_test_label(Primary, source_id, 2, 5)],
  )
  inspect(diagnostic.format(), content="unexpected token [2,5]")
  inspect(
    diagnostic.format_with_line_col(LineIndex::new("a\nbcd")),
    content="unexpected token [1:0,1:3]",
  )
  let locationless = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Error,
    message="locationless",
  )
  inspect(locationless.format(), content="locationless")
}

///|
test "labels preserve source style and message across source-scoped shifts" {
  let source_a = SourceId("a")
  let source_b = SourceId("b")
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("lexer"),
    severity=Warning,
    message="two sources",
    labels=[
      diagnostic_test_label(Primary, source_a, 3, 5, message=Some("primary")),
      diagnostic_test_label(Secondary, source_b, 3, 5, message=Some("related")),
    ],
  )
  let shifted = try
    diagnostic.offset_by(source_a, 2, diagnostic_test_offset(3))
  catch {
    _ => abort("expected a valid source-scoped shift")
  } noraise {
    shifted => shifted
  }
  let labels = shifted.labels()
  inspect(labels[0].span().range().start().value(), content="5")
  inspect(labels[1].span().range().start().value(), content="3")
  debug_inspect(labels[0].message(), content="Some(\"primary\")")
  inspect(labels[1].style() is Secondary, content="true")
}

///|
test "diagnostic arrays are defensively copied" {
  let source_id = SourceId("main")
  let labels = [diagnostic_test_label(Primary, source_id, 0, 1)]
  let notes = ["note"]
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Info,
    message="owned arrays",
    labels~,
    notes~,
  )
  labels.push(diagnostic_test_label(Secondary, source_id, 1, 2))
  notes.push("external")
  let exposed_labels = diagnostic.labels()
  let exposed_notes = diagnostic.notes()
  exposed_labels.push(diagnostic_test_label(Secondary, source_id, 2, 3))
  exposed_notes.push("exposed")
  inspect(diagnostic.labels().length(), content="1")
  debug_inspect(diagnostic.notes(), content="[\"note\"]")
}

///|
test "source identity remains distinct from diagnostic origin" {
  let source_id = SourceId("lexer")
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("lexer"),
    severity=Hint,
    message="distinct concepts",
    labels=[diagnostic_test_label(Primary, source_id, 0, 0)],
  )
  inspect(diagnostic.origin().name(), content="lexer")
  inspect(
    diagnostic.labels()[0].span().source_id() == source_id,
    content="true",
  )
}
