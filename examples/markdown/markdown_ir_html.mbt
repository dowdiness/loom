///|
fn html_escape_text(value : String) -> String {
  let buf = StringBuilder()
  for ch in value {
    match ch {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '\"' => buf.write_string("&quot;")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn markdown_ir_nodes_to_commonmark_html(
  children : Array[MarkdownIR],
  parent_list_spread~ : Bool,
) -> String {
  children
  .map(child => {
    markdown_ir_to_commonmark_html_with_list_context(child, parent_list_spread)
  })
  .join("")
}

///|
fn markdown_ir_children_to_commonmark_html(
  children : Array[MarkdownIR],
) -> String {
  markdown_ir_nodes_to_commonmark_html(children, parent_list_spread=false)
}

///|
fn markdown_ir_inline_children_to_commonmark_html(
  children : Array[MarkdownIR],
) -> String {
  markdown_ir_nodes_to_commonmark_html(children, parent_list_spread=false)
}

///|
fn markdown_ir_list_item_has_block_content(ir : MarkdownIR) -> Bool {
  match ir.node {
    Paragraph(children, _) => children.length() > 0
    _ => true
  }
}

///|
fn markdown_ir_list_item_child_to_commonmark_html(
  child : MarkdownIR,
  render_paragraphs~ : Bool,
) -> String {
  match child.node {
    Paragraph(children, _) if !render_paragraphs || children.length() == 0 =>
      markdown_ir_inline_children_to_commonmark_html(children)
    _ => markdown_ir_to_commonmark_html_with_list_context(child, false)
  }
}

///|
fn markdown_ir_child_is_paragraph(ir : MarkdownIR) -> Bool {
  match ir.node {
    Paragraph(_, _) => true
    _ => false
  }
}

///|
fn markdown_ir_list_item_children_to_commonmark_html(
  children : Array[MarkdownIR],
  render_paragraphs~ : Bool,
) -> String {
  let buf = StringBuilder::new()
  let mut previous_unwrapped_paragraph = false
  for child in children {
    let current_is_paragraph = markdown_ir_child_is_paragraph(child)
    if !render_paragraphs &&
      previous_unwrapped_paragraph &&
      !current_is_paragraph {
      buf.write_string("\n")
    }
    buf.write_string(
      markdown_ir_list_item_child_to_commonmark_html(child, render_paragraphs~),
    )
    previous_unwrapped_paragraph = !render_paragraphs && current_is_paragraph
  }
  buf.to_string()
}

///|
fn markdown_ir_code_block_commonmark_html(
  info : String,
  value : String,
) -> String {
  let class_attr = if info.length() > 0 {
    " class=\"language-" + html_escape_text(info) + "\""
  } else {
    ""
  }
  let body = if value.length() > 0 {
    html_escape_text(value) + "\n"
  } else {
    ""
  }
  "<pre><code" + class_attr + ">" + body + "</code></pre>\n"
}

///|
fn markdown_ir_to_commonmark_html_with_list_context(
  ir : MarkdownIR,
  parent_list_spread : Bool,
) -> String {
  match ir.node {
    Document(children) => markdown_ir_children_to_commonmark_html(children)
    Heading(depth, children, _) => {
      let tag = "h" + depth.to_string()
      "<" +
      tag +
      ">" +
      markdown_ir_inline_children_to_commonmark_html(children) +
      "</" +
      tag +
      ">\n"
    }
    Paragraph(children, _) =>
      "<p>" +
      markdown_ir_inline_children_to_commonmark_html(children) +
      "</p>\n"
    BlockQuote(children) =>
      "<blockquote>\n" +
      markdown_ir_children_to_commonmark_html(children) +
      "</blockquote>\n"
    UnorderedList(children, spread, _) =>
      "<ul>\n" +
      markdown_ir_nodes_to_commonmark_html(children, parent_list_spread=spread) +
      "</ul>\n"
    OrderedList(children, spread, marker) => {
      let start_attr = match marker {
        Some(marker) if marker.start != 1 =>
          " start=\"" + marker.start.to_string() + "\""
        _ => ""
      }
      "<ol" +
      start_attr +
      ">\n" +
      markdown_ir_nodes_to_commonmark_html(children, parent_list_spread=spread) +
      "</ol>\n"
    }
    ListItem(children, spread, _, _)
    | OrderedListItem(children, spread, _, _) => {
      let render_paragraphs = parent_list_spread || spread
      let has_block_content = children
        .iter()
        .any(markdown_ir_list_item_has_block_content)
      let open = if render_paragraphs && has_block_content {
        "<li>\n"
      } else {
        "<li>"
      }
      open +
      markdown_ir_list_item_children_to_commonmark_html(
        children,
        render_paragraphs~,
      ) +
      "</li>\n"
    }
    CodeBlock(info, value, _) =>
      markdown_ir_code_block_commonmark_html(info, value)
    HtmlBlock(value, _) => value
    ThematicBreak => "<hr />\n"
    Text(value) | Raw(value, _) => html_escape_text(value)
    HardBreak(_) => "<br />\n"
    Bold(children, _) =>
      "<strong>" +
      markdown_ir_inline_children_to_commonmark_html(children) +
      "</strong>"
    Italic(children, _) =>
      "<em>" +
      markdown_ir_inline_children_to_commonmark_html(children) +
      "</em>"
    InlineCode(value, _) => "<code>" + html_escape_text(value) + "</code>"
    Link(children, destination, _, _) =>
      "<a href=\"" +
      html_escape_text(destination) +
      "\">" +
      markdown_ir_inline_children_to_commonmark_html(children) +
      "</a>"
    Unsupported(message) =>
      "<!-- unsupported MarkdownIR: " + html_escape_text(message) + " -->"
    Recovered(message, _) if message == RECOVERED_PARSE_ERROR =>
      "<!-- recovered MarkdownIR: " + html_escape_text(message) + " -->"
    Recovered(message, _) => html_escape_text(message)
  }
}

///|
/// Experimental CommonMark-style HTML rendering adapter for MarkdownIR.
///
/// This target adapter is intentionally separate from mdast export: mdast
/// parity checks tree shape, while CommonMark HTML parity checks rendered
/// behavior and escaping. Unsupported IR and parse-error recovery placeholders
/// render as escaped comments; recovered nodes that carry literal source text
/// render as plain escaped text.
pub fn experimental_markdown_ir_to_commonmark_html(ir : MarkdownIR) -> String {
  markdown_ir_to_commonmark_html_with_list_context(ir, false)
}
