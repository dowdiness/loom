///|
fn raw_html_policy_origin(value : String) -> MarkdownIROrigin {
  MarkdownIROrigin(start=0, end=value.length())
}

///|
test "raw HTML policy core: block and inline surfaces cover all policies" {
  let value = "<span title=\"x\">&</span>"
  let origin = raw_html_policy_origin(value)
  for surface in [RawHtmlBlock, RawHtmlInline] {
    assert_eq(
      render_valid_raw_html(value, origin, surface, Escape),
      Ok("&lt;span title=&quot;x&quot;&gt;&amp;&lt;/span&gt;"),
    )
    assert_eq(render_valid_raw_html(value, origin, surface, Omit), Ok(""))
    assert_eq(
      render_valid_raw_html(value, origin, surface, Passthrough),
      Ok(value),
    )
    assert_eq(
      render_valid_raw_html(value, origin, surface, Reject),
      Err(RawHtmlRejected(surface, origin)),
    )
  }
}

///|
test "raw HTML policy adapter: product default escapes and conformance is explicit" {
  let value = "<div>\nraw & html\n</div>\n"
  let origin = raw_html_policy_origin(value)
  let ir = MarkdownIR::html_block(value, origin, Some(origin))
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content="&lt;div&gt;\nraw &amp; html\n&lt;/div&gt;\n",
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Escape),
    Ok("&lt;div&gt;\nraw &amp; html\n&lt;/div&gt;\n"),
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Omit),
    Ok(""),
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ),
    Ok(value),
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Reject),
    Err(RawHtmlRejected(RawHtmlBlock, origin)),
  )
}

///|
test "raw HTML policy adapter: nested rejection preserves the HTML origin" {
  let value = "<div>nested</div>\n"
  let child_origin = MarkdownIROrigin(start=7, end=7 + value.length())
  let container_origin = MarkdownIROrigin(start=0, end=child_origin.end())
  let html = MarkdownIR::html_block(value, child_origin, Some(child_origin))
  let quote = MarkdownIR::{ node: BlockQuote([html]), origin: container_origin }
  let ir = MarkdownIR::document([quote], container_origin)
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Reject),
    Err(RawHtmlRejected(RawHtmlBlock, child_origin)),
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Omit),
    Ok("<blockquote>\n</blockquote>\n"),
  )
}

///|
test "raw HTML policy adapter: malformed recovery Raw stays escaped" {
  let value = "<broken>"
  let origin = raw_html_policy_origin(value)
  let ir = MarkdownIR::{ node: Raw(value, []), origin }
  for policy in [Escape, Omit, Reject, Passthrough] {
    assert_eq(
      experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
        ir, policy,
      ),
      Ok("&lt;broken&gt;"),
    )
  }
}

///|
test "raw HTML policy adapter: mdast preserves valid HTML independently" {
  let value = "<div>ok</div>\n"
  let origin = raw_html_policy_origin(value)
  let ir = MarkdownIR::html_block(value, origin, Some(origin))
  for policy in [Escape, Omit, Reject, Passthrough] {
    ignore(
      experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
        ir, policy,
      ),
    )
    inspect(
      experimental_markdown_ir_to_mdast_json(ir).stringify(),
      content="{\"type\":\"html\",\"value\":\"<div>ok</div>\\n\"}",
    )
  }
}
