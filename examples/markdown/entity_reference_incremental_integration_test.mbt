///|
fn assert_entity_reference_incremental_projection_parity(
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
test "incremental entities: construction, destruction, boundaries, and neighbors match fresh" {
  let cases : Array[(String, String, @core.Edit, String, String)] = [
    (
      "named reference construction",
      "&copy\n\nTail\n",
      @core.Edit::insert("&copy".length(), 1),
      "&copy;\n\nTail\n",
      "<p>©</p>\n<p>Tail</p>\n",
    ),
    (
      "numeric reference destruction",
      "&#35;\n\nTail\n",
      @core.Edit::replace("&#35".length(), 1, 1),
      "&#35x\n\nTail\n",
      "<p>&amp;#35x</p>\n<p>Tail</p>\n",
    ),
    (
      "numeric reference exceeds seven digit boundary",
      "&#1114111;\n\nTail\n",
      @core.Edit::insert("&#1114111".length(), 1),
      "&#11141111;\n\nTail\n",
      "<p>&amp;#11141111;</p>\n<p>Tail</p>\n",
    ),
    (
      "named reference leaves the authoritative table",
      "&copy;\n\nTail\n",
      @core.Edit::insert("&copy".length(), 1),
      "&copyx;\n\nTail\n",
      "<p>&amp;copyx;</p>\n<p>Tail</p>\n",
    ),
    (
      "neighboring inline text changes beside a stable reference",
      "left &copy; right\n\nTail\n",
      @core.Edit::replace("left &copy; ".length(), "right".length(), 5),
      "left &copy; RIGHT\n\nTail\n",
      "<p>left © RIGHT</p>\n<p>Tail</p>\n",
    ),
  ]
  for entity_case in cases {
    let (label, source, edit, updated, expected_html) = entity_case
    assert_entity_reference_incremental_projection_parity(
      @core.SourceId("markdown-entity-incremental-" + label),
      label,
      source,
      edit,
      updated,
      expected_html,
    )
  }
}
