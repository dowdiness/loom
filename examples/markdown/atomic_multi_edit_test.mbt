///|
test "atomic multi-edit matches a fresh Markdown parse" {
  let source_id = @core.SourceId("markdown-atomic-multi-edit")
  let source = "# one\r\n\r\nParagraph 😀 cafe\u0301.\r\n\r\n- item\r\n"
  let heading = source.find("one").unwrap()
  let item = source.find("item").unwrap()
  let changes = @text_change.ChangeSet::ChangeSet(
    source_length=source.length(),
    changes=[
      @text_change.TextChange::ReplaceRange(
        start=heading,
        delete_len=3,
        inserted="two",
      ),
      @text_change.TextChange::ReplaceRange(
        start=item,
        delete_len=4,
        inserted="entry",
      ),
    ],
  )
  let updated = changes.apply(source).unwrap()
  let parser = @loom.new_parser(source_id, source, markdown_grammar)
  parser.apply_changes(changes, updated)
  let actual = parser.snapshot().read_or_abort()
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let expected = fresh.snapshot().read_or_abort()
  assert_eq(actual.source, expected.source)
  assert_eq(actual.syntax, expected.syntax)
  assert_eq(actual.ast, expected.ast)
  assert_eq(actual.diagnostics, expected.diagnostics)
}

///|
test "atomic multi-edit preserves Markdown recovery parity" {
  let source_id = @core.SourceId("markdown-atomic-multi-edit-recovery")
  let source = "# title\n\nplain\n"
  let title = source.find("title").unwrap()
  let plain = source.find("plain").unwrap()
  let changes = @text_change.ChangeSet::ChangeSet(
    source_length=source.length(),
    changes=[
      @text_change.TextChange::ReplaceRange(
        start=title,
        delete_len=5,
        inserted="[broken",
      ),
      @text_change.TextChange::ReplaceRange(
        start=plain,
        delete_len=5,
        inserted="`open",
      ),
    ],
  )
  let updated = changes.apply(source).unwrap()
  let parser = @loom.new_parser(source_id, source, markdown_grammar)
  parser.apply_changes(changes, updated)
  let actual = parser.snapshot().read_or_abort()
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let expected = fresh.snapshot().read_or_abort()
  assert_eq(actual.syntax, expected.syntax)
  assert_eq(actual.ast, expected.ast)
  assert_eq(actual.diagnostics, expected.diagnostics)
}
