///|
fn assert_line_break_incremental_projection_parity(
  source_id : @core.SourceId,
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  expected_html : String,
) -> Unit raise {
  ignore(
    markdown_incremental_edit_reuse_count(
      source_id, label, source, edit, updated,
    ),
  )
  let incremental = @loom.new_parser(source_id, source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let incremental_diagnostics = incremental.diagnostics().read_or_abort()
  let fresh_diagnostics = fresh.diagnostics().read_or_abort()
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, incremental_syntax, incremental_diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, fresh_syntax, fresh_diagnostics,
  )
  assert_eq(incremental_diagnostics, fresh_diagnostics)
  assert_eq(incremental.ast().read_or_abort(), fresh.ast().read_or_abort())
  assert_eq(incremental_ir, fresh_ir)
  assert_eq(
    project_markdown_roles(incremental_syntax),
    project_markdown_roles(fresh_syntax),
  )
  assert_eq(
    experimental_markdown_ir_to_mdast_json(incremental_ir),
    experimental_markdown_ir_to_mdast_json(fresh_ir),
  )
  let incremental_html = experimental_markdown_ir_to_commonmark_html(
    incremental_ir,
  )
  assert_eq(
    incremental_html,
    experimental_markdown_ir_to_commonmark_html(fresh_ir),
  )
  inspect(incremental_html, content=expected_html)
}

///|
test "incremental line breaks: construction, destruction, surfaces, and neighbors match fresh" {
  let cases : Array[(String, String, @core.Edit, String, String)] = [
    (
      "soft break construction",
      "foobar\n\nTail\n",
      @core.Edit::insert("foo".length(), 1),
      "foo\nbar\n\nTail\n",
      "<p>foo\nbar</p>\n<p>Tail</p>\n",
    ),
    (
      "trailing-space hard break construction",
      "foo \nbar\n\nTail\n",
      @core.Edit::insert("foo ".length(), 1),
      "foo  \nbar\n\nTail\n",
      "<p>foo<br />\nbar</p>\n<p>Tail</p>\n",
    ),
    (
      "hard break destruction",
      "foo  \nbar\n\nTail\n",
      @core.Edit::delete("foo ".length(), 1),
      "foo \nbar\n\nTail\n",
      "<p>foo\nbar</p>\n<p>Tail</p>\n",
    ),
    (
      "hard break surface changes from spaces to backslash",
      "foo  \nbar\n\nTail\n",
      @core.Edit::replace("foo".length(), 2, 1),
      "foo\\\nbar\n\nTail\n",
      "<p>foo<br />\nbar</p>\n<p>Tail</p>\n",
    ),
    (
      "neighboring inline edit beside nested hard break",
      "*foo\\\nbar*\n\nTail\n",
      @core.Edit::replace("*foo\\\n".length(), "bar".length(), 3),
      "*foo\\\nBAR*\n\nTail\n",
      "<p><em>foo<br />\nBAR</em></p>\n<p>Tail</p>\n",
    ),
  ]
  for line_break_case in cases {
    let (label, source, edit, updated, expected_html) = line_break_case
    assert_line_break_incremental_projection_parity(
      @core.SourceId("markdown-line-break-incremental-" + label),
      label,
      source,
      edit,
      updated,
      expected_html,
    )
  }
}
