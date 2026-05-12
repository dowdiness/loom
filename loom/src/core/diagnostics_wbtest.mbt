///|
fn test_offset(value : Int) -> TextOffset {
  let result : Result[TextOffset, DiagnosticBuildError] = try? TextOffset(value)
  match result {
    Ok(offset) => offset
    Err(_) => abort("expected valid offset")
  }
}

///|
fn test_range(start : Int, end : Int) -> TextRange {
  let result : Result[TextRange, DiagnosticBuildError] = try? TextRange::from_offsets(
    start,
    end,
  )
  match result {
    Ok(range) => range
    Err(_) => abort("expected valid range")
  }
}

///|
fn test_shift(
  set : DiagnosticSet,
  delta : Int,
  after : TextOffset,
) -> DiagnosticSet {
  let result : Result[DiagnosticSet, DiagnosticBuildError] = try? set.offset_by(
    delta,
    after,
  )
  match result {
    Ok(set) => set
    Err(_) => abort("expected valid diagnostic offset")
  }
}

///|
fn test_diagnostic(
  message : String,
  start : Int,
  end : Int,
  kind : Int,
) -> Diagnostic {
  let range = test_range(start, end)
  Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    code=Some(DiagnosticCode("parse.expected")),
    message~,
    primary=Some(range),
    token=Some({ kind: @seam.RawKind(kind), range }),
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
  let offset_result : Result[TextOffset, DiagnosticBuildError] = try? TextOffset(
    -3,
  )
  match offset_result {
    Err(NegativeTextOffset(value)) => inspect(value, content="-3")
    Ok(_) => abort("expected invalid offset")
    Err(_) => abort("expected offset error")
  }
  let range_result : Result[TextRange, DiagnosticBuildError] = try? TextRange(
    test_offset(5),
    test_offset(2),
  )
  match range_result {
    Err(InvalidTextRange(start, end)) => inspect([start, end], content="[5, 2]")
    Ok(_) => abort("expected invalid range")
    Err(_) => abort("expected range error")
  }
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
  inspect(set.format(), content="[\"first [0,1]\", \"second [3,4]\"]")
}

///|
test "DiagnosticSet offset_by shifts ranges at or after boundary" {
  let set = DiagnosticSet::empty()
  set.push(test_diagnostic("before", 0, 1, 1))
  set.push(test_diagnostic("after", 3, 4, 2))
  let shifted = test_shift(set, 10, test_offset(2))
  inspect(shifted.format(), content="[\"before [0,1]\", \"after [13,14]\"]")
  match shifted.items()[1].token {
    Some(token) => inspect(token.range.start().value(), content="13")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex shifts zero-width insertion boundary diagnostics" {
  let set = DiagnosticSet::single(test_diagnostic("eof", 2, 2, 1))
  let shifted = set.after_relex(2, 2, 3, failure_context="test")
  inspect(shifted.format(), content="[\"eof [5,5]\"]")
  match shifted.items()[0].token {
    Some(token) => inspect(token.range.start().value(), content="5")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex shifts ranges spanning insertion boundary" {
  let set = DiagnosticSet::single(test_diagnostic("span", 0, 2, 1))
  let shifted = set.after_relex(1, 1, 3, failure_context="test")
  inspect(shifted.format(), content="[\"span [0,5]\"]")
  match shifted.items()[0].token {
    Some(token) => inspect(token.range.end().value(), content="5")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex preserves ranges ending at insertion boundary" {
  let set = DiagnosticSet::single(test_diagnostic("before", 0, 2, 1))
  let shifted = set.after_relex(2, 2, 3, failure_context="test")
  inspect(shifted.format(), content="[\"before [0,2]\"]")
  match shifted.items()[0].token {
    Some(token) => inspect(token.range.end().value(), content="2")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex shifts secondary positional evidence" {
  let diagnostic = Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=Error,
    message="secondary",
    primary=Some(test_range(0, 1)),
    labels=[{ range: test_range(4, 5), message: Some("label") }],
    token=Some({ kind: @seam.RawKind(9), range: test_range(6, 7) }),
  )
  let shifted = DiagnosticSet::single(diagnostic).after_relex(
    2,
    4,
    3,
    failure_context="test",
  )
  let item = shifted.items()[0]
  inspect(item.primary.unwrap().start().value(), content="0")
  inspect(item.labels[0].range.start().value(), content="7")
  match item.token {
    Some(token) => inspect(token.range.start().value(), content="9")
    None => abort("expected token evidence")
  }
}

///|
test "DiagnosticSet after_relex drops diagnostics with secondary stale evidence" {
  let diagnostic = Diagnostic(
    source=DiagnosticSource::lexer(),
    severity=Error,
    message="secondary",
    primary=Some(test_range(0, 1)),
    labels=[{ range: test_range(3, 4), message: Some("label") }],
  )
  let shifted = DiagnosticSet::single(diagnostic).after_relex(
    2,
    5,
    3,
    failure_context="test",
  )
  inspect(shifted.length(), content="0")
}

///|
test "DiagnosticSet offset_by preserves invalid offset errors" {
  let set = DiagnosticSet::single(test_diagnostic("before", 0, 1, 1))
  let result : Result[DiagnosticSet, DiagnosticBuildError] = try? set.offset_by(
    -10,
    test_offset(0),
  )
  match result {
    Err(NegativeTextOffset(value)) => inspect(value, content="-10")
    Ok(_) => abort("expected invalid shifted offset")
    Err(_) => abort("expected offset error")
  }
}

///|
test "LexResult with_starts records mismatched token and start arrays" {
  let result = LexResult::with_starts(
    [TokenInfo::new("A", 1)],
    [],
    diagnostics=DiagnosticSet::empty(),
  )
  inspect(
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
  inspect(
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
  inspect(
    result.diagnostics().format(),
    content="[\"LexResult received overlapping token spans at index 1\"]",
  )
}

///|
test "LexResult constructor validates generated starts" {
  let result = LexResult([TokenInfo::new("A", -1)])
  inspect(
    result.diagnostics().format(),
    content="[\"LexResult received a negative token length at index 0\"]",
  )
}
