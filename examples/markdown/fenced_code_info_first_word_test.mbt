///|
fn assert_commonmark_fenced_info_first_word(
  example : Int,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-fenced-info-first-word-" + example.to_string(),
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
      "CommonMark fenced info first-word regression " +
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
test "CommonMark fenced info uses the first word only" {
  assert_commonmark_fenced_info_first_word(
    143, "~~~~    ruby startline=3 $%@#$\ndef foo(x)\n  return 3\nend\n~~~~~~~\n",
    "<pre><code class=\"language-ruby\">def foo(x)\n  return 3\nend\n</code></pre>\n",
  )
  assert_commonmark_fenced_info_first_word(
    146, "~~~ aa ``` ~~~\nfoo\n~~~\n", "<pre><code class=\"language-aa\">foo\n</code></pre>\n",
  )
}

///|
test "CommonMark fenced info unescapes backslash punctuation" {
  assert_commonmark_fenced_info_first_word(
    24, "``` foo\\+bar\nfoo\n```\n", "<pre><code class=\"language-foo+bar\">foo\n</code></pre>\n",
  )
}

///|
test "incremental: fenced info extra words match full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "fenced-code info extra words after language",
      "```ruby\nfoo\n```\n",
      @core.Edit::insert("```ruby".length(), " startline=3".length()),
      "```ruby startline=3\nfoo\n```\n",
    ),
  )
}
