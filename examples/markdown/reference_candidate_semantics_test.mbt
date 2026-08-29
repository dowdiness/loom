///|
fn reference_candidate_semantics_ir(
  source : String,
  extensions? : MarkdownExtensions = MarkdownExtensions::none(),
) -> MarkdownIR raise {
  let source_id = @core.SourceId("markdown-reference-candidate-semantics")
  let parser = try! @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let snapshot = parser.snapshot().read_or_abort()
  assert_eq(snapshot.source_id, source_id)
  let from_snapshot = experimental_markdown_ir_from_syntax_snapshot(
    snapshot,
    extensions~,
  )
  let from_syntax = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    snapshot.syntax,
    snapshot.diagnostics,
    extensions~,
  )
  assert_eq(from_snapshot, from_syntax)
  from_snapshot
}

///|
fn reference_candidate_semantics_assert_no_recovered(
  node : MarkdownIR,
) -> Unit raise {
  assert_false(node.is_recovered())
  for child in node.children() {
    reference_candidate_semantics_assert_no_recovered(child)
  }
}

///|
test "reference candidates become ordinary literal Markdown when unresolved" {
  let cases = [
    ("[unclosed\n", "<p>[unclosed</p>\n"),
    ("[text](\n", "<p>[text](</p>\n"),
    ("- [y] ordinary\n", "<ul>\n<li>[y] ordinary</li>\n</ul>\n"),
    ("𐐀[unclosed\n", "<p>𐐀[unclosed</p>\n"),
  ]
  for case in cases {
    let (source, expected_html) = case
    let ir = reference_candidate_semantics_ir(
      source,
      extensions=MarkdownExtensions::task_list(),
    )
    reference_candidate_semantics_assert_no_recovered(ir)
    assert_eq(experimental_markdown_ir_to_commonmark_html(ir), expected_html)
  }
}

///|
test "reference candidates still resolve every supported reference form" {
  let cases = [
    (
      "[label]\n\n[label]: /shortcut\n", "<p><a href=\"/shortcut\">label</a></p>\n",
    ),
    ("[text][label]\n\n[label]: /full\n", "<p><a href=\"/full\">text</a></p>\n"),
    (
      "[label][]\n\n[label]: /collapsed\n", "<p><a href=\"/collapsed\">label</a></p>\n",
    ),
    (
      "![label]\n\n[label]: /image.png\n", "<p><img src=\"/image.png\" alt=\"label\" /></p>\n",
    ),
    (
      "*[label*]\n\n[label*]: /emphasis\n", "<p>*<a href=\"/emphasis\">label*</a></p>\n",
    ),
  ]
  for case in cases {
    let (source, expected_html) = case
    let ir = reference_candidate_semantics_ir(source)
    reference_candidate_semantics_assert_no_recovered(ir)
    assert_eq(experimental_markdown_ir_to_commonmark_html(ir), expected_html)
  }
}

///|
test "code-owned and escaped brackets never become reference candidates" {
  let cases = [
    ("\\[label]\n\n[label]: /url\n", "<p>[label]</p>\n"),
    ("[foo`](/uri)`\n\n[foo]: /url\n", "<p>[foo<code>](/uri)</code></p>\n"),
  ]
  for case in cases {
    let (source, expected_html) = case
    let ir = reference_candidate_semantics_ir(source)
    reference_candidate_semantics_assert_no_recovered(ir)
    assert_eq(experimental_markdown_ir_to_commonmark_html(ir), expected_html)
  }
}
