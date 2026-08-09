///|
fn list_incremental_html(ir : MarkdownIR) -> String raise {
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Escape) {
    Ok(html) => html
    Err(error) => fail(@debug.to_string(error))
  }
}

///|
fn assert_list_incremental_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-list-incremental-" + label)
  let incremental = @loom.new_parser(source_id, source, markdown_grammar)
  assert_true(edit.start >= 0 && edit.old_len >= 0 && edit.new_len >= 0)
  assert_true(edit.old_end() <= source.length())
  assert_true(edit.new_end() <= updated.length())
  assert_eq(source[:edit.start].to_owned(), updated[:edit.start].to_owned())
  assert_eq(
    source[edit.old_end():].to_owned(),
    updated[edit.new_end():].to_owned(),
  )
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let (direct_cst, direct_diagnostics) = try! parse_cst(source_id, updated)
  let direct_syntax = @seam.SyntaxNode::from_cst(direct_cst)
  let incremental_diff = @core.tree_diff(
    incremental_syntax.cst_node(),
    direct_cst,
  )
  if !incremental_diff.is_empty() {
    fail(
      label +
      ": " +
      @debug.to_string(incremental_diff) +
      "\ninc=" +
      @debug.to_string(incremental_syntax) +
      "\ndirect=" +
      @debug.to_string(direct_syntax),
    )
  }
  assert_true(@core.tree_diff(fresh_syntax.cst_node(), direct_cst).is_empty())
  assert_eq(
    incremental.diagnostics().read_or_abort(),
    fresh.diagnostics().read_or_abort(),
  )
  assert_eq(fresh.diagnostics().read_or_abort(), direct_diagnostics)
  assert_eq(incremental.ast().read_or_abort(), fresh.ast().read_or_abort())
  assert_eq(
    project_markdown_roles(incremental_syntax),
    project_markdown_roles(fresh_syntax),
  )
  assert_eq(
    project_markdown_roles(fresh_syntax),
    project_markdown_roles(direct_syntax),
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
  let direct_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, direct_syntax, direct_diagnostics,
  )
  assert_eq(incremental_ir, fresh_ir)
  assert_eq(fresh_ir, direct_ir)
  assert_eq(
    list_incremental_html(incremental_ir),
    list_incremental_html(fresh_ir),
  )
  assert_eq(list_incremental_html(fresh_ir), list_incremental_html(direct_ir))
  ignore(
    markdown_incremental_edit_reuse_count(
      source_id, label, source, edit, updated,
    ),
  )
}

///|
test "list incremental construction destruction boundaries content and recovery stay fresh-parity" {
  let cases : Array[(String, String, @core.Edit, String)] = [
    (
      "construction",
      "- a\n- b\n",
      @core.Edit::new("- a\n".length(), 3, 5),
      "- a\n  - b\n",
    ),
    (
      "destruction",
      "- a\n  - b\n",
      @core.Edit::delete("- a\n".length(), "- a\n  - b\n".length()),
      "- a\n",
    ),
    (
      "boundary-movement",
      "- a\n- b\n",
      @core.Edit::insert("- a\n".length(), 1),
      "- a\n\n- b\n",
    ),
    ("content-edit", "- foo\n", @core.Edit::new(2, 3, 3), "- bar\n"),
    ("malformed-intermediate", "- [a](u)\n", @core.Edit::new(2, 6, 2), "- [a\n"),
    (
      "blank-blockquote-boundary",
      "- a\n\n  >\n\n  b\n",
      @core.Edit::new("- a\n\n  >\n\n  ".length(), 1, 1),
      "- a\n\n  >\n\n  c\n",
    ),
  ]
  for case in cases {
    let (label, source, edit, updated) = case
    assert_list_incremental_parity(label, source, edit, updated)
  }
}
