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
    if !(d == target) &&
      d.name == new_name &&
      defs_are_siblings(target, d, syntax) {
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
fn defs_are_siblings(
  target : @callers.Def,
  other : @callers.Def,
  syntax : @seam.SyntaxNode,
) -> Bool {
  if target.scope != other.scope {
    return false
  }
  let target_is_scope_binding = is_scope_binding_def(target)
  let other_is_scope_binding = is_scope_binding_def(other)
  if target_is_scope_binding || other_is_scope_binding {
    return target_is_scope_binding && other_is_scope_binding
  }
  same_let_container(target, other, syntax)
}

///|
fn same_let_container(
  a : @callers.Def,
  b : @callers.Def,
  syntax : @seam.SyntaxNode,
) -> Bool {
  match (find_def_node(syntax, a), find_def_node(syntax, b)) {
    (Some(a_node), Some(b_node)) =>
      nearest_let_container_range(a_node) == nearest_let_container_range(b_node)
    _ => false
  }
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
      is_strict_ancestor(target.scope, d.scope, enclosing) &&
      target_visible_at_source_position(target, syntax, d.name_start) {
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
/// Converse-capture check: if an existing call to `new_name` resolves at
/// an ancestor-or-equal scope, the renamed target may intercept it.
pub fn check_converse_capture(
  target : @callers.Def,
  new_name : String,
  calls : Array[@callers.Call],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
) -> @core.Diagnostic? {
  for c in calls {
    if c.callee == new_name {
      let (call_start, call_end) = call_name_range_of(c, syntax)
      let is_ancestor_or_equal = c.resolved_scope == target.scope ||
        is_strict_ancestor(c.resolved_scope, target.scope, enclosing)
      if is_ancestor_or_equal &&
        target_visible_at_source_position(target, syntax, call_start) {
        let (target_start, target_end) = name_range_of(target, syntax)
        return Some(
          make_converse_capture_diagnostic(
            call_start, call_end, target_start, target_end, new_name,
          ),
        )
      }
    }
  }
  None
}

///|
fn target_visible_at_source_position(
  target : @callers.Def,
  syntax : @seam.SyntaxNode,
  offset : Int,
) -> Bool {
  if is_scope_binding_def(target) {
    offset >= target.start && offset < target.end
  } else {
    target.end <= offset && let_container_contains(target, syntax, offset)
  }
}

///|
/// Shadow check: renaming to an outer visible binding name is legal but
/// changes readability and should be surfaced as a warning.
pub fn check_shadow(
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
) -> @core.Diagnostic? {
  match parent_scope_of(target.scope, enclosing) {
    Some(parent) => {
      let (target_start, target_end) = name_range_of(target, syntax)
      let visited : @hashset.HashSet[@callers.ScopeId] = @hashset.HashSet([])
      match
        resolve_binding_from(
          parent, new_name, defs, enclosing, syntax, target_start, visited,
        ) {
        Some(outer) => {
          let (outer_start, outer_end) = name_range_of(outer, syntax)
          Some(
            make_shadow_diagnostic(
              target_start, target_end, outer_start, outer_end, new_name,
            ),
          )
        }
        None => None
      }
    }
    None => None
  }
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
fn make_converse_capture_diagnostic(
  call_start : Int,
  call_end : Int,
  target_start : Int,
  target_end : Int,
  new_name : String,
) -> @core.Diagnostic {
  let primary = text_range_or_abort(call_start, call_end)
  let target_range = text_range_or_abort(target_start, target_end)
  @core.Diagnostic::Diagnostic(
    source=@core.DiagnosticSource::DiagnosticSource("rename"),
    severity=severity_error(),
    message="Cannot rename to '\{new_name}': an existing reference to that name may be captured",
    code=Some(@core.DiagnosticCode::DiagnosticCode("rename.capture")),
    primary=Some(primary),
    labels=[
      @core.DiagnosticLabel::DiagnosticLabel(
        target_range,
        Some("renamed binding would intercept"),
      ),
    ],
    notes=[
      "Conservative check: false positives may occur if the call's lexical chain does not pass through the renamed scope.",
    ],
  )
}

///|
fn make_shadow_diagnostic(
  target_start : Int,
  target_end : Int,
  shadowed_start : Int,
  shadowed_end : Int,
  new_name : String,
) -> @core.Diagnostic {
  let primary = text_range_or_abort(target_start, target_end)
  let shadowed_range = text_range_or_abort(shadowed_start, shadowed_end)
  @core.Diagnostic::Diagnostic(
    source=@core.DiagnosticSource::DiagnosticSource("rename"),
    severity=severity_warning(),
    message="Renaming to '\{new_name}' shadows an outer binding",
    code=Some(@core.DiagnosticCode::DiagnosticCode("rename.shadow")),
    primary=Some(primary),
    labels=[
      @core.DiagnosticLabel::DiagnosticLabel(
        shadowed_range,
        Some("shadowed binding"),
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

///|
fn severity_warning() -> @core.DiagnosticSeverity {
  @core.DiagnosticSeverity::all()[1]
}
