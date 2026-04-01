///|
fn inline_text(inlines : Array[Inline]) -> String {
  let buf = StringBuilder::new()
  for item in inlines {
    match item {
      Text(s) => buf.write_string(s)
      Bold(children) => {
        buf.write_string("**")
        buf.write_string(inline_text(children))
        buf.write_string("**")
      }
      Italic(children) => {
        buf.write_string("*")
        buf.write_string(inline_text(children))
        buf.write_string("*")
      }
      InlineCode(s) => {
        buf.write_string("`")
        buf.write_string(s)
        buf.write_string("`")
      }
      Link(children, url) => {
        buf.write_string("[")
        buf.write_string(inline_text(children))
        buf.write_string("](")
        buf.write_string(url)
        buf.write_string(")")
      }
      Error(msg) => buf.write_string("<error: " + msg + ">")
    }
  }
  buf.to_string()
}

///|
pub impl @core.TreeNode for Block with children(self) {
  match self {
    Document(blocks) | UnorderedList(blocks) => blocks
    _ => []
  }
}

///|
pub impl @core.TreeNode for Block with same_kind(self, other) {
  match (self, other) {
    (Document(_), Document(_)) => true
    (Heading(a, _), Heading(b, _)) => a == b
    (Paragraph(_), Paragraph(_)) => true
    (UnorderedList(_), UnorderedList(_)) => true
    (ListItem(_), ListItem(_)) => true
    (CodeBlock(a, _), CodeBlock(b, _)) => a == b
    (Error(_), Error(_)) => true
    _ => false
  }
}

///|
pub impl @core.Renderable for Block with kind_tag(self) {
  match self {
    Document(_) => "Document"
    Heading(n, _) => "H" + n.to_string()
    Paragraph(_) => "Paragraph"
    UnorderedList(_) => "List"
    ListItem(_) => "ListItem"
    CodeBlock(info, _) =>
      if info.length() > 0 {
        "Code(" + info + ")"
      } else {
        "Code"
      }
    Error(_) => "Error"
  }
}

///|
pub impl @core.Renderable for Block with label(self) {
  match self {
    Document(blocks) => "[" + blocks.length().to_string() + " blocks]"
    Heading(_, inlines) => inline_text(inlines)
    Paragraph(inlines) => {
      let text = inline_text(inlines)
      if text.length() > 40 {
        text[:40].to_string() + "..."
      } else {
        text
      }
    }
    UnorderedList(items) => "[" + items.length().to_string() + " items]"
    ListItem(inlines) => inline_text(inlines)
    CodeBlock(_, code) =>
      if code.length() > 30 {
        code[:30].to_string() + "..."
      } else {
        code
      }
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl @core.Renderable for Block with placeholder(_self) {
  "..."
}

///|
pub impl @core.Renderable for Block with unparse(self) {
  match self {
    Document(blocks) =>
      blocks.map(fn(b) { @core.Renderable::unparse(b) }).join("\n")
    Heading(n, inlines) => "#".repeat(n) + " " + inline_text(inlines)
    Paragraph(inlines) => inline_text(inlines)
    UnorderedList(items) =>
      items.map(fn(b) { @core.Renderable::unparse(b) }).join("\n")
    ListItem(inlines) => "- " + inline_text(inlines)
    CodeBlock(info, code) => "```" + info + "\n" + code + "\n```"
    Error(msg) => "<error: " + msg + ">"
  }
}

///|
pub impl @core.TreeNode for Inline with children(self) {
  match self {
    Bold(children) | Italic(children) | Link(children, _) => children
    _ => []
  }
}

///|
pub impl @core.TreeNode for Inline with same_kind(self, other) {
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
pub impl @core.Renderable for Inline with kind_tag(self) {
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
pub impl @core.Renderable for Inline with label(self) {
  match self {
    Text(s) => if s.length() > 30 { s[:30].to_string() + "..." } else { s }
    Bold(children) => "**" + inline_text(children) + "**"
    Italic(children) => "*" + inline_text(children) + "*"
    InlineCode(s) => "`" + s + "`"
    Link(children, url) => "[" + inline_text(children) + "](" + url + ")"
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl @core.Renderable for Inline with placeholder(_self) {
  "..."
}

///|
pub impl @core.Renderable for Inline with unparse(self) {
  inline_text([self])
}
