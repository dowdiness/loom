///|
fn delimiter_integration_ir_from_source(
  source_id : @core.SourceId,
  source : String,
) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ =>
      abort("Markdown parse failed for delimiter integration source: " + source)
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn delimiter_integration_origin_source(
  source : String,
  origin : MarkdownIROrigin,
) -> String {
  source[origin.start():origin.end()].to_owned()
}

///|
fn assert_delimiter_integration_origins(
  source : String,
  node : MarkdownIR,
  expected_full : String,
  expected_content : String,
) -> Unit raise {
  inspect(
    delimiter_integration_origin_source(source, node.origin()),
    content=expected_full,
  )
  match node.content_origin() {
    Some(origin) =>
      inspect(
        delimiter_integration_origin_source(source, origin),
        content=expected_content,
      )
    None => fail("expected delimiter integration content origin")
  }
}

///|
fn assert_delimiter_integration_text(
  source : String,
  node : MarkdownIR,
  expected : String,
) -> Unit raise {
  inspect(node.kind_tag(), content="Text")
  match node.text_value() {
    Some(value) => inspect(value, content=expected)
    None => fail("expected delimiter integration text node")
  }
  inspect(
    delimiter_integration_origin_source(source, node.origin()),
    content=expected,
  )
}

///|
test "delimiter integration: official examples keep direct and MarkdownIR Block parity" {
  let source_id = @core.SourceId("markdown-delimiter-official-parity")
  let sources = [
    "_foo bar_\n", "__foo bar__\n", "***foo**\n", "**foo***\n", "***foo***\n", "*[bar*](/url)\n",
    "_a `_`_\n",
  ]
  for source in sources {
    let via_ir = experimental_markdown_ir_to_block(
      delimiter_integration_ir_from_source(source_id, source),
    )
    inspect(via_ir, content=@debug.to_string(parse(source_id, source)))
  }
}

///|
test "delimiter integration: CommonMark 0.31.2 rule of three uses original run lengths" {
  let source_id = @core.SourceId("markdown-delimiter-rule-of-three")
  let cases = [
    ("*a***a*\n", "<p><em>a</em>*<em>a</em></p>\n"),
    ("***a*a*a*\n", "<p><em><em><em>a</em>a</em>a</em></p>\n"),
    ("***a*a*b*\n", "<p><em><em><em>a</em>a</em>b</em></p>\n"),
    ("_**a*a*a_\n", "<p><em>**a<em>a</em>a</em></p>\n"),
    ("**a****a***a*\n", "<p>**a<em><em><strong>a</strong></em>a</em></p>\n"),
  ]
  for case in cases {
    let (source, expected_html) = case
    inspect(
      experimental_markdown_ir_to_commonmark_html(
        delimiter_integration_ir_from_source(source_id, source),
      ),
      content=expected_html,
    )
  }
}

///|
test "delimiter integration: underscore emphasis and strong origins retain spelling" {
  let source_id = @core.SourceId("markdown-delimiter-underscore-origins")
  let cases = [
    ("_foo bar_\n", "Italic", "_foo bar_", "foo bar"),
    ("__foo bar__\n", "Bold", "__foo bar__", "foo bar"),
  ]
  for case in cases {
    let (source, expected_kind, expected_full, expected_content) = case
    let ir = delimiter_integration_ir_from_source(source_id, source)
    match ir.children() {
      [paragraph] =>
        match paragraph.children() {
          [emphasis] => {
            inspect(emphasis.kind_tag(), content=expected_kind)
            assert_delimiter_integration_origins(
              source, emphasis, expected_full, expected_content,
            )
          }
          _ => fail("expected one underscore emphasis child")
        }
      _ => fail("expected one underscore emphasis paragraph")
    }
  }
}

///|
test "delimiter integration: partial runs retain literal and matched origins" {
  let source_id = @core.SourceId("markdown-delimiter-partial-runs")
  let opener_source = "***foo**\n"
  let opener_ir = delimiter_integration_ir_from_source(source_id, opener_source)
  match opener_ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [literal, bold] => {
          assert_delimiter_integration_text(opener_source, literal, "*")
          inspect(bold.kind_tag(), content="Bold")
          assert_delimiter_integration_origins(
            opener_source, bold, "**foo**", "foo",
          )
        }
        _ => fail("expected literal opener prefix plus strong node")
      }
    _ => fail("expected partial opener paragraph")
  }

  let closer_source = "**foo***\n"
  let closer_ir = delimiter_integration_ir_from_source(source_id, closer_source)
  match closer_ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [bold, literal] => {
          inspect(bold.kind_tag(), content="Bold")
          assert_delimiter_integration_origins(
            closer_source, bold, "**foo**", "foo",
          )
          assert_delimiter_integration_text(closer_source, literal, "*")
        }
        _ => fail("expected strong node plus literal closer suffix")
      }
    _ => fail("expected partial closer paragraph")
  }
}

///|
test "delimiter integration: triple runs nest origins from the inside out" {
  let source_id = @core.SourceId("markdown-delimiter-triple-run-origins")
  let source = "***foo***\n"
  let ir = delimiter_integration_ir_from_source(source_id, source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [italic] => {
          inspect(italic.kind_tag(), content="Italic")
          assert_delimiter_integration_origins(
            source, italic, "***foo***", "**foo**",
          )
          match italic.children() {
            [bold] => {
              inspect(bold.kind_tag(), content="Bold")
              assert_delimiter_integration_origins(
                source, bold, "**foo**", "foo",
              )
            }
            _ => fail("expected nested strong child")
          }
        }
        _ => fail("expected outer emphasis child")
      }
    _ => fail("expected triple-run paragraph")
  }
}

///|
test "delimiter integration: links scope delimiters and code spans stay opaque" {
  let source_id = @core.SourceId("markdown-delimiter-link-and-code-scope")
  let link_source = "*[bar*](/url)\n"
  let link_ir = delimiter_integration_ir_from_source(source_id, link_source)
  match link_ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [literal, link] => {
          assert_delimiter_integration_text(link_source, literal, "*")
          inspect(link.kind_tag(), content="Link")
          inspect(
            delimiter_integration_origin_source(link_source, link.origin()),
            content="[bar*](/url)",
          )
          match link.label_origin() {
            Some(origin) =>
              inspect(
                delimiter_integration_origin_source(link_source, origin),
                content="bar*",
              )
            None => fail("expected link label origin")
          }
          match link.children() {
            [label] =>
              assert_delimiter_integration_text(link_source, label, "bar*")
            _ => fail("expected one literal link label child")
          }
        }
        _ => fail("expected literal opener plus link")
      }
    _ => fail("expected link-scope paragraph")
  }

  let code_source = "_a `_`_\n"
  let code_ir = delimiter_integration_ir_from_source(source_id, code_source)
  match code_ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [italic] => {
          inspect(italic.kind_tag(), content="Italic")
          assert_delimiter_integration_origins(
            code_source, italic, "_a `_`_", "a `_`",
          )
          match italic.children() {
            [text, inline_code] => {
              assert_delimiter_integration_text(code_source, text, "a ")
              inspect(inline_code.kind_tag(), content="InlineCode")
              assert_delimiter_integration_origins(
                code_source, inline_code, "`_`", "_",
              )
            }
            _ => fail("expected text plus opaque inline code")
          }
        }
        _ => fail("expected underscore emphasis around inline code")
      }
    _ => fail("expected code-span opacity paragraph")
  }
}

///|
test "delimiter integration: literal marker after soft break preserves spacing" {
  let source_id = @core.SourceId("markdown-delimiter-soft-break-spacing")
  let source = "a\n_b\n"
  let direct = parse(source_id, source)
  inspect(
    direct,
    content="Document([Paragraph([Text(\"a\"), Text(\" \"), Text(\"_b\")])])",
  )
  inspect(
    experimental_markdown_ir_to_block(
      delimiter_integration_ir_from_source(source_id, source),
    ),
    content=@debug.to_string(direct),
  )
}

///|
test "delimiter integration: literal marker coalescing respects source barriers" {
  let source_id = @core.SourceId("markdown-delimiter-source-barriers")
  let cases = [
    (
      "*a\n_b*\n", "Document([Paragraph([Italic([Text(\"a\"), Text(\"_b\")])])])",
    ),
    ("]_\n", "Document([Paragraph([Text(\"]\"), Text(\"_\")])])"),
    ("`_\n", "Document([Paragraph([Text(\"`_\")])])"),
    ("*`_*\n", "Document([Paragraph([Italic([Text(\"`_\")])])])"),
    ("[`_](u)\n", "Document([Paragraph([Link([Text(\"`_\")], \"u\")])])"),
  ]
  for case in cases {
    let (source, expected) = case
    let direct = parse(source_id, source)
    inspect(direct, content=expected)
    inspect(
      experimental_markdown_ir_to_block(
        delimiter_integration_ir_from_source(source_id, source),
      ),
      content=@debug.to_string(direct),
    )
  }
}
