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
test "atomic multi-edit uses a bounded reparse forest for safe paragraphs" {
  let source_id = @core.SourceId("markdown-atomic-reparse-forest")
  let source = "Alpha remains stable.\n\nBeta remains stable.\n\n"
  let first = source.find("remains").unwrap()
  let second = source.find("Beta remains").unwrap() + "Beta ".length()
  let changes = @text_change.ChangeSet::ChangeSet(
    source_length=source.length(),
    changes=[
      @text_change.TextChange::ReplaceRange(
        start=first,
        delete_len=1,
        inserted="R",
      ),
      @text_change.TextChange::ReplaceRange(
        start=second,
        delete_len=1,
        inserted="R",
      ),
    ],
  )
  let updated = changes.apply(source).unwrap()
  let parser = @loom.new_parser(source_id, source, markdown_grammar)
  parser.apply_changes(changes, updated)
  let actual = parser.snapshot().read_or_abort()
  let expected = @loom.new_parser(source_id, updated, markdown_grammar)
  assert_eq(actual.syntax, expected.syntax_tree().read_or_abort())
  assert_eq(actual.ast, expected.ast().read_or_abort())
  assert_eq(actual.diagnostics, expected.diagnostics().read_or_abort())
  assert_eq(actual.reuse_count, 2)
  let edit_start = updated.find("stable").unwrap()
  let next_source = @text_change.TextChange::ReplaceRange(
      start=edit_start,
      delete_len=1,
      inserted="S",
    )
    .apply(updated)
    .unwrap()
  parser.apply_edit(@core.Edit::new(edit_start, 1, 1), next_source)
  let after_edit = parser.snapshot().read_or_abort()
  let fresh_after_edit = @loom.new_parser(
    source_id, next_source, markdown_grammar,
  )
  assert_eq(after_edit.syntax, fresh_after_edit.syntax_tree().read_or_abort())
  assert_eq(after_edit.ast, fresh_after_edit.ast().read_or_abort())
  assert_eq(
    after_edit.diagnostics,
    fresh_after_edit.diagnostics().read_or_abort(),
  )
}

///|
test "atomic multi-edit forest matches fresh parse across line terminators" {
  for entry in [("lf", "\n"), ("crlf", "\r\n"), ("cr", "\r")] {
    let (name, terminator) = entry
    let source = "Alpha 😀 remains stable.\{terminator}\{terminator}Beta remains stable.\{terminator}\{terminator}"
    let first = source.find("remains").unwrap()
    let second = source.find("Beta remains").unwrap() + "Beta ".length()
    let changes = @text_change.ChangeSet::ChangeSet(
      source_length=source.length(),
      changes=[
        @text_change.TextChange::ReplaceRange(
          start=first,
          delete_len=1,
          inserted="R",
        ),
        @text_change.TextChange::ReplaceRange(
          start=second,
          delete_len=1,
          inserted="R",
        ),
      ],
    )
    let updated = changes.apply(source).unwrap()
    let source_id = @core.SourceId("markdown-atomic-terminator-\{name}")
    let parser = @loom.new_parser(source_id, source, markdown_grammar)
    parser.apply_changes(changes, updated)
    let actual = parser.snapshot().read_or_abort()
    let expected = @loom.new_parser(source_id, updated, markdown_grammar)
    assert_eq(actual.syntax, expected.syntax_tree().read_or_abort())
    assert_eq(actual.ast, expected.ast().read_or_abort())
    assert_eq(actual.diagnostics, expected.diagnostics().read_or_abort())
    assert_eq(actual.reuse_count, 2)
  }
}

///|
test "atomic multi-edit falls back for a structural same-length change" {
  let source_id = @core.SourceId("markdown-atomic-structural-fallback")
  let source = "Alpha remains stable.\n\nBeta remains stable.\n\n"
  let beta = source.find("Beta remains").unwrap() + "Beta ".length()
  let changes = @text_change.ChangeSet::ChangeSet(
    source_length=source.length(),
    changes=[
      @text_change.TextChange::ReplaceRange(start=0, delete_len=1, inserted="#"),
      @text_change.TextChange::ReplaceRange(
        start=beta,
        delete_len=1,
        inserted="R",
      ),
    ],
  )
  let updated = changes.apply(source).unwrap()
  let parser = @loom.new_parser(source_id, source, markdown_grammar)
  parser.apply_changes(changes, updated)
  let actual = parser.snapshot().read_or_abort()
  let expected = @loom.new_parser(source_id, updated, markdown_grammar)
  assert_eq(actual.syntax, expected.syntax_tree().read_or_abort())
  assert_eq(actual.ast, expected.ast().read_or_abort())
  assert_eq(actual.diagnostics, expected.diagnostics().read_or_abort())
  assert_eq(actual.reuse_count, 0)
}

///|
test "atomic multi-edit falls back for length-changing edits" {
  let source_id = @core.SourceId("markdown-atomic-reparse-fallback")
  let source = "Alpha remains stable.\n\nBeta remains stable.\n\n"
  let start = source.find("remains").unwrap()
  let changes = @text_change.ChangeSet::ChangeSet(
    source_length=source.length(),
    changes=[
      @text_change.TextChange::ReplaceRange(start~, delete_len=1, inserted="RR"),
    ],
  )
  let updated = changes.apply(source).unwrap()
  let parser = @loom.new_parser(source_id, source, markdown_grammar)
  parser.apply_changes(changes, updated)
  let actual = parser.snapshot().read_or_abort()
  let expected = @loom.new_parser(source_id, updated, markdown_grammar)
  assert_eq(actual.syntax, expected.syntax_tree().read_or_abort())
  assert_eq(actual.ast, expected.ast().read_or_abort())
  assert_eq(actual.diagnostics, expected.diagnostics().read_or_abort())
  assert_eq(actual.reuse_count, 0)
}

///|
test "atomic multi-edit falls back above the forest cutoff" {
  let source_id = @core.SourceId("markdown-atomic-reparse-cutoff")
  let builder = StringBuilder::StringBuilder()
  for index in 0..<40 {
    builder.write_string("Paragraph \{index} remains stable.\n\n")
  }
  let source = builder.to_string()
  let changes : Array[@text_change.TextChange] = []
  for index in 0..<33 {
    let prefix = "Paragraph \{index} "
    changes.push(
      @text_change.TextChange::ReplaceRange(
        start=source.find(prefix).unwrap() + prefix.length(),
        delete_len=1,
        inserted="R",
      ),
    )
  }
  let evidence = @text_change.ChangeSet::ChangeSet(
    source_length=source.length(),
    changes~,
  )
  let updated = evidence.apply(source).unwrap()
  let parser = @loom.new_parser(source_id, source, markdown_grammar)
  parser.apply_changes(evidence, updated)
  let actual = parser.snapshot().read_or_abort()
  let expected = @loom.new_parser(source_id, updated, markdown_grammar)
  assert_eq(actual.syntax, expected.syntax_tree().read_or_abort())
  assert_eq(actual.ast, expected.ast().read_or_abort())
  assert_eq(actual.diagnostics, expected.diagnostics().read_or_abort())
  assert_eq(actual.reuse_count, 0)
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
