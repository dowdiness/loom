///|
fn experimental_markdown_ir_to_inline(ir : MarkdownIR) -> Inline {
  match ir.node {
    Text(value) => Inline::Text(value)
    Bold(children, _) => Inline::Bold(ir_children_to_inlines(children))
    Italic(children, _) => Inline::Italic(ir_children_to_inlines(children))
    InlineCode(value, _) => Inline::InlineCode(value)
    Link(children, destination, _, _) =>
      Inline::Link(ir_children_to_inlines(children), destination)
    HardBreak(_) => Inline::Text("\n")
    Unsupported(message) => Inline::Error(message)
    Raw(value, _) => Inline::Text(value)
    Recovered(message, _) => Inline::Error(message)
    Document(_) => Inline::Error("expected inline MarkdownIR, got document")
    Heading(_, _, _) => Inline::Error("expected inline MarkdownIR, got heading")
    Paragraph(_, _) =>
      Inline::Error("expected inline MarkdownIR, got paragraph")
    BlockQuote(_) => Inline::Error("expected inline MarkdownIR, got blockquote")
    UnorderedList(_, _, _) | OrderedList(_, _, _) =>
      Inline::Error("expected inline MarkdownIR, got list")
    ListItem(_, _, _, _) | OrderedListItem(_, _, _, _) =>
      Inline::Error("expected inline MarkdownIR, got list item")
    CodeBlock(_, _, _) =>
      Inline::Error("expected inline MarkdownIR, got code block")
    HtmlBlock(value, _) => Inline::Text(value)
    ThematicBreak =>
      Inline::Error("expected inline MarkdownIR, got thematic break")
  }
}

///|
fn experimental_markdown_ir_to_editor_inline(ir : MarkdownIR) -> Inline {
  match ir.node {
    Bold(children, _) =>
      Inline::Bold(ir_children_to_editor_inlines(children, None))
    Italic(children, _) =>
      Inline::Italic(ir_children_to_editor_inlines(children, None))
    Link(children, destination, _, _) =>
      Inline::Link(ir_children_to_editor_inlines(children, None), destination)
    _ => experimental_markdown_ir_to_inline(ir)
  }
}

///|
fn ir_children_to_inlines(children : Array[MarkdownIR]) -> Array[Inline] {
  children.map(experimental_markdown_ir_to_inline)
}

///|
/// Convert IR inline children for the legacy editor Block adapter. The caller
/// chooses how direct paragraph soft breaks render (`" "` for top-level
/// paragraphs, `"\n"` for list-item paragraphs); inline-formatting soft breaks
/// use `None` to match the direct CST adapter.
fn ir_children_to_editor_inlines(
  children : Array[MarkdownIR],
  newline_text : String?,
) -> Array[Inline] {
  children
  .iter()
  .filter_map(child => {
    match child.node {
      Text("\n") => newline_text.map(text => Inline::Text(text))
      HardBreak(_) => Some(Inline::Text("\n"))
      _ => Some(experimental_markdown_ir_to_editor_inline(child))
    }
  })
  .collect()
}

///|
fn list_item_flow_child_to_editor_inlines(child : MarkdownIR) -> Array[Inline] {
  match child.node {
    Paragraph(paragraph_children, _) =>
      ir_children_to_editor_inlines(paragraph_children, Some("\n"))
    BlockQuote(_) | UnorderedList(_, _, _) | OrderedList(_, _, _) => []
    ListItem(item_children, _, _, _)
    | OrderedListItem(item_children, _, _, _) =>
      list_item_flow_children_to_editor_inlines(item_children)
    _ => [experimental_markdown_ir_to_inline(child)]
  }
}

///|
fn list_item_flow_children_to_editor_inlines(
  children : Array[MarkdownIR],
) -> Array[Inline] {
  children
  .iter()
  .flat_map(child => list_item_flow_child_to_editor_inlines(child).iter())
  .collect()
}

///|
pub fn experimental_markdown_ir_to_block(ir : MarkdownIR) -> Block {
  match ir.node {
    Document(children) =>
      Block::Document(children.map(experimental_markdown_ir_to_block))
    Heading(depth, children, _) =>
      Block::Heading(depth, ir_children_to_editor_inlines(children, None))
    Paragraph(children, _) =>
      Block::Paragraph(ir_children_to_editor_inlines(children, Some(" ")))
    BlockQuote(_) => Block::Error("expected editor Block, got blockquote")
    UnorderedList(children, _, _) =>
      Block::UnorderedList(children.map(experimental_markdown_ir_to_block))
    OrderedList(children, _, marker) =>
      Block::OrderedList(
        children.map(experimental_markdown_ir_to_block),
        marker,
      )
    ListItem(children, _, _, _) =>
      Block::UnorderedListItem(
        list_item_flow_children_to_editor_inlines(children),
      )
    OrderedListItem(children, _, _, marker) =>
      Block::OrderedListItem(
        list_item_flow_children_to_editor_inlines(children),
        marker,
      )
    CodeBlock(info, value, _) => Block::CodeBlock(info, value)
    HtmlBlock(value, _) => Block::HtmlBlock(value)
    ThematicBreak => Block::Error("thematic break")
    Text(_) => Block::Error("expected block MarkdownIR, got text")
    Bold(_, _) => Block::Error("expected block MarkdownIR, got bold")
    Italic(_, _) => Block::Error("expected block MarkdownIR, got italic")
    InlineCode(_, _) =>
      Block::Error("expected block MarkdownIR, got inline code")
    Link(_, _, _, _) => Block::Error("expected block MarkdownIR, got link")
    HardBreak(_) => Block::Error("expected block MarkdownIR, got hard break")
    Unsupported(message) => Block::Error(message)
    Raw(value, _) =>
      Block::Error("expected block MarkdownIR, got raw: " + value)
    Recovered(message, _) => Block::Error(message)
  }
}

///|
fn origin_json(origin : MarkdownIROrigin) -> Json {
  { "start": origin.start(), "end": origin.end() }
}

///|
fn diagnostics_json(diagnostics : Array[@core.Diagnostic]) -> Json {
  Json::array(diagnostics.map(diagnostic => Json::string(diagnostic.format())))
}

///|
fn unist_point_json(point : @core.LineCol, offset : Int) -> Json {
  { "line": point.line + 1, "column": point.column + 1, "offset": offset }
}

///|
fn unist_position_json(
  origin : MarkdownIROrigin,
  line_index : @core.LineIndex,
) -> Json {
  let range = line_index.line_range(origin.start(), origin.end())
  {
    "start": unist_point_json(range.start, origin.start()),
    "end": unist_point_json(range.end, origin.end()),
  }
}

///|
priv struct MdastPositionContext {
  line_index : @core.LineIndex
  source : String
}

///|
fn origin_without_trailing_line_endings(
  origin : MarkdownIROrigin,
  source : String,
) -> MarkdownIROrigin {
  let mut trimmed_end = origin.end()
  while trimmed_end > origin.start() {
    let text = source_slice_between(source, origin.start(), trimmed_end)
    if text.has_suffix("\r\n") {
      trimmed_end = trimmed_end - 2
    } else if text.has_suffix("\r") || text.has_suffix("\n") {
      trimmed_end = trimmed_end - 1
    } else {
      break
    }
  }
  MarkdownIROrigin(start=origin.start(), end=trimmed_end)
}

///|
fn code_fence_close_marker_end(
  origin : MarkdownIROrigin,
  source : String,
) -> Int? {
  match code_fence_close_line_start(origin, source) {
    Some(line_start) => Some(line_end_offset(source, line_start, origin.end()))
    None => None
  }
}

///|
fn code_block_mdast_position_origin(
  origin : MarkdownIROrigin,
  source : String,
) -> MarkdownIROrigin {
  match code_fence_close_marker_end(origin, source) {
    Some(end) => MarkdownIROrigin(start=origin.start(), end~)
    None => origin
  }
}

///|
fn mdast_position_origin(
  ir : MarkdownIR,
  context : MdastPositionContext,
) -> MarkdownIROrigin {
  match ir.node {
    Heading(_, _, _)
    | Paragraph(_, _)
    | BlockQuote(_)
    | UnorderedList(_, _, _)
    | OrderedList(_, _, _)
    | ListItem(_, _, _, _)
    | OrderedListItem(_, _, _, _) =>
      origin_without_trailing_line_endings(ir.origin(), context.source)
    CodeBlock(_, _, _) =>
      code_block_mdast_position_origin(ir.origin(), context.source)
    ThematicBreak =>
      origin_without_trailing_line_endings(ir.origin(), context.source)
    _ => ir.origin()
  }
}

///|
fn mdast_json_with_position(
  json : Json,
  origin : MarkdownIROrigin,
  context : MdastPositionContext?,
) -> Json {
  guard context is Some(position_context) else { return json }
  match json {
    Object(fields) => {
      fields.set(
        "position",
        unist_position_json(origin, position_context.line_index),
      )
      Json::object(fields)
    }
    _ => json
  }
}

///|
fn mdast_json_with_optional_spread(json : Json, spread : Bool) -> Json {
  guard spread else { return json }
  match json {
    Object(fields) => {
      fields.set("spread", true)
      Json::object(fields)
    }
    _ => json
  }
}

///|
fn mdast_json_with_optional_ordered_start(
  json : Json,
  marker : OrderedListMarker?,
) -> Json {
  guard marker is Some(marker) && marker.start != 1 else { return json }
  match json {
    Object(fields) => {
      fields.set("start", Json::number(Double::from_int(marker.start)))
      Json::object(fields)
    }
    _ => json
  }
}

///|
fn mdast_children_json(
  children : Array[MarkdownIR],
  context : MdastPositionContext?,
) -> Array[Json] {
  match context {
    Some(_) => children.map(child => markdown_ir_to_mdast_json(child, context))
    None => {
      let json_children : Array[Json] = []
      let pending_text = StringBuilder::new()
      fn flush_text() -> Unit {
        let text = pending_text.to_string()
        if text.length() > 0 {
          json_children.push({ "type": "text", "value": text })
          pending_text.reset()
        }
      }
      for child in children {
        match child.node {
          Text(value) => pending_text.write_string(value)
          HardBreak(_) => {
            flush_text()
            json_children.push(markdown_ir_to_mdast_json(child, None))
          }
          _ => {
            flush_text()
            json_children.push(markdown_ir_to_mdast_json(child, None))
          }
        }
      }
      flush_text()
      json_children
    }
  }
}

///|
fn markdown_ir_to_mdast_json(
  ir : MarkdownIR,
  context : MdastPositionContext?,
) -> Json {
  let json : Json = match ir.node {
    Document(children) =>
      { "type": "root", "children": mdast_children_json(children, context) }
    Heading(depth, children, _) =>
      {
        "type": "heading",
        "depth": depth,
        "children": mdast_children_json(children, context),
      }
    Paragraph(children, _) =>
      {
        "type": "paragraph",
        "children": mdast_children_json(children, context),
      }
    BlockQuote(children) =>
      {
        "type": "blockquote",
        "children": mdast_children_json(children, context),
      }
    UnorderedList(children, spread, _) =>
      mdast_json_with_optional_spread(
        {
          "type": "list",
          "ordered": false,
          "children": mdast_children_json(children, context),
        },
        spread,
      )
    OrderedList(children, spread, marker) =>
      mdast_json_with_optional_spread(
        mdast_json_with_optional_ordered_start(
          {
            "type": "list",
            "ordered": true,
            "children": mdast_children_json(children, context),
          },
          marker,
        ),
        spread,
      )
    ListItem(children, spread, _, _)
    | OrderedListItem(children, spread, _, _) =>
      mdast_json_with_optional_spread(
        {
          "type": "listItem",
          "children": mdast_children_json(children, context),
        },
        spread,
      )
    CodeBlock(info, value, _) =>
      if info.length() > 0 {
        { "type": "code", "lang": info, "value": value }
      } else {
        { "type": "code", "value": value }
      }
    HtmlBlock(value, _) => { "type": "html", "value": value }
    ThematicBreak => { "type": "thematicBreak" }
    Text(value) => { "type": "text", "value": value }
    HardBreak(_) => { "type": "break" }
    Bold(children, _) =>
      { "type": "strong", "children": mdast_children_json(children, context) }
    Italic(children, _) =>
      { "type": "emphasis", "children": mdast_children_json(children, context) }
    InlineCode(value, _) => { "type": "inlineCode", "value": value }
    Link(children, destination, _, _) =>
      {
        "type": "link",
        "url": destination,
        "children": mdast_children_json(children, context),
      }
    Unsupported(message) => { "type": "mdastUnsupported", "value": message }
    Raw(value, diagnostics) =>
      {
        "type": "mdastRaw",
        "value": value,
        "origin": origin_json(ir.origin()),
        "diagnostics": diagnostics_json(diagnostics),
      }
    Recovered(message, diagnostics) =>
      {
        "type": "mdastRecovered",
        "value": message,
        "origin": origin_json(ir.origin()),
        "diagnostics": diagnostics_json(diagnostics),
      }
  }
  mdast_json_with_position(
    json,
    match context {
      Some(position_context) => mdast_position_origin(ir, position_context)
      None => ir.origin()
    },
    context,
  )
}

///|
pub fn experimental_markdown_ir_to_mdast_json(ir : MarkdownIR) -> Json {
  markdown_ir_to_mdast_json(ir, None)
}

///|
/// Export MarkdownIR to mdast-shaped JSON with unist `position` objects.
///
/// MarkdownIR origins remain half-open UTF-16 source ranges. This adapter builds
/// a `LineIndex` from the source that produced the IR and converts each origin to
/// unist points with 1-based lines/columns and 0-based UTF-16 offsets at the
/// export boundary.
pub fn experimental_markdown_ir_to_mdast_json_with_positions(
  ir : MarkdownIR,
  source : String,
) -> Json {
  guard ir.origin().end() <= source.length() else {
    abort("MarkdownIR position export source does not cover IR origin")
  }
  markdown_ir_to_mdast_json(
    ir,
    Some({ line_index: @core.LineIndex::new(source), source }),
  )
}
