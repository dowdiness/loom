///|
/// Render this parser-owned collection through the standalone renderer while
/// preserving collection order and one shared source-resolution context.
pub fn[R : SourceResolver] DiagnosticSet::render_plain(
  self : DiagnosticSet,
  resolver : R,
) -> String raise DiagnosticRenderError {
  render_diagnostics_plain(self.items[:], resolver)
}
