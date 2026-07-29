///|
fn escaped_emphasis_ir_from_source(source : String) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(source) catch {
    _ =>
      abort(
        "Markdown parse failed for escaped-emphasis source: " +
        @debug.to_string(source),
      )
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn escaped_emphasis_ir_block(source : String) -> Block {
  experimental_markdown_ir_to_block(escaped_emphasis_ir_from_source(source))
}

///|
fn escaped_emphasis_origin_source(
  source : String,
  origin : MarkdownIROrigin,
) -> String {
  source[origin.start():origin.end()].to_owned()
}

///|
test "escaped emphasis recovery: direct and MarkdownIR lowering parity matrix" {
  let sources = [
    "\\*literal*\n",
    "\\*\\*literal**\n",
    "\\" + "\\" + "*em*\n",
    "\\*😈*\n",
    "prefix [\\*😈*](/)\n",
    "\\* literal *unclosed\n",
    "\\*a \\*b***\n",
    "\\*a \\*b\nc**\n",
    "\\*a [oops tail*\n",
    "\\*a [x**](/) b*\n",
    "[\\*\\*😈**](/)\n",
  ]
  for source in sources {
    inspect(
      escaped_emphasis_ir_block(source),
      content=@debug.to_string(parse(source)),
    )
  }
}

///|
test "escaped emphasis recovery: current opener-capacity divergence stays explicit" {
  let source = "\\*a b**\n"
  inspect(
    parse(source),
    content="Document([Paragraph([Text(\"*a b\"), Error(\"**\")])])",
  )
  inspect(
    escaped_emphasis_ir_block(source),
    content="Document([Paragraph([Text(\"*a b**\")])])",
  )
}

///|
test "escaped emphasis recovery: current list-item text coalescing difference stays explicit" {
  let source = "- \\*a \\*b**\n"
  inspect(
    parse(source),
    content="Document([UnorderedList([UnorderedListItem([Text(\"*a *b\"), Text(\"**\")])])])",
  )
  inspect(
    escaped_emphasis_ir_block(source),
    content="Document([UnorderedList([UnorderedListItem([Text(\"*a *b**\")])])])",
  )
}

///|
test "delimiter model: nested emphasis origins retain delimiters and content" {
  let source = "**outer *inner* tail**\n"
  let ir = escaped_emphasis_ir_from_source(source)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [bold] => {
          inspect(
            escaped_emphasis_origin_source(source, bold.origin()),
            content="**outer *inner* tail**",
          )
          match bold.content_origin() {
            Some(origin) =>
              inspect(
                escaped_emphasis_origin_source(source, origin),
                content="outer *inner* tail",
              )
            None => inspect("missing", content="bold content origin")
          }
          match bold.children() {
            [_, italic, _] => {
              inspect(
                escaped_emphasis_origin_source(source, italic.origin()),
                content="*inner*",
              )
              match italic.content_origin() {
                Some(origin) =>
                  inspect(
                    escaped_emphasis_origin_source(source, origin),
                    content="inner",
                  )
                None => inspect("missing", content="italic content origin")
              }
            }
            _ => inspect("unexpected", content="nested italic children")
          }
        }
        _ => inspect("unexpected", content="one bold child")
      }
    _ => inspect("unexpected", content="one paragraph")
  }
}
