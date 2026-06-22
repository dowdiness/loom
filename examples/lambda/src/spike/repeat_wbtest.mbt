// Top-level repeat-group reuse, driven by the reified lambda grammar. The
// bespoke `let_grammar` is gone; the full grammar's RepeatTopLevel node owns
// the reuse loop, so editing the second of two definitions still reuses the
// unchanged first.

///|
test "task5: two let defs get repeat-group reuse after editing second def" {
  let source = "let x = 1\nlet y = 2"
  let b_grammar = build_b_syntax_grammar()
  let parser = @loom.new_syntax_parser(source, b_grammar)
  // Edit: change "2" at position 18 to "3": "let x = 1\nlet y = 3"
  let edit = @core.Edit::new(18, 1, 1)
  let new_source = "let x = 1\nlet y = 3"
  parser.apply_edit(edit, new_source)
  let snapshot = parser.snapshot().read_or_abort()
  inspect(snapshot.reuse_count > 0, content="true")
}
