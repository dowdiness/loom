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
/// Forward-capture check: references edited from target.name to
/// `new_name` must still resolve to the renamed target.
pub fn check_forward_capture(
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  calls : Array[@callers.Call],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
) -> @core.Diagnostic? {
  for c in calls {
    if c.callee == target.name {
      let (call_start, _) = call_name_range_of(c, syntax)
      if call_resolves_to_target(target, defs, enclosing, syntax, c, call_start) {
        match
          post_rename_binding_at_call(
            target, new_name, defs, enclosing, syntax, call_start,
          ) {
          Some(capturer) =>
            if !(capturer == target) {
              let (target_start, target_end) = name_range_of(target, syntax)
              let (capture_start, capture_end) = name_range_of(capturer, syntax)
              return Some(
                make_forward_capture_diagnostic(
                  target_start, target_end, capture_start, capture_end, new_name,
                ),
              )
            }
          None => ()
        }
      }
    }
  }
  None
}

///|
fn post_rename_binding_at_call(
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
  call_start : Int,
) -> @callers.Def? {
  let lexical_scope = lexical_scope_at(defs, enclosing, call_start)
  let visited : @hashset.HashSet[@callers.ScopeId] = @hashset.HashSet([])
  resolve_binding_after_target_rename_from(
    lexical_scope, target, new_name, defs, enclosing, syntax, call_start, visited,
  )
}

///|
fn resolve_binding_after_target_rename_from(
  scope : @callers.ScopeId,
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
  call_start : Int,
  visited : @hashset.HashSet[@callers.ScopeId],
) -> @callers.Def? {
  if visited.contains(scope) {
    return None
  }
  visited.add(scope)
  match
    nearest_completed_let_after_target_rename(
      scope, target, new_name, defs, syntax, call_start,
    ) {
    Some(d) => return Some(d)
    None => ()
  }
  match scope_binding_after_target_rename(scope, target, new_name, defs) {
    Some(d) => return Some(d)
    None => ()
  }
  match parent_scope_of(scope, enclosing) {
    Some(parent) =>
      resolve_binding_after_target_rename_from(
        parent, target, new_name, defs, enclosing, syntax, call_start, visited,
      )
    None => None
  }
}

///|
fn nearest_completed_let_after_target_rename(
  scope : @callers.ScopeId,
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
  syntax : @seam.SyntaxNode,
  call_start : Int,
) -> @callers.Def? {
  let mut winner : @callers.Def? = None
  let mut winner_end = -1
  for d in defs {
    if d.scope == scope &&
      binding_matches_renamed_name(d, target, new_name) &&
      !is_scope_binding_def(d) &&
      let_container_contains(d, syntax, call_start) {
      if d.end <= call_start && d.end >= winner_end {
        winner = Some(d)
        winner_end = d.end
      }
    }
  }
  winner
}

///|
fn scope_binding_after_target_rename(
  scope : @callers.ScopeId,
  target : @callers.Def,
  new_name : String,
  defs : Array[@callers.Def],
) -> @callers.Def? {
  let mut winner : @callers.Def? = None
  for d in defs {
    if d.scope == scope &&
      binding_matches_renamed_name(d, target, new_name) &&
      is_scope_binding_def(d) {
      winner = Some(d)
    }
  }
  winner
}

///|
fn binding_matches_renamed_name(
  def : @callers.Def,
  target : @callers.Def,
  new_name : String,
) -> Bool {
  def == target || def.name == new_name
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
  let (target_start, target_end) = name_range_of(target, syntax)
  match shadow_lookup_scope(target, enclosing) {
    Some(scope) => {
      let visited : @hashset.HashSet[@callers.ScopeId] = @hashset.HashSet([])
      match
        resolve_binding_from(
          scope, new_name, defs, enclosing, syntax, target_start, visited,
        ) {
        Some(outer) =>
          if outer == target || defs_are_siblings(target, outer, syntax) {
            None
          } else {
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
fn shadow_lookup_scope(
  target : @callers.Def,
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
) -> @callers.ScopeId? {
  if is_scope_binding_def(target) {
    parent_scope_of(target.scope, enclosing)
  } else {
    Some(target.scope)
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
    message="Cannot rename to '\{new_name}': an existing binding with that name would capture references",
    code=Some(@core.DiagnosticCode::DiagnosticCode("rename.capture")),
    primary=Some(primary),
    labels=[
      @core.DiagnosticLabel::DiagnosticLabel(
        capture_range,
        Some("capturing binding"),
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
