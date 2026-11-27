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
  let (cst, diagnostics) = try! @markdown.parse_cst(source_id, source)
  assert_true(diagnostics.is_empty())
  let ir = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let actual = match
    @markdown.experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
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

///|
/// A tab between nested quote markers expands from the outer marker's
/// column. These lines used to abort the parser before a list marker and
/// must nest like their space-only spellings.
test "tab-indented nested quote markers stay nested" {
  let cases : Array[(String, String)] = [
    // No space after the inner marker still lets `+` open a list.
    (
      "> >+ >\n", "<blockquote>\n<blockquote>\n<ul>\n<li>\n<blockquote>\n</blockquote>\n</li>\n</ul>\n</blockquote>\n</blockquote>\n",
    ),
    (
      ">  \t>+\n", "<blockquote>\n<blockquote>\n<ul>\n<li></li>\n</ul>\n</blockquote>\n</blockquote>\n",
    ),
    (
      "> \t>+ >\n", "<blockquote>\n<blockquote>\n<ul>\n<li>\n<blockquote>\n</blockquote>\n</li>\n</ul>\n</blockquote>\n</blockquote>\n",
    ),
    (
      ">  \t>+ a\n", "<blockquote>\n<blockquote>\n<ul>\n<li>a</li>\n</ul>\n</blockquote>\n</blockquote>\n",
    ),
    (
      "> \t> a\n", "<blockquote>\n<blockquote>\n<p>a</p>\n</blockquote>\n</blockquote>\n",
    ),
    (
      ">  \t> a\n> \t> b\n", "<blockquote>\n<blockquote>\n<p>a\nb</p>\n</blockquote>\n</blockquote>\n",
    ),
    (
      "> \t>\t> a\n", "<blockquote>\n<blockquote>\n<blockquote>\n<p>a</p>\n</blockquote>\n</blockquote>\n</blockquote>\n",
    ),
    (
      ">\t\t> a\n", "<blockquote>\n<pre><code>  &gt; a\n</code></pre>\n</blockquote>\n",
    ),
    (
      ">   \t> a\n", "<blockquote>\n<pre><code>  &gt; a\n</code></pre>\n</blockquote>\n",
    ),
  ]
  for i, case in cases {
    let (source, expected_html) = case
    assert_commonmark_blockquote_html_regression(
      "tab-nested-marker",
      i.to_string(),
      source,
      expected_html,
    )
  }
}
