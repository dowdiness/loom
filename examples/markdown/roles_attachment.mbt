// Parser-backed Markdown role span attachment.
//
// The pure classifier lives in `roles.mbt`; this file only wires that pure
// projection into the parser's `@incr` runtime.

///|
/// A GC-rooted role-span projection attached to a Markdown syntax parser.
pub struct MarkdownRoleSpansAttachment {
  priv scope : @incr.Scope
  priv watch : @incr.Watch[Array[MarkdownRoleSpan]]
}

///|
fn MarkdownRoleSpansAttachment::MarkdownRoleSpansAttachment(
  scope~ : @incr.Scope,
  watch~ : @incr.Watch[Array[MarkdownRoleSpan]],
) -> MarkdownRoleSpansAttachment {
  { scope, watch }
}

///|
/// Attach Markdown role spans to an existing syntax parser.
///
/// The derived closure reads the parser syntax tree with `get_or_abort()` and
/// the persistent watch roots the downstream chain through runtime GC.
pub fn attach_markdown_role_spans(
  parser : @loom.SyntaxParser,
) -> MarkdownRoleSpansAttachment {
  let scope = @incr.Scope::new(parser.runtime())
  let spans = scope.derived(
    fn() { project_markdown_roles(parser.syntax_tree().get_or_abort()) },
    label="markdown_role_spans",
  )
  let watch = scope.add_watch(spans.watch())
  ignore(watch.read_or_abort())
  MarkdownRoleSpansAttachment(scope~, watch~)
}

///|
/// Read the latest parser-backed Markdown role spans as a defensive copy.
pub fn MarkdownRoleSpansAttachment::spans(
  self : MarkdownRoleSpansAttachment,
) -> Array[MarkdownRoleSpan] {
  self.watch.read_or_abort().copy()
}

///|
/// Read the latest parser-backed role spans in editor-neutral form.
pub fn MarkdownRoleSpansAttachment::export_spans(
  self : MarkdownRoleSpansAttachment,
) -> Array[MarkdownRoleSpanExport] {
  export_markdown_role_spans(self.spans())
}

///|
/// Dispose this attachment. It does not dispose the parser and is idempotent.
pub fn MarkdownRoleSpansAttachment::dispose(
  self : MarkdownRoleSpansAttachment,
) -> Unit {
  self.scope.dispose()
}
