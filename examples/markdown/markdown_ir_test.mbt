///|
fn markdown_ir_from_source(
  source_id : @core.SourceId,
  source : String,
) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  experimental_markdown_ir_from_cst_with_diagnostics(
    source_id, cst, diagnostics,
  )
}

///|
fn experimental_markdown_ir_from_cst_with_diagnostics(
  source_id : @core.SourceId,
  cst : @seam.CstNode,
  diagnostics : @core.DiagnosticSet,
) -> MarkdownIR {
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
/// Compare the two Block adapter paths for lex-valid current-subset fixtures.
fn assert_markdown_ir_block_matches_direct_parse(source : String) -> Unit raise {
  let direct = parse(@core.SourceId("markdown-ir-test-document"), source)
  let via_ir = experimental_markdown_ir_to_block(
    markdown_ir_from_source(@core.SourceId("markdown-ir-test-document"), source),
  )
  inspect(via_ir, content=@debug.to_string(direct))
}

///|
fn assert_recovered_markdown_ir_block_matches_direct_parse(
  source : String,
  recovered_text : String,
) -> Unit raise {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_block(ir),
    content=@debug.to_string(
      parse(@core.SourceId("markdown-ir-test-document"), source),
    ),
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) => {
          let recovered = paragraph.children()[index]
          inspect(recovered.kind_tag(), content="Recovered")
          inspect(
            origin_source(source, recovered.origin()),
            content=recovered_text,
          )
        }
        None => inspect("missing", content="recovered child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
fn assert_malformed_link_raws_preserved(
  source : String,
  expected_raw_text : String,
) -> Unit raise {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_block(ir),
    content=@debug.to_string(
      parse(@core.SourceId("markdown-ir-test-document"), source),
    ),
  )
  match ir.children() {
    [paragraph] => {
      let raw_text = paragraph
        .children()
        .iter()
        .filter(child => child.is_raw())
        .map(child => origin_source(source, child.origin()))
        .collect()
        .join("")
      inspect(raw_text, content=expected_raw_text)
    }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
fn current_parser_subset_source() -> String {
  (
    #|# Title
    #|
    #|Hello **world** and *moon* with `code` plus [link](u(1))
    #|
    #|- one
    #|- two
    #|
    #|```moonbit
    #|let x = 1
    #|```
    #|
  )
}

///|
fn origin_source(source : String, origin : MarkdownIROrigin) -> String {
  source[origin.start():origin.end()].to_owned()
}

///|
fn malformed_link_raw_diagnostics(
  source_id : @core.SourceId,
) -> @core.DiagnosticSet {
  let diagnostics = @core.DiagnosticSet::empty()
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      source_id, "synthetic raw bracket diagnostic", 5, 6, "synthetic-raw",
    ),
  )
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      source_id, "synthetic raw paren diagnostic", 6, 7, "synthetic-raw",
    ),
  )
  diagnostics
}

///|
test "experimental MarkdownIR: heading lowers with origin and Block adapter" {
  let source = "# Title\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(ir.kind_tag(), content="Document")
  inspect(ir.origin().start(), content="0")
  inspect(ir.origin().end(), content="8")
  match ir.children() {
    [heading] => {
      inspect(heading.kind_tag(), content="Heading")
      match heading.heading_depth() {
        Some(depth) => inspect(depth, content="1")
        None => inspect("missing", content="1")
      }
      inspect(origin_source(source, heading.origin()), content="# Title\n")
      match heading.content_origin() {
        Some(origin) => inspect(origin_source(source, origin), content="Title")
        None => inspect("missing", content="Title")
      }
      inspect(
        experimental_markdown_ir_to_block(ir),
        content="Document([Heading(1, [Text(\"Title\")])])",
      )
    }
    _ => inspect("unexpected child count", content="one heading")
  }
}

///|
test "experimental MarkdownIR: paragraph lowers with text origin and Block adapter" {
  let source = "Hello world\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] => {
      inspect(paragraph.kind_tag(), content="Paragraph")
      match paragraph.content_origin() {
        Some(origin) =>
          inspect(origin_source(source, origin), content="Hello world")
        None => inspect("missing", content="Hello world")
      }
      match paragraph.children() {
        [text] => {
          inspect(text.kind_tag(), content="Text")
          match text.text_value() {
            Some(value) => inspect(value, content="Hello world")
            None => inspect("missing", content="Hello world")
          }
          inspect(origin_source(source, text.origin()), content="Hello world")
        }
        _ => inspect("unexpected paragraph children", content="one text")
      }
      inspect(
        experimental_markdown_ir_to_block(ir),
        content="Document([Paragraph([Text(\"Hello world\")])])",
      )
    }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: text escapes decode semantically and retain raw origin" {
  let source = "\\!\\A\\φ\\\\z\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text] => {
          match text.text_value() {
            Some(value) => inspect(value, content="!\\A\\φ\\z")
            None => inspect("missing", content="decoded text value")
          }
          inspect(
            origin_source(source, text.origin()),
            content="\\!\\A\\φ\\\\z",
          )
        }
        _ => inspect("unexpected paragraph children", content="one text")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
  let trailing_source = "\\"
  let trailing_ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    trailing_source,
  )
  match trailing_ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text] => {
          match text.text_value() {
            Some(value) => inspect(value, content="\\")
            None => inspect("missing", content="trailing backslash text")
          }
          inspect(
            origin_source(trailing_source, text.origin()),
            content=trailing_source,
          )
        }
        _ => inspect("unexpected paragraph children", content="one text")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: escaped delimiter tails stay semantic text" {
  let source = "\\*not emphasized*\n\\[not a link](/foo)\n\\[\\[x]]\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] => {
      for child in paragraph.children() {
        inspect(child.diagnostics().length(), content="0")
      }
      inspect(
        paragraph.children().map(child => child.kind_tag()).join(","),
        content="Text,SoftBreak,Text,SoftBreak,Text",
      )
      match
        paragraph
        .children()
        .search_by(child => child.text_value() == Some("*not emphasized*")) {
        Some(index) =>
          inspect(
            origin_source(source, paragraph.children()[index].origin()),
            content="\\*not emphasized*",
          )
        None => inspect("missing", content="escaped emphasis literal")
      }
      match
        paragraph
        .children()
        .search_by(child => child.text_value() == Some("[not a link](/foo)")) {
        Some(index) =>
          inspect(
            origin_source(source, paragraph.children()[index].origin()),
            content="\\[not a link](/foo)",
          )
        None => inspect("missing", content="escaped link literal")
      }
      match
        paragraph
        .children()
        .search_by(child => child.text_value() == Some("[[x]]")) {
        Some(index) =>
          inspect(
            origin_source(source, paragraph.children()[index].origin()),
            content="\\[\\[x]]",
          )
        None => inspect("missing", content="nested escaped bracket literal")
      }
    }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: escaped emphasis recovery handles non-BMP flanking text" {
  let source = "\\*😈*\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text] => {
          inspect(text.kind_tag(), content="Text")
          match text.text_value() {
            Some(value) => inspect(value, content="*😈*")
            None => inspect("missing", content="escaped literal text")
          }
          inspect(origin_source(source, text.origin()), content="\\*😈*")
          inspect(text.diagnostics().length(), content="0")
        }
        _ => inspect("unexpected paragraph children", content="one text")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: child syntax lowering keeps document-relative escape origins" {
  let source = "😀 prefix\n\n\\*literal*\n"
  let (cst, _) = parse_cst(@core.SourceId("markdown-ir-test-document"), source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let paragraphs : Array[@seam.SyntaxNode] = syntax
    .children()
    .iter()
    .filter(child => {
      let kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
      kind == ParagraphNode
    })
    .collect()
  match paragraphs {
    [_, second] => {
      inspect(second.start(), content="11")
      let ir = experimental_markdown_ir_from_syntax(
        @core.SourceId("markdown-ir-test-document"),
        second,
      )
      inspect(ir.kind_tag(), content="Paragraph")
      inspect(ir.origin().start(), content="11")
      inspect(ir.origin().end(), content="22")
      match ir.children() {
        [text] => {
          inspect(text.kind_tag(), content="Text")
          match text.text_value() {
            Some(value) => inspect(value, content="*literal*")
            None => inspect("missing", content="escaped literal text")
          }
          inspect(text.origin().start(), content="11")
          inspect(text.origin().end(), content="21")
          inspect(origin_source(source, text.origin()), content="\\*literal*")
          inspect(text.diagnostics().length(), content="0")
        }
        _ => inspect("unexpected paragraph children", content="one text")
      }
    }
    _ => inspect(paragraphs.length(), content="two paragraphs")
  }
}

///|
test "experimental MarkdownIR: normalized whitespace adjusts text origins" {
  let paragraph_source = "   Foo\n"
  let paragraph_ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    paragraph_source,
  )
  match paragraph_ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text] => {
          match text.text_value() {
            Some(value) => inspect(value, content="Foo")
            None => inspect("missing", content="Foo")
          }
          inspect(origin_source(paragraph_source, text.origin()), content="Foo")
          inspect(
            experimental_markdown_ir_preserve_rewrite(text, paragraph_source),
            content="Foo",
          )
        }
        _ => inspect("unexpected paragraph children", content="one text")
      }
    _ => inspect("unexpected paragraph count", content="one paragraph")
  }
  let leading_heading_source = "   Foo\n---\n"
  let leading_heading_ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    leading_heading_source,
  )
  match leading_heading_ir.children() {
    [heading] =>
      match heading.children() {
        [text] => {
          match text.text_value() {
            Some(value) => inspect(value, content="Foo")
            None => inspect("missing", content="Foo")
          }
          inspect(
            origin_source(leading_heading_source, text.origin()),
            content="Foo",
          )
          inspect(
            experimental_markdown_ir_preserve_rewrite(
              text, leading_heading_source,
            ),
            content="Foo",
          )
        }
        _ => inspect("unexpected heading children", content="one text")
      }
    _ => inspect("unexpected heading count", content="one heading")
  }
  let trailing_heading_source = "Foo  \n---\n"
  let trailing_heading_ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    trailing_heading_source,
  )
  match trailing_heading_ir.children() {
    [heading] =>
      match heading.children() {
        [text] => {
          match text.text_value() {
            Some(value) => inspect(value, content="Foo")
            None => inspect("missing", content="Foo")
          }
          inspect(
            origin_source(trailing_heading_source, text.origin()),
            content="Foo",
          )
          inspect(
            experimental_markdown_ir_preserve_rewrite(
              text, trailing_heading_source,
            ),
            content="Foo",
          )
        }
        _ => inspect("unexpected heading children", content="one text")
      }
    _ => inspect("unexpected heading count", content="one heading")
  }
}

///|
test "experimental MarkdownIR: mdast JSON snapshots for current parser subset" {
  let source = current_parser_subset_source()
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"heading","depth":1,"children":[{"type":"text","value":"Title"}]},{"type":"paragraph","children":[{"type":"text","value":"Hello "},{"type":"strong","children":[{"type":"text","value":"world"}]},{"type":"text","value":" and "},{"type":"emphasis","children":[{"type":"text","value":"moon"}]},{"type":"text","value":" with "},{"type":"inlineCode","value":"code"},{"type":"text","value":" plus "},{"type":"link","url":"u(1)","children":[{"type":"text","value":"link"}]}]},{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"one"}]}]},{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"two"}]}]}]},{"type":"code","lang":"moonbit","value":"let x = 1"}]}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast JSON includes recovery metadata" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "[text](\n",
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"mdastRecovered","value":"[","origin":{"start":0,"end":1},"diagnostics":["recovered malformed Markdown: [ [0,1]"]},{"type":"text","value":"text"},{"type":"mdastRaw","value":"]","origin":{"start":5,"end":6},"diagnostics":["raw recovered Markdown [5,6]"]},{"type":"mdastRaw","value":"(","origin":{"start":6,"end":7},"diagnostics":["raw recovered Markdown [6,7]"]}]}]}
    ),
  )
}

///|
test "experimental MarkdownIR: Block adapter matches direct parse for headings" {
  assert_markdown_ir_block_matches_direct_parse("# Title\n")
  assert_markdown_ir_block_matches_direct_parse("### Deep Title\n")
}

///|
test "experimental MarkdownIR: Block adapter matches direct parse for paragraphs" {
  assert_markdown_ir_block_matches_direct_parse("Hello world\n")
  assert_markdown_ir_block_matches_direct_parse("line one\nline two\n")
}

///|
test "experimental MarkdownIR: Block adapter matches direct parse for unordered lists" {
  assert_markdown_ir_block_matches_direct_parse("- one\n- two\n")
  assert_markdown_ir_block_matches_direct_parse(
    "- **bold** item\n- [link](target)\n",
  )
}

///|
test "experimental MarkdownIR: list items expose flow-content paragraphs" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "- one\n- two\n",
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [first, second] => {
          debug_inspect(list.spread(), content="Some(false)")
          debug_inspect(first.spread(), content="Some(false)")
          debug_inspect(second.spread(), content="Some(false)")
          debug_inspect(
            first.children().map(child => child.kind_tag()),
            content="[\"Paragraph\"]",
          )
          debug_inspect(
            second.children().map(child => child.kind_tag()),
            content="[\"Paragraph\"]",
          )
          assert_markdown_ir_block_matches_direct_parse("- one\n- two\n")
        }
        _ => inspect("unexpected list children", content="two items")
      }
    _ => inspect("unexpected document children", content="one list")
  }
}

///|
test "experimental MarkdownIR: nested list item lowers as flow child" {
  let source = "- parent\n  - child\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [item] => {
          debug_inspect(list.spread(), content="Some(false)")
          debug_inspect(item.spread(), content="Some(false)")
          debug_inspect(
            item.children().map(child => child.kind_tag()),
            content="[\"Paragraph\", \"UnorderedList\"]",
          )
          inspect(
            experimental_markdown_ir_to_mdast_json(ir).stringify(),
            content=(
              #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"parent"}]},{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"child"}]}]}]}]}]}]}
            ),
          )
          assert_markdown_ir_block_matches_direct_parse(source)
        }
        _ => inspect("unexpected list children", content="one item")
      }
    _ => inspect("unexpected document children", content="one list")
  }
}

///|
test "experimental MarkdownIR: adjacent nested marker boundary stays in list item flow" {
  let source = "- parent\n  - child\n  + child2\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [item] => {
          debug_inspect(
            item.children().map(child => child.kind_tag()),
            content="[\"Paragraph\", \"UnorderedList\", \"UnorderedList\"]",
          )
          inspect(
            experimental_markdown_ir_canonical_format(
              @core.SourceId("markdown-ir-test-document"),
              ir,
            ),
            content="- parent\n  - child\n  + child2",
          )
          assert_markdown_ir_block_matches_direct_parse(source)
        }
        _ => inspect("unexpected list children", content="one item")
      }
    _ => inspect("unexpected document children", content="one list")
  }
}

///|
test "experimental MarkdownIR: multi-item nested list lowers as one flow child" {
  let source = "- a\n  - b\n  - c\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [item] => {
          debug_inspect(
            item.children().map(child => child.kind_tag()),
            content="[\"Paragraph\", \"UnorderedList\"]",
          )
          match item.children() {
            [_, nested] => {
              inspect(nested.children().length(), content="2")
              inspect(
                experimental_markdown_ir_to_mdast_json(ir).stringify(),
                content=(
                  #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"a"}]},{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"b"}]}]},{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"c"}]}]}]}]}]}]}
                ),
              )
              inspect(
                experimental_markdown_ir_canonical_format(
                  @core.SourceId("markdown-ir-test-document"),
                  ir,
                ),
                content="- a\n  - b\n  - c",
              )
              assert_markdown_ir_block_matches_direct_parse(source)
            }
            _ =>
              inspect(
                "unexpected item children",
                content="paragraph and nested list",
              )
          }
        }
        _ => inspect("unexpected list children", content="one item")
      }
    _ => inspect("unexpected document children", content="one list")
  }
}

///|
test "experimental MarkdownIR: outdented marker resumes top-level list after nested flow" {
  let source = "- a\n  - b\n- c\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [first, second] => {
          debug_inspect(
            first.children().map(child => child.kind_tag()),
            content="[\"Paragraph\", \"UnorderedList\"]",
          )
          debug_inspect(
            second.children().map(child => child.kind_tag()),
            content="[\"Paragraph\"]",
          )
          inspect(
            experimental_markdown_ir_to_mdast_json(ir).stringify(),
            content=(
              #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"a"}]},{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"b"}]}]}]}]},{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"c"}]}]}]}]}
            ),
          )
          inspect(
            experimental_markdown_ir_canonical_format(
              @core.SourceId("markdown-ir-test-document"),
              ir,
            ),
            content="- a\n  - b\n- c",
          )
          assert_markdown_ir_block_matches_direct_parse(source)
        }
        _ => inspect("unexpected list children", content="two items")
      }
    _ => inspect("unexpected document children", content="one list")
  }
}

///|
test "experimental MarkdownIR: list item lazy continuation stays in item paragraph" {
  let source = "- a\nb\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [item] => {
          debug_inspect(
            item.children().map(child => child.kind_tag()),
            content="[\"Paragraph\"]",
          )
          inspect(
            experimental_markdown_ir_to_mdast_json(ir).stringify(),
            content=(
              #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"a\nb"}]}]}]}]}
            ),
          )
          assert_markdown_ir_block_matches_direct_parse(source)
        }
        _ => inspect("unexpected list children", content="one item")
      }
    _ => inspect("unexpected document children", content="one list")
  }
}

///|
test "experimental MarkdownIR: non-one ordered marker lazy continuation stays in item paragraph" {
  let source = "- a\n2. b\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"a\n2. b"}]}]}]}]}
    ),
  )
  assert_markdown_ir_block_matches_direct_parse(source)
}

///|
test "experimental MarkdownIR: indented non-one ordered marker starts nested ordered list" {
  let source = "- a\n  2. b\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"a"}]},{"type":"list","ordered":true,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"b"}]}]}],"start":2}]}]}]}
    ),
  )
  assert_markdown_ir_block_matches_direct_parse(source)
}

///|
test "experimental MarkdownIR: list item preserves whitespace-only inline syntax" {
  let source = "- ` `\n- [](/)\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"inlineCode","value":" "}]}]},{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"link","url":"/","children":[]}]}]}]}]}
    ),
  )
  assert_markdown_ir_block_matches_direct_parse(source)
}

///|
test "experimental MarkdownIR: direct list-item inline filtering matches Block adapter" {
  for
    source in [
      "- \nfoo\n", "-   \nfoo\n", "- a\nb\n", "- parent\n  - child\n", "- ` `\n",
      "- [](/)\n",
    ] {
    assert_markdown_ir_block_matches_direct_parse(source)
  }
}

///|
test "experimental MarkdownIR: loose list separator sets list spread" {
  let source = "- one\n\n- two\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [first, second] => {
          debug_inspect(list.spread(), content="Some(true)")
          debug_inspect(first.spread(), content="Some(false)")
          debug_inspect(second.spread(), content="Some(false)")
          inspect(
            experimental_markdown_ir_to_mdast_json(ir).stringify(),
            content=(
              #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"one"}]}]},{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"two"}]}]}],"spread":true}]}
            ),
          )
          assert_markdown_ir_block_matches_direct_parse(source)
        }
        _ => inspect("unexpected list children", content="two items")
      }
    _ => inspect("unexpected document children", content="one list")
  }
}

///|
test "experimental MarkdownIR: same-marker loose list carries marker metadata" {
  let source = "- one\n\n- two\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [list] => {
      debug_inspect(list.list_marker(), content="Some(Dash)")
      match list.children() {
        [first, second] => {
          debug_inspect(first.list_marker(), content="Some(Dash)")
          debug_inspect(second.list_marker(), content="Some(Dash)")
        }
        _ => inspect("unexpected list children", content="two items")
      }
    }
    _ => inspect("unexpected document children", content="one list")
  }
}

///|
test "experimental MarkdownIR: marker-change boundary carries marker metadata" {
  let source = "- one\n\n+ two\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [first, second] => {
      debug_inspect(first.list_marker(), content="Some(Dash)")
      debug_inspect(second.list_marker(), content="Some(Plus)")
    }
    _ => inspect("unexpected document children", content="two lists")
  }
}

///|
test "experimental MarkdownIR: ordered list delimiter boundary carries start metadata" {
  let source = "1. one\n2. two\n3) three\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [first, second] => {
      inspect(first.kind_tag(), content="OrderedList")
      inspect(second.kind_tag(), content="OrderedList")
      inspect(
        experimental_markdown_ir_to_mdast_json(ir).stringify(),
        content=(
          #|{"type":"root","children":[{"type":"list","ordered":true,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"one"}]}]},{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"two"}]}]}]},{"type":"list","ordered":true,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"three"}]}]}],"start":3}]}
        ),
      )
      inspect(
        experimental_markdown_ir_to_block(ir),
        content=(
          #|Document(
          #|  [
          #|    OrderedList(
          #|      [
          #|        OrderedListItem([Text("one")], Some({ start: 1, delimiter: Period })),
          #|        OrderedListItem([Text("two")], Some({ start: 2, delimiter: Period })),
          #|      ],
          #|      Some({ start: 1, delimiter: Period }),
          #|    ),
          #|    OrderedList(
          #|      [OrderedListItem([Text("three")], Some({ start: 3, delimiter: Paren }))],
          #|      Some({ start: 3, delimiter: Paren }),
          #|    ),
          #|  ],
          #|)
        ),
      )
      assert_markdown_ir_block_matches_direct_parse(source)
    }
    _ => inspect("unexpected document children", content="two ordered lists")
  }
}

///|
test "experimental MarkdownIR: blank-line-separated marker change stays separate lists" {
  let source = "- one\n\n+ two\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [first, second] => {
      debug_inspect(first.spread(), content="Some(false)")
      debug_inspect(second.spread(), content="Some(false)")
      inspect(
        experimental_markdown_ir_to_mdast_json(ir).stringify(),
        content=(
          #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"one"}]}]}]},{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"two"}]}]}]}]}
        ),
      )
      assert_markdown_ir_block_matches_direct_parse(source)
    }
    _ => inspect("unexpected document children", content="two lists")
  }
}

///|
test "experimental MarkdownIR: Block adapter matches direct parse for fenced code blocks" {
  assert_markdown_ir_block_matches_direct_parse("```moonbit\nlet x = 1\n```\n")
  assert_markdown_ir_block_matches_direct_parse("````\n```\n````\n")
}

///|
test "experimental MarkdownIR: Block adapter matches direct parse for inline formatting" {
  assert_markdown_ir_block_matches_direct_parse(
    "Hello **world** and *moon* with `code` plus [link](u(1))\n",
  )
  assert_markdown_ir_block_matches_direct_parse("\\*a **b** c*\n")
  assert_markdown_ir_block_matches_direct_parse("[\\*literal*](/)\n")
}

///|
test "experimental MarkdownIR: genuine inline ErrorNodes stay explicit" {
  assert_recovered_markdown_ir_block_matches_direct_parse("[unclosed\n", "[")
  assert_recovered_markdown_ir_block_matches_direct_parse("[text\n", "[")
}

///|
test "experimental MarkdownIR: lex-valid malformed heading/list recovery matches direct parse" {
  let sources = [
    "# **unclosed\n", "# [text](\n", "- **unclosed\n", "- [text](\n",
  ]
  for source in sources {
    assert_markdown_ir_block_matches_direct_parse(source)
  }
}

///|
test "experimental MarkdownIR: recovered nodes carry parser recovery diagnostics" {
  let source = "[unclosed\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) => {
          let recovered = paragraph.children()[index]
          inspect(recovered.diagnostics().length(), content="1")
          inspect(
            recovered.diagnostics()[0].format(),
            content="recovered malformed Markdown: [ [0,1]",
          )
        }
        None => inspect("missing", content="recovered child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: incoming diagnostics are attached to recovered nodes" {
  let source = "[unclosed\n"
  let (cst, _) = parse_cst(@core.SourceId("markdown-ir-test-document"), source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostic = @core.Diagnostic::lexer_error_at(
    @core.SourceId("markdown-ir-test-document"),
    "synthetic recovery diagnostic",
    0,
    1,
    "synthetic-recovery",
  )
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
    @core.SourceId("markdown-ir-test-document"),
    cst,
    @core.DiagnosticSet::single(diagnostic),
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) =>
          inspect(
            paragraph.children()[index].diagnostics()[0].format(),
            content="synthetic recovery diagnostic [0,1]",
          )
        None => inspect("missing", content="recovered child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: diagnostics do not reclassify literal emphasis" {
  let source = "\\*literal*\n"
  let (cst, _) = parse_cst(@core.SourceId("markdown-ir-test-document"), source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostic = @core.Diagnostic::lexer_error_at(
    @core.SourceId("markdown-ir-test-document"),
    "synthetic literal diagnostic",
    9,
    10,
    "synthetic-literal",
  )
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
    @core.SourceId("markdown-ir-test-document"),
    cst,
    @core.DiagnosticSet::single(diagnostic),
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text] => {
          inspect(text.kind_tag(), content="Text")
          match text.text_value() {
            Some(value) => inspect(value, content="*literal*")
            None => inspect("missing", content="literal text value")
          }
          inspect(text.diagnostics().length(), content="0")
        }
        _ => inspect("unexpected", content="one literal text child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: zero-width incoming diagnostics attach only with positive overlap" {
  let source = "[unclosed\n"
  let (cst, _) = parse_cst(@core.SourceId("markdown-ir-test-document"), source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostics = @core.DiagnosticSet::empty()
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      @core.SourceId("markdown-ir-test-document"),
      "zero-width at recovered start",
      0,
      0,
      "synthetic-zero",
    ),
  )
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      @core.SourceId("markdown-ir-test-document"),
      "positive recovered overlap",
      0,
      1,
      "synthetic-positive",
    ),
  )
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      @core.SourceId("markdown-ir-test-document"),
      "zero-width at recovered end",
      1,
      1,
      "synthetic-zero",
    ),
  )
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
    @core.SourceId("markdown-ir-test-document"),
    cst,
    diagnostics,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) => {
          let recovered = paragraph.children()[index]
          inspect(origin_source(source, recovered.origin()), content="[")
          inspect(
            recovered
            .diagnostics()
            .iter()
            .map(diagnostic => diagnostic.format())
            .collect()
            .join("|"),
            content="positive recovered overlap [0,1]",
          )
        }
        None => inspect("missing", content="recovered child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: incoming diagnostics are attached to raw nodes" {
  let source = "[text](\n"
  let (cst, _) = parse_cst(@core.SourceId("markdown-ir-test-document"), source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
    @core.SourceId("markdown-ir-test-document"),
    cst,
    malformed_link_raw_diagnostics(@core.SourceId("markdown-ir-test-document")),
  )
  match ir.children() {
    [paragraph] =>
      match
        paragraph.children().iter().filter(child => child.is_raw()).collect() {
        [raw_bracket, raw_paren] => {
          inspect(origin_source(source, raw_bracket.origin()), content="]")
          match raw_bracket.diagnostics() {
            [diagnostic] =>
              inspect(
                diagnostic.format(),
                content="synthetic raw bracket diagnostic [5,6]",
              )
            _ => inspect("unexpected", content="one raw bracket diagnostic")
          }
          inspect(origin_source(source, raw_paren.origin()), content="(")
          match raw_paren.diagnostics() {
            [diagnostic] =>
              inspect(
                diagnostic.format(),
                content="synthetic raw paren diagnostic [6,7]",
              )
            _ => inspect("unexpected", content="one raw paren diagnostic")
          }
        }
        _ => inspect("unexpected", content="two raw children")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: unclosed link parens preserve orphan tokens as raw" {
  let source = "[text](\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  let via_ir = experimental_markdown_ir_to_block(ir)
  inspect(
    via_ir,
    content=@debug.to_string(
      parse(@core.SourceId("markdown-ir-test-document"), source),
    ),
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [recovered, text, raw_bracket, raw_paren] => {
          inspect(recovered.kind_tag(), content="Recovered")
          match text.text_value() {
            Some(value) => inspect(value, content="text")
            None => inspect("missing", content="text value")
          }
          inspect(raw_bracket.kind_tag(), content="Raw")
          inspect(origin_source(source, raw_bracket.origin()), content="]")
          inspect(raw_bracket.diagnostics().length(), content="1")
          inspect(raw_paren.kind_tag(), content="Raw")
          inspect(origin_source(source, raw_paren.origin()), content="(")
          inspect(raw_paren.diagnostics().length(), content="1")
        }
        _ => inspect("unexpected", content="recovered text raw raw")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: mdastRaw export carries injected diagnostics" {
  let source = "[text](\n"
  let (cst, _) = parse_cst(@core.SourceId("markdown-ir-test-document"), source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
    @core.SourceId("markdown-ir-test-document"),
    cst,
    malformed_link_raw_diagnostics(@core.SourceId("markdown-ir-test-document")),
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"mdastRecovered","value":"[","origin":{"start":0,"end":1},"diagnostics":["recovered malformed Markdown: [ [0,1]"]},{"type":"text","value":"text"},{"type":"mdastRaw","value":"]","origin":{"start":5,"end":6},"diagnostics":["synthetic raw bracket diagnostic [5,6]"]},{"type":"mdastRaw","value":"(","origin":{"start":6,"end":7},"diagnostics":["synthetic raw paren diagnostic [6,7]"]}]}]}
    ),
  )
}

///|
test "experimental MarkdownIR: mdastRecovered export carries injected diagnostics" {
  let source = "[text](\n"
  let (cst, _) = parse_cst(@core.SourceId("markdown-ir-test-document"), source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostic = @core.Diagnostic::lexer_error_at(
    @core.SourceId("markdown-ir-test-document"),
    "synthetic recovered diagnostic",
    0,
    1,
    "synthetic-recovery",
  )
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
    @core.SourceId("markdown-ir-test-document"),
    cst,
    @core.DiagnosticSet::single(diagnostic),
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"mdastRecovered","value":"[","origin":{"start":0,"end":1},"diagnostics":["synthetic recovered diagnostic [0,1]"]},{"type":"text","value":"text"},{"type":"mdastRaw","value":"]","origin":{"start":5,"end":6},"diagnostics":["raw recovered Markdown [5,6]"]},{"type":"mdastRaw","value":"(","origin":{"start":6,"end":7},"diagnostics":["raw recovered Markdown [6,7]"]}]}]}
    ),
  )
}

///|
test "experimental MarkdownIR: direct syntax entry point attaches injected diagnostics to mdast recovered node" {
  let source = "[text](\n"
  let (cst, _) = parse_cst(@core.SourceId("markdown-ir-test-document"), source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostic = @core.Diagnostic::lexer_error_at(
    @core.SourceId("markdown-ir-test-document"),
    "direct syntax recovered diagnostic",
    0,
    1,
    "synthetic-recovery",
  )
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    @core.SourceId("markdown-ir-test-document"),
    @seam.SyntaxNode::from_cst(cst),
    @core.DiagnosticSet::single(diagnostic),
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"mdastRecovered","value":"[","origin":{"start":0,"end":1},"diagnostics":["direct syntax recovered diagnostic [0,1]"]},{"type":"text","value":"text"},{"type":"mdastRaw","value":"]","origin":{"start":5,"end":6},"diagnostics":["raw recovered Markdown [5,6]"]},{"type":"mdastRaw","value":"(","origin":{"start":6,"end":7},"diagnostics":["raw recovered Markdown [6,7]"]}]}]}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export converts UTF-16 origins to unist points" {
  let source = "# T\n\n😀a"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"heading","depth":1,"children":[{"type":"text","value":"T","position":{"start":{"line":1,"column":3,"offset":2},"end":{"line":1,"column":4,"offset":3}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":1,"column":4,"offset":3}}},{"type":"paragraph","children":[{"type":"text","value":"😀a","position":{"start":{"line":3,"column":1,"offset":5},"end":{"line":3,"column":4,"offset":8}}}],"position":{"start":{"line":3,"column":1,"offset":5},"end":{"line":3,"column":4,"offset":8}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":4,"offset":8}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export covers raw and recovered nodes" {
  let source = "[text](\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"mdastRecovered","value":"[","origin":{"start":0,"end":1},"diagnostics":["recovered malformed Markdown: [ [0,1]"],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":1,"column":2,"offset":1}}},{"type":"text","value":"text","position":{"start":{"line":1,"column":2,"offset":1},"end":{"line":1,"column":6,"offset":5}}},{"type":"mdastRaw","value":"]","origin":{"start":5,"end":6},"diagnostics":["raw recovered Markdown [5,6]"],"position":{"start":{"line":1,"column":6,"offset":5},"end":{"line":1,"column":7,"offset":6}}},{"type":"mdastRaw","value":"(","origin":{"start":6,"end":7},"diagnostics":["raw recovered Markdown [6,7]"],"position":{"start":{"line":1,"column":7,"offset":6},"end":{"line":1,"column":8,"offset":7}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":1,"column":8,"offset":7}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":2,"column":1,"offset":8}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export trims code block separator blank lines" {
  let source = "```\nx\n```\n\nnext"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"code","value":"x","position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":4,"offset":9}}},{"type":"paragraph","children":[{"type":"text","value":"next","position":{"start":{"line":5,"column":1,"offset":11},"end":{"line":5,"column":5,"offset":15}}}],"position":{"start":{"line":5,"column":1,"offset":11},"end":{"line":5,"column":5,"offset":15}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":5,"column":5,"offset":15}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export trims tilde code block separator blank lines" {
  let source = "~~~\nx\n~~~\n\nnext"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"code","value":"x","position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":4,"offset":9}}},{"type":"paragraph","children":[{"type":"text","value":"next","position":{"start":{"line":5,"column":1,"offset":11},"end":{"line":5,"column":5,"offset":15}}}],"position":{"start":{"line":5,"column":1,"offset":11},"end":{"line":5,"column":5,"offset":15}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":5,"column":5,"offset":15}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export finds indented tilde close fence" {
  let source = "~~~\nx\n  ~~~\n\nnext"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"code","value":"x","position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":6,"offset":11}}},{"type":"paragraph","children":[{"type":"text","value":"next","position":{"start":{"line":5,"column":1,"offset":13},"end":{"line":5,"column":5,"offset":17}}}],"position":{"start":{"line":5,"column":1,"offset":13},"end":{"line":5,"column":5,"offset":17}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":5,"column":5,"offset":17}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export handles CRLF code fences" {
  let source = "```\r\nx\r\n```\r\n\r\nnext"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"code","value":"x","position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":4,"offset":11}}},{"type":"paragraph","children":[{"type":"text","value":"next","position":{"start":{"line":5,"column":1,"offset":15},"end":{"line":5,"column":5,"offset":19}}}],"position":{"start":{"line":5,"column":1,"offset":15},"end":{"line":5,"column":5,"offset":19}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":5,"column":5,"offset":19}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export includes closing fence trailing spaces" {
  let source = "```\nx\n```  \nnext"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"code","value":"x","position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":6,"offset":11}}},{"type":"paragraph","children":[{"type":"text","value":"next","position":{"start":{"line":4,"column":1,"offset":12},"end":{"line":4,"column":5,"offset":16}}}],"position":{"start":{"line":4,"column":1,"offset":12},"end":{"line":4,"column":5,"offset":16}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":4,"column":5,"offset":16}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export preserves unclosed CRLF code fence" {
  let source = "```\r\ncode\r\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"code","value":"code","position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":1,"offset":11}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":1,"offset":11}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export treats CRLF as paragraph newline" {
  let source = "Hello\r\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"text","value":"Hello","position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":1,"column":6,"offset":5}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":1,"column":6,"offset":5}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":2,"column":1,"offset":7}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export uses empty list item content range" {
  let source = "- \n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[],"position":{"start":{"line":1,"column":3,"offset":2},"end":{"line":1,"column":3,"offset":2}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":1,"column":3,"offset":2}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":1,"column":3,"offset":2}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":2,"column":1,"offset":3}}}
    ),
  )
}

///|
test "experimental MarkdownIR: adjacent malformed links preserve raw delimiters" {
  assert_malformed_link_raws_preserved("[text](url\n", "](")
  assert_malformed_link_raws_preserved("[text](\nnext\n", "](")
  assert_malformed_link_raws_preserved("[*x](url\n", "](")
  assert_malformed_link_raws_preserved("\\[prefix [text](\n", "](")
}

///|
test "experimental MarkdownIR: unclosed code fence remains a code block" {
  let source = "```\ncode without close\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_block(ir),
    content=@debug.to_string(
      parse(@core.SourceId("markdown-ir-test-document"), source),
    ),
  )
  match ir.children() {
    [code_block] => {
      inspect(code_block.kind_tag(), content="CodeBlock")
      inspect(origin_source(source, code_block.origin()), content=source)
      inspect(
        experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
        content=(
          #|{"type":"root","children":[{"type":"code","value":"code without close","position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":1,"offset":23}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":1,"offset":23}}}
        ),
      )
    }
    _ => inspect("unexpected", content="one code block")
  }
}

///|
test "experimental MarkdownIR: Block adapter matches direct parse for current subset mixture" {
  assert_markdown_ir_block_matches_direct_parse(current_parser_subset_source())
}

///|
test "experimental MarkdownIR: preserve rewrite keeps source slices" {
  let source = "# Title\nParagraph text\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
  match ir.children() {
    [heading, paragraph] => {
      inspect(
        experimental_markdown_ir_preserve_rewrite(heading, source),
        content="# Title\n",
      )
      inspect(
        experimental_markdown_ir_preserve_rewrite(paragraph, source),
        content="Paragraph text\n",
      )
    }
    _ => inspect("unexpected child count", content="heading and paragraph")
  }
}

///|
test "experimental MarkdownIR: preserve rewrite round-trips code block" {
  let source = "```moonbit\nlet x = 1\n```\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
}

///|
fn local_code_block_content_rewrite(
  source : String,
  replacement_text : String,
) -> String raise {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [code_block, ..] =>
      match code_block.content_origin() {
        Some(origin) =>
          experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=origin,
            replacement_text~,
          )
        None => {
          inspect("missing", content="code block content origin")
          ""
        }
      }
    [] => {
      inspect("unexpected child count", content="code block")
      ""
    }
  }
}

///|
fn assert_local_code_block_content_rewrite(
  source : String,
  replacement_text : String,
  expected : String,
) -> String raise {
  let result = local_code_block_content_rewrite(source, replacement_text)
  inspect(result, content=expected)
  result
}

///|
test "experimental MarkdownIR: local transform rewrites code block content origin" {
  let _ = assert_local_code_block_content_rewrite(
    "```moonbit\nlet x = 1\n```\n", "let y = 2", "```moonbit\nlet y = 2\n```\n",
  )
}

///|
test "experimental MarkdownIR: local transform preserves tilde code fence" {
  let _ = assert_local_code_block_content_rewrite(
    "~~~moonbit\nlet x = 1\n~~~\n", "let y = 2", "~~~moonbit\nlet y = 2\n~~~\n",
  )
}

///|
test "experimental MarkdownIR: local transform preserves indented tilde close fence" {
  let _ = assert_local_code_block_content_rewrite(
    "~~~\nold\n  ~~~\n", "new", "~~~\nnew\n  ~~~\n",
  )
}

///|
test "experimental MarkdownIR: local transform preserves wider code fence" {
  let _ = assert_local_code_block_content_rewrite(
    "````moonbit\nlet x = 1\n````\n", "let y = 2", "````moonbit\nlet y = 2\n````\n",
  )
}

///|
test "experimental MarkdownIR: local transform widens code fence for backticks" {
  let result = assert_local_code_block_content_rewrite(
    "```\nold code\n```\n", "line\n```\nline", "````\nline\n```\nline\n````\n",
  )
  inspect(
    parse(@core.SourceId("markdown-ir-test-document"), result),
    content="Document([CodeBlock(\"\", \"line\\n```\\nline\")])",
  )
}

///|
test "experimental MarkdownIR: local transform preserves unclosed code fence" {
  let result = assert_local_code_block_content_rewrite(
    "```\nold\n", "new", "```\nnew\n",
  )
  inspect(
    parse(@core.SourceId("markdown-ir-test-document"), result),
    content="Document([CodeBlock(\"\", \"new\")])",
  )
}

///|
test "experimental MarkdownIR: local transform widens unclosed code fence" {
  let result = assert_local_code_block_content_rewrite(
    "```\nold\n", "line\n```\nline", "````\nline\n```\nline\n",
  )
  inspect(
    parse(@core.SourceId("markdown-ir-test-document"), result),
    content="Document([CodeBlock(\"\", \"line\\n```\\nline\")])",
  )
}

///|
test "experimental MarkdownIR: local transform preserves code fence separator" {
  let _ = assert_local_code_block_content_rewrite(
    "```\nold\n```\n\nNext\n", "new", "```\nnew\n```\n\nNext\n",
  )
}

///|
test "experimental MarkdownIR: local transform preserves CRLF code fence" {
  let _ = assert_local_code_block_content_rewrite(
    "```\r\nold\r\n```\r\n", "new", "```\r\nnew\r\n```\r\n",
  )
}

///|
test "experimental MarkdownIR: local transform rewrites empty closed code fence" {
  let source = "```\n```\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [code_block] =>
      match code_block.content_origin() {
        Some(origin) => {
          inspect(origin.start(), content="4")
          inspect(origin.end(), content="4")
          let result = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=origin,
            replacement_text="new",
          )
          inspect(result, content="```\nnew\n```\n")
          inspect(
            parse(@core.SourceId("markdown-ir-test-document"), result),
            content="Document([CodeBlock(\"\", \"new\")])",
          )
        }
        None => inspect("missing", content="code block content origin")
      }
    _ => inspect("unexpected child count", content="one code block")
  }
}

///|
test "experimental MarkdownIR: local transform rewrites empty unclosed code fence" {
  let source = "```\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [code_block] =>
      match code_block.content_origin() {
        Some(origin) => {
          inspect(origin.start(), content="4")
          inspect(origin.end(), content="4")
          let result = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=origin,
            replacement_text="new",
          )
          inspect(result, content="```\nnew\n")
          inspect(
            parse(@core.SourceId("markdown-ir-test-document"), result),
            content="Document([CodeBlock(\"\", \"new\")])",
          )
        }
        None => inspect("missing", content="code block content origin")
      }
    _ => inspect("unexpected child count", content="one code block")
  }
}

///|
test "experimental MarkdownIR: local transform rewrites empty EOF code fence" {
  let source = "```"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [code_block] =>
      match code_block.content_origin() {
        Some(origin) => {
          inspect(origin.start(), content="3")
          inspect(origin.end(), content="3")
          let result = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=origin,
            replacement_text="new",
          )
          inspect(result, content="```\nnew\n")
          inspect(
            parse(@core.SourceId("markdown-ir-test-document"), result),
            content="Document([CodeBlock(\"\", \"new\")])",
          )
        }
        None => inspect("missing", content="code block content origin")
      }
    _ => inspect("unexpected child count", content="one code block")
  }
}

///|
test "experimental MarkdownIR: empty code fence rewrite preserves replacement trailing newline" {
  let result = assert_local_code_block_content_rewrite(
    "```\n```\n", "new\n", "```\nnew\n\n```\n",
  )
  inspect(
    parse(@core.SourceId("markdown-ir-test-document"), result),
    content="Document([CodeBlock(\"\", \"new\\n\")])",
  )
}

///|
test "experimental MarkdownIR: unclosed EOF code fence preserves replacement trailing newline" {
  let result = assert_local_code_block_content_rewrite(
    "```\nold", "new\n", "```\nnew\n\n",
  )
  inspect(
    parse(@core.SourceId("markdown-ir-test-document"), result),
    content="Document([CodeBlock(\"\", \"new\\n\")])",
  )
}

///|
test "experimental MarkdownIR: local transform rewrites code block full origin" {
  let source = "```\nold code\n```\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [code_block] => {
      let result = experimental_markdown_ir_local_transform_rewrite(
        ir,
        source,
        target_origin=code_block.origin(),
        replacement_text="Replaced\n",
      )
      inspect(result, content="Replaced\n")
    }
    _ => inspect("unexpected child count", content="one code block")
  }
}

///|
test "experimental MarkdownIR: local transform sibling preserves code block" {
  let source = "Para.\n\n```\ncode here\n```\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph, _] =>
      match paragraph.content_origin() {
        Some(origin) => {
          let result = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=origin,
            replacement_text="Changed.",
          )
          inspect(result, content="Changed.\n\n```\ncode here\n```\n")
        }
        None => inspect("missing", content="paragraph content origin")
      }
    _ => inspect("unexpected child count", content="paragraph and code block")
  }
}

///|
test "experimental MarkdownIR: unmatched inline delimiters adapt to text" {
  let source = "Hello *\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  let block = experimental_markdown_ir_to_block(ir)
  inspect(block, content="Document([Paragraph([Text(\"Hello *\")])])")
  inspect(
    block,
    content=@debug.to_string(
      parse(@core.SourceId("markdown-ir-test-document"), source),
    ),
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text] => {
          inspect(text.kind_tag(), content="Text")
          inspect(origin_source(source, text.origin()), content="Hello *")
        }
        _ => inspect("unexpected", content="one literal text child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform splices changed text" {
  let source = "# Title\nParagraph text\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [_, paragraph] =>
      match paragraph.children() {
        [text] => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=text.origin(),
            replacement_text="Changed text",
          )
          inspect(local_rewrite, content="# Title\nChanged text\n")
        }
        _ => inspect("unexpected paragraph children", content="one text")
      }
    _ => inspect("unexpected child count", content="heading and paragraph")
  }
}

///|
test "experimental MarkdownIR: Block adapter normalizes paragraph soft breaks" {
  assert_markdown_ir_block_matches_direct_parse("a\nb\nc\n")
}

///|
test "experimental MarkdownIR: Block adapter matches nested inline soft breaks" {
  assert_markdown_ir_block_matches_direct_parse("**bold\ntext**\n")
  assert_markdown_ir_block_matches_direct_parse("*italic\ntext*\n")
  assert_markdown_ir_block_matches_direct_parse("[link\ntext](target)\n")
}

///|
test "experimental MarkdownIR: canonical format preserves hard breaks" {
  let source = "aaa     \nbbb     \n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  let canonical = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    ir,
  )
  inspect(canonical, content="aaa     \nbbb")
  inspect(
    experimental_markdown_ir_to_block(ir),
    content="Document([Paragraph([Text(\"aaa\"), Text(\"\\n\"), Text(\"bbb\")])])",
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [_, hard_break, _] => {
          inspect(hard_break.kind_tag(), content="HardBreak")
          inspect(origin_source(source, hard_break.origin()), content="     \n")
        }
        _ => inspect("unexpected paragraph children", content="hard break")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
  let reparsed = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    canonical,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(reparsed),
    content="<p>aaa<br />\nbbb</p>\n",
  )
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      reparsed,
    ),
    content=canonical,
  )
}

///|
test "experimental MarkdownIR: inline delimiter close flushes pending breaks" {
  let strong_hard = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "**foo  \nbar**\n",
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(strong_hard),
    content="<p><strong>foo<br />\nbar</strong></p>\n",
  )
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      strong_hard,
    ),
    content="**foo  \nbar**",
  )
  inspect(
    experimental_markdown_ir_to_block(strong_hard),
    content=(
      #|Document([Paragraph([Bold([Text("foo"), Text("\n"), Text("bar")])])])
    ),
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        "**foo\nbar**\n",
      ),
    ),
    content="<p><strong>foo\nbar</strong></p>\n",
  )
}

///|
test "experimental MarkdownIR: local transform renders paragraph soft breaks" {
  let source = "line one\nline two\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text_before, _softbreak, _text_after] => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=text_before.origin(),
            replacement_text="first line",
          )
          inspect(local_rewrite, content="first line\nline two\n")
        }
        _ =>
          inspect("unexpected paragraph children", content="three text nodes")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform rewrites link destination origin" {
  let source = "[label](old)\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [link] =>
          match link.destination_origin() {
            Some(origin) => {
              let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
                ir,
                source,
                target_origin=origin,
                replacement_text="new",
              )
              inspect(local_rewrite, content="[label](new)\n")
            }
            None => inspect("missing", content="link destination origin")
          }
        _ => inspect("unexpected paragraph children", content="link")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: link label origin excludes brackets" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "[label](old)\n",
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [link] =>
          match link.label_origin() {
            Some(origin) => {
              inspect(origin.start(), content="1")
              inspect(origin.end(), content="6")
            }
            None => inspect("missing", content="link label origin")
          }
        _ => inspect("unexpected paragraph children", content="link")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: formatted link label origin includes delimiters" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "[**label**](old)\n",
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [link] =>
          match link.label_origin() {
            Some(origin) => {
              inspect(origin.start(), content="1")
              inspect(origin.end(), content="10")
            }
            None => inspect("missing", content="formatted link label origin")
          }
        _ => inspect("unexpected paragraph children", content="link")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform rewrites inline code content origin" {
  let source = "`code`\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [inline_code] =>
          match inline_code.content_origin() {
            Some(origin) => {
              let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
                ir,
                source,
                target_origin=origin,
                replacement_text="`",
              )
              inspect(local_rewrite, content="`` ` ``\n")
              inspect(
                experimental_markdown_ir_local_transform_rewrite(
                  ir,
                  source,
                  target_origin=origin,
                  replacement_text="",
                ),
                content="\n",
              )
            }
            None => inspect("missing", content="inline code content origin")
          }
        _ => inspect("unexpected paragraph children", content="inline code")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform preserves noncanonical inline code sibling" {
  let source = "`` foo ` bar ``old\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [_inline_code, text] => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=text.origin(),
            replacement_text="new",
          )
          inspect(local_rewrite, content="`` foo ` bar ``new\n")
          inspect(
            experimental_markdown_ir_to_mdast_json(
              markdown_ir_from_source(
                @core.SourceId("markdown-ir-test-document"),
                local_rewrite,
              ),
            ).stringify(),
            content=experimental_markdown_ir_to_mdast_json(
              markdown_ir_from_source(
                @core.SourceId("markdown-ir-test-document"),
                "`` foo ` bar ``new\n",
              ),
            ).stringify(),
          )
        }
        _ =>
          inspect(
            "unexpected paragraph children",
            content="inline code and text",
          )
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform rewrites container content origins" {
  let source = "# Old\n\nHello **world**\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [heading, paragraph] => {
      match heading.content_origin() {
        Some(origin) =>
          inspect(
            experimental_markdown_ir_local_transform_rewrite(
              ir,
              source,
              target_origin=origin,
              replacement_text="New",
            ),
            content="# New\n\nHello **world**\n",
          )
        None => inspect("missing", content="heading content origin")
      }
      match paragraph.content_origin() {
        Some(origin) =>
          inspect(
            experimental_markdown_ir_local_transform_rewrite(
              ir,
              source,
              target_origin=origin,
              replacement_text="Changed",
            ),
            content="# Old\n\nChanged\n",
          )
        None => inspect("missing", content="paragraph content origin")
      }
    }
    _ => inspect("unexpected child count", content="heading and paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform rewrites full node origins" {
  let source = "# Old\n\nParagraph\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [heading, _] => {
      let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
        ir,
        source,
        target_origin=heading.origin(),
        replacement_text="Replacement\n",
      )
      inspect(local_rewrite, content="Replacement\n\nParagraph\n")
    }
    _ => inspect("unexpected child count", content="heading and paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform preserves inline container siblings" {
  let source = "Hello **world** tail\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text, _, _] => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=text.origin(),
            replacement_text="Hi ",
          )
          inspect(local_rewrite, content="Hi **world** tail\n")
        }
        _ => inspect("unexpected paragraph children", content="text bold text")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform preserves escaped text sibling" {
  let source = "\\*literal* and **old**\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [escaped, bold] => {
          match escaped.text_value() {
            Some(value) => inspect(value, content="*literal* and ")
            None => inspect("missing", content="decoded escaped sibling")
          }
          inspect(
            origin_source(source, escaped.origin()),
            content="\\*literal* and ",
          )
          match bold.children() {
            [old_text] => {
              let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
                ir,
                source,
                target_origin=old_text.origin(),
                replacement_text="new",
              )
              inspect(local_rewrite, content="\\*literal* and **new**\n")
            }
            _ => inspect("unexpected bold children", content="one text")
          }
        }
        _ => inspect("unexpected paragraph children", content="text then bold")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform preserves underscore emphasis delimiters" {
  for case in [("_old_\n", "_new_\n"), ("__old__\n", "__new__\n")] {
    let (source, expected) = case
    let ir = markdown_ir_from_source(
      @core.SourceId("markdown-ir-test-document"),
      source,
    )
    match ir.children() {
      [paragraph] =>
        match paragraph.children() {
          [emphasis] =>
            match emphasis.children() {
              [old_text] => {
                let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
                  ir,
                  source,
                  target_origin=old_text.origin(),
                  replacement_text="new",
                )
                inspect(local_rewrite, content=expected)
              }
              _ => inspect("unexpected emphasis children", content="one text")
            }
          _ => inspect("unexpected paragraph children", content="one emphasis")
        }
      _ => inspect("unexpected child count", content="one paragraph")
    }
  }
}

///|
test "experimental MarkdownIR: local transform preserves CRLF block ending" {
  let source = "# Old\r\nParagraph\r\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [_, paragraph] =>
      match paragraph.content_origin() {
        Some(origin) => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=origin,
            replacement_text="Changed",
          )
          inspect(local_rewrite, content="# Old\r\nChanged\r\n")
        }
        None => inspect("missing", content="paragraph content origin")
      }
    _ => inspect("unexpected child count", content="heading and paragraph")
  }
}

///|
test "experimental MarkdownIR: canonical formatter renders inline containers" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "Hello **world** and [link](u(1))\n",
  )
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      ir,
    ),
    content="Hello **world** and [link](u(1))",
  )
}

///|
test "experimental MarkdownIR: checked canonical formatter preserves literal marker semantics" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "\\*a\\*\n",
  )
  match
    experimental_markdown_ir_canonical_format_checked(
      @core.SourceId("markdown-ir-test-document"),
      ir,
    ) {
    Ok(formatted) => {
      assert_eq(formatted, "\\*a\\*")
      let reparsed = markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        formatted,
      )
      assert_eq(
        experimental_markdown_ir_to_mdast_json(reparsed).stringify(),
        experimental_markdown_ir_to_mdast_json(ir).stringify(),
      )
    }
    Err(_) => fail("expected literal marker text to have a checked encoding")
  }
}

///|
fn assert_checked_canonical_round_trip(source : String) -> String raise {
  let intended = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match
    experimental_markdown_ir_canonical_format_checked(
      @core.SourceId("markdown-ir-test-document"),
      intended,
    ) {
    Ok(formatted) => {
      let reparsed = markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        formatted,
      )
      assert_eq(
        experimental_markdown_ir_to_commonmark_html(reparsed),
        experimental_markdown_ir_to_commonmark_html(intended),
      )
      assert_eq(
        experimental_markdown_ir_canonical_format_checked(
          @core.SourceId("markdown-ir-test-document"),
          reparsed,
        ),
        Ok(formatted),
      )
      formatted
    }
    Err(failure) =>
      fail(
        "checked canonical round trip failed for " +
        @debug.to_string(source) +
        ": " +
        @debug.to_string(failure),
      )
  }
}

///|
test "experimental MarkdownIR: checked canonical formatter covers delimiter interactions" {
  let sources = [
    "x*_a_*\n", "_a_*b*\n", "***a*** and __b *c*__\n", "*foo**bar*\n", "\\*odd\\* and \\\\*even*\n",
    "[\\*literal\\*](u) and `*code*`\n", "。_a_→*b*😈\n", "[a](u \"x\\\"y\")\n",
  ]
  for source in sources {
    ignore(assert_checked_canonical_round_trip(source))
  }
}

///|
test "experimental MarkdownIR: checked canonical formatter validates block context" {
  let formatted = assert_checked_canonical_round_trip("\\-\\-\\-\n")
  assert_eq(formatted, "\\-\\-\\-")
  assert_eq(
    parse(@core.SourceId("markdown-ir-test-document"), formatted),
    Document([Paragraph([Text("---")])]),
  )
}

///|
test "experimental MarkdownIR: checked and compatibility roots stay distinct" {
  let document = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "plain\n",
  )
  match document.children() {
    [paragraph] => {
      assert_eq(
        experimental_markdown_ir_canonical_format_checked(
          @core.SourceId("markdown-ir-test-document"),
          paragraph,
        ),
        Err(ExpectedDocument),
      )
      assert_eq(
        experimental_markdown_ir_canonical_format(
          @core.SourceId("markdown-ir-test-document"),
          paragraph,
        ),
        "plain",
      )
    }
    _ => fail("expected one paragraph")
  }
}

///|
test "experimental MarkdownIR: checked formatter rejects opaque compatibility input" {
  let document = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "[text](url\n",
  )
  match
    experimental_markdown_ir_canonical_format_checked(
      @core.SourceId("markdown-ir-test-document"),
      document,
    ) {
    Err(OpaqueNode(kind, Some(_))) =>
      assert_eq(kind, MarkdownIRCanonicalOpaqueKind::Recovered)
    other =>
      fail("expected checked opaque rejection, got " + @debug.to_string(other))
  }
  assert_eq(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      document,
    ),
    "[text](url",
  )
}

///|
test "experimental MarkdownIR: canonical code fence exceeds content backtick run" {
  let formatted = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(
      @core.SourceId("markdown-ir-test-document"),
      "````\n```\n````\n",
    ),
  )
  inspect(formatted, content="````\n```\n````")
  inspect(
    parse(@core.SourceId("markdown-ir-test-document"), formatted),
    content="Document([CodeBlock(\"\", \"```\")])",
  )
}

///|
test "experimental MarkdownIR: canonical inline code protects interior backticks" {
  let source = "``foo ` bar``\n"
  let canonical = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(@core.SourceId("markdown-ir-test-document"), source),
  )
  inspect(canonical, content="``foo ` bar``")
  inspect(
    experimental_markdown_ir_to_mdast_json(
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        canonical,
      ),
    ).stringify(),
    content=experimental_markdown_ir_to_mdast_json(
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        source,
      ),
    ).stringify(),
  )
}

///|
test "experimental MarkdownIR: canonical inline code preserves boundary spaces around backticks" {
  let source = "``  `  ``\n"
  let canonical = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(@core.SourceId("markdown-ir-test-document"), source),
  )
  inspect(canonical, content="``  `  ``")
  inspect(
    experimental_markdown_ir_to_mdast_json(
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        canonical,
      ),
    ).stringify(),
    content=experimental_markdown_ir_to_mdast_json(
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        source,
      ),
    ).stringify(),
  )
}

///|
test "experimental MarkdownIR: canonical inline code keeps all and one-sided spaces" {
  let source = "`  ` ``  foo `` `` foo  ``\n"
  let canonical = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(@core.SourceId("markdown-ir-test-document"), source),
  )
  inspect(canonical, content="`  ` ` foo` `foo `")
  inspect(
    experimental_markdown_ir_to_mdast_json(
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        canonical,
      ),
    ).stringify(),
    content=experimental_markdown_ir_to_mdast_json(
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        source,
      ),
    ).stringify(),
  )
}

///|
test "experimental MarkdownIR: canonical inline code protects edge and maximal runs" {
  let source = "`` `foo `` `` foo` `` ```foo `` bar```\n"
  let canonical = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(@core.SourceId("markdown-ir-test-document"), source),
  )
  inspect(canonical, content="`` `foo `` `` foo` `` ```foo `` bar```")
  inspect(
    experimental_markdown_ir_to_mdast_json(
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        canonical,
      ),
    ).stringify(),
    content=experimental_markdown_ir_to_mdast_json(
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        source,
      ),
    ).stringify(),
  )
}

///|
test "experimental MarkdownIR: canonical format preserves code block info string" {
  let formatted = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(
      @core.SourceId("markdown-ir-test-document"),
      "```moonbit\nlet x = 1\n```\n",
    ),
  )
  inspect(formatted, content="```moonbit\nlet x = 1\n```")
  inspect(
    parse(@core.SourceId("markdown-ir-test-document"), formatted),
    content="Document([CodeBlock(\"moonbit\", \"let x = 1\")])",
  )
}

///|
test "experimental MarkdownIR: rewrite modes are distinguishable" {
  let source = "# Title\nParagraph text\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  let preserve = experimental_markdown_ir_preserve_rewrite(ir, source)
  let canonical = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    ir,
  )
  match ir.children() {
    [_, paragraph] =>
      match paragraph.children() {
        [text] => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=text.origin(),
            replacement_text="Changed text",
          )
          inspect(preserve, content="# Title\nParagraph text\n")
          inspect(local_rewrite, content="# Title\nChanged text\n")
          inspect(canonical, content="# Title\n\nParagraph text")
          inspect(preserve != local_rewrite, content="true")
          inspect(local_rewrite != canonical, content="true")
        }
        _ => inspect("unexpected paragraph children", content="one text")
      }
    _ => inspect("unexpected child count", content="heading and paragraph")
  }
}

///|
test "experimental MarkdownIR: Inline adapter renders raw children as text" {
  let source = "[text](url\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  let block = experimental_markdown_ir_to_block(ir)
  inspect(
    block,
    content=@debug.to_string(
      parse(@core.SourceId("markdown-ir-test-document"), source),
    ),
  )
  match block {
    Document([Paragraph(inlines)]) =>
      match inlines {
        [Error("["), Text("text"), Text("]"), Text("("), Text("url")] => ()
        _ => inspect(block, content="raw delimiters lowered as inline text")
      }
    _ => inspect(block, content="one paragraph document")
  }
}

///|
test "experimental MarkdownIR: canonical formatter preserves recovered source text" {
  let source = "Hello *\n"
  let formatted = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(@core.SourceId("markdown-ir-test-document"), source),
  )
  inspect(formatted, content="Hello *")
}

///|
test "experimental MarkdownIR: canonical formatter passes raw text through" {
  let source = "[text](url\n"
  let formatted = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(@core.SourceId("markdown-ir-test-document"), source),
  )
  inspect(formatted, content="[text](url")
}

///|
test "experimental MarkdownIR: preserve rewrite keeps recovered source slice" {
  let source = "[unclosed\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [recovered, _] if recovered.is_recovered() =>
          inspect(origin_source(source, recovered.origin()), content="[")
        _ => inspect("unexpected", content="recovered opener plus text")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform replaces recovered text" {
  let source = "[unclosed\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [recovered, _] if recovered.is_recovered() => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=recovered.origin(),
            replacement_text="world",
          )
          inspect(local_rewrite, content="worldunclosed\n")
        }
        _ => inspect("unexpected", content="recovered opener plus text")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: preserve rewrite round-trips valid link" {
  let source = "[text](url)\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [link] =>
          inspect(
            experimental_markdown_ir_preserve_rewrite(link, source),
            content="[text](url)",
          )
        _ => inspect("unexpected paragraph children", content="link")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform rewrites link label" {
  let source = "[old](url)\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [link] =>
          match link.children() {
            [text] => {
              let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
                ir,
                source,
                target_origin=text.origin(),
                replacement_text="new",
              )
              inspect(local_rewrite, content="[new](url)\n")
            }
            _ => inspect("unexpected link children", content="text")
          }
        _ => inspect("unexpected paragraph children", content="link")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform preserves sibling link" {
  let source = "Hello [link](url) world\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text, link, _] => {
          inspect(link.kind_tag(), content="Link")
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=text.origin(),
            replacement_text="Hi ",
          )
          inspect(local_rewrite, content="Hi [link](url) world\n")
        }
        _ => inspect("unexpected paragraph children", content="text link text")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform replaces raw delimiter in malformed link" {
  let source = "[text](\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [_, _, raw_bracket, _] if raw_bracket.is_raw() => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=raw_bracket.origin(),
            replacement_text="X",
          )
          inspect(local_rewrite, content="[textX(\n")
        }
        _ =>
          inspect(
            "unexpected paragraph children",
            content="recovered text raw raw",
          )
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform replaces recovered opener in malformed link" {
  let source = "[text](\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [recovered, _, _, _] if recovered.is_recovered() => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=recovered.origin(),
            replacement_text="R",
          )
          inspect(local_rewrite, content="Rtext](\n")
        }
        _ =>
          inspect(
            "unexpected paragraph children",
            content="recovered text raw raw",
          )
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: canonical formatter renders rich and multiple links" {
  let bold_link = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "[**bold** text](url)",
  )
  match bold_link.children() {
    [paragraph] =>
      match paragraph.children() {
        [link] => {
          inspect(link.kind_tag(), content="Link")
          match link.children() {
            [bold, text] => {
              inspect(bold.kind_tag(), content="Bold")
              match text.text_value() {
                Some(value) => inspect(value, content=" text")
                None => inspect("missing", content="text value")
              }
            }
            _ => inspect("unexpected link children", content="bold text")
          }
        }
        _ => inspect("unexpected paragraph children", content="link")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      bold_link,
    ),
    content="[**bold** text](url)",
  )

  let code_link = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "[`code` here](url)",
  )
  match code_link.children() {
    [paragraph] =>
      match paragraph.children() {
        [link] => {
          inspect(link.kind_tag(), content="Link")
          match link.children() {
            [inline_code, text] => {
              inspect(inline_code.kind_tag(), content="InlineCode")
              match text.text_value() {
                Some(value) => inspect(value, content=" here")
                None => inspect("missing", content="text value")
              }
            }
            _ => inspect("unexpected link children", content="inline-code text")
          }
        }
        _ => inspect("unexpected paragraph children", content="link")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      code_link,
    ),
    content="[`code` here](url)",
  )

  let multiple_links = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "[a](u1) and [b](u2)\n",
  )
  match multiple_links.children() {
    [paragraph] =>
      match paragraph.children() {
        [first, text, second] => {
          inspect(first.kind_tag(), content="Link")
          match text.text_value() {
            Some(value) => inspect(value, content=" and ")
            None => inspect("missing", content="text value")
          }
          inspect(second.kind_tag(), content="Link")
        }
        _ => inspect("unexpected paragraph children", content="link text link")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      multiple_links,
    ),
    content="[a](u1) and [b](u2)",
  )
}

///|
test "experimental MarkdownIR: heading preserve rewrite keeps source slices" {
  let source = "### Deep\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
  match ir.children() {
    [heading] =>
      inspect(
        experimental_markdown_ir_preserve_rewrite(heading, source),
        content=origin_source(source, heading.origin()),
      )
    _ => inspect("unexpected child count", content="one heading")
  }
}

///|
test "experimental MarkdownIR: heading canonical format keeps ATX depth" {
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        "### Deep\n",
      ),
    ),
    content="### Deep",
  )
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        "# Shallow\n",
      ),
    ),
    content="# Shallow",
  )
}

///|
test "experimental MarkdownIR: heading local transform rewrites content origin" {
  let source = "### Old\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [heading] =>
      match heading.content_origin() {
        Some(origin) =>
          inspect(
            experimental_markdown_ir_local_transform_rewrite(
              ir,
              source,
              target_origin=origin,
              replacement_text="New",
            ),
            content="### New\n",
          )
        None => inspect("missing", content="heading content origin")
      }
    _ => inspect("unexpected child count", content="one heading")
  }
}

///|
test "experimental MarkdownIR: heading rewrite modes are distinguishable" {
  let source = "# Title\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  let preserve = experimental_markdown_ir_preserve_rewrite(ir, source)
  let canonical = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    ir,
  )
  match ir.children() {
    [heading] =>
      match heading.content_origin() {
        Some(origin) => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=origin,
            replacement_text="New",
          )
          inspect(preserve, content="# Title\n")
          inspect(local_rewrite, content="# New\n")
          inspect(canonical, content="# Title")
          inspect(preserve != local_rewrite, content="true")
          inspect(preserve != canonical, content="true")
          inspect(local_rewrite != canonical, content="true")
        }
        None => inspect("missing", content="heading content origin")
      }
    _ => inspect("unexpected child count", content="one heading")
  }
}

///|
test "experimental MarkdownIR: unordered list preserve rewrite keeps source slices" {
  let source = "- one\n- two\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
  match ir.children() {
    [list] => {
      inspect(
        experimental_markdown_ir_preserve_rewrite(list, source),
        content=origin_source(source, list.origin()),
      )
      match list.children() {
        [first, second] => {
          inspect(
            experimental_markdown_ir_preserve_rewrite(first, source),
            content=origin_source(source, first.origin()),
          )
          inspect(
            experimental_markdown_ir_preserve_rewrite(second, source),
            content=origin_source(source, second.origin()),
          )
        }
        _ => inspect("unexpected list children", content="two items")
      }
    }
    _ => inspect("unexpected child count", content="one list")
  }
}

///|
test "experimental MarkdownIR: unordered list canonical format keeps items" {
  let formatted = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(
      @core.SourceId("markdown-ir-test-document"),
      "- one\n- two\n",
    ),
  )
  inspect(formatted, content="- one\n- two")
  let normalized_marker_formatted = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(
      @core.SourceId("markdown-ir-test-document"),
      "* one\n* two\n",
    ),
  )
  inspect(normalized_marker_formatted, content="- one\n- two")
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        formatted,
      ),
    ),
    content=formatted,
  )

  let boundary_formatted = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(
      @core.SourceId("markdown-ir-test-document"),
      "* one\n+ two\n",
    ),
  )
  inspect(boundary_formatted, content="- one\n\n+ two")

  let rich_formatted = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    markdown_ir_from_source(
      @core.SourceId("markdown-ir-test-document"),
      "- **bold** item\n- `code`\n",
    ),
  )
  inspect(rich_formatted, content="- **bold** item\n- `code`")
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      markdown_ir_from_source(
        @core.SourceId("markdown-ir-test-document"),
        rich_formatted,
      ),
    ),
    content=rich_formatted,
  )
}

///|
test "experimental MarkdownIR: unordered list local transform and modes are distinguishable" {
  let source = "- old\n- two\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  let preserve = experimental_markdown_ir_preserve_rewrite(ir, source)
  let canonical = experimental_markdown_ir_canonical_format(
    @core.SourceId("markdown-ir-test-document"),
    ir,
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [first, _] =>
          match first.content_origin() {
            Some(origin) => {
              let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
                ir,
                source,
                target_origin=origin,
                replacement_text="new",
              )
              inspect(preserve, content="- old\n- two\n")
              inspect(local_rewrite, content="- new\n- two\n")
              inspect(canonical, content="- old\n- two")
              inspect(preserve != local_rewrite, content="true")
              inspect(preserve != canonical, content="true")
              inspect(local_rewrite != canonical, content="true")
            }
            None => inspect("missing", content="list item content origin")
          }
        _ => inspect("unexpected list children", content="two items")
      }
    _ => inspect("unexpected child count", content="one list")
  }
}

///|
test "experimental MarkdownIR: nested unordered list rewrites preserve flow children" {
  let source = "- parent\n  - child\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-ir-test-document"),
      ir,
    ),
    content="- parent\n  - child",
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [item] =>
          match item.content_origin() {
            Some(parent_origin) => {
              let parent_rewrite = experimental_markdown_ir_local_transform_rewrite(
                ir,
                source,
                target_origin=parent_origin,
                replacement_text="grown",
              )
              inspect(parent_rewrite, content="- grown\n  - child\n")
              match item.children() {
                [_, nested] =>
                  match nested.children() {
                    [nested_item] =>
                      match nested_item.content_origin() {
                        Some(child_origin) => {
                          let child_rewrite = experimental_markdown_ir_local_transform_rewrite(
                            ir,
                            source,
                            target_origin=child_origin,
                            replacement_text="kid",
                          )
                          inspect(child_rewrite, content="- parent\n  - kid\n")
                        }
                        None => inspect("missing", content="child origin")
                      }
                    _ => inspect("unexpected", content="nested item")
                  }
                _ => inspect("unexpected", content="paragraph and nested list")
              }
            }
            None => inspect("missing", content="parent origin")
          }
        _ => inspect("unexpected", content="one item")
      }
    _ => inspect("unexpected", content="one list")
  }
}

///|
test "experimental MarkdownIR: ordered list local transform preserves marker source" {
  let source = "01. old\n02. two\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [first, _] =>
          match first.content_origin() {
            Some(origin) => {
              let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
                ir,
                source,
                target_origin=origin,
                replacement_text="new",
              )
              inspect(local_rewrite, content="01. new\n02. two\n")
            }
            None => inspect("missing", content="list item content origin")
          }
        _ => inspect("unexpected list children", content="two items")
      }
    _ => inspect("unexpected child count", content="one list")
  }
}

///|
test "experimental MarkdownIR: unmatched maximal backtick run remains literal text" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "``unclosed\n",
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"text","value":"``unclosed"}]}]}
    ),
  )
}

///|
test "experimental MarkdownIR: escaped literal backtick spans token boundaries" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "\\`\n",
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"text","value":"`"}]}]}
    ),
  )
}

///|
test "experimental MarkdownIR: escaped literal backtick joins adjacent text" {
  let source = "\\`literal\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [text] => {
          match text.text_value() {
            Some(value) => inspect(value, content="`literal")
            None => inspect("missing", content="text value")
          }
          inspect(origin_source(source, text.origin()), content="\\`literal")
        }
        _ => inspect(paragraph.children().length(), content="one text child")
      }
    _ => inspect(ir.children().length(), content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: code spans normalize line endings and boundaries" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "` a\nb `\n",
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"inlineCode","value":"a b"}]}]}
    ),
  )
}

///|
test "experimental MarkdownIR: code spans normalize CRLF and carriage returns" {
  for source in ["`a\r\nb`\n", "`a\rb`\n"] {
    let ir = markdown_ir_from_source(
      @core.SourceId("markdown-ir-test-document"),
      source,
    )
    inspect(
      experimental_markdown_ir_to_mdast_json(ir).stringify(),
      content=(
        #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"inlineCode","value":"a b"}]}]}
      ),
    )
  }
}

///|
test "experimental MarkdownIR: code spans retain root indentation and content origin" {
  let source = "`a\n  b`\n"
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"inlineCode","value":"a   b"}]}]}
    ),
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [inline_code] =>
          match inline_code.content_origin() {
            Some(origin) =>
              inspect(origin_source(source, origin), content="a\n  b")
            None => inspect("missing", content="inline code content origin")
          }
        _ => inspect("unexpected paragraph children", content="inline code")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: code spans retain excess list continuation indentation" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "- `a\n    b`\n",
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"inlineCode","value":"a   b"}]}]}]}]}
    ),
  )
}

///|
test "experimental MarkdownIR: code spans crossing a block quote have no content origin" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "> `a\n> b`\n",
  )
  match ir.children() {
    [quote] =>
      match quote.children() {
        [paragraph] =>
          match paragraph.children() {
            [inline_code] =>
              inspect(inline_code.content_origin() is None, content="true")
            _ => inspect("unexpected paragraph children", content="inline code")
          }
        _ => inspect("unexpected quote children", content="paragraph")
      }
    _ => inspect("unexpected root children", content="block quote")
  }
}

///|
test "experimental MarkdownIR: code spans crossing a list continuation have no content origin" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "- `a\n  b`\n",
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [item] =>
          match item.children() {
            [paragraph] =>
              match paragraph.children() {
                [inline_code] =>
                  inspect(inline_code.content_origin() is None, content="true")
                _ =>
                  inspect(
                    "unexpected paragraph children",
                    content="inline code",
                  )
              }
            _ => inspect("unexpected list item children", content="paragraph")
          }
        _ => inspect("unexpected list children", content="list item")
      }
    _ => inspect("unexpected root children", content="list")
  }
}

///|
test "experimental MarkdownIR: link label retains escaped literal backtick" {
  let ir = markdown_ir_from_source(
    @core.SourceId("markdown-ir-test-document"),
    "[\\`literal](/)\n",
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"link","url":"/","children":[{"type":"text","value":"`literal"}]}]}]}
    ),
  )
}
