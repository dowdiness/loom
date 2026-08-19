///|
fn entity_reference_ir(
  source_id : @core.SourceId,
  source : String,
) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("entity reference fixture parse failed")
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn entity_reference_origin_source(
  source : String,
  origin : MarkdownIROrigin,
) -> String {
  source[origin.start():origin.end()].to_owned()
}

///|
test "CommonMark entities: named and numeric references decode semantically" {
  inspect(
    decode_markdown_inline_text(
      "&nbsp; &amp; &copy; &AElig; &Dcaron; &frac34; " +
      "&HilbertSpace; &DifferentialD; &ClockwiseContourIntegral; &ngE;",
    ),
    content="  & © Æ Ď ¾ ℋ ⅆ ∲ ≧̸",
  )
  inspect(
    decode_markdown_inline_text(
      "&#35; &#1234; &#992; &#0; &#X22; &#XD06; &#xcab; &#x1F600;",
    ),
    content="# Ӓ Ϡ � \" ആ ಫ 😀",
  )
}

///|
test "CommonMark entities: all 2,125 authoritative named references decode" {
  let mut count = 0
  for name, replacement in commonmark_named_entities {
    assert_eq(decode_markdown_inline_text("&" + name + ";"), replacement)
    count = count + 1
  }
  inspect(count, content="2125")
}

///|
test "CommonMark entities: invalid and escaped references stay literal" {
  let source = "&nbsp &x; &#; &#x; &#87654321; &#abcdef0; " +
    "&ThisIsNotDefined; &hi?; &copy \\&copy;"
  inspect(
    decode_markdown_inline_text(source),
    content="&nbsp &x; &#; &#x; &#87654321; &#abcdef0; " +
      "&ThisIsNotDefined; &hi?; &copy &copy;",
  )
  inspect(decode_markdown_inline_text("&#xD800; &#1114112;"), content="� �")
  inspect(
    decode_markdown_inline_text(
      "&#x10FFFF; &#x110000; &#x0000000; &#9999999; &#00000000;",
    ),
    content="\u{10FFFF} � &#x0000000; � &#00000000;",
  )
  inspect(
    decode_markdown_info_string_entities("foo\\+bar &ouml; \\&copy;"),
    content="foo+bar ö &copy;",
  )
}

///|
test "CommonMark entities: MarkdownIR keeps decoded text over source origins" {
  let source = "before &copy; and &#x1F600; after\n"
  let ir = entity_reference_ir(@core.SourceId("markdown-entity-origin"), source)
  debug_inspect(
    experimental_markdown_ir_to_block(ir),
    content="Document([Paragraph([Text(\"before © and 😀 after\")])])",
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text] => {
          debug_inspect(
            text.text_value(),
            content="Some(\"before © and 😀 after\")",
          )
          inspect(
            entity_reference_origin_source(source, text.origin()),
            content="before &copy; and &#x1F600; after",
          )
        }
        _ => fail("expected one decoded text child")
      }
    _ => fail("expected one paragraph")
  }
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content="<p>before © and 😀 after</p>\n",
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content="{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"before © and 😀 after\"}]}]}",
  )
}

///|
test "CommonMark entities: decoded whitespace never becomes source syntax" {
  let cases : Array[(String, String)] = [
    ("a&#32;\nb\n", "<p>a \nb</p>\n"),
    ("a&#32;  \nb\n", "<p>a <br />\nb</p>\n"),
    ("a\n&#9;b\n", "<p>a\n\tb</p>\n"),
    ("a\n  &#9;b\n", "<p>a\n\tb</p>\n"),
    ("# &#32;x&#32;\n", "<h1> x </h1>\n"),
    ("&#32;x&#32;\n---\n", "<h2> x </h2>\n"),
    ("- &#32;x\n", "<ul>\n<li> x</li>\n</ul>\n"),
  ]
  for index, entity_case in cases {
    let (source, expected_html) = entity_case
    let ir = entity_reference_ir(
      @core.SourceId("markdown-entity-source-whitespace-" + index.to_string()),
      source,
    )
    inspect(
      experimental_markdown_ir_to_commonmark_html(ir),
      content=expected_html,
    )
  }
}

///|
test "CommonMark entities: code content and raw HTML do not decode" {
  let source = "``` f&ouml;&ouml;\nf&ouml;\n```\n\n`f&ouml;`\n\n<a href=\"&ouml;\">\n"
  let ir = entity_reference_ir(
    @core.SourceId("markdown-entity-non-text-contexts"),
    source,
  )
  match experimental_markdown_ir_to_block(ir) {
    Document(
      [CodeBlock(info, code), Paragraph([InlineCode(inline)]), HtmlBlock(html)]
    ) => {
      inspect(info, content="föö")
      inspect(code, content="f&ouml;")
      inspect(inline, content="f&ouml;")
      inspect(html, content="<a href=\"&ouml;\">\n")
    }
    _ => fail("expected code, inline-code, and raw-HTML contexts")
  }
}

///|
test "CommonMark entities: owned examples 25-31 and 34-40 match mdast" {
  let cases : Array[(Int, String, String)] = [
    (
      25, "&nbsp; &amp; &copy; &AElig; &Dcaron;\n&frac34; &HilbertSpace; &DifferentialD;\n&ClockwiseContourIntegral; &ngE;\n",
      "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"  & © Æ Ď\\n¾ ℋ ⅆ\\n∲ ≧̸\"}]}]}",
    ),
    (
      26, "&#35; &#1234; &#992; &#0;\n", "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"# Ӓ Ϡ �\"}]}]}",
    ),
    (
      27, "&#X22; &#XD06; &#xcab;\n", "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"\\\" ആ ಫ\"}]}]}",
    ),
    (
      28, "&nbsp &x; &#; &#x;\n&#87654321;\n&#abcdef0;\n&ThisIsNotDefined; &hi?;\n",
      "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"&nbsp &x; &#; &#x;\\n&#87654321;\\n&#abcdef0;\\n&ThisIsNotDefined; &hi?;\"}]}]}",
    ),
    (
      29, "&copy\n", "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"&copy\"}]}]}",
    ),
    (
      30, "&MadeUpEntity;\n", "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"&MadeUpEntity;\"}]}]}",
    ),
    (
      31, "<a href=\"&ouml;&ouml;.html\">\n", "{\"type\":\"root\",\"children\":[{\"type\":\"html\",\"value\":\"<a href=\\\"&ouml;&ouml;.html\\\">\\n\"}]}",
    ),
    (
      34, "``` f&ouml;&ouml;\nfoo\n```\n", "{\"type\":\"root\",\"children\":[{\"type\":\"code\",\"lang\":\"föö\",\"value\":\"foo\"}]}",
    ),
    (
      35, "`f&ouml;&ouml;`\n", "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"inlineCode\",\"value\":\"f&ouml;&ouml;\"}]}]}",
    ),
    (
      36, "    f&ouml;f&ouml;\n", "{\"type\":\"root\",\"children\":[{\"type\":\"code\",\"value\":\"f&ouml;f&ouml;\"}]}",
    ),
    (
      37, "&#42;foo&#42;\n*foo*\n", "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"*foo*\\n\"},{\"type\":\"emphasis\",\"children\":[{\"type\":\"text\",\"value\":\"foo\"}]}]}]}",
    ),
    (
      38, "&#42; foo\n\n* foo\n", "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"* foo\"}]},{\"type\":\"list\",\"ordered\":false,\"children\":[{\"type\":\"listItem\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"foo\"}]}]}]}]}",
    ),
    (
      39, "foo&#10;&#10;bar\n", "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"foo\\n\\nbar\"}]}]}",
    ),
    (
      40, "&#9;foo\n", "{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"\\tfoo\"}]}]}",
    ),
  ]
  for entity_case in cases {
    let (example, source, expected) = entity_case
    let ir = entity_reference_ir(
      @core.SourceId("markdown-entity-mdast-" + example.to_string()),
      source,
    )
    inspect(
      experimental_markdown_ir_to_mdast_json(ir).stringify(),
      content=expected,
    )
  }
}
