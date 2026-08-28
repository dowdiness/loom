///|
fn experimental_markdown_ir_to_inline(ir : MarkdownIR) -> Inline {
  match ir.node {
    Text(value) => Inline::Text(value)
    Bold(children, _) => Inline::Bold(ir_children_to_inlines(children))
    Italic(children, _) => Inline::Italic(ir_children_to_inlines(children))
    InlineCode(value, _) => Inline::InlineCode(value)
    Link(children, destination, _, _) =>
      Inline::Link(ir_children_to_inlines(children), destination)
    Image(children, destination, _, _) =>
      Inline::Link(ir_children_to_inlines(children), destination)
    Autolink(_, display, destination, _, _) =>
      Inline::Link([Inline::Text(display)], destination)
    InlineHtml(value, _) => Inline::Text(value)
    SoftBreak(_) | HardBreak(_, _) => Inline::Text("\n")
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
    ListItem(_, _, _, _, _) | OrderedListItem(_, _, _, _, _) =>
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
    Image(children, destination, _, _) =>
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
      SoftBreak(_) => newline_text.map(text => Inline::Text(text))
      HardBreak(_, _) => Some(Inline::Text("\n"))
      _ => Some(experimental_markdown_ir_to_editor_inline(child))
    }
  })
  .collect()
}

///|
fn markdown_ir_legacy_destination(
  ir : MarkdownIR,
  destination : String,
  source : String,
) -> String {
  match ir.node {
    Link(_, _, _, surface) | Image(_, _, _, surface) =>
      match surface.form {
        LinkReferenceForm::InlineLinkForm =>
          match surface.target_origin {
            Some(origin) => source[origin.start():origin.end()].to_owned()
            None =>
              match ir.destination_origin() {
                Some(origin) => source[origin.start():origin.end()].to_owned()
                None => destination
              }
          }
        _ => ""
      }
    _ => destination
  }
}

///|
fn markdown_ir_legacy_text(
  value : String,
  origin : MarkdownIROrigin,
  source : String,
  next : MarkdownIR?,
  after_next : MarkdownIR?,
) -> Inline {
  let next_is_text_bracket = match next {
    Some(next) =>
      match next.node {
        Text(text) =>
          text == "[" &&
          source[next.origin().start():next.origin().end()] == "["
        _ => false
      }
    None => false
  }
  let next_is_inline_link = match next {
    Some(next) =>
      match next.node {
        Link(_, _, _, _) | Image(_, _, _, _) | Autolink(_, _, _, _, _) => true
        _ => false
      }
    None => false
  }
  let after_next_is_inline_link = match after_next {
    Some(after_next) =>
      match after_next.node {
        Link(_, _, _, _) | Image(_, _, _, _) | Autolink(_, _, _, _, _) => true
        _ => false
      }
    None => false
  }
  if value == "[" &&
    source[origin.start():origin.end()] == "[" &&
    !next_is_inline_link &&
    !(next_is_text_bracket && after_next_is_inline_link) {
    Inline::Error(value)
  } else {
    Inline::Text(value)
  }
}

///|
fn markdown_ir_to_legacy_editor_inline(
  ir : MarkdownIR,
  source : String,
) -> Inline {
  match ir.node {
    Text(value) =>
      markdown_ir_legacy_text(value, ir.origin(), source, None, None)
    Bold(children, _) =>
      Inline::Bold(
        markdown_ir_children_to_legacy_editor_inlines(children, None, source),
      )
    Italic(children, _) =>
      Inline::Italic(
        markdown_ir_children_to_legacy_editor_inlines(children, None, source),
      )
    Link(children, destination, _, _) =>
      Inline::Link(
        markdown_ir_children_to_legacy_editor_inlines(children, None, source),
        markdown_ir_legacy_destination(ir, destination, source),
      )
    Image(children, destination, _, _) =>
      Inline::Link(
        markdown_ir_children_to_legacy_editor_inlines(children, None, source),
        markdown_ir_legacy_destination(ir, destination, source),
      )
    ThematicBreak =>
      Inline::Text(markdown_ir_legacy_block_text(source, ir.origin()))
    _ => experimental_markdown_ir_to_inline(ir)
  }
}

///|
fn markdown_ir_legacy_text_around_soft_break(
  child : MarkdownIR,
  value : String,
  previous : MarkdownIR?,
  next : MarkdownIR?,
  source : String,
  trim_spaces : Bool,
) -> String {
  let mut result = value
  match previous {
    Some(previous) if previous.node is SoftBreak(_) => {
      let start = previous.origin().end()
      let end = child.origin().start()
      if start <= end {
        let prefix = source[start:end].to_owned()
        result = prefix + result
        if trim_spaces {
          result = result.trim_start(chars=" ".view()).to_owned()
        }
      }
    }
    _ => ()
  }
  match next {
    Some(next) if next.node is SoftBreak(_) => {
      let start = child.origin().end()
      let end = next.origin().start()
      if start <= end {
        let suffix = source[start:end].to_owned()
        result = result + suffix
        if trim_spaces {
          result = result.trim_end(chars=" ".view()).to_owned()
        }
      }
    }
    _ => ()
  }
  result
}

///|
fn markdown_ir_legacy_bracket(
  child : MarkdownIR,
  value : String,
  source : String,
) -> Bool {
  match child.node {
    Text(text) | Raw(text, _) | Recovered(text, _) =>
      text == value &&
      source[child.origin().start():child.origin().end()] == value
    _ => false
  }
}

///|
fn markdown_ir_legacy_unresolved_full_reference_children(
  children : Array[MarkdownIR],
  source : String,
) -> Array[MarkdownIR] {
  let result : Array[MarkdownIR] = []
  let mut index = 0
  while index < children.length() {
    let opener = children[index]
    let mut matched : (MarkdownIR, Int)? = None
    if markdown_ir_legacy_bracket(opener, "[", source) {
      let mut label_end = index + 1
      let mut valid_label = true
      while label_end < children.length() &&
            !markdown_ir_legacy_bracket(children[label_end], "]", source) {
        if markdown_ir_legacy_bracket(children[label_end], "[", source) {
          valid_label = false
        }
        label_end = label_end + 1
      }
      if valid_label &&
        label_end < children.length() &&
        label_end + 1 < children.length() &&
        markdown_ir_legacy_bracket(children[label_end], "]", source) &&
        markdown_ir_legacy_bracket(children[label_end + 1], "[", source) {
        let mut reference_end = label_end + 2
        let mut valid_reference = true
        while reference_end < children.length() &&
              !markdown_ir_legacy_bracket(children[reference_end], "]", source) {
          if markdown_ir_legacy_bracket(children[reference_end], "[", source) {
            valid_reference = false
          }
          reference_end = reference_end + 1
        }
        if valid_reference &&
          reference_end < children.length() &&
          markdown_ir_legacy_bracket(children[reference_end], "]", source) {
          let label_children : Array[MarkdownIR] = []
          for label_index = index + 1
              label_index < label_end
              label_index = label_index + 1 {
            label_children.push(children[label_index])
          }
          let label_origin = MarkdownIROrigin(
            start=opener.origin().end(),
            end=children[label_end].origin().start(),
          )
          let reference_origin = MarkdownIROrigin(
            start=children[label_end + 1].origin().end(),
            end=children[reference_end].origin().start(),
          )
          let link = MarkdownIR::link_with_metadata(
            label_children,
            "",
            None,
            LinkReferenceForm::FullReferenceLinkForm,
            MarkdownIROrigin(
              start=opener.origin().start(),
              end=children[reference_end].origin().end(),
            ),
            Some(label_origin),
            Some(reference_origin),
            None,
            None,
          )
          matched = Some((link, reference_end + 1))
        }
      }
    }
    match matched {
      Some((link, next_index)) => {
        result.push(link)
        index = next_index
      }
      None => {
        result.push(opener)
        index = index + 1
      }
    }
  }
  result
}

///|
fn markdown_ir_legacy_text_parts(
  child : MarkdownIR,
  value : String,
  source : String,
) -> Array[MarkdownIR] {
  let parts : Array[MarkdownIR] = []
  let origin = child.origin()
  let raw = source[origin.start():origin.end()].to_owned()
  if value.length() > 1 &&
    raw.contains("[") &&
    raw.get_char(raw.length() - 1) is Some(']') &&
    value.get_char(value.length() - 1) is Some(']') {
    let split = origin.end() - 1
    parts.push(
      MarkdownIR::text(
        value[0:value.length() - 1].to_owned(),
        MarkdownIROrigin(start=origin.start(), end=split),
      ),
    )
    parts.push(
      MarkdownIR::text("]", MarkdownIROrigin(start=split, end=origin.end())),
    )
  } else {
    parts.push(child)
  }
  parts
}

///|
fn markdown_ir_legacy_split_bracket_text(
  children : Array[MarkdownIR],
  source : String,
) -> Array[MarkdownIR] {
  let result : Array[MarkdownIR] = []
  for child in children {
    match child.node {
      Text(value) =>
        for part in markdown_ir_legacy_text_parts(child, value, source) {
          result.push(part)
        }
      _ => result.push(child)
    }
  }
  result
}

///|
fn markdown_ir_children_to_legacy_editor_inlines(
  children : Array[MarkdownIR],
  newline_text : String?,
  source : String,
) -> Array[Inline] {
  let inlines : Array[Inline] = []
  let trim_spaces = newline_text is Some(_)
  let projected_children = markdown_ir_legacy_split_bracket_text(
    markdown_ir_legacy_unresolved_full_reference_children(children, source),
    source,
  )
  for index, child in projected_children {
    let previous = if index > 0 {
      Some(projected_children[index - 1])
    } else {
      None
    }
    let next = if index + 1 < projected_children.length() {
      Some(projected_children[index + 1])
    } else {
      None
    }
    let after_next = if index + 2 < projected_children.length() {
      Some(projected_children[index + 2])
    } else {
      None
    }
    match child.node {
      SoftBreak(_) =>
        match newline_text {
          Some(text) => inlines.push(Inline::Text(text))
          None => ()
        }
      HardBreak(_, _) =>
        match newline_text {
          Some(text) => inlines.push(Inline::Text(text))
          None => inlines.push(Inline::Text("\n"))
        }
      Text(value) =>
        inlines.push(
          markdown_ir_legacy_text(
            markdown_ir_legacy_text_around_soft_break(
              child, value, previous, next, source, trim_spaces,
            ),
            child.origin(),
            source,
            next,
            after_next,
          ),
        )
      Image(_, _, _, _) => {
        let can_merge_image_marker = match previous {
          Some(previous) => previous.node is Text(_)
          None => false
        }
        if can_merge_image_marker && inlines.length() > 0 {
          let last = inlines.length() - 1
          match inlines[last] {
            Inline::Text(value) => inlines[last] = Inline::Text(value + "!")
            _ => inlines.push(Inline::Text("!"))
          }
        } else {
          inlines.push(Inline::Text("!"))
        }
        inlines.push(markdown_ir_to_legacy_editor_inline(child, source))
      }
      _ => inlines.push(markdown_ir_to_legacy_editor_inline(child, source))
    }
  }
  inlines
}

///|
fn markdown_ir_legacy_editor_inlines(
  children : Array[MarkdownIR],
  newline_text : String?,
  source : String?,
) -> Array[Inline] {
  match source {
    Some(source) =>
      markdown_ir_children_to_legacy_editor_inlines(
        children, newline_text, source,
      )
    None => ir_children_to_editor_inlines(children, newline_text)
  }
}

///|
fn markdown_ir_to_legacy_inline(ir : MarkdownIR, source : String) -> Inline {
  markdown_ir_to_legacy_editor_inline(ir, source)
}

///|
fn list_item_flow_child_to_legacy_editor_inlines(
  child : MarkdownIR,
) -> Array[Inline] {
  match child.node {
    Paragraph(paragraph_children, _) =>
      ir_children_to_editor_inlines(paragraph_children, Some("\n"))
    BlockQuote(_) | UnorderedList(_, _, _) | OrderedList(_, _, _) => []
    ListItem(item_children, _, _, _, _)
    | OrderedListItem(item_children, _, _, _, _) =>
      list_item_flow_children_to_legacy_editor_inlines(item_children)
    _ => [experimental_markdown_ir_to_inline(child)]
  }
}

///|
fn list_item_flow_children_to_legacy_editor_inlines(
  children : Array[MarkdownIR],
) -> Array[Inline] {
  children
  .iter()
  .flat_map(child => list_item_flow_child_to_legacy_editor_inlines(child).iter())
  .collect()
}

///|
fn list_item_flow_child_to_editor_inlines(
  child : MarkdownIR,
  source : String?,
) -> Array[Inline] {
  match child.node {
    Paragraph(paragraph_children, _) =>
      markdown_ir_legacy_editor_inlines(paragraph_children, Some("\n"), source)
    BlockQuote(_) | UnorderedList(_, _, _) | OrderedList(_, _, _) => []
    ListItem(item_children, _, _, _, _)
    | OrderedListItem(item_children, _, _, _, _) =>
      markdown_ir_legacy_list_item_inlines(child, item_children, source)
    _ =>
      match source {
        Some(source) =>
          match child.node {
            Heading(_, _, _) | CodeBlock(_, _, _) | HtmlBlock(_) => []
            _ => [markdown_ir_to_legacy_inline(child, source)]
          }
        None => [experimental_markdown_ir_to_inline(child)]
      }
  }
}

///|
fn list_item_flow_children_to_editor_inlines(
  children : Array[MarkdownIR],
  source : String?,
) -> Array[Inline] {
  let inlines : Array[Inline] = []
  let mut seen_paragraph = false
  for child in children {
    match child.node {
      Paragraph(_, _) if seen_paragraph => ()
      Paragraph(_, _) => {
        seen_paragraph = true
        inlines.append(list_item_flow_child_to_editor_inlines(child, source))
      }
      _ => inlines.append(list_item_flow_child_to_editor_inlines(child, source))
    }
  }
  inlines
}

///|
fn markdown_ir_legacy_list_prefix(item : MarkdownIR, source : String) -> String {
  let ordered = match item.node {
    ListItem(_, _, _, _, _) => false
    OrderedListItem(_, _, _, _, _) => true
    _ => return ""
  }
  match item.content_origin() {
    Some(content_origin) => {
      let item_origin = item.origin()
      let item_source = source[item_origin.start():item_origin.end()].to_owned()
      match list_marker_body_end_offset(item_source, ordered~) {
        Some(marker_end) => {
          let prefix_start = item_origin.start() + marker_end
          let content_start = content_origin.start()
          if prefix_start < content_start {
            let prefix = source[prefix_start:content_start].to_owned()
            if prefix.length() > 0 {
              prefix[1:].to_owned()
            } else {
              ""
            }
          } else {
            ""
          }
        }
        None => ""
      }
    }
    None => ""
  }
}

///|
fn markdown_ir_prepend_legacy_list_prefix(
  inlines : Array[Inline],
  prefix : String,
) -> Array[Inline] {
  if prefix == "" || inlines.length() == 0 {
    return inlines
  }
  match inlines[0] {
    Inline::Text(value) => {
      inlines[0] = Inline::Text(prefix + value)
      inlines
    }
    _ => {
      let result : Array[Inline] = [Inline::Text(prefix)]
      result.append(inlines)
      result
    }
  }
}

///|
fn markdown_ir_legacy_list_item_inlines(
  item : MarkdownIR,
  children : Array[MarkdownIR],
  source : String?,
) -> Array[Inline] {
  let inlines = match source {
    None => list_item_flow_children_to_legacy_editor_inlines(children)
    Some(_) => list_item_flow_children_to_editor_inlines(children, source)
  }
  match source {
    Some(source) =>
      markdown_ir_prepend_legacy_list_prefix(
        inlines,
        markdown_ir_legacy_list_prefix(item, source),
      )
    None => inlines
  }
}

///|
fn markdown_ir_legacy_block_text(
  source : String,
  origin : MarkdownIROrigin,
) -> String {
  trim_trailing_line_ending(source[origin.start():origin.end()].to_owned())
}

///|
fn markdown_ir_require_source_origin(
  origin : MarkdownIROrigin?,
  source_length : Int,
) -> Unit {
  match origin {
    Some(origin) => {
      guard origin.end() <= source_length else {
        abort("MarkdownIR Block projection source does not cover IR origin")
      }
    }
    None => ()
  }
}

///|
fn markdown_ir_require_source_coverage(
  ir : MarkdownIR,
  source_length : Int,
) -> Unit {
  markdown_ir_require_source_origin(Some(ir.origin()), source_length)
  markdown_ir_require_source_origin(ir.content_origin(), source_length)
  markdown_ir_require_source_origin(ir.label_origin(), source_length)
  markdown_ir_require_source_origin(ir.destination_origin(), source_length)
  match ir.node {
    Link(_, _, _, surface) | Image(_, _, _, surface) => {
      markdown_ir_require_source_origin(
        surface.reference_label_origin,
        source_length,
      )
      markdown_ir_require_source_origin(surface.title_origin, source_length)
      markdown_ir_require_source_origin(surface.target_origin, source_length)
    }
    ListItem(_, _, _, _, Some(task))
    | OrderedListItem(_, _, _, _, Some(task)) =>
      markdown_ir_require_source_origin(
        Some(task.marker_origin()),
        source_length,
      )
    _ => ()
  }
  match ir.node {
    Document(children)
    | Heading(_, children, _)
    | Paragraph(children, _)
    | BlockQuote(children)
    | UnorderedList(children, _, _)
    | OrderedList(children, _, _)
    | ListItem(children, _, _, _, _)
    | OrderedListItem(children, _, _, _, _)
    | Bold(children, _)
    | Italic(children, _)
    | Link(children, _, _, _)
    | Image(children, _, _, _) =>
      for child in children {
        markdown_ir_require_source_coverage(child, source_length)
      }
    _ => ()
  }
}

///|
fn markdown_ir_to_block_with_source(ir : MarkdownIR, source : String?) -> Block {
  match source {
    Some(source) => {
      markdown_ir_require_source_coverage(ir, source.length())
      markdown_ir_to_block_with_source_unchecked(ir, Some(source))
    }
    None => markdown_ir_to_block_with_source_unchecked(ir, None)
  }
}

///|
fn markdown_ir_to_block_with_source_unchecked(
  ir : MarkdownIR,
  source : String?,
) -> Block {
  match ir.node {
    Document(children) =>
      Block::Document(
        children.map(child => {
          markdown_ir_to_block_with_source_unchecked(child, source)
        }),
      )
    Heading(depth, children, _) =>
      Block::Heading(
        depth,
        markdown_ir_legacy_editor_inlines(children, None, source),
      )
    Paragraph(children, _) =>
      Block::Paragraph(
        markdown_ir_legacy_editor_inlines(children, Some(" "), source),
      )
    BlockQuote(_) =>
      match source {
        Some(source) =>
          Block::Paragraph([
            Inline::Text(markdown_ir_legacy_block_text(source, ir.origin())),
          ])
        None => Block::Error("expected editor Block, got blockquote")
      }
    UnorderedList(children, _, _) =>
      Block::UnorderedList(
        children.map(child => {
          markdown_ir_to_block_with_source_unchecked(child, source)
        }),
      )
    OrderedList(children, _, marker) =>
      Block::OrderedList(
        children.map(child => {
          markdown_ir_to_block_with_source_unchecked(child, source)
        }),
        marker,
      )
    ListItem(children, _, _, _, _) =>
      Block::UnorderedListItem(
        markdown_ir_legacy_list_item_inlines(ir, children, source),
      )
    OrderedListItem(children, _, _, marker, _) =>
      Block::OrderedListItem(
        markdown_ir_legacy_list_item_inlines(ir, children, source),
        marker,
      )
    CodeBlock(info, value, _) => Block::CodeBlock(info, value)
    HtmlBlock(value, _) => Block::HtmlBlock(value)
    ThematicBreak =>
      match source {
        Some(source) =>
          Block::Paragraph([
            Inline::Text(markdown_ir_legacy_block_text(source, ir.origin())),
          ])
        None => Block::Error("thematic break")
      }
    Text(_) => Block::Error("expected block MarkdownIR, got text")
    Bold(_, _) => Block::Error("expected block MarkdownIR, got bold")
    Italic(_, _) => Block::Error("expected block MarkdownIR, got italic")
    InlineCode(_, _) =>
      Block::Error("expected block MarkdownIR, got inline code")
    Link(_, _, _, _) => Block::Error("expected block MarkdownIR, got link")
    Image(_, _, _, _) => Block::Error("expected block MarkdownIR, got image")
    Autolink(_, _, _, _, _) =>
      Block::Error("expected block MarkdownIR, got autolink")
    InlineHtml(_, _) =>
      Block::Error("expected block MarkdownIR, got inline HTML")
    SoftBreak(_) => Block::Error("expected block MarkdownIR, got soft break")
    HardBreak(_, _) => Block::Error("expected block MarkdownIR, got hard break")
    Unsupported(message) => Block::Error(message)
    Raw(value, _) =>
      Block::Error("expected block MarkdownIR, got raw: " + value)
    Recovered(message, _) => Block::Error(message)
  }
}

///|
pub fn experimental_markdown_ir_to_block(ir : MarkdownIR) -> Block {
  markdown_ir_to_block_with_source(ir, None)
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
    | ListItem(_, _, _, _, _)
    | OrderedListItem(_, _, _, _, _) =>
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
fn mdast_json_with_optional_checked(
  json : Json,
  task : MarkdownIRTask?,
) -> Json {
  guard task is Some(task) else { return json }
  match json {
    Object(fields) => {
      fields.set("checked", Json::boolean(task.checked()))
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
          SoftBreak(_) => pending_text.write_char('\n')
          HardBreak(_, _) => {
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
    ListItem(children, spread, _, _, task)
    | OrderedListItem(children, spread, _, _, task) =>
      mdast_json_with_optional_checked(
        mdast_json_with_optional_spread(
          {
            "type": "listItem",
            "children": mdast_children_json(children, context),
          },
          spread,
        ),
        task,
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
    SoftBreak(_) => { "type": "text", "value": "\n" }
    HardBreak(_, _) => { "type": "break" }
    Bold(children, _) =>
      { "type": "strong", "children": mdast_children_json(children, context) }
    Italic(children, _) =>
      { "type": "emphasis", "children": mdast_children_json(children, context) }
    InlineCode(value, _) => { "type": "inlineCode", "value": value }
    Link(children, destination, title, _) =>
      match title {
        Some(title) =>
          {
            "type": "link",
            "url": destination,
            "title": title,
            "children": mdast_children_json(children, context),
          }
        None =>
          {
            "type": "link",
            "url": destination,
            "children": mdast_children_json(children, context),
          }
      }
    Image(children, destination, title, _) =>
      match title {
        Some(title) =>
          {
            "type": "image",
            "url": destination,
            "title": title,
            "alt": markdown_ir_plain_text(children),
          }
        None =>
          {
            "type": "image",
            "url": destination,
            "alt": markdown_ir_plain_text(children),
          }
      }
    Autolink(_, display, destination, display_origin, _) =>
      {
        "type": "link",
        "url": destination,
        "children": [
          mdast_json_with_position(
            { "type": "text", "value": display },
            display_origin.unwrap_or(ir.origin()),
            context,
          ),
        ],
      }
    InlineHtml(value, _) => { "type": "html", "value": value }
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
