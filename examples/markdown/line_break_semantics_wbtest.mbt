///|
fn line_break_semantics_ir(
  source_id : @core.SourceId,
  source : String,
) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("line-break fixture parse failed")
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
test "line breaks: MarkdownIR owns typed soft and hard surfaces with origins" {
  let source = "soft\nbreak\n\nspaces  \nbreak\n\nslash\\\nbreak\n"
  let ir = line_break_semantics_ir(
    @core.SourceId("markdown-line-break-surfaces"),
    source,
  )
  match ir.children() {
    [soft_paragraph, spaces_paragraph, slash_paragraph] => {
      match soft_paragraph.children() {
        [_, { node: SoftBreak(Some(origin)), .. }, _] =>
          inspect(source[origin.start():origin.end()].to_owned(), content="\n")
        _ => fail("expected an explicit soft break")
      }
      match spaces_paragraph.children() {
        [_, { node: HardBreak(TrailingSpaces(2), Some(origin)), .. }, _] =>
          inspect(
            source[origin.start():origin.end()].to_owned(),
            content="  \n",
          )
        _ => fail("expected a trailing-space hard break")
      }
      match slash_paragraph.children() {
        [_, { node: HardBreak(Backslash, Some(origin)), .. }, _] =>
          inspect(
            source[origin.start():origin.end()].to_owned(),
            content="\\\n",
          )
        _ => fail("expected a backslash hard break")
      }
    }
    _ => fail("expected three line-break paragraphs")
  }
}

///|
test "line breaks: HTML, mdast, and editor compatibility preserve semantics" {
  let source = "soft\nbreak\n\nspaces  \nbreak\n\nslash\\\nbreak\n"
  let ir = line_break_semantics_ir(
    @core.SourceId("markdown-line-break-adapters"),
    source,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content="<p>soft\nbreak</p>\n<p>spaces<br />\nbreak</p>\n<p>slash<br />\nbreak</p>\n",
  )
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content="{\"type\":\"root\",\"children\":[{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"soft\\nbreak\"}]},{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"spaces\"},{\"type\":\"break\"},{\"type\":\"text\",\"value\":\"break\"}]},{\"type\":\"paragraph\",\"children\":[{\"type\":\"text\",\"value\":\"slash\"},{\"type\":\"break\"},{\"type\":\"text\",\"value\":\"break\"}]}]}",
  )
  debug_inspect(
    experimental_markdown_ir_to_block(ir),
    content=(
      #|Document(
      #|  [
      #|    Paragraph([Text("soft"), Text(" "), Text("break")]),
      #|    Paragraph([Text("spaces"), Text("\n"), Text("break")]),
      #|    Paragraph([Text("slash"), Text("\n"), Text("break")]),
      #|  ],
      #|)
    ),
  )
}

///|
test "line breaks: odd backslash runs own the break marker only" {
  let source = "even\\\\\nbreak\n\nodd\\\\\\\nbreak\n"
  let ir = line_break_semantics_ir(
    @core.SourceId("markdown-line-break-backslash-runs"),
    source,
  )
  match ir.children() {
    [even_paragraph, odd_paragraph] => {
      match even_paragraph.children() {
        [
          { node: Text("even\\"), .. },
          { node: SoftBreak(_), .. },
          { node: Text("break"), .. },
        ] => ()
        _ => fail("expected an even backslash run to remain a soft break")
      }
      match odd_paragraph.children() {
        [
          { node: Text("odd\\"), .. },
          { node: HardBreak(Backslash, _), .. },
          { node: Text("break"), .. },
        ] => ()
        _ => fail("expected an odd backslash run to own one hard-break marker")
      }
    }
    _ => fail("expected even and odd backslash-run paragraphs")
  }
}

///|
test "line breaks: canonical formatting preserves both hard-break surfaces" {
  let source = "spaces     \nbreak\n\nslash\\\nbreak\n"
  let ir = line_break_semantics_ir(
    @core.SourceId("markdown-line-break-canonical-surfaces"),
    source,
  )
  inspect(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("markdown-line-break-canonical-surfaces"),
      ir,
    ),
    content="spaces     \nbreak\n\nslash\\\nbreak",
  )
}
