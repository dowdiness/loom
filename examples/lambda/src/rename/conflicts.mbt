///|
/// Sibling-def collision check: returns Some(diagnostic) iff another
/// def shares target's scope and has the proposed new name.
pub fn check_sibling_collision(
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  syntax : @seam.SyntaxNode,
) -> @core.Diagnostic? {
  for d in defs {
    if d.scope == target.scope && d.name == new_name {
      let (target_start, target_end) = name_range_of(target, syntax)
      let (collider_start, collider_end) = name_range_of(d, syntax)
      return Some(
        make_sibling_diagnostic(
          target_start, target_end, collider_start, collider_end, new_name,
        ),
      )
    }
  }
  None
}

///|
fn make_sibling_diagnostic(
  target_start : Int,
  target_end : Int,
  collider_start : Int,
  collider_end : Int,
  new_name : String,
) -> @core.Diagnostic {
  let primary = text_range_or_abort(target_start, target_end)
  let collider_range = text_range_or_abort(collider_start, collider_end)
  @core.Diagnostic::Diagnostic(
    source=@core.DiagnosticSource::DiagnosticSource("rename"),
    severity=severity_error(),
    message="Cannot rename to '\{new_name}': another binding with that name already exists in the same scope",
    code=Some(@core.DiagnosticCode::DiagnosticCode("rename.sibling_collision")),
    primary=Some(primary),
    labels=[
      @core.DiagnosticLabel::DiagnosticLabel(
        collider_range,
        Some("existing binding"),
      ),
    ],
  )
}

///|
fn text_range_or_abort(start : Int, end : Int) -> @core.TextRange {
  try @core.TextRange::from_offsets(start, end) catch {
    _ => abort("rename: invalid diagnostic range")
  } noraise {
    range => range
  }
}

///|
fn severity_error() -> @core.DiagnosticSeverity {
  @core.DiagnosticSeverity::all()[0]
}
