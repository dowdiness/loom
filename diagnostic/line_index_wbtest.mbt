///|
fn render_line_col(pos : LineCol) -> String {
  pos.line.to_string() + ":" + pos.column.to_string()
}

///|
fn render_line_range(range : LineRange) -> String {
  render_line_col(range.start) + "-" + render_line_col(range.end)
}

///|
test "LineIndex: empty source clamps to origin" {
  let index = LineIndex::new("")
  inspect(render_line_col(index.line_col(0)), content="0:0")
  inspect(render_line_col(index.line_col(-5)), content="0:0")
  inspect(render_line_col(index.line_col(99)), content="0:0")
}

///|
test "LineIndex: single line offsets" {
  let index = LineIndex::new("abc")
  inspect(render_line_col(index.line_col(0)), content="0:0")
  inspect(render_line_col(index.line_col(2)), content="0:2")
  inspect(render_line_col(index.line_col(3)), content="0:3")
  inspect(render_line_col(index.line_col(9)), content="0:3")
}

///|
test "LineIndex: LF newline" {
  let index = LineIndex::new("ab\ncd")
  inspect(render_line_col(index.line_col(0)), content="0:0")
  inspect(render_line_col(index.line_col(2)), content="0:2")
  inspect(render_line_col(index.line_col(3)), content="1:0")
  inspect(render_line_col(index.line_col(5)), content="1:2")
}

///|
test "LineIndex: CRLF newline counts as one line break" {
  let index = LineIndex::new("ab\r\ncd")
  inspect(render_line_col(index.line_col(0)), content="0:0")
  inspect(render_line_col(index.line_col(2)), content="0:2")
  inspect(render_line_col(index.line_col(3)), content="0:3")
  inspect(render_line_col(index.line_col(4)), content="1:0")
  inspect(render_line_col(index.line_col(6)), content="1:2")
}

///|
test "LineIndex: lone CR newline" {
  let index = LineIndex::new("ab\rcd")
  inspect(render_line_col(index.line_col(2)), content="0:2")
  inspect(render_line_col(index.line_col(3)), content="1:0")
  inspect(render_line_col(index.line_col(5)), content="1:2")
}

///|
test "LineIndex: trailing newline creates empty final line" {
  let index = LineIndex::new("ab\n")
  inspect(render_line_col(index.line_col(3)), content="1:0")
}

///|
test "LineIndex: non-BMP character uses UTF-16 column width" {
  let index = LineIndex::new("a😈b\n😈")
  inspect(render_line_col(index.line_col(0)), content="0:0")
  inspect(render_line_col(index.line_col(1)), content="0:1")
  inspect(render_line_col(index.line_col(3)), content="0:3")
  inspect(render_line_col(index.line_col(4)), content="0:4")
  inspect(render_line_col(index.line_col(5)), content="1:0")
  inspect(render_line_col(index.line_col(7)), content="1:2")
}

///|
test "LineIndex: lone surrogate advances one UTF-16 code unit" {
  let lone_high_surrogate = (0xD800).unsafe_to_char().to_string()
  let index = LineIndex::new(lone_high_surrogate + "\nx")
  inspect(render_line_col(index.line_col(1)), content="0:1")
  inspect(render_line_col(index.line_col(2)), content="1:0")
}

///|
test "LineIndex: line range maps both endpoints" {
  let index = LineIndex::new("ab\ncd")
  inspect(render_line_range(index.line_range(1, 5)), content="0:1-1:2")
}

///|
test "format_diagnostic_with_line_col uses line range" {
  let index = LineIndex::new("ab\ncd")
  let range = try TextRange::from_offsets(1, 5) catch {
    _ => abort("expected valid diagnostic range")
  } noraise {
    range => range
  }
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Error,
    message="expected token",
    labels=[
      DiagnosticLabel(
        LabelStyle::Primary,
        SourceSpan(SourceId("line-index-source"), range),
        None,
      ),
    ],
  )
  inspect(
    diagnostic.format_with_line_col(index),
    content="expected token [0:1,1:2]",
  )
}

///|
test "LineIndex strict inverse round-trips only valid UTF-16 boundaries" {
  let source = "a😈\r\nb"
  let index = LineIndex::new(source)
  debug_inspect(
    index.strict_offset(source, { line: 0, column: 0 }),
    content="Some(0)",
  )
  debug_inspect(
    index.strict_offset(source, { line: 0, column: 1 }),
    content="Some(1)",
  )
  debug_inspect(
    index.strict_offset(source, { line: 0, column: 2 }),
    content="None",
  )
  debug_inspect(
    index.strict_offset(source, { line: 0, column: 3 }),
    content="Some(3)",
  )
  debug_inspect(
    index.strict_offset(source, { line: 0, column: 4 }),
    content="Some(4)",
  )
  debug_inspect(
    index.strict_offset(source, { line: 1, column: 0 }),
    content="Some(5)",
  )
  debug_inspect(
    index.strict_offset(source, { line: 1, column: 1 }),
    content="Some(6)",
  )
  debug_inspect(
    index.strict_offset(source, { line: 0, column: 5 }),
    content="None",
  )
  debug_inspect(
    index.strict_offset(source, { line: 2, column: 0 }),
    content="None",
  )
}

///|
test "property: valid UTF-16 offsets round-trip and line columns are monotonic" {
  let sources : Array[String] = @quickcheck.samples(64)
  sources.each(source => {
    let index = LineIndex::new(source)
    let valid_offsets = Array::makei(source.length() + 1, offset => offset).filter(offset => {
        match source.get_view(start=offset, end=offset) {
          Some(_) => true
          None => false
        }
      },
    )
    valid_offsets.each(offset => {
      guard index.strict_offset(source, index.line_col(offset)) == Some(offset) else {
        abort("valid UTF-16 offset did not round-trip: " + offset.to_string())
      }
    })
    valid_offsets
    .windows(2)
    .each(pair => {
      let before = index.line_col(pair[0])
      let after = index.line_col(pair[1])
      guard after.line > before.line ||
        (after.line == before.line && after.column > before.column) else {
        abort(
          "line/column mapping was not monotonic at offset " +
          pair[0].to_string(),
        )
      }
    })
  })
}
