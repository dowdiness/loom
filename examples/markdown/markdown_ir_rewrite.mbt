///|
/// Experimental preserve-mode rewrite for unchanged IR.
///
/// This is intentionally source-slice based: the caller must pass the source
/// that produced the IR. MarkdownIR itself does not store trivia or token lists.
pub fn experimental_markdown_ir_preserve_rewrite(
  ir : MarkdownIR,
  source : String,
) -> String {
  source_slice(source, ir.origin())
}

///|
fn original_block_trailing_newline(
  source : String,
  origin : MarkdownIROrigin,
) -> String {
  let text = source_slice(source, origin)
  if text.has_suffix("\r\n") {
    "\r\n"
  } else if text.has_suffix("\r") {
    "\r"
  } else if text.has_suffix("\n") {
    "\n"
  } else {
    ""
  }
}

///|
fn local_transform_inline_text(
  children : Array[MarkdownIR],
  source : String,
  target_origin : MarkdownIROrigin,
  replacement_text : String,
) -> String {
  match children {
    [] => ""
    [first, ..] => {
      let buf = StringBuilder::new()
      for child in children; cursor = first.origin().start() {
        let child_origin = child.origin()
        buf.write_string(
          source_slice_between(source, cursor, child_origin.start()),
        )
        if child_origin.contains(target_origin) {
          buf.write_string(
            local_transform_render(
              child, source, target_origin, replacement_text,
            ),
          )
        } else {
          match child.node {
            Text(_) | Raw(_, _) | HardBreak(_) =>
              buf.write_string(source_slice(source, child_origin))
            InlineCode(value, _) => buf.write_string("`" + value + "`")
            _ => buf.write_string(source_slice(source, child_origin))
          }
        }
        continue child_origin.end()
      } nobreak {
        buf.to_string()
      }
    }
  }
}

///|
fn max_backtick_run(value : String) -> Int {
  let mut max_run = 0
  let mut cur_run = 0
  for i = 0; i < value.length(); i = i + 1 {
    match value.code_unit_at(i).to_char() {
      Some('`') => {
        cur_run = cur_run + 1
        if cur_run > max_run {
          max_run = cur_run
        }
      }
      _ => cur_run = 0
    }
  }
  max_run
}

///|
fn code_block_backtick_width(value : String, minimum_width : Int) -> Int {
  let run_width = max_backtick_run(value)
  let required_width = if run_width >= 3 { run_width + 1 } else { 3 }
  if minimum_width > required_width {
    minimum_width
  } else {
    required_width
  }
}

///|
fn local_code_block_suffix(
  source : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin,
  fence_width : Int,
) -> String {
  match code_fence_close_line_start(origin, source) {
    Some(close_start) => {
      let close_width = count_backticks(source, close_start)
      if close_width < fence_width {
        "`".repeat(fence_width) +
        source_slice_between(source, close_start + close_width, origin.end())
      } else {
        source_slice_between(source, close_start, origin.end())
      }
    }
    None => source_slice_between(source, content_origin.end(), origin.end())
  }
}

///|
fn code_block_content_line_ending(
  source : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin,
) -> String {
  let prefix = source_slice_between(
    source,
    origin.start(),
    content_origin.start(),
  )
  if prefix.has_suffix("\r\n") {
    "\r\n"
  } else if prefix.has_suffix("\r") {
    "\r"
  } else {
    "\n"
  }
}

///|
fn local_code_block_markdown(
  source : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin,
  value : String,
) -> String {
  let original_width = count_backticks(source, origin.start())
  let minimum_width = if original_width >= 3 { original_width } else { 3 }
  let fence_width = code_block_backtick_width(value, minimum_width)
  let opening = "`".repeat(fence_width) +
    source_slice_between(
      source,
      origin.start() + original_width,
      content_origin.start(),
    )
  let suffix_prefix = match code_fence_close_line_start(origin, source) {
    Some(close_start) =>
      source_slice_between(source, content_origin.end(), close_start)
    None => ""
  }
  let zero_content = content_origin.start() == content_origin.end()
  let content_line_ending = code_block_content_line_ending(
    source, origin, content_origin,
  )
  let opening_suffix = if zero_content &&
    value != "" &&
    !opening.has_suffix("\n") &&
    !opening.has_suffix("\r") {
    content_line_ending
  } else {
    ""
  }
  let suffix = local_code_block_suffix(
    source, origin, content_origin, fence_width,
  )
  let replacement_ends_with_line_ending = value.has_suffix("\n") ||
    value.has_suffix("\r")
  let replacement_suffix = if value != "" &&
    suffix_prefix == "" &&
    (zero_content || (suffix == "" && replacement_ends_with_line_ending)) {
    content_line_ending
  } else {
    ""
  }
  opening + opening_suffix + value + replacement_suffix + suffix_prefix + suffix
}

///|
fn local_transform_render(
  ir : MarkdownIR,
  source : String,
  target_origin : MarkdownIROrigin,
  replacement_text : String,
) -> String {
  if ir.origin() == target_origin {
    return replacement_text
  }
  match ir.node {
    Document(children) => {
      let buf = StringBuilder::new()
      let final_cursor = for child in children; cursor = ir.origin().start() {
        let child_origin = child.origin()
        buf.write_string(
          source_slice_between(source, cursor, child_origin.start()),
        )
        if child_origin.contains(target_origin) {
          buf.write_string(
            local_transform_render(
              child, source, target_origin, replacement_text,
            ),
          )
        } else {
          buf.write_string(source_slice(source, child_origin))
        }
        continue child_origin.end()
      } nobreak {
        cursor
      }
      buf.write_string(
        source_slice_between(source, final_cursor, ir.origin().end()),
      )
      buf.to_string()
    }
    Heading(depth, children, content_origin) => {
      let rendered = if content_origin == Some(target_origin) {
        replacement_text
      } else {
        local_transform_inline_text(
          children, source, target_origin, replacement_text,
        )
      }
      "#".repeat(depth) +
      " " +
      rendered +
      original_block_trailing_newline(source, ir.origin())
    }
    Paragraph(children, content_origin) => {
      let rendered = if content_origin == Some(target_origin) {
        replacement_text
      } else {
        local_transform_inline_text(
          children, source, target_origin, replacement_text,
        )
      }
      rendered + original_block_trailing_newline(source, ir.origin())
    }
    BlockQuote(children)
    | UnorderedList(children, _, _)
    | OrderedList(children, _, _) => {
      let buf = StringBuilder::new()
      let final_cursor = for child in children; cursor = ir.origin().start() {
        let child_origin = child.origin()
        buf.write_string(
          source_slice_between(source, cursor, child_origin.start()),
        )
        if child_origin.contains(target_origin) {
          buf.write_string(
            local_transform_render(
              child, source, target_origin, replacement_text,
            ),
          )
        } else {
          buf.write_string(source_slice(source, child_origin))
        }
        continue child_origin.end()
      } nobreak {
        cursor
      }
      buf.write_string(
        source_slice_between(source, final_cursor, ir.origin().end()),
      )
      buf.to_string()
    }
    ListItem(children, _, _, _) | OrderedListItem(children, _, _, _) => {
      let buf = StringBuilder::new()
      let final_cursor = for child in children; cursor = ir.origin().start() {
        let child_origin = child.origin()
        buf.write_string(
          source_slice_between(source, cursor, child_origin.start()),
        )
        if child_origin.contains(target_origin) {
          buf.write_string(
            local_transform_render(
              child, source, target_origin, replacement_text,
            ),
          )
        } else {
          buf.write_string(source_slice(source, child_origin))
        }
        continue child_origin.end()
      } nobreak {
        cursor
      }
      buf.write_string(
        source_slice_between(source, final_cursor, ir.origin().end()),
      )
      buf.to_string()
    }
    CodeBlock(_info, _value, content_origin) =>
      if content_origin == Some(target_origin) {
        local_code_block_markdown(
          source,
          ir.origin(),
          target_origin,
          replacement_text,
        )
      } else {
        source_slice(source, ir.origin())
      }
    ThematicBreak => source_slice(source, ir.origin())
    HtmlBlock(_, _) => source_slice(source, ir.origin())
    Text(_) | Raw(_, _) | HardBreak(_) => source_slice(source, ir.origin())
    Bold(children, content_origin) => {
      let rendered = if content_origin == Some(target_origin) {
        replacement_text
      } else {
        local_transform_inline_text(
          children, source, target_origin, replacement_text,
        )
      }
      "**" + rendered + "**"
    }
    Italic(children, content_origin) => {
      let rendered = if content_origin == Some(target_origin) {
        replacement_text
      } else {
        local_transform_inline_text(
          children, source, target_origin, replacement_text,
        )
      }
      "*" + rendered + "*"
    }
    InlineCode(value, content_origin) =>
      if content_origin == Some(target_origin) {
        "`" + replacement_text + "`"
      } else {
        "`" + value + "`"
      }
    Link(children, destination, destination_origin) => {
      let rendered_destination = if destination_origin == Some(target_origin) {
        replacement_text
      } else {
        destination
      }
      "[" +
      local_transform_inline_text(
        children, source, target_origin, replacement_text,
      ) +
      "](" +
      rendered_destination +
      ")"
    }
    Unsupported(_message) | Recovered(_message, _) =>
      // The caller only reaches this branch when target_origin is inside the
      // unsupported/recovered node's origin. Emit the replacement text rather
      // than a diagnostic comment so the edit is not silently lost.
      replacement_text
  }
}

///|
/// Experimental local-transform rewrite for the M1 text slice.
///
/// Unchanged document gaps and sibling nodes are copied from `source` by origin;
/// the block containing `target_origin` is re-rendered with `replacement_text`.
/// The target origin must come from the supplied IR, for example from `origin`,
/// `content_origin`, or `destination_origin`; `MarkdownIROrigin` construction is
/// intentionally not public while the rewrite contract is experimental. This
/// intentionally demonstrates local rewrite semantics without promoting CST
/// trivia into MarkdownIR.
pub fn experimental_markdown_ir_local_transform_rewrite(
  ir : MarkdownIR,
  source : String,
  target_origin~ : MarkdownIROrigin,
  replacement_text~ : String,
) -> String {
  if ir.origin().contains(target_origin) {
    local_transform_render(ir, source, target_origin, replacement_text)
  } else {
    experimental_markdown_ir_preserve_rewrite(ir, source)
  }
}
