///|
test "incremental delimiter edit uses block reparse and matches fresh projections" {
  let source = "Before *alpha* after\n\nTail paragraph\n"
  let updated = "Before _alpha* after\n\nTail paragraph\n"
  let edit = @core.Edit::new("Before ".length(), 1, 1)
  assert_delimiter_incremental_projection_parity(
    "markdown emphasis opener changes from asterisk to underscore", source, edit,
    updated, "<p>Before _alpha* after</p>\n<p>Tail paragraph</p>\n",
  )
}

///|
fn assert_delimiter_incremental_projection_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  expected_html : String,
) -> Unit raise {
  let reuse_count = markdown_incremental_edit_reuse_count(
    label, source, edit, updated,
  )

  let incremental = @loom.new_parser(source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let incremental_diagnostics = incremental.diagnostics().read_or_abort()
  let fresh_diagnostics = fresh.diagnostics().read_or_abort()
  let incremental_block = incremental.ast().read_or_abort()
  let fresh_block = fresh.ast().read_or_abort()
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    incremental_syntax, incremental_diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    fresh_syntax, fresh_diagnostics,
  )
  let incremental_roles = project_markdown_roles(incremental_syntax)
  let fresh_roles = project_markdown_roles(fresh_syntax)

  inspect(incremental_block, content=@debug.to_string(fresh_block))
  guard incremental_ir == fresh_ir else {
    fail(
      "expected incremental MarkdownIR to match a fresh projection: " + label,
    )
  }
  guard incremental_roles == fresh_roles else {
    fail(
      "expected incremental delimiter roles to match a fresh projection: " +
      label,
    )
  }
  inspect(
    experimental_markdown_ir_to_block(incremental_ir),
    content=@debug.to_string(incremental_block),
  )
  let actual_html = experimental_markdown_ir_to_commonmark_html(incremental_ir)
  guard actual_html == expected_html else {
    fail(
      "unexpected incremental CommonMark HTML: " +
      label +
      "\nexpected: " +
      @debug.to_string(expected_html) +
      "\nactual:   " +
      @debug.to_string(actual_html),
    )
  }

  let role_parser = @loom.new_syntax_parser(
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let role_attachment = attach_markdown_role_spans(role_parser)
  role_parser.apply_edit(edit, updated)
  guard role_attachment.spans() == fresh_roles else {
    role_attachment.dispose()
    fail(
      "expected attached delimiter roles to match a fresh projection: " + label,
    )
  }
  role_attachment.dispose()
  inspect(reuse_count, content="1")
}

///|
test "incremental delimiter run-length and flanking edits match fresh projections" {
  let cases : Array[(String, String, @core.Edit, String, String)] = [
    (
      "markdown partial triple opener becomes a strong opener",
      "***foo**\n\nTail\n",
      @core.Edit::delete(0, 1),
      "**foo**\n\nTail\n",
      "<p><strong>foo</strong></p>\n<p>Tail</p>\n",
    ),
    (
      "markdown whitespace edit makes an asterisk opener left-flanking",
      "x * b* z\n\nTail\n",
      @core.Edit::delete("x *".length(), "x * ".length()),
      "x *b* z\n\nTail\n",
      "<p>x <em>b</em> z</p>\n<p>Tail</p>\n",
    ),
    (
      "markdown punctuation edit makes an underscore opener eligible",
      "a_b_.\n\nTail\n",
      @core.Edit::new(0, 1, 1),
      "._b_.\n\nTail\n",
      "<p>.<em>b</em>.</p>\n<p>Tail</p>\n",
    ),
  ]
  for case in cases {
    let (label, source, edit, updated, expected_html) = case
    assert_delimiter_incremental_projection_parity(
      label, source, edit, updated, expected_html,
    )
  }
}

///|
test "incremental delimiter semantic-boundary edits match fresh projections" {
  let cases : Array[(String, String, @core.Edit, String, String)] = [
    (
      "markdown rule-of-three middle run gains a marker",
      "*a**a*\n\nTail\n",
      @core.Edit::insert("*a**".length(), "*".length()),
      "*a***a*\n\nTail\n",
      "<p><em>a</em>*<em>a</em></p>\n<p>Tail</p>\n",
    ),
    (
      "markdown adjacent nested strong closer gains a marker",
      "*foo**bar*baz*\n\nTail\n",
      @core.Edit::insert("*foo**bar*".length(), "*".length()),
      "*foo**bar**baz*\n\nTail\n",
      "<p><em>foo<strong>bar</strong>baz</em></p>\n<p>Tail</p>\n",
    ),
    (
      "markdown link label gains a scoped delimiter marker",
      "*[bar](/url)\n\nTail\n",
      @core.Edit::insert("*[bar".length(), "*".length()),
      "*[bar*](/url)\n\nTail\n",
      "<p>*<a href=\"/url\">bar*</a></p>\n<p>Tail</p>\n",
    ),
    (
      "markdown code span content becomes an opaque delimiter marker",
      "_a `x`_\n\nTail\n",
      @core.Edit::new("_a `".length(), "x".length(), "_".length()),
      "_a `_`_\n\nTail\n",
      "<p><em>a <code>_</code></em></p>\n<p>Tail</p>\n",
    ),
    (
      "markdown CommonMark Unicode punctuation adjacency gains a marker",
      "*£bravo.\n\nTail\n",
      @core.Edit::insert("*£".length(), "*".length()),
      "*£*bravo.\n\nTail\n",
      "<p>*£*bravo.</p>\n<p>Tail</p>\n",
    ),
  ]
  for case in cases {
    let (label, source, edit, updated, expected_html) = case
    assert_delimiter_incremental_projection_parity(
      label, source, edit, updated, expected_html,
    )
  }
}
