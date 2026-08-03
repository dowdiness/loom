///|
test "markdown projection attachment collection retires the prior revision" {
  let source = "old [x]\n\n[x]: /x\n"
  let updated = "new [y]\n\n[y]: /y\n"
  let parser = reactive_keyed_markdown_test_parser(
    @core.SourceId("markdown-projection-attachment-collect"),
    source,
  )
  let attachment = attach_markdown_projection(parser)
  parser.apply_edit(
    @core.Edit::new(0, source.length(), updated.length()),
    updated,
  )
  ignore(attachment.projection())
  assert_eq(attachment.shell.plan_by_cst.cache_len(), 2)
  assert_eq(attachment.shell.resolved_by_cst.cache_len(), 2)
  assert_eq(attachment.shell.definition_by_label.cache_len(), 2)
  assert_eq(attachment.block_cache_len(), 2)
  attachment.collect()
  assert_eq(attachment.shell.plan_by_cst.cache_len(), 1)
  assert_eq(attachment.shell.resolved_by_cst.cache_len(), 1)
  assert_eq(attachment.shell.definition_by_label.cache_len(), 1)
  assert_eq(attachment.block_cache_len(), 1)
  attachment.dispose()
}
