///|
test "lexer line facts: indented same-line thematic break" {
  inspect(
    same_line_list_item_line_is_thematic_break("  - - - -\n", 4),
    content="true",
  )
}
