// Parser-backed Markdown editor projection attachment.
//
// The keyed MarkdownIR shell owns retained language work. This narrow public
// wrapper exposes only the current legacy editor Block and its lifecycle; IR
// maps, watches, and collection ordering remain private.

///|
/// A keyed Markdown editor projection attached to a live syntax parser.
///
/// The attachment does not own the parser. Its scope roots and owns all
/// retained MarkdownIR computations until `dispose()` is called.
pub struct MarkdownProjectionAttachment {
  priv shell : ReactiveKeyedMarkdownIR
  priv block_by_cst : @incr.DerivedMap[@seam.CstNode, Block]
  priv watch : @incr.Watch[Block]
}

///|
fn MarkdownProjectionAttachment::MarkdownProjectionAttachment(
  shell : ReactiveKeyedMarkdownIR,
  block_by_cst : @incr.DerivedMap[@seam.CstNode, Block],
  watch : @incr.Watch[Block],
) -> MarkdownProjectionAttachment {
  { shell, block_by_cst, watch }
}

///|
#warnings("-unused_value")
fn MarkdownProjectionAttachment::block_cache_len(
  self : MarkdownProjectionAttachment,
) -> Int {
  self.block_by_cst.cache_len()
}

///|
fn copy_markdown_projection_inline(inline : Inline) -> Inline {
  match inline {
    Text(value) => Inline::Text(value)
    Bold(children) =>
      Inline::Bold(
        children.map(child => copy_markdown_projection_inline(child)),
      )
    Italic(children) =>
      Inline::Italic(
        children.map(child => copy_markdown_projection_inline(child)),
      )
    InlineCode(value) => Inline::InlineCode(value)
    Link(children, destination) =>
      Inline::Link(
        children.map(child => copy_markdown_projection_inline(child)),
        destination,
      )
    Error(message) => Inline::Error(message)
  }
}

///|
fn copy_markdown_projection_block(block : Block) -> Block {
  match block {
    Document(children) =>
      Block::Document(
        children.map(child => copy_markdown_projection_block(child)),
      )
    Heading(depth, children) =>
      Block::Heading(
        depth,
        children.map(child => copy_markdown_projection_inline(child)),
      )
    Paragraph(children) =>
      Block::Paragraph(
        children.map(child => copy_markdown_projection_inline(child)),
      )
    UnorderedList(children) =>
      Block::UnorderedList(
        children.map(child => copy_markdown_projection_block(child)),
      )
    OrderedList(children, marker) =>
      Block::OrderedList(
        children.map(child => copy_markdown_projection_block(child)),
        marker,
      )
    UnorderedListItem(children) =>
      Block::UnorderedListItem(
        children.map(child => copy_markdown_projection_inline(child)),
      )
    OrderedListItem(children, marker) =>
      Block::OrderedListItem(
        children.map(child => copy_markdown_projection_inline(child)),
        marker,
      )
    CodeBlock(info, value) => Block::CodeBlock(info, value)
    HtmlBlock(value) => Block::HtmlBlock(value)
    Error(message) => Block::Error(message)
  }
}

///|
/// Attach the editor-facing Block projection to an existing Markdown syntax
/// parser.
///
/// Direct one-shot MarkdownIR lowering remains independent of this attachment.
pub fn attach_markdown_projection(
  parser : @loom.SyntaxParser,
) -> MarkdownProjectionAttachment {
  let shell = attach_reactive_keyed_markdown_ir_for_projection(parser)
  // Block ignores source origins. Cache each non-recovery projection by the
  // same structural CST key as its resolved local IR, then assemble only the
  // top-level document array on each revision. This keeps the editor path
  // block-local instead of rebuilding the complete positioned IR tree merely
  // to discard its positions in the Block adapter.
  let block_by_cst = shell.scope.derived_map(
    cst => {
      let resolved = shell.resolved_by_cst.get_or_abort(cst)
      guard !resolved_local_block_requires_context(resolved) else {
        abort("contextual Markdown block entered the reusable projection map")
      }
      experimental_markdown_ir_to_block(resolved.ir)
    },
    label="markdown_block_projection_by_cst",
  )
  let projection = shell.scope.derived(
    () => {
      let layout = shell.document_layout.get_or_abort()
      let blocks : Array[Block] = []
      for slot in layout.blocks {
        let local_result = shell.resolved_by_cst.get_or_abort(slot.cst)
        if resolved_local_block_requires_context(local_result) {
          let contextual = reactive_markdown_contextual_block(
            shell.source_id,
            shell.snapshot_view,
            shell.definition_by_label,
            slot,
          )
          blocks.push(experimental_markdown_ir_to_block(contextual.ir))
        } else {
          blocks.push(block_by_cst.get_or_abort(slot.cst))
        }
      }
      Block::Document(blocks)
    },
    label="markdown_block_projection",
  )
  let watch = shell.scope.watch(projection)
  MarkdownProjectionAttachment(shell, block_by_cst, watch)
}

///|
/// Read the current editor-facing Block through the authoritative MarkdownIR
/// adapter.
///
/// Conversion returns a fresh Block value, so callers cannot mutate retained
/// reactive state through the arrays carried by `Block` and `Inline`.
pub fn MarkdownProjectionAttachment::projection(
  self : MarkdownProjectionAttachment,
) -> Block {
  copy_markdown_projection_block(self.watch.read_or_abort())
}

///|
/// Collect stale keyed work at a caller-selected safe point.
///
/// The current terminal value is read before delegating graph collection and
/// scope-owned `DerivedMap` retirement to Incr. Callers never coordinate GC or
/// keyed-map sweeps themselves.
pub fn MarkdownProjectionAttachment::collect(
  self : MarkdownProjectionAttachment,
) -> Unit {
  ignore(self.watch.read_or_abort())
  self.shell.scope.collect()
}

///|
/// Dispose retained projection work. The parser remains usable and repeated
/// disposal is safe.
pub fn MarkdownProjectionAttachment::dispose(
  self : MarkdownProjectionAttachment,
) -> Unit {
  self.shell.dispose()
}
