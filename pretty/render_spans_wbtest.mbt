///|
test "render_spans no annotations" {
  let doc : Layout[String] = text("hello")
  let spans = render_spans(doc)
  debug_inspect(spans, content="[]")
}

///|
test "render_spans single annotation" {
  let doc = annotate("kw", text("let"))
  let spans = render_spans(doc)
  debug_inspect(
    spans,
    content=(
      #|[({ start: 0, end: 3 }, "kw")]
    ),
  )
}

///|
test "render_spans nested annotations" {
  let doc = annotate(
    "expr",
    annotate("kw", text("let")) + text(" ") + annotate("id", text("x")),
  )
  let spans = render_spans(doc)
  debug_inspect(
    spans,
    content=(
      #|[
      #|  ({ start: 0, end: 3 }, "kw"),
      #|  ({ start: 4, end: 5 }, "id"),
      #|  ({ start: 0, end: 5 }, "expr"),
      #|]
    ),
  )
}

///|
test "render_spans with line breaks" {
  let doc = annotate("block", text("a") + hardline() + text("b"))
  let spans = render_spans(doc)
  debug_inspect(
    spans,
    content=(
      #|[({ start: 0, end: 3 }, "block")]
    ),
  )
}

///|
test "render_spans with indented line" {
  let doc = annotate("block", text("a") + nest(hardline() + text("b")))
  let spans = render_spans(doc)
  debug_inspect(
    spans,
    content=(
      #|[({ start: 0, end: 5 }, "block")]
    ),
  )
}

///|
test "render_spans keeps emitted UTF-16 offsets for measured text" {
  let doc = annotate("wide", text_with_width("界", 2)) +
    annotate("emoji", text_with_width("😈", 2))
  debug_inspect(
    render_spans(doc),
    content=(
      #|[({ start: 0, end: 1 }, "wide"), ({ start: 1, end: 3 }, "emoji")]
    ),
  )
}
