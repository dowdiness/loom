///|
test "MarkdownIR public view exposes private unsupported nodes explicitly" {
  let origin = MarkdownIROrigin(start=0, end=0)
  assert_eq(
    MarkdownIR::unsupported("extension", origin).view(),
    MarkdownIRView::Unsupported(message="extension"),
  )
}
