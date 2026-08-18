///|
fn assert_commonmark_fenced_indent_strip(
  example : Int,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-fenced-indent-strip-" + example.to_string(),
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
      "CommonMark fenced indent-strip regression " +
      example.to_string() +
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
test "CommonMark fenced code indent strip 131-133" {
  assert_commonmark_fenced_indent_strip(
    131, " ```\n aaa\naaa\n```\n", "<pre><code>aaa\naaa\n</code></pre>\n",
  )
  assert_commonmark_fenced_indent_strip(
    132, "  ```\naaa\n  aaa\naaa\n  ```\n", "<pre><code>aaa\naaa\naaa\n</code></pre>\n",
  )
  assert_commonmark_fenced_indent_strip(
    133, "   ```\n   aaa\n    aaa\n  aaa\n   ```\n", "<pre><code>aaa\n aaa\naaa\n</code></pre>\n",
  )
}

///|
test "incremental: fenced indent strip matches full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "fenced-code indent-strip opening space",
      "```\n aaa\naaa\n```\n",
      @core.Edit::insert(0, " ".length()),
      " ```\n aaa\naaa\n```\n",
    ),
  )
}
