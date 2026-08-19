///|
fn assert_commonmark_blockquote_fenced_blank_close(
  label : String,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-blockquote-fenced-blank-close-" + label,
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
      "CommonMark blockquote fenced blank-close regression " +
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
test "CommonMark example 128: blank line closes blockquote fenced code" {
  assert_commonmark_blockquote_fenced_blank_close(
    "128", "> ```\n> aaa\n\nbbb\n", "<blockquote>\n<pre><code>aaa\n</code></pre>\n</blockquote>\n<p>bbb</p>\n",
  )
}

///|
test "incremental: blank line closes blockquote fenced code" {
  ignore(
    assert_block_container_incremental_parity(
      "blank line closes blockquote fenced code",
      "> ```\n> aaa\n> bbb\n",
      @core.Edit::new("> ```\n> aaa\n".length(), "> ".length(), "\n".length()),
      "> ```\n> aaa\n\nbbb\n",
    ),
  )
}

///|
test "incremental: blank line closes blockquote fenced code after multiple lines" {
  ignore(
    assert_block_container_incremental_parity(
      "blank line closes blockquote fenced code after multiple lines",
      "> ```\n> aaa\n> bbb\n> ccc\n",
      @core.Edit::new(
        "> ```\n> aaa\n> bbb\n".length(),
        "> ".length(),
        "\n".length(),
      ),
      "> ```\n> aaa\n> bbb\n\nccc\n",
    ),
  )
}
