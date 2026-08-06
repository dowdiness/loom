///|
fn assert_inline_angle_parser_matches_fresh(
  source_id : @core.SourceId,
  parser : @loom.Parser[Block],
  source : String,
  expected_html : String,
) -> Unit raise {
  let fresh = @loom.new_parser(source_id, source, markdown_grammar)
  assert_eq(parser.source().read_or_abort(), source)
  let syntax = parser.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let diagnostics = parser.diagnostics().read_or_abort()
  let fresh_diagnostics = fresh.diagnostics().read_or_abort()
  assert_eq(syntax, fresh_syntax)
  assert_eq(diagnostics, fresh_diagnostics)
  assert_eq(parser.ast().read_or_abort(), fresh.ast().read_or_abort())
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, syntax, diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, fresh_syntax, fresh_diagnostics,
  )
  assert_eq(ir, fresh_ir)
  assert_eq(
    project_markdown_roles(syntax),
    project_markdown_roles(fresh_syntax),
  )
  assert_eq(
    experimental_markdown_ir_to_mdast_json(ir),
    experimental_markdown_ir_to_mdast_json(fresh_ir),
  )
  let html = experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
    ir,
    Passthrough,
  )
  assert_eq(
    html,
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      fresh_ir,
      Passthrough,
    ),
  )
  assert_eq(html, Ok(expected_html))
}

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
  assert_inline_angle_parser_matches_fresh(
    source_id, incremental, updated, expected_html,
  )
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
      "URI construction before CRLF",
      "<http://foo.bar.baz\r\n",
      @core.Edit::insert("<http://foo.bar.baz".length(), 1),
      "<http://foo.bar.baz>\r\n",
      "<p><a href=\"http://foo.bar.baz\">http://foo.bar.baz</a></p>\n",
    ),
    (
      "URI construction before CR",
      "<http://foo.bar.baz\r",
      @core.Edit::insert("<http://foo.bar.baz".length(), 1),
      "<http://foo.bar.baz>\r",
      "<p><a href=\"http://foo.bar.baz\">http://foo.bar.baz</a></p>\n",
    ),
    (
      "URI construction at EOF",
      "<http://foo.bar.baz",
      @core.Edit::insert("<http://foo.bar.baz".length(), 1),
      "<http://foo.bar.baz>",
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

///|
test "CommonMark example 91 edits and restores match fresh parsing" {
  let source_id = @core.SourceId("markdown-commonmark-example-91-incremental")
  let fixture = commonmark_html_fixture_case_by_example(91).unwrap()
  let source = fixture.source
  let expected = fixture.expected_html
  let parser = @loom.new_parser(source_id, source, markdown_grammar)
  assert_inline_angle_parser_matches_fresh(source_id, parser, source, expected)

  guard source.find("\n---\nof dashes") is Some(anchor_start) else {
    fail("expected example 91 underline anchor")
  }
  let underline_start = anchor_start + 1
  let invalid_underline = source[:underline_start].to_owned() +
    "-x-" +
    source[underline_start + 3:].to_owned()
  parser.apply_edit(@core.Edit::new(underline_start, 3, 3), invalid_underline)
  assert_inline_angle_parser_matches_fresh(
    source_id, parser, invalid_underline, "<h2>`Foo</h2>\n<p>`</p>\n<p><a title=\"a lot\n-x-\nof dashes\"/></p>\n",
  )
  parser.apply_edit(@core.Edit::new(underline_start, 3, 3), source)
  assert_inline_angle_parser_matches_fresh(source_id, parser, source, expected)

  guard source.find("a lot") is Some(content_start) else {
    fail("expected example 91 multiline content anchor")
  }
  let inserted = "very "
  let edited_content = source[:content_start].to_owned() +
    inserted +
    source[content_start:].to_owned()
  parser.apply_edit(
    @core.Edit::insert(content_start, inserted.length()),
    edited_content,
  )
  assert_inline_angle_parser_matches_fresh(
    source_id, parser, edited_content, "<h2>`Foo</h2>\n<p>`</p>\n<h2>&lt;a title=&quot;very a lot</h2>\n<p>of dashes&quot;/&gt;</p>\n",
  )
  parser.apply_edit(
    @core.Edit::delete(content_start, content_start + inserted.length()),
    source,
  )
  assert_inline_angle_parser_matches_fresh(source_id, parser, source, expected)
}

///|
test "inline angle index invalidation is isolated across parser sessions" {
  let source_id_a = @core.SourceId("markdown-inline-angle-session-a")
  let source_a = "x <!--open\n"
  let updated_a = "x <!--open-->\n"
  let parser_a = @loom.new_parser(source_id_a, source_a, markdown_grammar)
  let source_id_b = @core.SourceId("markdown-inline-angle-session-b")
  let source_b = "x <?pi?>\n"
  let updated_b = "x <?pi\n"
  let parser_b = @loom.new_parser(source_id_b, source_b, markdown_grammar)
  parser_a.apply_edit(
    @core.Edit::insert("x <!--open".length(), "-->".length()),
    updated_a,
  )
  parser_b.apply_edit(
    @core.Edit::delete("x <?pi".length(), "?>".length()),
    updated_b,
  )
  let fresh_a = @loom.new_parser(source_id_a, updated_a, markdown_grammar)
  let fresh_b = @loom.new_parser(source_id_b, updated_b, markdown_grammar)
  assert_eq(
    parser_a.syntax_tree().read_or_abort(),
    fresh_a.syntax_tree().read_or_abort(),
  )
  assert_eq(
    parser_b.syntax_tree().read_or_abort(),
    fresh_b.syntax_tree().read_or_abort(),
  )
  assert_eq(
    experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id_a,
      parser_a.syntax_tree().read_or_abort(),
      parser_a.diagnostics().read_or_abort(),
    ),
    experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id_a,
      fresh_a.syntax_tree().read_or_abort(),
      fresh_a.diagnostics().read_or_abort(),
    ),
  )
  assert_eq(
    experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id_b,
      parser_b.syntax_tree().read_or_abort(),
      parser_b.diagnostics().read_or_abort(),
    ),
    experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id_b,
      fresh_b.syntax_tree().read_or_abort(),
      fresh_b.diagnostics().read_or_abort(),
    ),
  )
}
