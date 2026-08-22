///|
fn assert_commonmark_blockquote_indented_code_boundary(
  label : String,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-blockquote-indented-code-boundary-" + label,
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
      "CommonMark blockquote indented-code boundary regression " +
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
  assert_commonmark_blockquote_indented_code_boundary(
    "236", ">     foo\n    bar\n", "<blockquote>\n<pre><code>foo\n</code></pre>\n</blockquote>\n<pre><code>bar\n</code></pre>\n",
  )
}
