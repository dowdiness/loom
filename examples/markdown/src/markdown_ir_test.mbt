///|
fn markdown_ir_from_source(source : String) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
/// Compare the two Block adapter paths for lex-valid current-subset fixtures.
fn assert_markdown_ir_block_matches_direct_parse(source : String) -> Unit raise {
  let direct = parse(source)
  let via_ir = experimental_markdown_ir_to_block(
    markdown_ir_from_source(source),
  )
  inspect(via_ir, content=@debug.to_string(direct))
}

///|
fn assert_recovered_markdown_ir_block_matches_direct_parse(
  source : String,
  recovered_text : String,
) -> Unit raise {
  let ir = markdown_ir_from_source(source)
  inspect(
    experimental_markdown_ir_to_block(ir),
    content=@debug.to_string(parse(source)),
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
  let ir = markdown_ir_from_source(source)
  inspect(
    experimental_markdown_ir_to_block(ir),
    content=@debug.to_string(parse(source)),
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
test "experimental MarkdownIR: heading lowers with origin and Block adapter" {
  let source = "# Title\n"
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
test "experimental MarkdownIR: mdast JSON snapshots for current parser subset" {
  let source = current_parser_subset_source()
  let ir = markdown_ir_from_source(source)
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"heading","depth":1,"children":[{"type":"text","value":"Title"}]},{"type":"paragraph","children":[{"type":"text","value":"Hello "},{"type":"strong","children":[{"type":"text","value":"world"}]},{"type":"text","value":" and "},{"type":"emphasis","children":[{"type":"text","value":"moon"}]},{"type":"text","value":" with "},{"type":"inlineCode","value":"code"},{"type":"text","value":" plus "},{"type":"link","url":"u(1)","children":[{"type":"text","value":"link"}]}]},{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"one"}]}]},{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"two"}]}]}]},{"type":"code","lang":"moonbit","value":"let x = 1"}]}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast JSON includes recovery metadata" {
  let ir = markdown_ir_from_source("[text](\n")
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
test "experimental MarkdownIR: Block adapter matches direct parse for fenced code blocks" {
  assert_markdown_ir_block_matches_direct_parse("```moonbit\nlet x = 1\n```\n")
  assert_markdown_ir_block_matches_direct_parse("````\n```\n````\n")
}

///|
test "experimental MarkdownIR: Block adapter matches direct parse for inline formatting" {
  assert_markdown_ir_block_matches_direct_parse(
    "Hello **world** and *moon* with `code` plus [link](u(1))\n",
  )
}

///|
test "experimental MarkdownIR: recovered inline ErrorNodes stay explicit" {
  assert_recovered_markdown_ir_block_matches_direct_parse("Hello *\n", "*")
  assert_recovered_markdown_ir_block_matches_direct_parse(
    "Hello **unclosed\n", "**",
  )
  assert_recovered_markdown_ir_block_matches_direct_parse("`unclosed\n", "`")
  assert_recovered_markdown_ir_block_matches_direct_parse("[unclosed\n", "[")
  assert_recovered_markdown_ir_block_matches_direct_parse("[text\n", "[")
  assert_recovered_markdown_ir_block_matches_direct_parse("**a *b** c*\n", "*")
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
  let source = "Hello *\n"
  let ir = markdown_ir_from_source(source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) => {
          let recovered = paragraph.children()[index]
          inspect(recovered.diagnostics().length(), content="1")
          inspect(
            recovered.diagnostics()[0].format(),
            content="recovered malformed Markdown: * [6,7]",
          )
        }
        None => inspect("missing", content="recovered child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: incoming diagnostics are attached to recovered nodes" {
  let source = "Hello *\n"
  let (cst, _) = parse_cst(source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostic = @core.Diagnostic::lexer_error_at(
    "synthetic recovery diagnostic", 6, 7, "synthetic-recovery",
  )
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    @seam.SyntaxNode::from_cst(cst),
    @core.DiagnosticSet::single(diagnostic),
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) =>
          inspect(
            paragraph.children()[index].diagnostics()[0].format(),
            content="synthetic recovery diagnostic [6,7]",
          )
        None => inspect("missing", content="recovered child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: incoming diagnostics are attached to raw nodes" {
  let source = "[text](\n"
  let (cst, _) = parse_cst(source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostics = @core.DiagnosticSet::empty()
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      "synthetic raw bracket diagnostic", 5, 6, "synthetic-raw",
    ),
  )
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      "synthetic raw paren diagnostic", 6, 7, "synthetic-raw",
    ),
  )
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
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
  let ir = markdown_ir_from_source(source)
  let via_ir = experimental_markdown_ir_to_block(ir)
  inspect(via_ir, content=@debug.to_string(parse(source)))
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
test "experimental MarkdownIR: adjacent malformed links preserve raw delimiters" {
  assert_malformed_link_raws_preserved("[text](url\n", "](")
  assert_malformed_link_raws_preserved("[text](\nnext\n", "](")
  assert_malformed_link_raws_preserved("[*x](url\n", "](")
}

///|
test "experimental MarkdownIR: unclosed code fence remains a code block" {
  let source = "```\ncode without close\n"
  let ir = markdown_ir_from_source(source)
  inspect(
    experimental_markdown_ir_to_block(ir),
    content=@debug.to_string(parse(source)),
  )
  match ir.children() {
    [code_block] => {
      inspect(code_block.kind_tag(), content="CodeBlock")
      inspect(origin_source(source, code_block.origin()), content=source)
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
  let ir = markdown_ir_from_source(source)
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
test "experimental MarkdownIR: recovered inline delimiters adapt to explicit error" {
  let source = "Hello *\n"
  let ir = markdown_ir_from_source(source)
  let block = experimental_markdown_ir_to_block(ir)
  inspect(
    block,
    content="Document([Paragraph([Text(\"Hello \"), Error(\"*\")])])",
  )
  inspect(block, content=@debug.to_string(parse(source)))
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [_, recovered] => {
          inspect(recovered.kind_tag(), content="Recovered")
          inspect(origin_source(source, recovered.origin()), content="*")
        }
        _ => inspect("unexpected", content="text plus recovered")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform splices changed text" {
  let source = "# Title\nParagraph text\n"
  let ir = markdown_ir_from_source(source)
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
test "experimental MarkdownIR: local transform renders paragraph soft breaks" {
  let source = "line one\nline two\n"
  let ir = markdown_ir_from_source(source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [first, _, _] => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=first.origin(),
            replacement_text="first line",
          )
          inspect(local_rewrite, content="first line line two\n")
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
  let ir = markdown_ir_from_source(source)
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
test "experimental MarkdownIR: local transform rewrites inline code content origin" {
  let source = "`code`\n"
  let ir = markdown_ir_from_source(source)
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
                replacement_text="new",
              )
              inspect(local_rewrite, content="`new`\n")
            }
            None => inspect("missing", content="inline code content origin")
          }
        _ => inspect("unexpected paragraph children", content="inline code")
      }
    _ => inspect("unexpected child count", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform preserves inline container siblings" {
  let source = "Hello **world** tail\n"
  let ir = markdown_ir_from_source(source)
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
test "experimental MarkdownIR: canonical formatter renders inline containers" {
  let ir = markdown_ir_from_source("Hello **world** and [link](u(1))\n")
  inspect(
    experimental_markdown_ir_canonical_format(ir),
    content="Hello **world** and [link](u(1))",
  )
}

///|
test "experimental MarkdownIR: canonical code fence exceeds content backtick run" {
  let formatted = experimental_markdown_ir_canonical_format(
    markdown_ir_from_source("````\n```\n````\n"),
  )
  inspect(formatted, content="````\n```\n````")
  inspect(parse(formatted), content="Document([CodeBlock(\"\", \"```\")])")
}

///|
test "experimental MarkdownIR: rewrite modes are distinguishable" {
  let source = "# Title\nParagraph text\n"
  let ir = markdown_ir_from_source(source)
  let preserve = experimental_markdown_ir_preserve_rewrite(ir, source)
  let canonical = experimental_markdown_ir_canonical_format(ir)
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
