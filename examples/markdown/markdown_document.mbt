///|
/// A detached Markdown document from one complete parser snapshot.
///
/// The document owns source text, diagnostics, and its complete semantic root.
/// It does not retain a parser runtime or require one for later reads.
pub struct MarkdownDocument {
  priv source_id : @core.SourceId
  priv source : String
  priv diagnostics : @core.DiagnosticSet
  priv ir : MarkdownIR
}

///|
/// Parse one source snapshot into a detached semantic document.
///
/// Malformed Markdown is represented by recovered nodes and diagnostics. A
/// raised `Failure` indicates an internal parser or tree-construction defect.
pub fn parse(
  source : String,
  source_id? : @core.SourceId = @core.SourceId("markdown"),
  extensions? : MarkdownExtensions = MarkdownExtensions::none(),
) -> MarkdownDocument raise Failure {
  let (cst, parse_diagnostics) = parse_cst(source_id, source) catch {
    Failure::Failure(_) as failure => raise failure
    error => fail("internal Markdown parse failure: " + @debug.to_string(error))
  }
  let diagnostics = parse_diagnostics.copy()
  let ir = experimental_markdown_ir_from_syntax_core(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    source,
    Some(diagnostics),
    extensions,
  )
  { source_id, source, diagnostics, ir }
}

///|
/// Build a document from one parser-owned complete snapshot.
fn markdown_document_from_snapshot(
  source_id : @core.SourceId,
  snapshot : @loom.ParseSnapshot[Block],
  ir : MarkdownIR,
) -> MarkdownDocument {
  {
    source_id,
    source: snapshot.source,
    diagnostics: snapshot.diagnostics.copy(),
    ir,
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
/// Return a detached advanced semantic read over this document's retained root.
pub fn MarkdownDocument::semantic_read(
  self : MarkdownDocument,
) -> MarkdownSemanticRead {
  { document: self, ir: self.ir }
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
/// Return the stable opaque root node for this advanced semantic read.
pub fn MarkdownSemanticRead::root(self : MarkdownSemanticRead) -> MarkdownNode {
  { read: self, node: self.ir }
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

///|
/// Resolve the source snapshot owned by this detached document.
pub impl @diagnostic.SourceResolver for MarkdownDocument with fn resolve_source(
  self,
  source_id,
) {
  guard source_id == self.source_id else { return None }
  Some(
    @core.SourceSnapshot::SourceSnapshot(
      source_id.value(),
      self.source,
      @core.LineIndex::new(self.source),
    ),
  )
}
