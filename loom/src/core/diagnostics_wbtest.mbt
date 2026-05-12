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
test "DiagnosticSet deduplicates by stable key and refreshes token evidence" {
  let set = DiagnosticSet::empty()
  set.push(test_diagnostic("expected", 1, 2, 7))
  set.push(test_diagnostic("expected", 1, 2, 8))
  inspect(set.length(), content="1")
  match set.items()[0].token {
    Some(token) => {
      let @seam.RawKind(kind) = token.kind
      inspect(kind, content="8")
    }
    None => abort("expected token evidence")
  }
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
