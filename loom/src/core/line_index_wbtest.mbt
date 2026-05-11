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
test "LineIndex: line range maps both endpoints" {
  let index = LineIndex::new("ab\ncd")
  inspect(render_line_range(index.line_range(1, 5)), content="0:1-1:2")
}

///|
test "format_diagnostic_with_line_col uses line range" {
  let index = LineIndex::new("ab\ncd")
  let diagnostic : Diagnostic[String] = {
    message: "expected token",
    start: 1,
    end: 5,
    got_token: "tok",
  }
  inspect(
    format_diagnostic_with_line_col(diagnostic, index),
    content="expected token [0:1,1:2]",
  )
}
