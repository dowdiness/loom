// PROTOTYPE — relative-origin MarkdownIR block decomposition.
//
// Question: can one top-level CST block be lowered with block-relative owned
// origins, then placed at its current document offset, while preserving the
// exact MarkdownIR produced by the existing whole-document lowering?
//
// This file is intentionally private and lives only on the prototype branch.
// Recovery diagnostics are not rebased yet; the prototype targets valid CSTs.

///|
#warnings("-unused_value")
priv struct PrototypeLocalRawBlock {
  ir : MarkdownIR
} derive(Eq)

///|
#warnings("-unused_value-unused_field")
priv struct PrototypeDefinitionSnapshot {
  table : LinkReferenceDefinitionTable
  signature : String
}

///|
#warnings("-unused_value")
impl Eq for PrototypeDefinitionSnapshot with fn equal(self, other) {
  self.signature == other.signature
}

///|
fn prototype_signature_write_string(
  out : StringBuilder,
  value : String,
) -> Unit {
  out.write_string(value.length().to_string())
  out.write_char(':')
  out.write_string(value)
  out.write_char(';')
}

///|
fn prototype_signature_write_origin(
  out : StringBuilder,
  origin : MarkdownIROrigin,
) -> Unit {
  out.write_string(origin.start().to_string())
  out.write_char(':')
  out.write_string(origin.end().to_string())
  out.write_char(';')
}

///|
fn prototype_signature_write_optional_origin(
  out : StringBuilder,
  origin : MarkdownIROrigin?,
) -> Unit {
  match origin {
    Some(value) => {
      out.write_char('1')
      prototype_signature_write_origin(out, value)
    }
    None => out.write_char('0')
  }
}

///|
fn prototype_signature_write_optional_string(
  out : StringBuilder,
  value : String?,
) -> Unit {
  match value {
    Some(text) => {
      out.write_char('1')
      prototype_signature_write_string(out, text)
    }
    None => out.write_char('0')
  }
}

///|
fn prototype_definition_signature(
  table : LinkReferenceDefinitionTable,
) -> String {
  let labels : Array[String] = []
  for label, _ in table.entries {
    labels.push(label)
  }
  labels.sort_by((left, right) => left.compare(right))
  let out = StringBuilder::StringBuilder()
  for label in labels {
    let definition = table.lookup(label).unwrap()
    prototype_signature_write_string(out, definition.normalized_label)
    prototype_signature_write_string(out, definition.destination_value)
    prototype_signature_write_optional_string(out, definition.title_value)
    prototype_signature_write_origin(out, definition.definition_origin)
    prototype_signature_write_origin(out, definition.label_value_origin)
    prototype_signature_write_origin(out, definition.destination_value_origin)
    prototype_signature_write_optional_origin(
      out,
      definition.title_value_origin,
    )
  }
  out.to_string()
}

///|
#warnings("-unused_value")
fn prototype_definition_snapshot(
  root : @seam.SyntaxNode,
) -> PrototypeDefinitionSnapshot {
  let table = collect_link_reference_definitions(syntax_root(root))
  { table, signature: prototype_definition_signature(table) }
}

///|
fn prototype_shift_origin(
  origin : MarkdownIROrigin,
  base : Int,
) -> MarkdownIROrigin {
  MarkdownIROrigin(start=origin.start() + base, end=origin.end() + base)
}

///|
fn prototype_shift_optional_origin(
  origin : MarkdownIROrigin?,
  base : Int,
) -> MarkdownIROrigin? {
  origin.map(value => prototype_shift_origin(value, base))
}

///|
fn prototype_place_link_surface(
  surface : LinkSurface,
  base : Int,
) -> LinkSurface {
  let destination_is_local = surface.form is InlineLinkForm
  {
    form: surface.form,
    label_origin: prototype_shift_optional_origin(surface.label_origin, base),
    reference_label_origin: prototype_shift_optional_origin(
      surface.reference_label_origin,
      base,
    ),
    destination_origin: if destination_is_local {
      prototype_shift_optional_origin(surface.destination_origin, base)
    } else {
      surface.destination_origin
    },
    title_origin: if destination_is_local {
      prototype_shift_optional_origin(surface.title_origin, base)
    } else {
      surface.title_origin
    },
  }
}

///|
fn prototype_place_markdown_ir(ir : MarkdownIR, base : Int) -> MarkdownIR {
  let origin = prototype_shift_origin(ir.origin, base)
  let node : MarkdownIRNode = match ir.node {
    Document(children) =>
      Document(children.map(child => prototype_place_markdown_ir(child, base)))
    Heading(depth, children, content_origin) =>
      Heading(
        depth,
        children.map(child => prototype_place_markdown_ir(child, base)),
        prototype_shift_optional_origin(content_origin, base),
      )
    Paragraph(children, content_origin) =>
      Paragraph(
        children.map(child => prototype_place_markdown_ir(child, base)),
        prototype_shift_optional_origin(content_origin, base),
      )
    BlockQuote(children) =>
      BlockQuote(
        children.map(child => prototype_place_markdown_ir(child, base)),
      )
    UnorderedList(children, spread, marker) =>
      UnorderedList(
        children.map(child => prototype_place_markdown_ir(child, base)),
        spread,
        marker,
      )
    OrderedList(children, spread, marker) =>
      OrderedList(
        children.map(child => prototype_place_markdown_ir(child, base)),
        spread,
        marker,
      )
    ListItem(children, spread, content_origin, marker) =>
      ListItem(
        children.map(child => prototype_place_markdown_ir(child, base)),
        spread,
        prototype_shift_optional_origin(content_origin, base),
        marker,
      )
    OrderedListItem(children, spread, content_origin, marker) =>
      OrderedListItem(
        children.map(child => prototype_place_markdown_ir(child, base)),
        spread,
        prototype_shift_optional_origin(content_origin, base),
        marker,
      )
    CodeBlock(info, value, content_origin) =>
      CodeBlock(
        info,
        value,
        prototype_shift_optional_origin(content_origin, base),
      )
    HtmlBlock(value, content_origin) =>
      HtmlBlock(value, prototype_shift_optional_origin(content_origin, base))
    ThematicBreak => ThematicBreak
    Text(value) => Text(value)
    Bold(children, content_origin) =>
      Bold(
        children.map(child => prototype_place_markdown_ir(child, base)),
        prototype_shift_optional_origin(content_origin, base),
      )
    Italic(children, content_origin) =>
      Italic(
        children.map(child => prototype_place_markdown_ir(child, base)),
        prototype_shift_optional_origin(content_origin, base),
      )
    InlineCode(value, content_origin) =>
      InlineCode(value, prototype_shift_optional_origin(content_origin, base))
    Link(children, destination, title, surface) =>
      Link(
        children.map(child => prototype_place_markdown_ir(child, base)),
        destination,
        title,
        prototype_place_link_surface(surface, base),
      )
    Image(children, destination, title, surface) =>
      Image(
        children.map(child => prototype_place_markdown_ir(child, base)),
        destination,
        title,
        prototype_place_link_surface(surface, base),
      )
    Autolink(kind, display, destination, display_origin, destination_origin) =>
      Autolink(
        kind,
        display,
        destination,
        prototype_shift_optional_origin(display_origin, base),
        prototype_shift_optional_origin(destination_origin, base),
      )
    InlineHtml(value, content_origin) =>
      InlineHtml(value, prototype_shift_optional_origin(content_origin, base))
    SoftBreak(content_origin) =>
      SoftBreak(prototype_shift_optional_origin(content_origin, base))
    HardBreak(surface, content_origin) =>
      HardBreak(surface, prototype_shift_optional_origin(content_origin, base))
    Unsupported(message) => Unsupported(message)
    Raw(value, diagnostics) => Raw(value, diagnostics)
    Recovered(message, diagnostics) => Recovered(message, diagnostics)
  }
  { node, origin }
}

///|
fn prototype_lower_local_raw_block(
  source_id : @core.SourceId,
  cst : @seam.CstNode,
  reference_definitions : LinkReferenceDefinitionTable,
) -> PrototypeLocalRawBlock {
  let root = @seam.SyntaxNode::from_cst(cst)
  let source = root.text()
  let context : MarkdownIRLoweringContext = {
    source_id,
    source,
    reference_definitions,
    diagnostics_in_origin: _ => [],
  }
  fn lower(node : @seam.SyntaxNode) -> MarkdownIR {
    experimental_markdown_ir_fold_node(node, lower, context)
  }
  { ir: decode_markdown_ir_text_entities(lower(root), source) }
}

///|
fn prototype_is_document_block(node : @seam.SyntaxNode) -> Bool {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    HeadingNode
    | ParagraphNode
    | BlockQuoteNode
    | UnorderedListNode
    | OrderedListNode
    | CodeBlockNode
    | HtmlBlockNode
    | ThematicBreakNode
    | ErrorNode => true
    _ => false
  }
}

///|
#warnings("-unused_value")
fn prototype_markdown_ir_from_syntax(
  source_id : @core.SourceId,
  root : @seam.SyntaxNode,
) -> MarkdownIR {
  let document_root = syntax_root(root)
  let reference_definitions = collect_link_reference_definitions(document_root)
  let children : Array[MarkdownIR] = []
  for child in document_root.children() {
    if prototype_is_document_block(child) {
      let raw_block = prototype_lower_local_raw_block(
        source_id,
        child.cst_node(),
        reference_definitions,
      )
      children.push(prototype_place_markdown_ir(raw_block.ir, child.start()))
    }
  }
  MarkdownIR::document(children, origin_from_node(document_root))
}
