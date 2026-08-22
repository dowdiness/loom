///|
fn assert_commonmark_html_block_regression(
  example : Int,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-html-block-regression-" + example.to_string(),
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
      "CommonMark HTML block regression " +
      example.to_string() +
      "\nexpected: " +
      @debug.to_string(expected_html) +
      "\nactual:   " +
      @debug.to_string(actual),
    )
  }
}

///|
test "CommonMark HTML block type 7 interrupt regressions 148 187" {
  assert_commonmark_html_block_regression(
    148, "<table><tr><td>\n<pre>\n**Hello**,\n\n_world_.\n</pre>\n</td></tr></table>\n",
    "<table><tr><td>\n<pre>\n**Hello**,\n<p><em>world</em>.\n</pre></p>\n</td></tr></table>\n",
  )
  assert_commonmark_html_block_regression(
    187, "Foo\n<a href=\"bar\">\nbaz\n", "<p>Foo\n<a href=\"bar\">\nbaz</p>\n",
  )
}
