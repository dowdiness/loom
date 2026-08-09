///|
test "lexer line facts: indented same-line thematic break" {
  inspect(
    same_line_list_item_prefix_facts("  - - - -\n", 4).line_is_thematic_break,
    content="true",
  )
}

///|
test "same-line facts are pure and repeatable" {
  let source = "  - nested\n"
  let first = same_line_list_item_prefix_facts(source, 4)
  let second = same_line_list_item_prefix_facts(source, 5)
  assert_eq(first.line_start, second.line_start)
  assert_eq(first.prefix_end, second.prefix_end)
  assert_eq(first.list_marker_count, second.list_marker_count)
}

///|
test "session-owned same-line cache replaces source and clears at EOF" {
  let first_source = "- first\n"
  let second_source = "- first\n- second\n"
  let session = MarkdownLexSession()
  let _ = session.step(first_source, 2, Inline)
  assert_true(session.same_line_cache.val is Some(_))
  let _ = session.step(second_source, 8, Inline)
  match session.same_line_cache.val {
    Some(facts) => assert_true(physical_equal(facts.source, second_source))
    None => fail("session same-line cache was not populated")
  }
  let _ = session.step(second_source, second_source.length(), LineStart)
  assert_true(session.same_line_cache.val is None)
}
