///|
/// Serialize inline AST back to Markdown source text.
/// Uses a shared StringBuilder to avoid intermediate string allocations
/// at each nesting level (bold inside link, etc.).
fn inline_text_to(inlines : Array[Inline], buf : StringBuilder) -> Unit {
  for item in inlines {
    match item {
      Text(s) => buf.write_string(s)
      Bold(children) => {
        buf.write_string("**")
        inline_text_to(children, buf)
        buf.write_string("**")
      }
      Italic(children) => {
        buf.write_string("*")
        inline_text_to(children, buf)
        buf.write_string("*")
      }
      InlineCode(s) => {
        buf.write_string("`")
        buf.write_string(s)
        buf.write_string("`")
      }
      Link(children, url) => {
        buf.write_string("[")
        inline_text_to(children, buf)
        buf.write_string("](")
        buf.write_string(url)
        buf.write_string(")")
      }
      Error(msg) => buf.write_string("<error: " + msg + ">")
    }
  }
}

///|
fn inline_text(inlines : Array[Inline]) -> String {
  let buf = StringBuilder::new()
  inline_text_to(inlines, buf)
  buf.to_string()
}

///|
fn ordered_marker_text(
  marker : OrderedListMarker?,
  fallback_start : Int,
  fallback_delimiter : OrderedListDelimiter,
) -> String {
  match marker {
    Some(marker) => marker.text()
    None => fallback_start.to_string() + fallback_delimiter.text()
  }
}

///|
pub impl @core.TreeNode for Block with fn children(self) {
  match self {
    Document(blocks) | UnorderedList(blocks) | OrderedList(blocks, _) => blocks
    _ => []
  }
}

///|
pub impl @core.TreeNode for Block with fn same_kind(self, other) {
  match (self, other) {
    (Document(_), Document(_)) => true
    (Heading(a, _), Heading(b, _)) => a == b
    (Paragraph(_), Paragraph(_)) => true
    (UnorderedList(_), UnorderedList(_)) => true
    (OrderedList(_, _), OrderedList(_, _)) => true
    (UnorderedListItem(_), UnorderedListItem(_)) => true
    (OrderedListItem(_, _), OrderedListItem(_, _)) => true
    (CodeBlock(a, _), CodeBlock(b, _)) => a == b
    (HtmlBlock(_), HtmlBlock(_)) => true
    (Error(_), Error(_)) => true
    _ => false
  }
}

///|
pub impl @core.Renderable for Block with fn kind_tag(self) {
  match self {
    Document(_) => "Document"
    Heading(n, _) => "H" + n.to_string()
    Paragraph(_) => "Paragraph"
    UnorderedList(_) => "List"
    OrderedList(_, _) => "OrderedList"
    UnorderedListItem(_) => "UnorderedListItem"
    OrderedListItem(_, _) => "OrderedListItem"
    CodeBlock(info, _) =>
      if info.length() > 0 {
        "Code(" + info + ")"
      } else {
        "Code"
      }
    HtmlBlock(_) => "HtmlBlock"
    Error(_) => "Error"
  }
}

///|
pub impl @core.Renderable for Block with fn label(self) {
  match self {
    Document(blocks) => "[" + blocks.length().to_string() + " blocks]"
    Heading(_, inlines) => inline_text(inlines)
    Paragraph(inlines) => {
      let text = inline_text(inlines)
      if text.length() > 40 {
        text[:40].to_owned() + "..."
      } else {
        text
      }
    }
    UnorderedList(items) | OrderedList(items, _) =>
      "[" + items.length().to_string() + " items]"
    UnorderedListItem(inlines) | OrderedListItem(inlines, _) =>
      inline_text(inlines)
    CodeBlock(_, code) =>
      if code.length() > 30 {
        code[:30].to_owned() + "..."
      } else {
        code
      }
    HtmlBlock(s) => if s.length() > 40 { s[:40].to_owned() + "..." } else { s }
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl @core.Renderable for Block with fn placeholder(_self) {
  "..."
}

///|
pub impl @core.Renderable for Block with fn unparse(self) {
  match self {
    Document(blocks) => {
      // Separate blocks with blank lines so paragraphs don't merge
      let parts = blocks.map(b => @core.Renderable::unparse(b))
      parts.join("\n\n")
    }
    Heading(n, inlines) => "#".repeat(n) + " " + inline_text(inlines)
    Paragraph(inlines) => inline_text(inlines)
    UnorderedList(items) =>
      items.map(item => @core.Renderable::unparse(item)).join("\n")
    OrderedList(items, marker) => {
      let start = match marker {
        Some(marker) => marker.start()
        None => 1
      }
      let delimiter = match marker {
        Some(marker) => marker.delimiter()
        None => Period
      }
      items
      .mapi((index, item) => {
        match item {
          OrderedListItem(inlines, item_marker) =>
            ordered_marker_text(item_marker, start + index, delimiter) +
            " " +
            inline_text(inlines)
          _ => @core.Renderable::unparse(item)
        }
      })
      .join("\n")
    }
    UnorderedListItem(inlines) => "- " + inline_text(inlines)
    OrderedListItem(inlines, marker) =>
      ordered_marker_text(marker, 1, Period) + " " + inline_text(inlines)
    CodeBlock(info, code) => {
      // Compute fence width: must be longer than any backtick run in code
      let mut max_run = 0
      let mut cur_run = 0
      for i = 0; i < code.length(); i = i + 1 {
        match code.code_unit_at(i).to_char() {
          Some('`') => {
            cur_run = cur_run + 1
            if cur_run > max_run {
              max_run = cur_run
            }
          }
          _ => cur_run = 0
        }
      }
      let fence_width = if max_run >= 3 { max_run + 1 } else { 3 }
      let fence = "`".repeat(fence_width)
      fence + info + "\n" + code + "\n" + fence
    }
    HtmlBlock(s) => s
    Error(msg) => "<error: " + msg + ">"
  }
}

///|
pub impl @core.TreeNode for Inline with fn children(self) {
  match self {
    Bold(children) | Italic(children) | Link(children, _) => children
    _ => []
  }
}

///|
pub impl @core.TreeNode for Inline with fn same_kind(self, other) {
  match (self, other) {
    (Text(_), Text(_)) => true
    (Bold(_), Bold(_)) => true
    (Italic(_), Italic(_)) => true
    (InlineCode(_), InlineCode(_)) => true
    (Link(_, _), Link(_, _)) => true
    (Error(_), Error(_)) => true
    _ => false
  }
}

///|
pub impl @core.Renderable for Inline with fn kind_tag(self) {
  match self {
    Text(_) => "Text"
    Bold(_) => "Bold"
    Italic(_) => "Italic"
    InlineCode(_) => "Code"
    Link(_, _) => "Link"
    Error(_) => "Error"
  }
}

///|
pub impl @core.Renderable for Inline with fn label(self) {
  match self {
    Text(s) => if s.length() > 30 { s[:30].to_owned() + "..." } else { s }
    Bold(children) => "**" + inline_text(children) + "**"
    Italic(children) => "*" + inline_text(children) + "*"
    InlineCode(s) => "`" + s + "`"
    Link(children, url) => "[" + inline_text(children) + "](" + url + ")"
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl @core.Renderable for Inline with fn placeholder(_self) {
  "..."
}

///|
pub impl @core.Renderable for Inline with fn unparse(self) {
  inline_text([self])
}
