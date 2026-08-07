///|
fn inline_angle_ir_from_source(source : String) -> MarkdownIR {
  let source_id = @core.SourceId("inline-angle-semantics")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown parse failed")
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn assert_inline_angle_html(source : String, expected : String) -> Unit raise {
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      inline_angle_ir_from_source(source),
      Passthrough,
    ) {
    Ok(html) => inspect(html, content=expected)
    Err(_) => inspect("rejected", content="rendered")
  }
}

///|
test "URI autolink lowers through the public IR and HTML seams" {
  let source = "<http://foo.bar.baz>\n"
  let ir = inline_angle_ir_from_source(source)
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(html) =>
      inspect(
        html,
        content=(
          #|<p><a href="http://foo.bar.baz">http://foo.bar.baz</a></p>
          #|
        ),
      )
    Err(_) => inspect("rejected", content="rendered")
  }
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [autolink] => {
          inspect(autolink.kind_tag(), content="Autolink")
          inspect(
            source[autolink.origin().start():autolink.origin().end()],
            content="<http://foo.bar.baz>",
          )
          match autolink.node {
            Autolink(
              UriAutolinkKind,
              "http://foo.bar.baz",
              "http://foo.bar.baz",
              Some(display_origin),
              Some(destination_origin)
            ) => assert_eq(display_origin, destination_origin)
            _ => inspect("unexpected", content="typed URI autolink")
          }
        }
        _ => inspect("unexpected", content="one inline child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
fn issue_893_inline_node_texts(
  root : @seam.SyntaxNode,
  expected_kind : SyntaxKind,
) -> Array[String] {
  let texts : Array[String] = []
  fn walk(node : @seam.SyntaxNode) -> Unit {
    let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
    if kind == expected_kind {
      texts.push(node.text())
    }
    for child in node.children() {
      walk(child)
    }
  }
  walk(root)
  texts
}

///|
test "issue 893: CommonMark 345 and 346 resolve code and URI ownership" {
  let cases : Array[(String, Array[String], Array[String], String)] = [
    (
      "`<https://foo.bar.`baz>`\n",
      [],
      ["`<https://foo.bar.`"],
      "<p><code>&lt;https://foo.bar.</code>baz&gt;`</p>\n",
    ),
    (
      "<https://foo.bar.`baz>`\n",
      ["<https://foo.bar.`baz>"],
      [],
      "<p><a href=\"https://foo.bar.%60baz\">https://foo.bar.`baz</a>`</p>\n",
    ),
  ]
  for angle_case in cases {
    let (source, expected_autolinks, expected_code, expected_html) = angle_case
    let (cst, diagnostics) = parse_cst(
      @core.SourceId("markdown-issue-893-code-uri-precedence"),
      source,
    ) catch {
      _ => abort("Issue #893 parse failed")
    }
    assert_eq(diagnostics.length(), 0)
    let syntax = @seam.SyntaxNode::from_cst(cst)
    assert_eq(
      issue_893_inline_node_texts(syntax, UriAutolinkNode),
      expected_autolinks,
    )
    assert_eq(
      issue_893_inline_node_texts(syntax, InlineCodeNode),
      expected_code,
    )
    assert_inline_angle_html(source, expected_html)
  }
}

///|
test "issue 893: link and image suffixes remain structural around autolinks" {
  let cases : Array[(String, String, Array[String])] = [
    ("[link](<>)\n", "<p><a href=\"\">link</a></p>\n", []),
    ("[link](</my uri>)\n", "<p><a href=\"/my%20uri\">link</a></p>\n", []),
    ("[a](<b)c>)\n", "<p><a href=\"b)c\">a</a></p>\n", []),
    (
      "[link](<foo(and(bar)>)\n",
      "<p><a href=\"foo(and(bar)\">link</a></p>\n",
      [],
    ),
    (
      "[foo<https://example.com/?search=](uri)>\n",
      "<p>[foo<a href=\"https://example.com/?search=%5D(uri)\">https://example.com/?search=](uri)</a></p>\n",
      ["<https://example.com/?search=](uri)>"],
    ),
    ("![foo](<url>)\n", "<p><img src=\"url\" alt=\"foo\" /></p>\n", []),
    (
      "![<http://example.test>](url)\n",
      "<p><img src=\"url\" alt=\"http://example.test\" /></p>\n",
      ["<http://example.test>"],
    ),
    (
      "![foo<https://example.com/?search=](uri)>\n",
      "<p>![foo<a href=\"https://example.com/?search=%5D(uri)\">https://example.com/?search=](uri)</a></p>\n",
      ["<https://example.com/?search=](uri)>"],
    ),
  ]
  for angle_case in cases {
    let (source, expected_html, expected_autolinks) = angle_case
    let (cst, diagnostics) = parse_cst(
      @core.SourceId("markdown-issue-893-link-image-controls"),
      source,
    ) catch {
      _ => abort("Issue #893 control parse failed")
    }
    assert_eq(diagnostics.length(), 0)
    assert_eq(
      issue_893_inline_node_texts(
        @seam.SyntaxNode::from_cst(cst),
        UriAutolinkNode,
      ),
      expected_autolinks,
    )
    assert_inline_angle_html(source, expected_html)
  }
}

///|
test "autolink escaping and inline HTML validity follow CommonMark boundaries" {
  let cases : Array[(String, String)] = [
    (
      "<https://example.com/\\[\\>\n", "<p><a href=\"https://example.com/%5C%5B%5C\">https://example.com/\\[\\</a></p>\n",
    ),
    (
      "<a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 />\n", "<p><a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 /></p>\n",
    ),
    ("<a h*#ref=\"hi\">\n", "<p>&lt;a h*#ref=&quot;hi&quot;&gt;</p>\n"),
    (
      "< a><\nfoo><bar/ >\n<foo bar=baz\nbim!bop />\n", "<p>&lt; a&gt;&lt;\nfoo&gt;&lt;bar/ &gt;\n&lt;foo bar=baz\nbim!bop /&gt;</p>\n",
    ),
    ("</a href=\"foo\">\n", "<p>&lt;/a href=&quot;foo&quot;&gt;</p>\n"),
    (
      "foo <!--> foo -->\n\nfoo <!---> foo -->\n", "<p>foo <!--> foo --&gt;</p>\n<p>foo <!---> foo --&gt;</p>\n",
    ),
  ]
  for angle_case in cases {
    let (source, expected) = angle_case
    assert_inline_angle_html(source, expected)
  }
}

///|
test "email autolinks retain typed display and destination origins" {
  let source = "<foo@bar.example.com>\n"
  let ir = inline_angle_ir_from_source(source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [autolink] => {
          inspect(autolink.kind_tag(), content="Autolink")
          assert_eq(autolink.text_value(), Some("foo@bar.example.com"))
          match autolink.label_origin() {
            Some(origin) =>
              inspect(
                source[origin.start():origin.end()],
                content="foo@bar.example.com",
              )
            None => inspect("missing", content="display origin")
          }
          assert_eq(autolink.destination_origin(), None)
          match autolink.node {
            Autolink(
              EmailAutolinkKind,
              "foo@bar.example.com",
              "mailto:foo@bar.example.com",
              Some(_),
              None
            ) => ()
            _ => inspect("unexpected", content="typed email autolink")
          }
        }
        _ => inspect("unexpected", content="one inline child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"link","url":"mailto:foo@bar.example.com","children":[{"type":"text","value":"foo@bar.example.com"}]}]}]}
    ),
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"link","url":"mailto:foo@bar.example.com","children":[{"type":"text","value":"foo@bar.example.com","position":{"start":{"line":1,"column":2,"offset":1},"end":{"line":1,"column":21,"offset":20}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":1,"column":22,"offset":21}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":1,"column":22,"offset":21}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":2,"column":1,"offset":22}}}
    ),
  )
}

///|
test "inline HTML obeys render policy while mdast preserves valid HTML" {
  let source = "x <i>y</i>\n"
  let ir = inline_angle_ir_from_source(source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [_, open, _, close] => {
          match (open.node, close.node) {
            (InlineHtml("<i>", Some(_)), InlineHtml("</i>", Some(_))) => ()
            _ => inspect("unexpected", content="typed inline HTML nodes")
          }
          assert_eq(open.is_raw(), false)
          assert_eq(close.is_raw(), false)
        }
        _ => inspect("unexpected", content="four inline children")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ),
    Ok("<p>x <i>y</i></p>\n"),
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Escape),
    Ok("<p>x &lt;i&gt;y&lt;/i&gt;</p>\n"),
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Omit),
    Ok("<p>x y</p>\n"),
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Reject),
    Err(RawHtmlRejected(RawHtmlInline, MarkdownIROrigin(start=2, end=5))),
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"text","value":"x "},{"type":"html","value":"<i>"},{"type":"text","value":"y"},{"type":"html","value":"</i>"}]}]}
    ),
  )
}

///|
test "inline angle semantics cover LF CRLF CR and EOF terminators" {
  let cases : Array[(String, String)] = [
    ("LF", "\n"),
    ("CRLF", "\r\n"),
    ("CR", "\r"),
    ("EOF", ""),
  ]
  for angle_case in cases {
    let (label, terminator) = angle_case
    let source = "x <http://foo.bar.baz> <i>y</i>" + terminator
    assert_inline_angle_html(
      source, "<p>x <a href=\"http://foo.bar.baz\">http://foo.bar.baz</a> <i>y</i></p>\n",
    ) catch {
      _ => fail("inline angle terminator case failed: " + label)
    }
  }
}

///|
test "issue 893: an autolink deactivates an enclosing ordinary link" {
  let source = "[<http://example.test>](outer)\n"
  let autolink = Inline::Link(
    [Inline::Text("http://example.test")],
    "http://example.test",
  )
  let expected = Block::Document([
    Block::Paragraph([
      Inline::Text("["),
      autolink,
      Inline::Text("]"),
      Inline::Text("("),
      Inline::Text("outer"),
      Inline::Text(")"),
    ]),
  ])
  assert_eq(
    parse(@core.SourceId("issue-893-direct-nested-autolink"), source),
    expected,
  )
  assert_eq(
    experimental_markdown_ir_to_block(inline_angle_ir_from_source(source)),
    expected,
  )
  assert_inline_angle_html(
    source, "<p>[<a href=\"http://example.test\">http://example.test</a>](outer)</p>\n",
  )
}

///|
test "issue 893: an autolink deactivates every enclosing ordinary link" {
  let source = "[[<http://example.test>](inner)](outer)\n"
  let autolink = Inline::Link(
    [Inline::Text("http://example.test")],
    "http://example.test",
  )
  let expected = Block::Document([
    Block::Paragraph([
      Inline::Text("["),
      Inline::Text("["),
      autolink,
      Inline::Text("]"),
      Inline::Text("("),
      Inline::Text("inner"),
      Inline::Text(")"),
      Inline::Text("]"),
      Inline::Text("("),
      Inline::Text("outer"),
      Inline::Text(")"),
    ]),
  ])
  assert_eq(
    parse(@core.SourceId("issue-893-direct-nested-autolink-stack"), source),
    expected,
  )
  assert_eq(
    experimental_markdown_ir_to_block(inline_angle_ir_from_source(source)),
    expected,
  )
  assert_inline_angle_html(
    source, "<p>[[<a href=\"http://example.test\">http://example.test</a>](inner)](outer)</p>\n",
  )
}

///|
test "inline angle MarkdownIR uses legacy editor types without changing links" {
  let ordinary_link_source = "x [foo](bar)\n"
  assert_eq(
    experimental_markdown_ir_to_block(
      inline_angle_ir_from_source(ordinary_link_source),
    ),
    parse(
      @core.SourceId("inline-angle-existing-link-projection"),
      ordinary_link_source,
    ),
  )
  let source = "x <http://foo.bar.baz> <i>y</i>\n"
  let via_ir = experimental_markdown_ir_to_block(
    inline_angle_ir_from_source(source),
  )
  assert_eq(
    via_ir,
    Block::Document([
      Block::Paragraph([
        Inline::Text("x "),
        Inline::Link([Inline::Text("http://foo.bar.baz")], "http://foo.bar.baz"),
        Inline::Text(" "),
        Inline::Text("<i>"),
        Inline::Text("y"),
        Inline::Text("</i>"),
      ]),
    ]),
  )
}
