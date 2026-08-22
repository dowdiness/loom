///|
fn assert_commonmark_blockquote_blank_line_split(
  label : String,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-blockquote-blank-line-split-" + label,
  )
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  assert_true(diagnostics.is_empty())
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let actual = match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(html) => html
    Err(_) => abort("Passthrough raw HTML policy cannot reject valid HTML")
  }
  guard actual == expected_html else {
    fail(
      "CommonMark blockquote blank-line split regression " +
      label +
      "\nexpected: " +
      @debug.to_string(expected_html) +
      "\nactual:   " +
      @debug.to_string(actual) +
      "\nir:       " +
      ir.kind_tag(),
    )
  }
}

///|
test "CommonMark example 252: blank line splits blockquote after indented code" {
  assert_commonmark_blockquote_blank_line_split(
    "252", ">     code\n\n>    not code\n", "<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n<blockquote>\n<p>not code</p>\n</blockquote>\n",
  )
}

///|
test "CommonMark example 242: blank line splits consecutive blockquotes" {
  assert_commonmark_blockquote_blank_line_split(
    "242", "> foo\n\n> bar\n", "<blockquote>\n<p>foo</p>\n</blockquote>\n<blockquote>\n<p>bar</p>\n</blockquote>\n",
  )
}

///|
/// List item content indent for `10.` is four columns (W+N). Stripping that
/// prefix leaves CommonMark example 252, so the item must contain two sibling
/// blockquotes rather than absorbing the second quote into indented code.
test "list-owned indent: blank line splits blockquote after indented code" {
  assert_commonmark_blockquote_blank_line_split(
    "252-in-list-10", "10. >     code\n\n    >    not code\n", "<ol start=\"10\">\n<li>\n<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n<blockquote>\n<p>not code</p>\n</blockquote>\n</li>\n</ol>\n",
  )
}
