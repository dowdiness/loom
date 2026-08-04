// Parser-backed source-aware Markdown semantic attachment.
//
// The attachment is the imperative shell around the private keyed MarkdownIR
// core. It owns only its reactive scope; the parser remains caller-owned.

///|
/// A source-aware MarkdownIR document attached to a caller-owned live parser.
///
/// `document()` returns an owning read-only semantic value and performs all
/// stale-work maintenance before returning. Call `dispose()` when the consumer
/// lifetime ends; repeated disposal is safe and never disposes the parser.
pub struct MarkdownSemanticAttachment {
  priv shell : ReactiveKeyedMarkdownIR
  priv mut disposed : Bool
}

///|
/// Attach source-aware MarkdownIR lowering to an existing Markdown parser.
///
/// The attachment observes the parser's complete coherent snapshot and joins
/// its runtime. It does not create, mutate, own, or dispose the parser.
pub fn MarkdownSemanticAttachment::MarkdownSemanticAttachment(
  parser : @loom.Parser[Block],
) -> MarkdownSemanticAttachment {
  {
    shell: attach_reactive_keyed_markdown_ir_from_block_parser(parser),
    disposed: false,
  }
}

///|
/// Return the current owning source-aware MarkdownIR document.
///
/// The terminal value is obtained before scope-owned stale work is collected,
/// so the returned value remains valid across collection and later parser
/// revisions.
pub fn MarkdownSemanticAttachment::document(
  self : MarkdownSemanticAttachment,
) -> MarkdownIR {
  guard !self.disposed else { abort("MarkdownSemanticAttachment is disposed") }
  let document = self.shell.read()
  self.shell.scope.collect()
  document
}

///|
/// Dispose attachment-owned reactive work without disposing the parser.
///
/// Repeated calls are safe.
pub fn MarkdownSemanticAttachment::dispose(
  self : MarkdownSemanticAttachment,
) -> Unit {
  if !self.disposed {
    self.disposed = true
    self.shell.dispose()
  }
}
