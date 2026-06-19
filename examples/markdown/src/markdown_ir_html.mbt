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
fn markdown_ir_list_item_child_to_commonmark_html(
  child : MarkdownIR,
  render_paragraphs~ : Bool,
) -> String {
  match child.node {
    Paragraph(children, _) if !render_paragraphs =>
      markdown_ir_inline_children_to_commonmark_html(children)
    _ => markdown_ir_to_commonmark_html_with_list_context(child, false)
  }
}

///|
fn markdown_ir_list_item_children_to_commonmark_html(
  children : Array[MarkdownIR],
  render_paragraphs~ : Bool,
) -> String {
  children
  .map(child => {
    markdown_ir_list_item_child_to_commonmark_html(child, render_paragraphs~)
  })
  .join("")
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
    UnorderedList(children, spread) =>
      "<ul>\n" +
      markdown_ir_nodes_to_commonmark_html(children, parent_list_spread=spread) +
      "</ul>\n"
    ListItem(children, spread, _) => {
      let render_paragraphs = parent_list_spread || spread
      let open = if render_paragraphs { "<li>\n" } else { "<li>" }
      open +
      markdown_ir_list_item_children_to_commonmark_html(
        children,
        render_paragraphs~,
      ) +
      "</li>\n"
    }
    CodeBlock(info, value, _) =>
      markdown_ir_code_block_commonmark_html(info, value)
    Text(value) | Raw(value, _) => html_escape_text(value)
    Bold(children, _) =>
      "<strong>" +
      markdown_ir_inline_children_to_commonmark_html(children) +
      "</strong>"
    Italic(children, _) =>
      "<em>" +
      markdown_ir_inline_children_to_commonmark_html(children) +
      "</em>"
    InlineCode(value, _) => "<code>" + html_escape_text(value) + "</code>"
    Link(children, destination, _) =>
      "<a href=\"" +
      html_escape_text(destination) +
      "\">" +
      markdown_ir_inline_children_to_commonmark_html(children) +
      "</a>"
    Unsupported(message) =>
      "<!-- unsupported MarkdownIR: " + html_escape_text(message) + " -->"
    Recovered(message, _) =>
      "<!-- recovered MarkdownIR: " + html_escape_text(message) + " -->"
  }
}

///|
/// Experimental CommonMark-style HTML rendering adapter for MarkdownIR.
///
/// This target adapter is intentionally separate from mdast export: mdast
/// parity checks tree shape, while CommonMark HTML parity checks rendered
/// behavior and escaping. Unsupported or recovered IR nodes render as escaped
/// comments until later CommonMark semantics add explicit handling.
pub fn experimental_markdown_ir_to_commonmark_html(ir : MarkdownIR) -> String {
  markdown_ir_to_commonmark_html_with_list_context(ir, false)
}
