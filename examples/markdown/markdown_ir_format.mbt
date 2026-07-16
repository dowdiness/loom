///|
fn code_block_markdown(info : String, value : String) -> String {
  @core.Renderable::unparse(Block::CodeBlock(info, value))
}

///|
fn inline_code_markdown(value : String) -> String {
  let mut longest_run = 0
  let mut run = 0
  let mut has_non_space = false
  for ch in value {
    match ch {
      '`' => {
        run = run + 1
        if run > longest_run {
          longest_run = run
        }
        has_non_space = true
      }
      ' ' => run = 0
      _ => {
        run = 0
        has_non_space = true
      }
    }
  }
  let delimiter = "`".repeat(longest_run + 1)
  let boundary_spaces = value.has_prefix(" ") &&
    value.has_suffix(" ") &&
    has_non_space
  let padding = if value.has_prefix("`") ||
    value.has_suffix("`") ||
    boundary_spaces {
    " "
  } else {
    ""
  }
  delimiter + padding + value + padding + delimiter
}

///|
fn canonical_inline_text(children : Array[MarkdownIR]) -> String {
  children.map(child => canonical_format_with_list_marker(child, Dash)).join("")
}

///|
fn indent_canonical_block(text : String, indent : String) -> String {
  text.split("\n").map(line => indent + line.to_owned()).join("\n")
}

///|
fn canonical_nested_flow_child(
  child : MarkdownIR,
  list_marker : UnorderedListMarker,
  previous_nested_marker : UnorderedListMarker?,
) -> (String, UnorderedListMarker?) {
  let (marker, next_previous) = match child.node {
    UnorderedList(_, _, surface_marker) => {
      let marker = match previous_nested_marker {
        Some(previous_marker) =>
          boundary_preserving_list_marker(previous_marker, surface_marker)
        None => list_marker
      }
      (marker, Some(marker))
    }
    _ => (list_marker, None)
  }
  (
    "\n" +
    indent_canonical_block(
      canonical_format_with_list_marker(child, marker),
      "  ",
    ),
    next_previous,
  )
}

///|
fn canonical_nested_flow_children(
  children : ArrayView[MarkdownIR],
  list_marker : UnorderedListMarker,
) -> String {
  let buf = StringBuilder::new()
  for child in children; previous_nested_marker = None {
    let (rendered, next_previous) = canonical_nested_flow_child(
      child, list_marker, previous_nested_marker,
    )
    buf.write_string(rendered)
    continue next_previous
  }
  buf.to_string()
}

///|
fn canonical_list_item_flow(
  marker_text : String,
  children : Array[MarkdownIR],
  list_marker : UnorderedListMarker,
) -> String {
  match children {
    [] => marker_text + " "
    [first, .. rest] => {
      let first_text = canonical_format_with_list_marker(first, list_marker)
      marker_text +
      " " +
      first_text +
      canonical_nested_flow_children(rest, list_marker)
    }
  }
}

///|
fn boundary_preserving_list_marker(
  previous_marker : UnorderedListMarker,
  surface_marker : UnorderedListMarker?,
) -> UnorderedListMarker {
  match surface_marker {
    Some(marker) if marker != previous_marker => marker
    _ =>
      match previous_marker {
        Dash => Plus
        Star | Plus => Dash
      }
  }
}

///|
fn canonical_document_format(children : Array[MarkdownIR]) -> String {
  let buf = StringBuilder::new()
  let mut previous_list_marker : UnorderedListMarker? = None
  for i, child in children {
    if i > 0 {
      buf.write_string("\n\n")
    }
    match child.node {
      UnorderedList(_, _, surface_marker) => {
        let marker = match previous_list_marker {
          Some(previous_marker) =>
            boundary_preserving_list_marker(previous_marker, surface_marker)
          None => Dash
        }
        buf.write_string(canonical_format_with_list_marker(child, marker))
        previous_list_marker = Some(marker)
      }
      OrderedList(_, _, _) => {
        buf.write_string(canonical_format_with_list_marker(child, Dash))
        previous_list_marker = None
      }
      _ => {
        buf.write_string(canonical_format_with_list_marker(child, Dash))
        previous_list_marker = None
      }
    }
  }
  buf.to_string()
}

///|
fn canonical_format_with_list_marker(
  ir : MarkdownIR,
  list_marker : UnorderedListMarker,
) -> String {
  match ir.node {
    Document(children) => canonical_document_format(children)
    Heading(depth, children, _) =>
      "#".repeat(depth) + " " + canonical_inline_text(children)
    Paragraph(children, _) => canonical_inline_text(children)
    BlockQuote(children) =>
      indent_canonical_block(canonical_document_format(children), "> ")
    UnorderedList(children, _, _) =>
      children
      .map(child => canonical_format_with_list_marker(child, list_marker))
      .join("\n")
    OrderedList(children, _, _) =>
      children
      .map(child => canonical_format_with_list_marker(child, list_marker))
      .join("\n")
    ListItem(children, _, _, _) =>
      canonical_list_item_flow(list_marker.text(), children, list_marker)
    OrderedListItem(children, _, _, marker) => {
      let item_marker = match marker {
        Some(marker) => marker.text()
        None => "1."
      }
      canonical_list_item_flow(item_marker, children, list_marker)
    }
    CodeBlock(info, value, _) => code_block_markdown(info, value)
    HtmlBlock(value, _) => value
    ThematicBreak => "---"
    Text(value) | Raw(value, _) => value
    HardBreak(_) => "  \n"
    Bold(children, _) => "**" + canonical_inline_text(children) + "**"
    Italic(children, _) => "*" + canonical_inline_text(children) + "*"
    InlineCode(value, _) => inline_code_markdown(value)
    Link(children, destination, _) =>
      "[" + canonical_inline_text(children) + "](" + destination + ")"
    Unsupported(message) => "<!-- unsupported MarkdownIR: " + message + " -->"
    Recovered(message, _) if message == RECOVERED_PARSE_ERROR =>
      "<!-- recovered MarkdownIR: " + message + " -->"
    Recovered(message, _) => message
  }
}

///|
pub fn experimental_markdown_ir_canonical_format(ir : MarkdownIR) -> String {
  canonical_format_with_list_marker(ir, Dash)
}
