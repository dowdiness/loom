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
fn markdown_ir_html_href_hex_digit(value : Int) -> Char {
  if value < 10 {
    (value + 48).unsafe_to_char()
  } else {
    (value - 10 + 65).unsafe_to_char()
  }
}

///|
fn markdown_ir_html_write_percent_encoded_byte(
  buf : StringBuilder,
  value : Int,
) -> Unit {
  buf.write_char('%')
  buf.write_char(markdown_ir_html_href_hex_digit(value >> 4))
  buf.write_char(markdown_ir_html_href_hex_digit(value & 0x0F))
}

///|
fn markdown_ir_html_escape_href(value : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for ch in value {
    let codepoint = ch.to_int()
    match ch {
      '&' => buf.write_string("&amp;")
      '\'' => buf.write_string("&#x27;")
      'A'..='Z'
      | 'a'..='z'
      | '0'..='9'
      | '-'
      | '.'
      | '_'
      | '~'
      | ':'
      | '/'
      | '?'
      | '#'
      | '@'
      | '!'
      | '$'
      | '*'
      | '+'
      | ','
      | ';'
      | '='
      | '('
      | ')'
      | '%' => buf.write_char(ch)
      _ if codepoint <= 0x7F =>
        markdown_ir_html_write_percent_encoded_byte(buf, codepoint)
      _ if codepoint <= 0x7FF => {
        markdown_ir_html_write_percent_encoded_byte(
          buf,
          0xC0 | (codepoint >> 6),
        )
        markdown_ir_html_write_percent_encoded_byte(
          buf,
          0x80 | (codepoint & 0x3F),
        )
      }
      _ if codepoint <= 0xFFFF => {
        markdown_ir_html_write_percent_encoded_byte(
          buf,
          0xE0 | (codepoint >> 12),
        )
        markdown_ir_html_write_percent_encoded_byte(
          buf,
          0x80 | ((codepoint >> 6) & 0x3F),
        )
        markdown_ir_html_write_percent_encoded_byte(
          buf,
          0x80 | (codepoint & 0x3F),
        )
      }
      _ => {
        markdown_ir_html_write_percent_encoded_byte(
          buf,
          0xF0 | (codepoint >> 18),
        )
        markdown_ir_html_write_percent_encoded_byte(
          buf,
          0x80 | ((codepoint >> 12) & 0x3F),
        )
        markdown_ir_html_write_percent_encoded_byte(
          buf,
          0x80 | ((codepoint >> 6) & 0x3F),
        )
        markdown_ir_html_write_percent_encoded_byte(
          buf,
          0x80 | (codepoint & 0x3F),
        )
      }
    }
  }
  buf.to_string()
}

///|
pub(all) enum RawHtmlPolicy {
  Escape
  Omit
  Reject
  Passthrough
} derive(Eq, Debug)

///|
pub(all) enum RawHtmlSurface {
  RawHtmlBlock
  RawHtmlInline
} derive(Eq, Debug)

///|
pub(all) enum MarkdownIRHtmlRenderError {
  RawHtmlRejected(RawHtmlSurface, MarkdownIROrigin)
} derive(Eq, Debug)

///|
fn render_valid_raw_html(
  value : String,
  origin : MarkdownIROrigin,
  surface : RawHtmlSurface,
  policy : RawHtmlPolicy,
) -> Result[String, MarkdownIRHtmlRenderError] {
  match policy {
    Escape => Ok(html_escape_text(value))
    Omit => Ok("")
    Reject => Err(RawHtmlRejected(surface, origin))
    Passthrough => Ok(value)
  }
}

///|
fn markdown_ir_nodes_to_commonmark_html(
  children : Array[MarkdownIR],
  parent_list_spread~ : Bool,
  raw_html_policy~ : RawHtmlPolicy,
) -> Result[String, MarkdownIRHtmlRenderError] {
  let buf = StringBuilder::new()
  for child in children {
    match
      markdown_ir_to_commonmark_html_with_list_context(
        child,
        parent_list_spread,
        raw_html_policy~,
      ) {
      Ok(html) => buf.write_string(html)
      Err(error) => return Err(error)
    }
  }
  Ok(buf.to_string())
}

///|
fn markdown_ir_children_to_commonmark_html(
  children : Array[MarkdownIR],
  raw_html_policy~ : RawHtmlPolicy,
) -> Result[String, MarkdownIRHtmlRenderError] {
  markdown_ir_nodes_to_commonmark_html(
    children,
    parent_list_spread=false,
    raw_html_policy~,
  )
}

///|
fn markdown_ir_inline_children_to_commonmark_html(
  children : Array[MarkdownIR],
  raw_html_policy~ : RawHtmlPolicy,
) -> Result[String, MarkdownIRHtmlRenderError] {
  markdown_ir_nodes_to_commonmark_html(
    children,
    parent_list_spread=false,
    raw_html_policy~,
  )
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
  raw_html_policy~ : RawHtmlPolicy,
) -> Result[String, MarkdownIRHtmlRenderError] {
  match child.node {
    Paragraph(children, _) if !render_paragraphs || children.length() == 0 =>
      markdown_ir_inline_children_to_commonmark_html(children, raw_html_policy~)
    _ =>
      markdown_ir_to_commonmark_html_with_list_context(
        child,
        false,
        raw_html_policy~,
      )
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
  raw_html_policy~ : RawHtmlPolicy,
) -> Result[String, MarkdownIRHtmlRenderError] {
  let buf = StringBuilder::new()
  let mut previous_unwrapped_paragraph = false
  for child in children {
    let current_is_paragraph = markdown_ir_child_is_paragraph(child)
    if !render_paragraphs &&
      previous_unwrapped_paragraph &&
      !current_is_paragraph {
      buf.write_string("\n")
    }
    match
      markdown_ir_list_item_child_to_commonmark_html(
        child,
        render_paragraphs~,
        raw_html_policy~,
      ) {
      Ok(html) => buf.write_string(html)
      Err(error) => return Err(error)
    }
    previous_unwrapped_paragraph = !render_paragraphs && current_is_paragraph
  }
  Ok(buf.to_string())
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
fn wrap_commonmark_html(
  rendered : Result[String, MarkdownIRHtmlRenderError],
  open : String,
  close : String,
) -> Result[String, MarkdownIRHtmlRenderError] {
  match rendered {
    Ok(html) => Ok(open + html + close)
    Err(error) => Err(error)
  }
}

///|
fn markdown_ir_to_commonmark_html_with_list_context(
  ir : MarkdownIR,
  parent_list_spread : Bool,
  raw_html_policy~ : RawHtmlPolicy,
) -> Result[String, MarkdownIRHtmlRenderError] {
  match ir.node {
    Document(children) =>
      markdown_ir_children_to_commonmark_html(children, raw_html_policy~)
    Heading(depth, children, _) => {
      let tag = "h" + depth.to_string()
      wrap_commonmark_html(
        markdown_ir_inline_children_to_commonmark_html(
          children,
          raw_html_policy~,
        ),
        "<" + tag + ">",
        "</" + tag + ">\n",
      )
    }
    Paragraph(children, _) =>
      wrap_commonmark_html(
        markdown_ir_inline_children_to_commonmark_html(
          children,
          raw_html_policy~,
        ),
        "<p>",
        "</p>\n",
      )
    BlockQuote(children) =>
      wrap_commonmark_html(
        markdown_ir_children_to_commonmark_html(children, raw_html_policy~),
        "<blockquote>\n",
        "</blockquote>\n",
      )
    UnorderedList(children, spread, _) =>
      wrap_commonmark_html(
        markdown_ir_nodes_to_commonmark_html(
          children,
          parent_list_spread=spread,
          raw_html_policy~,
        ),
        "<ul>\n",
        "</ul>\n",
      )
    OrderedList(children, spread, marker) => {
      let start_attr = match marker {
        Some(marker) if marker.start != 1 =>
          " start=\"" + marker.start.to_string() + "\""
        _ => ""
      }
      wrap_commonmark_html(
        markdown_ir_nodes_to_commonmark_html(
          children,
          parent_list_spread=spread,
          raw_html_policy~,
        ),
        "<ol" + start_attr + ">\n",
        "</ol>\n",
      )
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
      wrap_commonmark_html(
        markdown_ir_list_item_children_to_commonmark_html(
          children,
          render_paragraphs~,
          raw_html_policy~,
        ),
        open,
        "</li>\n",
      )
    }
    CodeBlock(info, value, _) =>
      Ok(markdown_ir_code_block_commonmark_html(info, value))
    HtmlBlock(value, _) =>
      render_valid_raw_html(value, ir.origin, RawHtmlBlock, raw_html_policy)
    ThematicBreak => Ok("<hr />\n")
    Text(value) | Raw(value, _) => Ok(html_escape_text(value))
    SoftBreak(_) => Ok("\n")
    HardBreak(_, _) => Ok("<br />\n")
    Bold(children, _) =>
      wrap_commonmark_html(
        markdown_ir_inline_children_to_commonmark_html(
          children,
          raw_html_policy~,
        ),
        "<strong>",
        "</strong>",
      )
    Italic(children, _) =>
      wrap_commonmark_html(
        markdown_ir_inline_children_to_commonmark_html(
          children,
          raw_html_policy~,
        ),
        "<em>",
        "</em>",
      )
    InlineCode(value, _) => Ok("<code>" + html_escape_text(value) + "</code>")
    Link(children, destination, title, _) => {
      let title_attribute = match title {
        Some(title) => " title=\"" + html_escape_text(title) + "\""
        None => ""
      }
      wrap_commonmark_html(
        markdown_ir_inline_children_to_commonmark_html(
          children,
          raw_html_policy~,
        ),
        "<a href=\"" +
        markdown_ir_html_escape_href(destination) +
        "\"" +
        title_attribute +
        ">",
        "</a>",
      )
    }
    Image(children, destination, title, _) => {
      let title_attribute = match title {
        Some(title) => " title=\"" + html_escape_text(title) + "\""
        None => ""
      }
      Ok(
        "<img src=\"" +
        markdown_ir_html_escape_href(destination) +
        "\" alt=\"" +
        html_escape_text(markdown_ir_plain_text(children)) +
        "\"" +
        title_attribute +
        " />",
      )
    }
    Autolink(_, display, destination, _, _) =>
      Ok(
        "<a href=\"" +
        html_escape_text(destination) +
        "\">" +
        html_escape_text(display) +
        "</a>",
      )
    InlineHtml(value, _) =>
      render_valid_raw_html(value, ir.origin, RawHtmlInline, raw_html_policy)
    Unsupported(message) =>
      Ok("<!-- unsupported MarkdownIR: " + html_escape_text(message) + " -->")
    Recovered(message, _) if message == RECOVERED_PARSE_ERROR =>
      Ok("<!-- recovered MarkdownIR: " + html_escape_text(message) + " -->")
    Recovered(message, _) => Ok(html_escape_text(message))
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
pub fn experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
  ir : MarkdownIR,
  raw_html_policy : RawHtmlPolicy,
) -> Result[String, MarkdownIRHtmlRenderError] {
  markdown_ir_to_commonmark_html_with_list_context(ir, false, raw_html_policy~)
}

///|
/// Experimental CommonMark-style HTML rendering with a safe product default.
///
/// Valid raw HTML is escaped. Call
/// `experimental_markdown_ir_to_commonmark_html_with_raw_html_policy` when a
/// different trust decision is intentional.
pub fn experimental_markdown_ir_to_commonmark_html(ir : MarkdownIR) -> String {
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(ir, Escape) {
    Ok(html) => html
    Err(_) => abort("Escape raw HTML policy cannot reject valid HTML")
  }
}
