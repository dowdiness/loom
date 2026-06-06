///|
test "skeleton grammar works with reactive parser" {
  let parser = @loom.new_parser("let x = 1\nlet y = 2\n", moonbit_grammar)
  let ast = parser.ast().read_or_abort()
  inspect(ast.item_count, content="2")
  inspect(ast.contains_errors, content="false")
}

///|
test "skeleton grammar reuses CST nodes after edits" {
  let source = "let x = 1\nlet y = 2\n"
  let parser = @loom.new_imperative_parser(source, moonbit_grammar)
  ignore(parser.parse())
  let next_source = "let x = 10\nlet y = 2\n"
  let edit = @core.Edit::replace(8, 1, 2)
  let snapshot = parser.edit(edit, next_source)
  inspect(
    snapshot.ast.item_count,
    content=(
      #|3
    ),
  )
  assert_true(snapshot.reuse_count >= 1)
}
