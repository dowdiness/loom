///|
fn renderer_test_range(start : Int, end : Int) -> TextRange {
  try TextRange::from_offsets(start, end) catch {
    _ => abort("expected valid renderer test range")
  } noraise {
    range => range
  }
}

///|
fn renderer_test_label(
  style : LabelStyle,
  source_id : SourceId,
  start : Int,
  end : Int,
  message : String,
) -> DiagnosticLabel {
  DiagnosticLabel(
    style,
    SourceSpan(source_id, renderer_test_range(start, end)),
    Some(message),
  )
}

///|
test "plain diagnostic renderer renders a locationless diagnostic without source lookup" {
  let mut resolve_calls = 0
  let provider = test_source_resolver(_ => {
    resolve_calls = resolve_calls + 1
    None
  })
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("lexer"),
    severity=Warning,
    code=Some(DiagnosticCode("W001")),
    message="locationless warning",
    notes=["first note", "second note"],
  )
  inspect(
    diagnostic.render_plain(provider),
    content=(
      #|warning[W001]: locationless warning
      #|= note: first note
      #|= note: second note
    ),
  )
  inspect(resolve_calls, content="0")
}

///|
test "plain diagnostic renderer renders a source-backed primary label" {
  let source_id = SourceId("main")
  let source = "let x = foo"
  let range = try TextRange::from_offsets(8, 11) catch {
    _ => abort("expected valid renderer test range")
  } noraise {
    range => range
  }
  let provider = test_source_resolver(requested => {
    if requested == source_id {
      Some(SourceSnapshot("src/main.mbt", source, LineIndex::new(source)))
    } else {
      None
    }
  })
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Error,
    code=Some(DiagnosticCode("E100")),
    message="unexpected name",
    labels=[
      DiagnosticLabel(
        LabelStyle::Primary,
        SourceSpan(source_id, range),
        Some("expected expression"),
      ),
    ],
  )
  inspect(
    diagnostic.render_plain(provider),
    content=(
      #|error[E100]: unexpected name
      #|--> src/main.mbt
      #|primary 1:9-1:12: expected expression
      #|  1 | let x = foo
      #|    |         ^^^
    ),
  )
}

///|
test "plain diagnostic renderer groups styled labels in source order" {
  let source_id = SourceId("main")
  let source = "abc def ghi"
  let mut resolve_calls = 0
  let provider = test_source_resolver(requested => {
    resolve_calls = resolve_calls + 1
    if requested == source_id {
      Some(SourceSnapshot("main.mbt", source, LineIndex::new(source)))
    } else {
      None
    }
  })
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Warning,
    message="related ranges",
    labels=[
      renderer_test_label(Primary, source_id, 0, 3, "first primary"),
      renderer_test_label(Secondary, source_id, 4, 7, "secondary"),
      renderer_test_label(Primary, source_id, 8, 11, "second primary"),
    ],
  )
  inspect(
    diagnostic.render_plain(provider),
    content=(
      #|warning: related ranges
      #|--> main.mbt
      #|primary 1:1-1:4: first primary
      #|  1 | abc def ghi
      #|    | ^^^
      #|secondary 1:5-1:8: secondary
      #|  1 | abc def ghi
      #|    |     ---
      #|primary 1:9-1:12: second primary
      #|  1 | abc def ghi
      #|    |         ^^^
    ),
  )
  inspect(resolve_calls, content="1")
}

///|
test "plain diagnostic renderer renders every line of a multiline half-open span" {
  let source_id = SourceId("multiline")
  let source = "abc\ndef\nghi"
  let provider = test_source_resolver(requested => {
    if requested == source_id {
      Some(SourceSnapshot("multi.mbt", source, LineIndex::new(source)))
    } else {
      None
    }
  })
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Error,
    message="multiline",
    labels=[renderer_test_label(Primary, source_id, 1, 10, "across lines")],
  )
  inspect(
    diagnostic.render_plain(provider),
    content=(
      #|error: multiline
      #|--> multi.mbt
      #|primary 1:2-3:3: across lines
      #|  1 | abc
      #|    |  ^^
      #|  2 | def
      #|    | ^^^
      #|  3 | ghi
      #|    | ^^
    ),
  )
}

///|
test "plain diagnostic array renderer preserves order and stable separators" {
  let mut resolve_calls = 0
  let provider = test_source_resolver(_ => {
    resolve_calls = resolve_calls + 1
    None
  })
  let diagnostics = [
    Diagnostic(
      origin=DiagnosticOrigin("parser"),
      severity=Error,
      message="first",
    ),
    Diagnostic(
      origin=DiagnosticOrigin("lexer"),
      severity=Hint,
      code=Some(DiagnosticCode("H2")),
      message="second",
    ),
  ]
  inspect(render_diagnostics_plain([], provider), content="")
  inspect(
    render_diagnostics_plain(diagnostics[:], provider),
    content=(
      #|error: first
      #|
      #|hint[H2]: second
    ),
  )
  inspect(resolve_calls, content="0")
}

///|
test "plain diagnostic array renderer resolves each source once per render" {
  let source_id = SourceId("shared")
  let source = "xy"
  let mut resolve_calls = 0
  let provider = test_source_resolver(requested => {
    resolve_calls = resolve_calls + 1
    if requested == source_id {
      Some(SourceSnapshot("shared.mbt", source, LineIndex::new(source)))
    } else {
      None
    }
  })
  let diagnostics = [
    Diagnostic(
      origin=DiagnosticOrigin("parser"),
      severity=Error,
      message="first",
      labels=[renderer_test_label(Primary, source_id, 0, 1, "x")],
    ),
    Diagnostic(
      origin=DiagnosticOrigin("lexer"),
      severity=Info,
      message="second",
      labels=[renderer_test_label(Secondary, source_id, 1, 2, "y")],
    ),
  ]
  inspect(
    render_diagnostics_plain(diagnostics[:], provider),
    content=(
      #|error: first
      #|--> shared.mbt
      #|primary 1:1-1:2: x
      #|  1 | xy
      #|    | ^
      #|
      #|info: second
      #|--> shared.mbt
      #|secondary 1:2-1:3: y
      #|  1 | xy
      #|    |  -
    ),
  )
  inspect(resolve_calls, content="1")
}

///|
test "plain diagnostic renderer reports typed source boundary failures" {
  let source_id = SourceId("boundary")
  let diagnostic_for : (Int, Int) -> Diagnostic = (start, end) => {
    Diagnostic(
      origin=DiagnosticOrigin("parser"),
      severity=Error,
      message="boundary",
      labels=[renderer_test_label(Primary, source_id, start, end, "label")],
    )
  }
  let missing : Result[String, DiagnosticRenderError] = Ok(
    diagnostic_for(0, 1).render_plain(test_source_resolver(_ => None)),
  ) catch {
    error => Err(error)
  }
  match missing {
    Err(MissingSource(actual)) => inspect(actual == source_id, content="true")
    _ => abort("expected missing source render error")
  }
  let mismatched : Result[String, DiagnosticRenderError] = Ok(
    diagnostic_for(0, 1).render_plain(
      test_source_resolver(_ => {
        Some(SourceSnapshot("bad.mbt", "x", LineIndex::new("\n")))
      }),
    ),
  ) catch {
    error => Err(error)
  }
  match mismatched {
    Err(MismatchedLineIndex(actual)) =>
      inspect(actual == source_id, content="true")
    _ => abort("expected mismatched line index render error")
  }
  let out_of_bounds : Result[String, DiagnosticRenderError] = Ok(
    diagnostic_for(0, 2).render_plain(
      test_source_resolver(_ => {
        Some(SourceSnapshot("short.mbt", "x", LineIndex::new("x")))
      }),
    ),
  ) catch {
    error => Err(error)
  }
  match out_of_bounds {
    Err(RangeOutOfBounds(span, source_len)) => {
      inspect(span.source_id() == source_id, content="true")
      inspect(span.range().start().value(), content="0")
      inspect(span.range().end().value(), content="2")
      inspect(source_len, content="1")
    }
    _ => abort("expected out-of-bounds render error")
  }
  let surrogate : Result[String, DiagnosticRenderError] = Ok(
    diagnostic_for(1, 2).render_plain(
      test_source_resolver(_ => {
        Some(SourceSnapshot("emoji.mbt", "😈", LineIndex::new("😈")))
      }),
    ),
  ) catch {
    error => Err(error)
  }
  match surrogate {
    Err(InvalidUtf16Boundary(span)) => {
      inspect(span.source_id() == source_id, content="true")
      inspect(span.range().start().value(), content="1")
      inspect(span.range().end().value(), content="2")
    }
    _ => abort("expected invalid UTF-16 boundary render error")
  }
}

///|
test "plain diagnostic renderer preserves UTF-16 point and Unicode semantics" {
  let empty_id = SourceId("empty")
  let eof_id = SourceId("eof")
  let unicode_id = SourceId("unicode")
  let unicode_source = "a😈e\u0301"
  let provider = test_source_resolver(source_id => {
    if source_id == empty_id {
      Some(SourceSnapshot("empty.mbt", "", LineIndex::new("")))
    } else if source_id == eof_id {
      Some(SourceSnapshot("eof.mbt", "ab", LineIndex::new("ab")))
    } else if source_id == unicode_id {
      Some(
        SourceSnapshot(
          "unicode.mbt",
          unicode_source,
          LineIndex::new(unicode_source),
        ),
      )
    } else {
      None
    }
  })
  let empty = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Error,
    message="empty source",
    labels=[renderer_test_label(Primary, empty_id, 0, 0, "empty point")],
  )
  inspect(
    empty.render_plain(provider),
    content=(
      #|error: empty source
      #|--> empty.mbt
      #|primary 1:1-1:1: empty point
      #|  1 |
      #|    | ^
    ),
  )
  let eof = Diagnostic(
    origin=DiagnosticOrigin("lexer"),
    severity=Info,
    message="eof point",
    labels=[
      DiagnosticLabel(
        Secondary,
        SourceSpan(eof_id, renderer_test_range(2, 2)),
        None,
      ),
    ],
  )
  inspect(
    eof.render_plain(provider),
    content=(
      #|info: eof point
      #|--> eof.mbt
      #|secondary 1:3-1:3
      #|  1 | ab
      #|    |   -
    ),
  )
  let unicode = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Hint,
    message="unicode widths",
    labels=[
      renderer_test_label(Primary, unicode_id, 1, 3, "emoji"),
      renderer_test_label(Secondary, unicode_id, 3, 5, "combining"),
    ],
  )
  inspect(
    unicode.render_plain(provider),
    content=(
      #|hint: unicode widths
      #|--> unicode.mbt
      #|primary 1:2-1:4: emoji
      #|  1 | a😈é
      #|    |  ^^
      #|secondary 1:4-1:6: combining
      #|  1 | a😈é
      #|    |    -
    ),
  )
}

///|
test "plain diagnostic renderer aligns markers by display cells" {
  let source_id = SourceId("width")
  let source = "界\tx"
  let resolver = test_source_resolver(requested => {
    if requested == source_id {
      Some(SourceSnapshot("width.mbt", source, LineIndex::new(source)))
    } else {
      None
    }
  })
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("renderer"),
    severity=Hint,
    message="display cells",
    labels=[
      renderer_test_label(Primary, source_id, 0, 1, "wide"),
      renderer_test_label(Secondary, source_id, 2, 3, "after tab"),
    ],
  )
  inspect(
    diagnostic.render_plain(resolver),
    content=(
      #|hint: display cells
      #|--> width.mbt
      #|primary 1:1-1:2: wide
      #|  1 | 界    x
      #|    | ^^
      #|secondary 1:3-1:4: after tab
      #|  1 | 界    x
      #|    |       -
    ),
  )
}

///|
test "plain diagnostic renderer keeps a marker for a zero-width span" {
  let source_id = SourceId("zero-width")
  let source = "a\u{200B}b"
  let resolver = test_source_resolver(requested => {
    if requested == source_id {
      Some(SourceSnapshot("zero.mbt", source, LineIndex::new(source)))
    } else {
      None
    }
  })
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("renderer"),
    severity=Warning,
    message="zero width",
    labels=[renderer_test_label(Primary, source_id, 1, 2, "invisible")],
  )
  inspect(
    diagnostic.render_plain(resolver),
    content="warning: zero width\n--> zero.mbt\nprimary 1:2-1:3: invisible\n  1 | a\u{200B}b\n    |  ^",
  )
}

///|
test "plain diagnostic renderer expands interior spans to display units" {
  let sequence_id = SourceId("sequence")
  let combining_id = SourceId("combining-interior")
  let sequence = "\u{16D69}\u{16D68}\u{16D67}"
  let combining = "e\u{301}"
  let resolver = test_source_resolver(requested => {
    if requested == sequence_id {
      Some(SourceSnapshot("sequence.mbt", sequence, LineIndex::new(sequence)))
    } else if requested == combining_id {
      Some(
        SourceSnapshot("combining.mbt", combining, LineIndex::new(combining)),
      )
    } else {
      None
    }
  })
  let sequence_diagnostic = Diagnostic(
    origin=DiagnosticOrigin("renderer"),
    severity=Error,
    message="non-additive sequence",
    labels=[renderer_test_label(Primary, sequence_id, 4, 6, "last grapheme")],
  )
  inspect(
    sequence_diagnostic.render_plain(resolver),
    content="error: non-additive sequence\n--> sequence.mbt\nprimary 1:5-1:7: last grapheme\n  1 | \u{16D69}\u{16D68}\u{16D67}\n    | ^^",
  )
  let combining_diagnostic = Diagnostic(
    origin=DiagnosticOrigin("renderer"),
    severity=Warning,
    message="combining interior",
    labels=[renderer_test_label(Secondary, combining_id, 1, 2, "mark")],
  )
  inspect(
    combining_diagnostic.render_plain(resolver),
    content="warning: combining interior\n--> combining.mbt\nsecondary 1:2-1:3: mark\n  1 | e\u{301}\n    | -",
  )
}

///|
test "plain diagnostic renderer preserves LF CRLF and CR terminator positions" {
  let lf_id = SourceId("lf")
  let crlf_id = SourceId("crlf")
  let cr_id = SourceId("cr")
  let provider = test_source_resolver(source_id => {
    if source_id == lf_id {
      Some(SourceSnapshot("lf.mbt", "ab\ncd", LineIndex::new("ab\ncd")))
    } else if source_id == crlf_id {
      Some(SourceSnapshot("crlf.mbt", "ab\r\ncd", LineIndex::new("ab\r\ncd")))
    } else if source_id == cr_id {
      Some(SourceSnapshot("cr.mbt", "ab\rcd", LineIndex::new("ab\rcd")))
    } else {
      None
    }
  })
  let diagnostics = [
    Diagnostic(
      origin=DiagnosticOrigin("parser"),
      severity=Error,
      message="LF",
      labels=[renderer_test_label(Primary, lf_id, 2, 3, "line feed")],
    ),
    Diagnostic(
      origin=DiagnosticOrigin("parser"),
      severity=Error,
      message="CRLF",
      labels=[renderer_test_label(Primary, crlf_id, 3, 4, "inside CRLF")],
    ),
    Diagnostic(
      origin=DiagnosticOrigin("parser"),
      severity=Error,
      message="CR",
      labels=[renderer_test_label(Primary, cr_id, 2, 3, "carriage return")],
    ),
  ]
  inspect(
    render_diagnostics_plain(diagnostics[:], provider),
    content=(
      #|error: LF
      #|--> lf.mbt
      #|primary 1:3-2:1: line feed
      #|  1 | ab
      #|    |   ^
      #|
      #|error: CRLF
      #|--> crlf.mbt
      #|primary 1:4-2:1: inside CRLF
      #|  1 | ab
      #|    |    ^
      #|
      #|error: CR
      #|--> cr.mbt
      #|primary 1:3-2:1: carriage return
      #|  1 | ab
      #|    |   ^
    ),
  )
}

///|
test "plain diagnostic renderer groups by source identity and keeps defensive copies" {
  let source_a = SourceId("parser")
  let source_b = SourceId("lexer")
  let labels = [
    renderer_test_label(Primary, source_a, 0, 1, "a primary"),
    renderer_test_label(Secondary, source_b, 1, 2, "b secondary"),
    renderer_test_label(Secondary, source_a, 2, 3, "a secondary"),
  ]
  let notes = ["stable note"]
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("lexer"),
    severity=Warning,
    message="identity domains",
    labels~,
    notes~,
  )
  labels.push(renderer_test_label(Primary, source_b, 0, 3, "input mutation"))
  notes.push("input mutation")
  diagnostic
  .labels()
  .push(renderer_test_label(Primary, source_b, 0, 3, "accessor mutation"))
  diagnostic.notes().push("accessor mutation")
  let mut source_a_calls = 0
  let mut source_b_calls = 0
  let provider = test_source_resolver(source_id => {
    if source_id == source_a {
      source_a_calls = source_a_calls + 1
      Some(SourceSnapshot("same.mbt", "abc", LineIndex::new("abc")))
    } else if source_id == source_b {
      source_b_calls = source_b_calls + 1
      Some(SourceSnapshot("same.mbt", "abc", LineIndex::new("abc")))
    } else {
      None
    }
  })
  inspect(
    diagnostic.render_plain(provider),
    content=(
      #|warning: identity domains
      #|--> same.mbt
      #|primary 1:1-1:2: a primary
      #|  1 | abc
      #|    | ^
      #|secondary 1:3-1:4: a secondary
      #|  1 | abc
      #|    |   -
      #|--> same.mbt
      #|secondary 1:2-1:3: b secondary
      #|  1 | abc
      #|    |  -
      #|= note: stable note
    ),
  )
  inspect(source_a_calls, content="1")
  inspect(source_b_calls, content="1")
}

///|
test "plain diagnostic array rendering fails atomically" {
  let source_id = SourceId("atomic")
  let diagnostics = [
    Diagnostic(
      origin=DiagnosticOrigin("parser"),
      severity=Error,
      message="valid first",
      labels=[renderer_test_label(Primary, source_id, 0, 1, "valid")],
    ),
    Diagnostic(
      origin=DiagnosticOrigin("parser"),
      severity=Error,
      message="invalid second",
      labels=[renderer_test_label(Primary, source_id, 0, 2, "invalid")],
    ),
  ]
  let mut resolve_calls = 0
  let provider = test_source_resolver(_ => {
    resolve_calls = resolve_calls + 1
    Some(SourceSnapshot("atomic.mbt", "x", LineIndex::new("x")))
  })
  let rendered : Result[String, DiagnosticRenderError] = Ok(
    render_diagnostics_plain(diagnostics[:], provider),
  ) catch {
    error => Err(error)
  }
  match rendered {
    Err(RangeOutOfBounds(span, source_len)) => {
      inspect(span.source_id() == source_id, content="true")
      inspect(span.range().start().value(), content="0")
      inspect(span.range().end().value(), content="2")
      inspect(source_len, content="1")
    }
    _ => abort("expected atomic render failure")
  }
  inspect(resolve_calls, content="1")
}
