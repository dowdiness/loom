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
/// True iff `ancestor` is a strict lexical ancestor of `descendant`.
pub fn is_strict_ancestor(
  ancestor : @callers.ScopeId,
  descendant : @callers.ScopeId,
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
) -> Bool {
  if ancestor == descendant {
    return false
  }
  is_ancestor_from_parent(ancestor, descendant, enclosing)
}

///|
fn is_ancestor_from_parent(
  ancestor : @callers.ScopeId,
  descendant : @callers.ScopeId,
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
) -> Bool {
  match parent_scope_of(descendant, enclosing) {
    Some(parent) =>
      if parent == ancestor {
        true
      } else {
        is_ancestor_from_parent(ancestor, parent, enclosing)
      }
    None => false
  }
}

///|
/// Forward-capture check: renaming an outer binding to `new_name` would
/// capture references below any descendant binding already named `new_name`.
pub fn check_forward_capture(
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
) -> @core.Diagnostic? {
  for d in defs {
    if d.name == new_name &&
      is_strict_ancestor(target.scope, d.scope, enclosing) {
      let (target_start, target_end) = name_range_of(target, syntax)
      let (capture_start, capture_end) = name_range_of(d, syntax)
      return Some(
        make_forward_capture_diagnostic(
          target_start, target_end, capture_start, capture_end, new_name,
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
fn make_forward_capture_diagnostic(
  target_start : Int,
  target_end : Int,
  capture_start : Int,
  capture_end : Int,
  new_name : String,
) -> @core.Diagnostic {
  let primary = text_range_or_abort(target_start, target_end)
  let capture_range = text_range_or_abort(capture_start, capture_end)
  @core.Diagnostic::Diagnostic(
    source=@core.DiagnosticSource::DiagnosticSource("rename"),
    severity=severity_error(),
    message="Cannot rename to '\{new_name}': a descendant binding with that name would capture references",
    code=Some(@core.DiagnosticCode::DiagnosticCode("rename.capture")),
    primary=Some(primary),
    labels=[
      @core.DiagnosticLabel::DiagnosticLabel(
        capture_range,
        Some("capturing descendant binding"),
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
