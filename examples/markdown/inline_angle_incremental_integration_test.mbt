///|
fn assert_inline_angle_incremental_parity(
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
  let incremental_html = experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
    incremental_ir,
    Passthrough,
  )
  assert_eq(
    incremental_html,
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      fresh_ir,
      Passthrough,
    ),
  )
  assert_eq(incremental_html, Ok(expected_html))
}

///|
test "incremental inline angle candidates match fresh parsing at every boundary" {
  let cases : Array[(String, String, @core.Edit, String, String)] = [
    (
      "URI construction",
      "<http://foo.bar.baz\n",
      @core.Edit::insert("<http://foo.bar.baz".length(), 1),
      "<http://foo.bar.baz>\n",
      "<p><a href=\"http://foo.bar.baz\">http://foo.bar.baz</a></p>\n",
    ),
    (
      "email destruction",
      "<foo@bar.example.com>\n",
      @core.Edit::delete("<foo".length(), 1),
      "<foobar.example.com>\n",
      "<p>&lt;foobar.example.com&gt;</p>\n",
    ),
    (
      "delimiter-bearing HTML construction",
      "x <a title='*'y</a>\n",
      @core.Edit::insert("x <a title='*'".length(), 1),
      "x <a title='*'>y</a>\n",
      "<p>x <a title='*'>y</a></p>\n",
    ),
    (
      "multiline trailing-space HTML construction",
      "<a href=\"foo  \nbar\"\n",
      @core.Edit::insert("<a href=\"foo  \nbar\"".length(), 1),
      "<a href=\"foo  \nbar\">\n",
      "<p><a href=\"foo  \nbar\"></p>\n",
    ),
    (
      "multiline backslash HTML construction",
      "<a href=\"foo\\\nbar\"\n",
      @core.Edit::insert("<a href=\"foo\\\nbar\"".length(), 1),
      "<a href=\"foo\\\nbar\">\n",
      "<p><a href=\"foo\\\nbar\"></p>\n",
    ),
  ]
  for angle_case in cases {
    let (label, source, edit, updated, expected_html) = angle_case
    assert_inline_angle_incremental_parity(
      @core.SourceId("markdown-inline-angle-incremental-" + label),
      label,
      source,
      edit,
      updated,
      expected_html,
    )
  }
}
