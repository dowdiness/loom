///|
test "MarkdownIR lowering: discontinuous label origin is omitted" {
  let first_origin = MarkdownIROrigin(start=1, end=3)
  let second_origin = MarkdownIROrigin(start=4, end=6)
  let children = [
    MarkdownIR::text("ab", first_origin),
    MarkdownIR::text("cd", second_origin),
  ]
  inspect(contiguous_label_origin(children, 1, 6) is None, content="true")
}
