///|
fn assert_reference_definition_incremental_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  lookup_label : String?,
  expected_destination : String?,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-reference-definition-" + label)
  ignore(
    @loom.assert_incremental_edit_matches_full_parse(
      source_id,
      label,
      source,
      edit,
      updated,
      markdown_grammar.to_syntax_grammar(),
    ),
  )
  let incremental = @loom.new_parser(source_id, source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let incremental_diagnostics = incremental.diagnostics().read_or_abort()
  let fresh_diagnostics = fresh.diagnostics().read_or_abort()
  assert_eq(incremental_diagnostics, fresh_diagnostics)
  assert_eq(incremental.ast().read_or_abort(), fresh.ast().read_or_abort())
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, incremental_syntax, incremental_diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, fresh_syntax, fresh_diagnostics,
  )
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
  let incremental_table = collect_link_reference_definitions(incremental_syntax)
  let fresh_table = collect_link_reference_definitions(fresh_syntax)
  assert_eq(incremental_table.length(), fresh_table.length())
  match (lookup_label, expected_destination) {
    (Some(normalized_label), Some(destination)) =>
      match
        (
          incremental_table.lookup(normalized_label),
          fresh_table.lookup(normalized_label),
        ) {
        (Some(incremental_definition), Some(fresh_definition)) => {
          assert_eq(
            incremental_definition.normalized_label,
            fresh_definition.normalized_label,
          )
          assert_eq(
            incremental_definition.destination_value,
            fresh_definition.destination_value,
          )
          assert_eq(
            incremental_definition.title_value,
            fresh_definition.title_value,
          )
          assert_eq(
            incremental_definition.definition_origin,
            fresh_definition.definition_origin,
          )
          assert_eq(
            incremental_definition.label_value_origin,
            fresh_definition.label_value_origin,
          )
          assert_eq(
            incremental_definition.destination_value_origin,
            fresh_definition.destination_value_origin,
          )
          assert_eq(
            incremental_definition.title_value_origin,
            fresh_definition.title_value_origin,
          )
          inspect(incremental_definition.destination_value, content=destination)
        }
        _ =>
          fail("expected reference definition in incremental and fresh tables")
      }
    (None, None) => assert_eq(incremental_table.length(), 0)
    _ =>
      fail("lookup label and expected destination must be specified together")
  }
}

///|
test "incremental reference definitions: construction, destruction, duplicate, and label edits match fresh" {
  let tail = "\nTail\n"
  assert_reference_definition_incremental_parity(
    "construct-definition",
    "[foo] /url" + tail,
    @core.Edit::insert("[foo]".length(), 1),
    "[foo]: /url" + tail,
    Some("foo"),
    Some("/url"),
    "<p>Tail</p>\n",
  )
  assert_reference_definition_incremental_parity(
    "destroy-definition",
    "[foo]: /url" + tail,
    @core.Edit::new("[foo]".length(), 1, 0),
    "[foo] /url" + tail,
    None,
    None,
    "<p>[foo] /url\nTail</p>\n",
  )
  let first_prefix = "[foo]: /first\n[FOO]"
  assert_reference_definition_incremental_parity(
    "construct-duplicate",
    first_prefix + " /second" + tail,
    @core.Edit::insert(first_prefix.length(), 1),
    first_prefix + ": /second" + tail,
    Some("foo"),
    Some("/first"),
    "<p>Tail</p>\n",
  )
  assert_reference_definition_incremental_parity(
    "edit-normalized-label",
    "[Foo Bar]: /url" + tail,
    @core.Edit::new(1, "Foo Bar".length(), "ΑΓΩ".length()),
    "[ΑΓΩ]: /url" + tail,
    Some("αγω"),
    Some("/url"),
    "<p>Tail</p>\n",
  )
  assert_reference_definition_incremental_parity(
    "construct-block-quote-definition",
    "> [foo]: x)y\n",
    @core.Edit::new("> [foo]: x".length(), 1, 1),
    "> [foo]: xay\n",
    Some("foo"),
    Some("xay"),
    "<blockquote>\n</blockquote>\n",
  )
  assert_reference_definition_incremental_parity(
    "destroy-block-quote-definition",
    "> [foo]: xay\n",
    @core.Edit::new("> [foo]: x".length(), 1, 1),
    "> [foo]: x)y\n",
    None,
    None,
    "<blockquote>\n<p>[foo]: x)y</p>\n</blockquote>\n",
  )
  let list_paragraph_prefix = "- text\n  [foo]"
  assert_reference_definition_incremental_parity(
    "list-paragraph-does-not-become-definition",
    list_paragraph_prefix + " /url\n",
    @core.Edit::insert(list_paragraph_prefix.length(), 1),
    list_paragraph_prefix + ": /url\n",
    None,
    None,
    "<ul>\n<li>text\n[foo]: /url</li>\n</ul>\n",
  )
  let blank_separated_prefix = "- text\n\n  [foo]"
  assert_reference_definition_incremental_parity(
    "blank-separated-list-definition",
    blank_separated_prefix + " /url\n",
    @core.Edit::insert(blank_separated_prefix.length(), 1),
    blank_separated_prefix + ": /url\n",
    Some("foo"),
    Some("/url"),
    "<ul>\n<li>\n<p>text</p>\n</li>\n</ul>\n",
  )
  let empty_item_prefix = "-\n  [foo]"
  assert_reference_definition_incremental_parity(
    "empty-list-item-definition",
    empty_item_prefix + " /url\n",
    @core.Edit::insert(empty_item_prefix.length(), 1),
    empty_item_prefix + ": /url\n",
    Some("foo"),
    Some("/url"),
    "<ul>\n<li></li>\n</ul>\n",
  )
}

///|
test "incremental reference definitions: official angle, title, and indentation boundaries match fresh" {
  let angle_prefix = "[foo]: <bar>"
  assert_reference_definition_incremental_parity(
    "commonmark-201-angle-boundary",
    angle_prefix + "\n",
    @core.Edit::insert(angle_prefix.length(), 5),
    angle_prefix + "(baz)\n",
    None,
    None,
    "<p>[foo]: &lt;bar&gt;(baz)</p>\n",
  )
  let escaped_angle_prefix = "[foo]: <bar\\>ba"
  assert_reference_definition_incremental_parity(
    "escaped-angle-destination",
    escaped_angle_prefix + "x>\n\n[foo]\n",
    @core.Edit::replace(
      escaped_angle_prefix.length(),
      escaped_angle_prefix.length() + 1,
      1,
    ),
    escaped_angle_prefix + "z>\n\n[foo]\n",
    Some("foo"),
    Some("bar>baz"),
    "<p><a href=\"bar%3Ebaz\">foo</a></p>\n",
  )
  let escaped_punctuation_prefix = "[foo]: <bar\\*ba"
  assert_reference_definition_incremental_parity(
    "escaped-punctuation-destination",
    escaped_punctuation_prefix + "x>\n\n[foo]\n",
    @core.Edit::replace(
      escaped_punctuation_prefix.length(),
      escaped_punctuation_prefix.length() + 1,
      1,
    ),
    escaped_punctuation_prefix + "z>\n\n[foo]\n",
    Some("foo"),
    Some("bar*baz"),
    "<p><a href=\"bar*baz\">foo</a></p>\n",
  )
  let continuation_prefix = "[foo]: <bar>"
  assert_reference_definition_incremental_parity(
    "commonmark-201-paragraph-continuation-boundary",
    continuation_prefix + "\ncontinued\n",
    @core.Edit::insert(continuation_prefix.length(), 5),
    continuation_prefix + "(baz)\ncontinued\n",
    None,
    None,
    "<p>[foo]: &lt;bar&gt;(baz)\ncontinued</p>\n",
  )
  let title_prefix = "[foo]: /url"
  assert_reference_definition_incremental_parity(
    "multiline-title-boundary",
    title_prefix + " \"title\"\n",
    @core.Edit::replace(title_prefix.length(), title_prefix.length() + 1, 1),
    title_prefix + "\n \"title\"\n",
    Some("foo"),
    Some("/url"),
    "",
  )
  let indentation_prefix = "   [foo]: /url \"title\"\n"
  assert_reference_definition_incremental_parity(
    "commonmark-211-indentation-boundary",
    indentation_prefix,
    @core.Edit::insert(3, 1),
    " " + indentation_prefix,
    None,
    None,
    "<pre><code>[foo]: /url &quot;title&quot;\n</code></pre>\n",
  )
}
