///|
fn markdown_ir_from_source(source : String) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  experimental_markdown_ir_from_cst_with_diagnostics(cst, diagnostics)
}

///|
fn experimental_markdown_ir_from_cst_with_diagnostics(
  cst : @seam.CstNode,
  diagnostics : @core.DiagnosticSet,
) -> MarkdownIR {
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
fn malformed_link_raw_diagnostics() -> @core.DiagnosticSet {
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
  diagnostics
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
test "experimental MarkdownIR: list items expose flow-content paragraphs" {
  let ir = markdown_ir_from_source("- one\n- two\n")
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
test "experimental MarkdownIR: loose list separator sets list spread" {
  let source = "- one\n\n- two\n"
  let ir = markdown_ir_from_source(source)
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
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
    cst,
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
test "experimental MarkdownIR: zero-width incoming diagnostics attach only with positive overlap" {
  let source = "Hello **unclosed\n"
  let (cst, _) = parse_cst(source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostics = @core.DiagnosticSet::empty()
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      "zero-width at recovered start", 6, 6, "synthetic-zero",
    ),
  )
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      "zero-width inside recovered", 7, 7, "synthetic-zero",
    ),
  )
  diagnostics.push(
    @core.Diagnostic::lexer_error_at(
      "zero-width at recovered end", 8, 8, "synthetic-zero",
    ),
  )
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(cst, diagnostics)
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) => {
          let recovered = paragraph.children()[index]
          inspect(origin_source(source, recovered.origin()), content="**")
          inspect(
            recovered
            .diagnostics()
            .iter()
            .map(diagnostic => diagnostic.format())
            .collect()
            .join("|"),
            content="zero-width inside recovered [7,7]",
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
  let (cst, _) = parse_cst(source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
    cst,
    malformed_link_raw_diagnostics(),
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
test "experimental MarkdownIR: mdastRaw export carries injected diagnostics" {
  let source = "[text](\n"
  let (cst, _) = parse_cst(source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
    cst,
    malformed_link_raw_diagnostics(),
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
  let (cst, _) = parse_cst(source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostic = @core.Diagnostic::lexer_error_at(
    "synthetic recovered diagnostic", 0, 1, "synthetic-recovery",
  )
  let ir = experimental_markdown_ir_from_cst_with_diagnostics(
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
  let (cst, _) = parse_cst(source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let diagnostic = @core.Diagnostic::lexer_error_at(
    "direct syntax recovered diagnostic", 0, 1, "synthetic-recovery",
  )
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
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
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
  inspect(
    experimental_markdown_ir_to_mdast_json_with_positions(ir, source).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"code","value":"x","position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":3,"column":4,"offset":9}}},{"type":"paragraph","children":[{"type":"text","value":"next","position":{"start":{"line":5,"column":1,"offset":11},"end":{"line":5,"column":5,"offset":15}}}],"position":{"start":{"line":5,"column":1,"offset":11},"end":{"line":5,"column":5,"offset":15}}}],"position":{"start":{"line":1,"column":1,"offset":0},"end":{"line":5,"column":5,"offset":15}}}
    ),
  )
}

///|
test "experimental MarkdownIR: mdast position export handles CRLF code fences" {
  let source = "```\r\nx\r\n```\r\n\r\nnext"
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
test "experimental MarkdownIR: preserve rewrite round-trips code block" {
  let source = "```moonbit\nlet x = 1\n```\n"
  let ir = markdown_ir_from_source(source)
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
}

///|
fn local_code_block_content_rewrite(
  source : String,
  replacement_text : String,
) -> String raise {
  let ir = markdown_ir_from_source(source)
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
    parse(result),
    content="Document([CodeBlock(\"\", \"line\\n```\\nline\")])",
  )
}

///|
test "experimental MarkdownIR: local transform preserves unclosed code fence" {
  let result = assert_local_code_block_content_rewrite(
    "```\nold\n", "new", "```\nnew\n",
  )
  inspect(parse(result), content="Document([CodeBlock(\"\", \"new\")])")
}

///|
test "experimental MarkdownIR: local transform widens unclosed code fence" {
  let result = assert_local_code_block_content_rewrite(
    "```\nold\n", "line\n```\nline", "````\nline\n```\nline\n",
  )
  inspect(
    parse(result),
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
  let ir = markdown_ir_from_source(source)
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
          inspect(parse(result), content="Document([CodeBlock(\"\", \"new\")])")
        }
        None => inspect("missing", content="code block content origin")
      }
    _ => inspect("unexpected child count", content="one code block")
  }
}

///|
test "experimental MarkdownIR: local transform rewrites empty unclosed code fence" {
  let source = "```\n"
  let ir = markdown_ir_from_source(source)
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
          inspect(parse(result), content="Document([CodeBlock(\"\", \"new\")])")
        }
        None => inspect("missing", content="code block content origin")
      }
    _ => inspect("unexpected child count", content="one code block")
  }
}

///|
test "experimental MarkdownIR: local transform rewrites empty EOF code fence" {
  let source = "```"
  let ir = markdown_ir_from_source(source)
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
          inspect(parse(result), content="Document([CodeBlock(\"\", \"new\")])")
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
  inspect(parse(result), content="Document([CodeBlock(\"\", \"new\\n\")])")
}

///|
test "experimental MarkdownIR: unclosed EOF code fence preserves replacement trailing newline" {
  let result = assert_local_code_block_content_rewrite(
    "```\nold", "new\n", "```\nnew\n\n",
  )
  inspect(parse(result), content="Document([CodeBlock(\"\", \"new\\n\")])")
}

///|
test "experimental MarkdownIR: local transform rewrites code block full origin" {
  let source = "```\nold code\n```\n"
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
test "experimental MarkdownIR: local transform rewrites container content origins" {
  let source = "# Old\n\nHello **world**\n"
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
test "experimental MarkdownIR: local transform preserves CRLF block ending" {
  let source = "# Old\r\nParagraph\r\n"
  let ir = markdown_ir_from_source(source)
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
test "experimental MarkdownIR: canonical format preserves code block info string" {
  let formatted = experimental_markdown_ir_canonical_format(
    markdown_ir_from_source("```moonbit\nlet x = 1\n```\n"),
  )
  inspect(formatted, content="```moonbit\nlet x = 1\n```")
  inspect(
    parse(formatted),
    content="Document([CodeBlock(\"moonbit\", \"let x = 1\")])",
  )
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

///|
test "experimental MarkdownIR: Inline adapter renders raw children as text" {
  let source = "[text](url\n"
  let ir = markdown_ir_from_source(source)
  let block = experimental_markdown_ir_to_block(ir)
  inspect(block, content=@debug.to_string(parse(source)))
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
test "experimental MarkdownIR: canonical formatter emits recovered comments" {
  let source = "Hello *\n"
  let formatted = experimental_markdown_ir_canonical_format(
    markdown_ir_from_source(source),
  )
  inspect(formatted, content="Hello <!-- recovered MarkdownIR: * -->")
}

///|
test "experimental MarkdownIR: canonical formatter passes raw text through" {
  let source = "[text](url\n"
  let formatted = experimental_markdown_ir_canonical_format(
    markdown_ir_from_source(source),
  )
  inspect(formatted, content="<!-- recovered MarkdownIR: [ -->text](url")
}

///|
test "experimental MarkdownIR: preserve rewrite keeps recovered source slice" {
  let source = "Hello *\n"
  let ir = markdown_ir_from_source(source)
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [_, recovered] if recovered.is_recovered() =>
          inspect(origin_source(source, recovered.origin()), content="*")
        _ => inspect("unexpected", content="text plus recovered")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: local transform replaces recovered text" {
  let source = "Hello *\n"
  let ir = markdown_ir_from_source(source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [_, recovered] if recovered.is_recovered() => {
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=recovered.origin(),
            replacement_text="world",
          )
          inspect(local_rewrite, content="Hello world\n")
        }
        _ => inspect("unexpected", content="text plus recovered")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}

///|
test "experimental MarkdownIR: preserve rewrite round-trips valid link" {
  let source = "[text](url)\n"
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
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
  let bold_link = markdown_ir_from_source("[**bold** text](url)")
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
    experimental_markdown_ir_canonical_format(bold_link),
    content="[**bold** text](url)",
  )

  let code_link = markdown_ir_from_source("[`code` here](url)")
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
    experimental_markdown_ir_canonical_format(code_link),
    content="[`code` here](url)",
  )

  let multiple_links = markdown_ir_from_source("[a](u1) and [b](u2)\n")
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
    experimental_markdown_ir_canonical_format(multiple_links),
    content="[a](u1) and [b](u2)",
  )
}

///|
test "experimental MarkdownIR: heading preserve rewrite keeps source slices" {
  let source = "### Deep\n"
  let ir = markdown_ir_from_source(source)
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
      markdown_ir_from_source("### Deep\n"),
    ),
    content="### Deep",
  )
  inspect(
    experimental_markdown_ir_canonical_format(
      markdown_ir_from_source("# Shallow\n"),
    ),
    content="# Shallow",
  )
}

///|
test "experimental MarkdownIR: heading local transform rewrites content origin" {
  let source = "### Old\n"
  let ir = markdown_ir_from_source(source)
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
  let ir = markdown_ir_from_source(source)
  let preserve = experimental_markdown_ir_preserve_rewrite(ir, source)
  let canonical = experimental_markdown_ir_canonical_format(ir)
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
  let ir = markdown_ir_from_source(source)
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
    markdown_ir_from_source("- one\n- two\n"),
  )
  inspect(formatted, content="- one\n- two")
  inspect(
    experimental_markdown_ir_canonical_format(
      markdown_ir_from_source(formatted),
    ),
    content=formatted,
  )

  let rich_formatted = experimental_markdown_ir_canonical_format(
    markdown_ir_from_source("- **bold** item\n- `code`\n"),
  )
  inspect(rich_formatted, content="- **bold** item\n- `code`")
  inspect(
    experimental_markdown_ir_canonical_format(
      markdown_ir_from_source(rich_formatted),
    ),
    content=rich_formatted,
  )
}

///|
test "experimental MarkdownIR: unordered list local transform and modes are distinguishable" {
  let source = "- old\n- two\n"
  let ir = markdown_ir_from_source(source)
  let preserve = experimental_markdown_ir_preserve_rewrite(ir, source)
  let canonical = experimental_markdown_ir_canonical_format(ir)
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
