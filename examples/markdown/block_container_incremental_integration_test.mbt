///|
fn assert_block_container_incremental_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
) -> Int raise {
  let source_id = @core.SourceId("markdown-block-container-decision-core")
  let reuse_count = markdown_incremental_edit_reuse_count(
    source_id, label, source, edit, updated,
  )
  let incremental = @loom.new_parser(source_id, source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  assert_eq(incremental.ast().read_or_abort(), fresh.ast().read_or_abort())
  assert_eq(
    project_markdown_roles(incremental_syntax),
    project_markdown_roles(fresh_syntax),
  )
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    incremental_syntax,
    incremental.diagnostics().read_or_abort(),
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    fresh_syntax,
    fresh.diagnostics().read_or_abort(),
  )
  assert_eq(incremental_ir, fresh_ir)
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(incremental_ir),
    experimental_markdown_ir_to_commonmark_html(fresh_ir),
  )
  reuse_count
}

///|
test "block container core: migrated edit families match fresh semantic projections" {
  ignore(
    assert_block_container_incremental_parity(
      "block container indentation boundary",
      "paragraph\n   # heading\n",
      @core.Edit::insert("paragraph\n".length(), " ".length()),
      "paragraph\n    # heading\n",
    ),
  )
  let blank_line_reuse = assert_block_container_incremental_parity(
    "block container blank-line boundary",
    "- one\n- two\n",
    @core.Edit::insert("- one\n".length(), "\n".length()),
    "- one\n\n- two\n",
  )
  inspect(blank_line_reuse != 1, content="true")
  ignore(
    assert_block_container_incremental_parity(
      "block container blockquote lazy continuation",
      "> bar\n> baz\n",
      @core.Edit::delete("> bar\n".length(), "> bar\n> ".length()),
      "> bar\nbaz\n",
    ),
  )
  let marker_reuse = assert_block_container_incremental_parity(
    "block container marker boundary",
    "- one\n- two\n- three\n",
    @core.Edit::new("- one\n".length(), "-".length(), "*".length()),
    "- one\n* two\n- three\n",
  )
  inspect(marker_reuse != 1, content="true")
  let fence_reuse = assert_block_container_incremental_parity(
    "block container fence boundary",
    "`` text\nTail\n",
    @core.Edit::insert("``".length(), "`".length()),
    "``` text\nTail\n",
  )
  inspect(fence_reuse != 1, content="true")
}
