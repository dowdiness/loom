///|
test "Markdown semantic attachment bounds keyed work across 10000 edits" {
  let source_id = @core.SourceId("markdown-semantic-attachment-long-churn")
  let initial = "seed\n"
  let parser = @loom.new_parser(source_id, initial, markdown_grammar)
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  ignore(attachment.document())
  let mut current = initial
  for index = 0; index < 5000; index = index + 1 {
    let replacement = "unique-" + index.to_string() + "\n"
    parser.apply_edit(
      @core.Edit::new(0, current.length(), replacement.length()),
      replacement,
    )
    ignore(attachment.document())
    assert_true(attachment.shell.plan_by_cst.cache_len() <= 1)
    assert_true(attachment.shell.resolved_by_cst.cache_len() <= 1)
    assert_eq(attachment.shell.definition_by_label.cache_len(), 0)

    parser.apply_edit(@core.Edit::new(0, replacement.length(), 0), "")
    ignore(attachment.document())
    assert_eq(attachment.shell.plan_by_cst.cache_len(), 0)
    assert_eq(attachment.shell.resolved_by_cst.cache_len(), 0)
    assert_eq(attachment.shell.definition_by_label.cache_len(), 0)
    current = ""
  }
  attachment.dispose()
}
