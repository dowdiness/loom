///|
fn assert_commonmark_atx_paragraph_interrupt(
  label : String,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-atx-paragraph-interrupt-" + label,
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
      "CommonMark ATX paragraph-interrupt regression " +
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
test "CommonMark ATX heading does not interrupt a paragraph when indented" {
  assert_commonmark_atx_paragraph_interrupt(
    "70", "foo\n    # bar\n", "<p>foo\n# bar</p>\n",
  )
}

///|
test "ATX heading with three spaces still interrupts a paragraph" {
  assert_commonmark_atx_paragraph_interrupt(
    "three-space-interrupt", "foo\n   # bar\n", "<p>foo</p>\n<h1>bar</h1>\n",
  )
}

///|
test "incremental: over-indented ATX stays a paragraph continuation" {
  ignore(
    assert_block_container_incremental_parity(
      "ATX heading indent crosses the paragraph-interrupt boundary",
      "foo\n   # bar\n",
      @core.Edit::insert("foo\n".length(), " ".length()),
      "foo\n    # bar\n",
    ),
  )
}
