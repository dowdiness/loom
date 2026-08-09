///|
fn assert_commonmark_list_regression(
  example : Int,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-list-regression-" + example.to_string(),
  )
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  assert_true(diagnostics.is_empty())
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let actual = experimental_markdown_ir_to_commonmark_html(ir)
  guard actual == expected_html else {
    fail(
      "CommonMark list regression " +
      example.to_string() +
      "\nexpected: " +
      @debug.to_string(expected_html) +
      "\nactual:   " +
      @debug.to_string(actual),
    )
  }
}

///|
test "CommonMark list regressions 254 280 286 287 288 290" {
  let cases : Array[(Int, String, String)] = [
    (
      254,
      "1.  A paragraph\n" +
      "    with two lines.\n" +
      "\n" +
      "        indented code\n" +
      "\n" +
      "    > A block quote.\n",
      "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n" +
      "<pre><code>indented code\n</code></pre>\n" +
      "<blockquote>\n<p>A block quote.</p>\n</blockquote>\n" +
      "</li>\n</ol>\n",
    ),
    (280, "-\n\n  foo\n", "<ul>\n<li></li>\n</ul>\n<p>foo</p>\n"),
    (
      286,
      " 1.  A paragraph\n" +
      "     with two lines.\n" +
      "\n" +
      "         indented code\n" +
      "\n" +
      "     > A block quote.\n",
      "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n" +
      "<pre><code>indented code\n</code></pre>\n" +
      "<blockquote>\n<p>A block quote.</p>\n</blockquote>\n" +
      "</li>\n</ol>\n",
    ),
    (
      287,
      "  1.  A paragraph\n" +
      "      with two lines.\n" +
      "\n" +
      "          indented code\n" +
      "\n" +
      "      > A block quote.\n",
      "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n" +
      "<pre><code>indented code\n</code></pre>\n" +
      "<blockquote>\n<p>A block quote.</p>\n</blockquote>\n" +
      "</li>\n</ol>\n",
    ),
    (
      288,
      "   1.  A paragraph\n" +
      "       with two lines.\n" +
      "\n" +
      "           indented code\n" +
      "\n" +
      "       > A block quote.\n",
      "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n" +
      "<pre><code>indented code\n</code></pre>\n" +
      "<blockquote>\n<p>A block quote.</p>\n</blockquote>\n" +
      "</li>\n</ol>\n",
    ),
    (
      290,
      "  1.  A paragraph\n" +
      "with two lines.\n" +
      "\n" +
      "          indented code\n" +
      "\n" +
      "      > A block quote.\n",
      "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n" +
      "<pre><code>indented code\n</code></pre>\n" +
      "<blockquote>\n<p>A block quote.</p>\n</blockquote>\n" +
      "</li>\n</ol>\n",
    ),
  ]
  for case in cases {
    let (example, source, expected_html) = case
    assert_commonmark_list_regression(example, source, expected_html)
  }
}

///|
test "CommonMark list regressions: structural first children keep continuation" {
  let cases : Array[(Int, String, String)] = [
    (
      39401, "- > a\n\n  b\n", "<ul>\n<li>\n<blockquote>\n<p>a</p>\n</blockquote>\n<p>b</p>\n</li>\n</ul>\n",
    ),
    (
      39402, "- - a\n\n  b\n", "<ul>\n<li>\n<ul>\n<li>a</li>\n</ul>\n<p>b</p>\n</li>\n</ul>\n",
    ),
    (
      39403, "- # a\n\n  b\n", "<ul>\n<li>\n<h1>a</h1>\n<p>b</p>\n</li>\n</ul>\n",
    ),
    (
      39404, "- 1. a\n\n  b\n", "<ul>\n<li>\n<ol>\n<li>a</li>\n</ol>\n<p>b</p>\n</li>\n</ul>\n",
    ),
    (
      39405, "  - - foo\n- bar\n", "<ul>\n<li>\n<ul>\n<li>foo</li>\n</ul>\n</li>\n<li>bar</li>\n</ul>\n",
    ),
  ]
  for case in cases {
    let (example, source, expected_html) = case
    assert_commonmark_list_regression(example, source, expected_html)
  }
}
