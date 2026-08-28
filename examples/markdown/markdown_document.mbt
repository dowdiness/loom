///|
/// A source-aware Markdown document from one complete parser snapshot.
///
/// The document owns the source text, syntax snapshot, and diagnostics that
/// were produced together. It does not lower MarkdownIR until `semantic_read`
/// is requested.
pub struct MarkdownDocument {
  priv source_id : @core.SourceId
  priv source : String
  priv syntax : @seam.SyntaxNode
  priv diagnostics : @core.DiagnosticSet
  priv extensions : MarkdownExtensions
}

///|
/// Parse one source snapshot into an owning source-aware document.
///
/// Lowering uses CommonMark semantics by default. Pass `extensions` to opt in
/// to supported semantic extensions for this document's reads. Lexing failures
/// propagate with the same error behavior as `parse_cst`.
pub fn parse_document(
  source_id : @core.SourceId,
  source : String,
  extensions? : MarkdownExtensions = MarkdownExtensions::none(),
) -> MarkdownDocument raise {
  let (cst, diagnostics) = parse_cst(source_id, source)
  {
    source_id,
    source,
    syntax: @seam.SyntaxNode::from_cst(cst),
    diagnostics,
    extensions,
  }
}

///|
/// Build a document from one parser-owned complete snapshot.
fn markdown_document_from_snapshot(
  source_id : @core.SourceId,
  snapshot : @loom.ParseSnapshot[Block],
) -> MarkdownDocument {
  {
    source_id,
    source: snapshot.source,
    syntax: snapshot.syntax,
    diagnostics: snapshot.diagnostics.copy(),
    extensions: MarkdownExtensions::none(),
  }
}

///|
pub fn MarkdownDocument::source_id(self : MarkdownDocument) -> @core.SourceId {
  self.source_id
}

///|
pub fn MarkdownDocument::source(self : MarkdownDocument) -> String {
  self.source
}

///|
pub fn MarkdownDocument::diagnostics(
  self : MarkdownDocument,
) -> @core.DiagnosticSet {
  self.diagnostics.copy()
}

///|
/// Lower this document exactly once into a detached semantic read.
///
/// The returned read keeps the source facts needed by source-aware adapters;
/// it remains valid after this document and its parser no longer exist.
pub fn MarkdownDocument::semantic_read(
  self : MarkdownDocument,
) -> MarkdownSemanticRead {
  let lowering_diagnostics = self.diagnostics.copy()
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    self.source_id,
    self.syntax,
    lowering_diagnostics,
    extensions=self.extensions,
  )
  { document: self, ir }
}

///|
/// One detached semantic read of a source-aware Markdown document.
pub struct MarkdownSemanticRead {
  priv document : MarkdownDocument
  priv ir : MarkdownIR
}

///|
pub fn MarkdownSemanticRead::ir(self : MarkdownSemanticRead) -> MarkdownIR {
  self.ir
}

///|
/// Return a read-bound root node.
pub fn MarkdownSemanticRead::root(
  self : MarkdownSemanticRead,
) -> MarkdownSemanticReadNode {
  { read: self, node: self.ir }
}

///|
/// A read-bound, opaque semantic node.
pub struct MarkdownSemanticReadNode {
  priv read : MarkdownSemanticRead
  priv node : MarkdownIR
}

///|
pub fn MarkdownSemanticReadNode::view(
  self : MarkdownSemanticReadNode,
) -> MarkdownIRView {
  self.node.view()
}

///|
pub fn MarkdownSemanticReadNode::origin(
  self : MarkdownSemanticReadNode,
) -> MarkdownIROrigin {
  self.node.origin()
}

///|
pub fn MarkdownSemanticReadNode::children(
  self : MarkdownSemanticReadNode,
) -> Array[MarkdownSemanticReadNode] {
  self.node.children().map(child => { read: self.read, node: child })
}

///|
/// Select one source-owned semantic region from this read-bound node.
pub fn MarkdownSemanticReadNode::selection(
  self : MarkdownSemanticReadNode,
  kind~ : MarkdownSemanticSelectionKind,
) -> MarkdownSemanticSelection? {
  match markdown_semantic_selection_origin(self.node, kind) {
    Some(origin) => Some({ read: self.read, origin })
    None => None
  }
}

///|
/// The semantic region a source-aware consumer may rewrite.
pub(all) enum MarkdownSemanticSelectionKind {
  WholeNode
  Content
  Destination
  Title
  AutolinkDisplay
} derive(Eq, Debug)

///|
/// An opaque source selection retained from one `MarkdownSemanticRead`.
pub struct MarkdownSemanticSelection {
  priv read : MarkdownSemanticRead
  priv origin : MarkdownIROrigin
}

///|
fn markdown_semantic_selection_origin(
  node : MarkdownIR,
  kind : MarkdownSemanticSelectionKind,
) -> MarkdownIROrigin? {
  match kind {
    WholeNode => Some(node.origin())
    Content =>
      match node.view() {
        Link(..) | Image(..) => node.label_origin()
        _ => node.content_origin()
      }
    Destination => node.destination_origin()
    Title =>
      match node.view() {
        Link(surface~, ..) => surface.title_origin
        Image(surface~, ..) => surface.title_origin
        _ => None
      }
    AutolinkDisplay =>
      match node.view() {
        Autolink(label_origin~, ..) => label_origin
        _ => None
      }
  }
}

///|
/// Convert a detached read to the legacy editor-facing Block projection.
pub fn markdown_semantic_read_to_block(read : MarkdownSemanticRead) -> Block {
  markdown_ir_to_block_with_source(read.ir, Some(read.document.source))
}

///|
/// Convert a detached read to mdast-shaped JSON with unist positions.
pub fn markdown_semantic_read_to_mdast_json_with_positions(
  read : MarkdownSemanticRead,
) -> Json {
  markdown_ir_to_mdast_json(
    read.ir,
    Some({
      line_index: @core.LineIndex::new(read.document.source),
      source: read.document.source,
    }),
  )
}

///|
/// Preserve the exact source spelling represented by a detached read.
pub fn markdown_semantic_read_preserve_rewrite(
  read : MarkdownSemanticRead,
) -> String {
  experimental_markdown_ir_preserve_rewrite(read.ir, read.document.source)
}

///|
/// Rewrite a source-owned selection without accepting a free origin.
pub fn markdown_semantic_read_local_transform_rewrite(
  selection : MarkdownSemanticSelection,
  replacement_text~ : String,
) -> String {
  experimental_markdown_ir_local_transform_rewrite(
    selection.read.ir,
    selection.read.document.source,
    target_origin=selection.origin,
    replacement_text~,
  )
}
