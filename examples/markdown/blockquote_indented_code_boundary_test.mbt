///|
fn assert_commonmark_blockquote_html_regression(
  kind : String,
  label : String,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-blockquote-" + kind + "-" + label,
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
      "CommonMark blockquote " +
      kind +
      " regression " +
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
/// Indented code does not lazy-continue a blockquote. An unmarked ≥4-space
/// line after `>     foo` is a new root indented code block (CommonMark 236).
test "CommonMark example 236: unmarked indent ends blockquote indented code" {
  assert_commonmark_blockquote_html_regression(
    "indented-code-boundary", "236", ">     foo\n    bar\n", "<blockquote>\n<pre><code>foo\n</code></pre>\n</blockquote>\n<pre><code>bar\n</code></pre>\n",
  )
}

///|
/// List item content indent for `10.` is four columns. Stripping that prefix
/// leaves CommonMark example 236, so the unmarked indented line must become a
/// sibling indented code block inside the list item.
test "list-owned indent: unmarked indent ends blockquote indented code" {
  assert_commonmark_blockquote_html_regression(
    "indented-code-boundary", "236-in-list-10", "10. >     foo\n        bar\n", "<ol start=\"10\">\n<li>\n<blockquote>\n<pre><code>foo\n</code></pre>\n</blockquote>\n<pre><code>bar\n</code></pre>\n</li>\n</ol>\n",
  )
}

///|
/// Marked continuation lines remain inside one blockquote code block.
test "marked continuation keeps one blockquote indented code block" {
  assert_commonmark_blockquote_html_regression(
    "indented-code-boundary", "marked-continuation", ">     foo\n>     bar\n", "<blockquote>\n<pre><code>foo\nbar\n</code></pre>\n</blockquote>\n",
  )
}
