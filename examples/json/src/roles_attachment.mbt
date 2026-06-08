// Parser-backed JSON role span attachment.
//
// The pure classifier lives in `roles.mbt`; this file only wires that pure
// projection into the parser's `@incr` runtime so consumers can keep a stable
// GC-rooted role-span view across syntax parser updates.

///|
/// A GC-rooted role-span projection attached to a JSON syntax parser.
///
/// The attachment shares `parser.runtime()` and derives spans from
/// `parser.syntax_tree()`, so `SyntaxParser::apply_edit` publishes coherent role
/// updates without constructing another parser. `dispose()` releases only this
/// attachment's scope; the parser remains owned by its caller.
pub struct JsonRoleSpansAttachment {
  priv scope : @incr.Scope
  priv watch : @incr.Watch[Array[JsonRoleSpan]]
}

///|
fn JsonRoleSpansAttachment::JsonRoleSpansAttachment(
  scope~ : @incr.Scope,
  watch~ : @incr.Watch[Array[JsonRoleSpan]],
) -> JsonRoleSpansAttachment {
  { scope, watch }
}

///|
/// Attach JSON role-span projection to an existing syntax parser.
///
/// The derived closure reads the parser's syntax tree with `get_or_abort()` so
/// dependency tracking stays inside the parser runtime. The persistent `Watch`
/// is registered with the scope and primed immediately, keeping the chain alive
/// even if `parser.runtime().gc()` runs before the first external read.
pub fn attach_json_role_spans(
  parser : @loom.SyntaxParser,
) -> JsonRoleSpansAttachment {
  let scope = @incr.Scope::new(parser.runtime())
  let spans = scope.derived(
    fn() { project_json_roles(parser.syntax_tree().get_or_abort()) },
    label="json_role_spans",
  )
  let watch = scope.add_watch(spans.watch())
  ignore(watch.read_or_abort())
  JsonRoleSpansAttachment(scope~, watch~)
}

///|
/// Read the latest parser-backed JSON role spans.
///
/// The returned array is a copy so callers cannot mutate the cached derived
/// value held by the attachment.
pub fn JsonRoleSpansAttachment::spans(
  self : JsonRoleSpansAttachment,
) -> Array[JsonRoleSpan] {
  self.watch.read_or_abort().copy()
}

///|
/// Dispose the attachment scope. Idempotent; does not dispose the parser.
pub fn JsonRoleSpansAttachment::dispose(self : JsonRoleSpansAttachment) -> Unit {
  self.scope.dispose()
}
