///|
test "detached lexeme preserves Unicode content" {
  let source = "prefix 日本語 😀 suffix"
  let view = source[7:source.length() - 7]
  let detached = detach_lexeme(view)
  assert_eq(detached, view.to_owned())
}
