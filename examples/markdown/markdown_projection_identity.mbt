///|
priv enum MarkdownSemanticKey {
  Heading(Int)
  Paragraph
  UnorderedListItem(Bool)
  OrderedListItem(Bool)
  CodeBlock(String)
  Text
  InlineCode
  LinkLabel
  LinkDestination(String)
} derive(Eq, Debug)

///|
priv struct MarkdownNodeId {
  value : String
} derive(Eq, Debug)

///|
priv struct MarkdownIdentityLeaf {
  anchor : MarkdownIROrigin
  key : MarkdownSemanticKey
} derive(Eq, Debug)

///|
fn MarkdownIdentityLeaf::new(
  anchor : MarkdownIROrigin,
  key : MarkdownSemanticKey,
) -> MarkdownIdentityLeaf {
  { anchor, key }
}

///|
fn MarkdownIdentityLeaf::projection_leaf(
  self : MarkdownIdentityLeaf,
) -> @projection.ProjectionLeaf {
  @projection.ProjectionLeaf::new(
    self.anchor.start(),
    self.anchor.end(),
    self.key.projection_key(),
  )
}

///|
fn append_key_component(buf : StringBuilder, component : String) -> Unit {
  buf.write_string(component.length().to_string())
  buf.write_string(":")
  buf.write_string(component)
}

///|
fn MarkdownSemanticKey::projection_key(self : MarkdownSemanticKey) -> String {
  let buf = StringBuilder::new()
  match self {
    Heading(depth) => {
      append_key_component(buf, "Heading")
      append_key_component(buf, depth.to_string())
    }
    Paragraph => append_key_component(buf, "Paragraph")
    UnorderedListItem(spread) => {
      append_key_component(buf, "UnorderedListItem")
      append_key_component(buf, spread.to_string())
    }
    OrderedListItem(spread) => {
      append_key_component(buf, "OrderedListItem")
      append_key_component(buf, spread.to_string())
    }
    CodeBlock(language) => {
      append_key_component(buf, "CodeBlock")
      append_key_component(buf, language)
    }
    Text => append_key_component(buf, "Text")
    InlineCode => append_key_component(buf, "InlineCode")
    LinkLabel => append_key_component(buf, "LinkLabel")
    LinkDestination(destination) => {
      append_key_component(buf, "LinkDestination")
      append_key_component(buf, destination)
    }
  }
  buf.to_string()
}

///|
fn normalized_link_label_fingerprint(children : Array[MarkdownIR]) -> String {
  let buf = StringBuilder::new()
  for child in children {
    append_normalized_link_label_node(buf, child)
  }
  buf.to_string()
}

///|
fn append_normalized_link_label_node(
  buf : StringBuilder,
  ir : MarkdownIR,
) -> Unit {
  match ir.node {
    Bold(children, _) | Italic(children, _) =>
      for child in children {
        append_normalized_link_label_node(buf, child)
      }
    _ => append_key_component(buf, normalized_link_label_node_fingerprint(ir))
  }
}

///|
fn normalized_link_label_node_fingerprint(ir : MarkdownIR) -> String {
  let buf = StringBuilder::new()
  match ir.node {
    Text(value) => {
      append_key_component(buf, "Text")
      append_key_component(buf, value)
    }
    InlineCode(value, _) => {
      append_key_component(buf, "InlineCode")
      append_key_component(buf, value)
    }
    HardBreak(_) => append_key_component(buf, "HardBreak")
    Link(children, destination, _, _) => {
      append_key_component(buf, "Link")
      append_key_component(buf, destination)
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    Unsupported(message) => {
      append_key_component(buf, "Unsupported")
      append_key_component(buf, message)
    }
    Raw(value, _) => {
      append_key_component(buf, "Raw")
      append_key_component(buf, value)
    }
    Recovered(message, _) => {
      append_key_component(buf, "Recovered")
      append_key_component(buf, message)
    }
    Document(children) => {
      append_key_component(buf, "Document")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    Heading(depth, children, _) => {
      append_key_component(buf, "Heading")
      append_key_component(buf, depth.to_string())
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    Paragraph(children, _) => {
      append_key_component(buf, "Paragraph")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    BlockQuote(children) => {
      append_key_component(buf, "BlockQuote")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    UnorderedList(children, _, _) => {
      append_key_component(buf, "UnorderedList")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    OrderedList(children, _, _) => {
      append_key_component(buf, "OrderedList")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    ListItem(children, _, _, _) => {
      append_key_component(buf, "ListItem")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    OrderedListItem(children, _, _, _) => {
      append_key_component(buf, "OrderedListItem")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    CodeBlock(language, value, _) => {
      append_key_component(buf, "CodeBlock")
      append_key_component(buf, language)
      append_key_component(buf, value)
    }
    HtmlBlock(value, _) => {
      append_key_component(buf, "HtmlBlock")
      append_key_component(buf, value)
    }
    ThematicBreak => append_key_component(buf, "ThematicBreak")
    Bold(_, _) | Italic(_, _) =>
      abort("formatting wrapper must be erased before fingerprinting")
  }
  buf.to_string()
}

///|
fn markdown_ir_identity_leaves(ir : MarkdownIR) -> Array[MarkdownIdentityLeaf] {
  let leaves = []
  collect_markdown_ir_identity_leaves(ir, leaves)
  leaves
}

///|
fn append_markdown_identity_leaf(
  leaves : Array[MarkdownIdentityLeaf],
  origin : MarkdownIROrigin?,
  key : MarkdownSemanticKey,
) -> Unit {
  match origin {
    Some(anchor) => leaves.push(MarkdownIdentityLeaf::new(anchor, key))
    None => ()
  }
}

///|
fn collect_markdown_ir_identity_leaves(
  ir : MarkdownIR,
  leaves : Array[MarkdownIdentityLeaf],
) -> Unit {
  match ir.node {
    Document(children) =>
      collect_markdown_ir_identity_children(children, leaves)
    Heading(depth, children, content_origin) => {
      append_markdown_identity_leaf(leaves, content_origin, Heading(depth))
      collect_markdown_ir_identity_children(children, leaves)
    }
    Paragraph(children, content_origin) => {
      append_markdown_identity_leaf(leaves, content_origin, Paragraph)
      collect_markdown_ir_identity_children(children, leaves)
    }
    BlockQuote(children)
    | UnorderedList(children, _, _)
    | OrderedList(children, _, _) =>
      collect_markdown_ir_identity_children(children, leaves)
    ListItem(children, spread, content_origin, _) => {
      append_markdown_identity_leaf(
        leaves,
        content_origin,
        UnorderedListItem(spread),
      )
      collect_markdown_ir_identity_children(children, leaves)
    }
    OrderedListItem(children, spread, content_origin, _) => {
      append_markdown_identity_leaf(
        leaves,
        content_origin,
        OrderedListItem(spread),
      )
      collect_markdown_ir_identity_children(children, leaves)
    }
    CodeBlock(language, _, content_origin) =>
      append_markdown_identity_leaf(leaves, content_origin, CodeBlock(language))
    HtmlBlock(_, _)
    | ThematicBreak
    | HardBreak(_)
    | Raw(_, _)
    | Recovered(_, _)
    | Unsupported(_) => ()
    Text(_) => leaves.push(MarkdownIdentityLeaf::new(ir.origin, Text))
    Bold(children, _) | Italic(children, _) =>
      collect_markdown_ir_identity_children(children, leaves)
    InlineCode(_, content_origin) =>
      append_markdown_identity_leaf(leaves, content_origin, InlineCode)
    Link(children, destination, label_origin, destination_origin) => {
      append_markdown_identity_leaf(leaves, label_origin, LinkLabel)
      append_markdown_identity_leaf(
        leaves,
        destination_origin,
        LinkDestination(destination),
      )
      collect_markdown_ir_identity_children(children, leaves)
    }
  }
}

///|
fn collect_markdown_ir_identity_children(
  children : Array[MarkdownIR],
  leaves : Array[MarkdownIdentityLeaf],
) -> Unit {
  for child in children {
    collect_markdown_ir_identity_leaves(child, leaves)
  }
}
