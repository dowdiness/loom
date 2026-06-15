///|
/// Experimental source origin for MarkdownIR nodes.
///
/// Offsets are half-open UTF-16 code-unit source ranges, matching
/// `@seam.SyntaxNode::start` / `end`. Origins point back to the original
/// source; MarkdownIR does not copy CST tokens or trivia.
pub struct MarkdownIROrigin {
  priv start : Int
  priv end : Int
} derive(Eq, Debug)

///|
fn MarkdownIROrigin::MarkdownIROrigin(
  start~ : Int,
  end~ : Int,
) -> MarkdownIROrigin {
  guard start >= 0 && start <= end else { abort("invalid MarkdownIR origin") }
  { start, end }
}

///|
pub fn MarkdownIROrigin::start(self : MarkdownIROrigin) -> Int {
  self.start
}

///|
pub fn MarkdownIROrigin::end(self : MarkdownIROrigin) -> Int {
  self.end
}

///|
fn MarkdownIROrigin::contains(
  self : MarkdownIROrigin,
  other : MarkdownIROrigin,
) -> Bool {
  self.start <= other.start && other.end <= self.end
}

///|
priv enum MarkdownIRNode {
  Document(Array[MarkdownIR])
  Heading(Int, Array[MarkdownIR], MarkdownIROrigin?)
  Paragraph(Array[MarkdownIR], MarkdownIROrigin?)
  Text(String)
  Unsupported(String)
} derive(Eq, Debug)

///|
/// Experimental Markdown semantic IR for the M1 heading/paragraph slice.
///
/// Public construction is intentionally withheld while the IR contract is
/// experimental. Build values through `experimental_markdown_ir_from_syntax`,
/// then consume them through the experimental adapters in this file.
pub struct MarkdownIR {
  priv node : MarkdownIRNode
  priv origin : MarkdownIROrigin
} derive(Eq, Debug)

///|
fn MarkdownIR::document(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  { node: Document(children), origin }
}

///|
fn MarkdownIR::heading(
  depth : Int,
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  guard depth >= 1 && depth <= 6 else {
    abort("MarkdownIR heading depth must be in 1..6")
  }
  { node: Heading(depth, children, content_origin), origin }
}

///|
fn MarkdownIR::paragraph(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: Paragraph(children, content_origin), origin }
}

///|
fn MarkdownIR::text(value : String, origin : MarkdownIROrigin) -> MarkdownIR {
  { node: Text(value), origin }
}

///|
fn MarkdownIR::unsupported(
  message : String,
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  { node: Unsupported(message), origin }
}

///|
pub fn MarkdownIR::origin(self : MarkdownIR) -> MarkdownIROrigin {
  self.origin
}

///|
pub fn MarkdownIR::kind_tag(self : MarkdownIR) -> String {
  match self.node {
    Document(_) => "Document"
    Heading(_, _, _) => "Heading"
    Paragraph(_, _) => "Paragraph"
    Text(_) => "Text"
    Unsupported(_) => "Unsupported"
  }
}

///|
pub fn MarkdownIR::children(self : MarkdownIR) -> Array[MarkdownIR] {
  match self.node {
    Document(children) | Heading(_, children, _) | Paragraph(children, _) =>
      children.copy()
    Text(_) | Unsupported(_) => []
  }
}

///|
pub fn MarkdownIR::heading_depth(self : MarkdownIR) -> Int? {
  match self.node {
    Heading(depth, _, _) => Some(depth)
    _ => None
  }
}

///|
pub fn MarkdownIR::text_value(self : MarkdownIR) -> String? {
  match self.node {
    Text(value) => Some(value)
    _ => None
  }
}

///|
pub fn MarkdownIR::content_origin(self : MarkdownIR) -> MarkdownIROrigin? {
  match self.node {
    Heading(_, _, origin) | Paragraph(_, origin) => origin
    _ => None
  }
}

///|
fn origin_from_node(node : @seam.SyntaxNode) -> MarkdownIROrigin {
  MarkdownIROrigin(start=node.start(), end=node.end())
}

///|
fn origin_from_token(token : @seam.SyntaxToken) -> MarkdownIROrigin {
  MarkdownIROrigin(start=token.start(), end=token.end())
}

///|
fn content_origin(children : Array[MarkdownIR]) -> MarkdownIROrigin? {
  match children {
    [] => None
    [first, .. rest] => {
      let last = rest.fold(init=first, fn(_, item) { item })
      Some(
        MarkdownIROrigin(start=first.origin().start(), end=last.origin().end()),
      )
    }
  }
}

///|
fn lower_inline_element(element : @seam.SyntaxElement) -> MarkdownIR? {
  match element {
    @seam.SyntaxElement::Token(token) => {
      let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
      match token_kind {
        TextToken =>
          Some(MarkdownIR::text(token.text(), origin_from_token(token)))
        HeadingMarkerToken | NewlineToken | BlankLineToken | EofToken => None
        ErrorToken =>
          Some(
            MarkdownIR::unsupported(
              "error token: " + token.text(),
              origin_from_token(token),
            ),
          )
        _ => None
      }
    }
    @seam.SyntaxElement::Node(child) => {
      let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
      Some(
        MarkdownIR::unsupported(
          "unsupported inline node: " + child_kind.to_string(),
          origin_from_node(child),
        ),
      )
    }
  }
}

///|
fn lower_inline_children(node : @seam.SyntaxNode) -> Array[MarkdownIR] {
  node.all_children().iter().filter_map(lower_inline_element).collect()
}

///|
fn heading_depth_from_marker(node : @seam.SyntaxNode) -> Int {
  match node.direct_token_of_kind(HeadingMarkerToken.to_raw()) {
    Some(marker) => {
      let n = count_hashes(marker.text(), 0)
      if n >= 1 && n <= 6 {
        n
      } else {
        1
      }
    }
    None => 1
  }
}

///|
fn lower_document_child(
  child : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> MarkdownIR? {
  let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
  match child_kind {
    HeadingNode | ParagraphNode => Some(recurse(child))
    ErrorNode =>
      Some(MarkdownIR::unsupported("parse error", origin_from_node(child)))
    _ =>
      Some(
        MarkdownIR::unsupported(
          "unsupported block node: " + child_kind.to_string(),
          origin_from_node(child),
        ),
      )
  }
}

///|
/// Experimental CstFold algebra for the M1 MarkdownIR slice.
///
/// Covers documents, headings, paragraphs, and text. Other Markdown constructs
/// lower to explicit `Unsupported` IR nodes instead of cloned CST token piles.
fn experimental_markdown_ir_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> MarkdownIR {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    DocumentNode => {
      let children : Array[MarkdownIR] = node
        .children()
        .iter()
        .filter_map(child => lower_document_child(child, recurse))
        .collect()
      MarkdownIR::document(children, origin_from_node(node))
    }
    HeadingNode => {
      let children = lower_inline_children(node)
      MarkdownIR::heading(
        heading_depth_from_marker(node),
        children,
        origin_from_node(node),
        content_origin(children),
      )
    }
    ParagraphNode => {
      let children = lower_inline_children(node)
      MarkdownIR::paragraph(
        children,
        origin_from_node(node),
        content_origin(children),
      )
    }
    ErrorNode => MarkdownIR::unsupported("parse error", origin_from_node(node))
    _ =>
      MarkdownIR::unsupported(
        "unsupported node: " + kind.to_string(),
        origin_from_node(node),
      )
  }
}

///|
/// Experimental `SyntaxNode -> MarkdownIR` lowering for the M1 slice.
pub fn experimental_markdown_ir_from_syntax(
  root : @seam.SyntaxNode,
) -> MarkdownIR {
  let fold = @core.CstFold::new(experimental_markdown_ir_fold_node)
  fold.fold(root)
}

///|
fn experimental_markdown_ir_to_inline(ir : MarkdownIR) -> Inline {
  match ir.node {
    Text(value) => Inline::Text(value)
    Unsupported(message) => Inline::Error(message)
    Document(_) => Inline::Error("expected inline MarkdownIR, got document")
    Heading(_, _, _) => Inline::Error("expected inline MarkdownIR, got heading")
    Paragraph(_, _) =>
      Inline::Error("expected inline MarkdownIR, got paragraph")
  }
}

///|
fn ir_children_to_inlines(children : Array[MarkdownIR]) -> Array[Inline] {
  children.map(experimental_markdown_ir_to_inline)
}

///|
pub fn experimental_markdown_ir_to_block(ir : MarkdownIR) -> Block {
  match ir.node {
    Document(children) =>
      Block::Document(children.map(experimental_markdown_ir_to_block))
    Heading(depth, children, _) =>
      Block::Heading(depth, ir_children_to_inlines(children))
    Paragraph(children, _) => Block::Paragraph(ir_children_to_inlines(children))
    Text(_) => Block::Error("expected block MarkdownIR, got text")
    Unsupported(message) => Block::Error(message)
  }
}

///|
pub fn experimental_markdown_ir_to_mdast_json(ir : MarkdownIR) -> Json {
  match ir.node {
    Document(children) =>
      {
        "type": "root",
        "children": children.map(experimental_markdown_ir_to_mdast_json),
      }
    Heading(depth, children, _) =>
      {
        "type": "heading",
        "depth": depth,
        "children": children.map(experimental_markdown_ir_to_mdast_json),
      }
    Paragraph(children, _) =>
      {
        "type": "paragraph",
        "children": children.map(experimental_markdown_ir_to_mdast_json),
      }
    Text(value) => { "type": "text", "value": value }
    Unsupported(message) => { "type": "mdastUnsupported", "value": message }
  }
}

///|
fn source_slice_between(source : String, start : Int, end : Int) -> String {
  guard start >= 0 && start <= end && end <= source.length() else { return "" }
  source[start:end].to_owned()
}

///|
fn source_slice(source : String, origin : MarkdownIROrigin) -> String {
  source_slice_between(source, origin.start(), origin.end())
}

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
  if source_slice(source, origin).has_suffix("\n") {
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
      ignore(
        children.fold(init=first.origin().start(), fn(cursor, child) {
          let child_origin = child.origin()
          buf.write_string(
            source_slice_between(source, cursor, child_origin.start()),
          )
          match child.node {
            Text(value) =>
              if child_origin == target_origin {
                buf.write_string(replacement_text)
              } else {
                buf.write_string(value)
              }
            _ => buf.write_string(source_slice(source, child_origin))
          }
          child_origin.end()
        }),
      )
      buf.to_string()
    }
  }
}

///|
fn local_transform_render(
  ir : MarkdownIR,
  source : String,
  target_origin : MarkdownIROrigin,
  replacement_text : String,
) -> String {
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
    Heading(depth, children, _) =>
      "#".repeat(depth) +
      " " +
      local_transform_inline_text(
        children, source, target_origin, replacement_text,
      ) +
      original_block_trailing_newline(source, ir.origin())
    Paragraph(children, _) =>
      local_transform_inline_text(
        children, source, target_origin, replacement_text,
      ) +
      original_block_trailing_newline(source, ir.origin())
    Text(value) =>
      if ir.origin() == target_origin {
        replacement_text
      } else {
        value
      }
    Unsupported(message) => "<!-- unsupported MarkdownIR: " + message + " -->"
  }
}

///|
/// Experimental local-transform rewrite for the M1 text slice.
///
/// Unchanged document gaps and sibling nodes are copied from `source` by origin;
/// the block containing `target_origin` is re-rendered with `replacement_text`.
/// This intentionally demonstrates local rewrite semantics without promoting
/// CST trivia into MarkdownIR.
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

///|
fn canonical_inline_text(children : Array[MarkdownIR]) -> String {
  children.map(experimental_markdown_ir_canonical_format).join("")
}

///|
pub fn experimental_markdown_ir_canonical_format(ir : MarkdownIR) -> String {
  match ir.node {
    Document(children) =>
      children.map(experimental_markdown_ir_canonical_format).join("\n\n")
    Heading(depth, children, _) =>
      "#".repeat(depth) + " " + canonical_inline_text(children)
    Paragraph(children, _) => canonical_inline_text(children)
    Text(value) => value
    Unsupported(message) => "<!-- unsupported MarkdownIR: " + message + " -->"
  }
}
