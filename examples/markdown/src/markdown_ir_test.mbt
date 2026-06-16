///|
fn markdown_ir_from_source(source : String) -> MarkdownIR {
  let (cst, _) = parse_cst(source) catch { _ => abort("Markdown parse failed") }
  experimental_markdown_ir_from_syntax(@seam.SyntaxNode::from_cst(cst))
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
  let source =
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
  let ir = markdown_ir_from_source(source)
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=(
      #|{"type":"root","children":[{"type":"heading","depth":1,"children":[{"type":"text","value":"Title"}]},{"type":"paragraph","children":[{"type":"text","value":"Hello "},{"type":"strong","children":[{"type":"text","value":"world"}]},{"type":"text","value":" and "},{"type":"emphasis","children":[{"type":"text","value":"moon"}]},{"type":"text","value":" with "},{"type":"inlineCode","value":"code"},{"type":"text","value":" plus "},{"type":"link","url":"u(1)","children":[{"type":"text","value":"link"}]}]},{"type":"list","ordered":false,"children":[{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"one"}]}]},{"type":"listItem","children":[{"type":"paragraph","children":[{"type":"text","value":"two"}]}]}]},{"type":"code","lang":"moonbit","value":"let x = 1"}]}
    ),
  )
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
test "experimental MarkdownIR: recovered inline delimiters adapt to text" {
  let source = "Hello *\n"
  let block = experimental_markdown_ir_to_block(markdown_ir_from_source(source))
  inspect(
    block,
    content="Document([Paragraph([Text(\"Hello \"), Text(\"*\")])])",
  )
  inspect(block == parse(source), content="true")
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
