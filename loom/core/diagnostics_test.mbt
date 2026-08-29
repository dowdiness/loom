///|
test "label styles are constructible across the public package boundary" {
  let primary = LabelStyle::Primary
  let secondary = LabelStyle::Secondary
  inspect(primary is LabelStyle::Primary, content="true")
  inspect(secondary is LabelStyle::Secondary, content="true")
}

///|
test "LexResult with_starts owns constructor arrays" {
  let tokens = [TokenInfo::new("A", 1)]
  let starts = [0]
  let result = LexResult::with_starts(
    tokens,
    starts,
    diagnostics=DiagnosticSet::empty(),
  )
  tokens[0] = TokenInfo::new("changed", 7)
  starts[0] = 9
  inspect(result.tokens()[0].token, content="A")
  inspect(result.tokens()[0].len, content="1")
  inspect(result.starts()[0], content="0")
}

///|
test "LexResult compatibility getters return detached arrays" {
  let result = LexResult::with_starts(
    [TokenInfo::new("A", 1)],
    [0],
    diagnostics=DiagnosticSet::empty(),
  )
  let tokens = result.tokens()
  let starts = result.starts()
  tokens[0] = TokenInfo::new("changed", 7)
  starts[0] = 9
  inspect(result.tokens()[0].token, content="A")
  inspect(result.tokens()[0].len, content="1")
  inspect(result.starts()[0], content="0")
}

///|
test "LexResult rejects token and start cardinality mismatch" {
  try
    LexResult::with_starts(
      [TokenInfo::new("A", 1)],
      [],
      diagnostics=DiagnosticSet::empty(),
    )
  catch {
    TokenStartCountMismatch(tokens, starts) => {
      inspect(tokens, content="1")
      inspect(starts, content="0")
    }
    _ => abort("expected TokenStartCountMismatch")
  } noraise {
    _ => abort("invalid arrays must not produce a LexResult")
  }
}

///|
test "LexResult rejects a negative token length" {
  try LexResult::LexResult([TokenInfo::new("A", -1)]) catch {
    NegativeTokenLength(index, length) => {
      inspect(index, content="0")
      inspect(length, content="-1")
    }
    _ => abort("expected NegativeTokenLength")
  } noraise {
    _ => abort("invalid arrays must not produce a LexResult")
  }
}

///|
test "LexResult rejects a negative start" {
  try
    LexResult::with_starts(
      [TokenInfo::new("A", 1)],
      [-1],
      diagnostics=DiagnosticSet::empty(),
    )
  catch {
    NegativeStart(index, start) => {
      inspect(index, content="0")
      inspect(start, content="-1")
    }
    _ => abort("expected NegativeStart")
  } noraise {
    _ => abort("invalid arrays must not produce a LexResult")
  }
}

///|
test "LexResult rejects decreasing starts" {
  try
    LexResult::with_starts(
      [TokenInfo::new("A", 0), TokenInfo::new("B", 0)],
      [2, 1],
      diagnostics=DiagnosticSet::empty(),
    )
  catch {
    DecreasingStart(index, previous, current) => {
      inspect(index, content="1")
      inspect(previous, content="2")
      inspect(current, content="1")
    }
    _ => abort("expected DecreasingStart")
  } noraise {
    _ => abort("invalid arrays must not produce a LexResult")
  }
}

///|
test "LexResult rejects overlapping tokens" {
  try
    LexResult::with_starts(
      [TokenInfo::new("A", 2), TokenInfo::new("B", 1)],
      [0, 1],
      diagnostics=DiagnosticSet::empty(),
    )
  catch {
    OverlappingToken(index, previous_end, current) => {
      inspect(index, content="1")
      inspect(previous_end, content="2")
      inspect(current, content="1")
    }
    _ => abort("expected OverlappingToken")
  } noraise {
    _ => abort("invalid arrays must not produce a LexResult")
  }
}

///|
test "LexResult offers checked indexed and paired iteration" {
  let result = LexResult::with_starts(
    [TokenInfo::new("A", 1), TokenInfo::new("B", 2)],
    [0, 3],
    diagnostics=DiagnosticSet::empty(),
  )
  inspect(result.length(), content="2")
  inspect(result.token_at(1).unwrap().token, content="B")
  inspect(result.token_at(-1) is None, content="true")
  inspect(result.token_at(2) is None, content="true")
  debug_inspect(result.start_at(1), content="Some(3)")
  inspect(result.start_at(-1) is None, content="true")
  inspect(result.start_at(2) is None, content="true")
  let summary = result
    .iter()
    .map(pair => pair.0.token + "@" + pair.1.to_string())
    .collect()
  debug_inspect(summary, content="[\"A@0\", \"B@3\"]")
}

///|
test "LexResult from_located_tokens owns positioned input" {
  let located = [LocatedToken::LocatedToken("A", start=0, end=1)]
  let result = LexResult::from_located_tokens(SourceId("located"), "a", located)
  located[0] = LocatedToken::LocatedToken("changed", start=0, end=1)
  inspect(result.token_at(0).unwrap().token, content="A")
  debug_inspect(result.start_at(0), content="Some(0)")
}

///|
test "LexResult from_located_tokens repairs overlapping positioned input" {
  let result = LexResult::from_located_tokens(SourceId("overlap"), "abc", [
    LocatedToken::LocatedToken("A", start=0, end=2),
    LocatedToken::LocatedToken("B", start=1, end=3),
  ])
  debug_inspect(result.starts(), content="[0, 2]")
  inspect(result.token_at(0).unwrap().len, content="2")
  inspect(result.token_at(1).unwrap().len, content="1")
  inspect(result.diagnostics().is_empty(), content="false")
}
