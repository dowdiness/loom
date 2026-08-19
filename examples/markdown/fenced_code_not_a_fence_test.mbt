///|
fn assert_commonmark_fenced_not_a_fence(
  example : Int,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-fenced-not-a-fence-" + example.to_string(),
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
      "CommonMark fenced not-a-fence regression " +
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
test "CommonMark backtick fence with info backticks is not a fence" {
  assert_commonmark_fenced_not_a_fence(
    138, "``` ```\naaa\n", "<p><code> </code>\naaa</p>\n",
  )
  assert_commonmark_fenced_not_a_fence(
    145, "``` aa ```\nfoo\n", "<p><code>aa</code>\nfoo</p>\n",
  )
  assert_commonmark_fenced_not_a_fence(347, "```foo``\n", "<p>```foo``</p>\n")
}

///|
test "incremental: backtick info fence fallback matches full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "fenced-code info backtick turns opener into code span",
      "``` aa\nfoo\n```\n",
      @core.Edit::insert("``` aa".length(), " ```".length()),
      "``` aa ```\nfoo\n```\n",
    ),
  )
}
