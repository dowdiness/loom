///|
test "lexer line facts: indented same-line thematic break" {
  inspect(
    same_line_list_item_prefix_facts("  - - - -\n", 4).line_is_thematic_break,
    content="true",
  )
}

///|
test "same-line prefix cache lifecycle" {
  clear_same_line_list_item_prefix_cache()
  let source = "  - nested\n"
  let first = same_line_list_item_prefix_facts(source, 4)
  let second = same_line_list_item_prefix_facts(source, 5)
  assert_eq(first.line_start, second.line_start)
  assert_true(same_line_list_item_prefix_cache.val is Some(_))
  clear_same_line_list_item_prefix_cache()
  assert_true(same_line_list_item_prefix_cache.val is None)
}

///|
test "same-line prefix cache replaces source and line" {
  clear_same_line_list_item_prefix_cache()
  let first_source = StringBuilder::StringBuilder()
  first_source.write_string("- first\n")
  let first_source = first_source.to_string()
  let second_source = StringBuilder::StringBuilder()
  second_source.write_string("- first\n- second\n")
  let second_source = second_source.to_string()
  let first = same_line_list_item_prefix_facts(first_source, 0)
  assert_eq(first.line_start, 0)
  let second = same_line_list_item_prefix_facts(second_source, 8)
  assert_eq(second.line_start, 8)
  match same_line_list_item_prefix_cache.val {
    Some(facts) => assert_true(physical_equal(facts.source, second_source))
    None => fail("same-line prefix cache was not populated")
  }
  clear_same_line_list_item_prefix_cache()
}

///|
test "session tokenization does not use the compatibility cache" {
  clear_same_line_list_item_prefix_cache()
  let source = "- nested\n"
  let _ = tokenize(source)
  assert_true(same_line_list_item_prefix_cache.val is None)
}
