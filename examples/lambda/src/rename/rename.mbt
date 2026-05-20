// Rename + conflict-detection consumer of `CallersPipeline`.
//
// `plan_rename(pipeline, source, syntax, offset, new_name)` returns a
// `RenamePlan` carrying source edits and `@core.Diagnostic` conflicts.
// Three conflict classes are detected: sibling-def collision, capture
// (two-pass: forward + converse), and shadow.
//
// Conflict detection is conservative: the analysis layer overcounts to
// guarantee soundness because `Call.resolved_scope` records the binding
// scope, not the call's lexical scope. False positives surface in editor
// UI as "review before applying"; false negatives are correctness bugs.
// See docs/plans/2026-05-19-rename-consumer-design.md.

///|
/// Source-text edit produced by a rename. `(start, end)` is a half-open
/// byte range into the source; `new_text` is the replacement.
pub struct TextEdit {
  start : Int
  end : Int
  new_text : String
} derive(Eq, Debug)

///|
pub impl Show for TextEdit with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// The result of a rename request: the target def (or None if the
/// offset doesn't land on a binding identifier), the set of source
/// edits, and a diagnostics array carrying conflicts and input errors.
///
/// Editors should apply edits only if `diagnostics` contains no
/// `Error`-severity entries (or surface them and let the user override).
pub struct RenamePlan {
  target : @callers.Def?
  edits : Array[TextEdit]
  diagnostics : Array[@core.Diagnostic]
}

///|
/// Plan a rename from a source offset: locate the target binding, compute
/// edits, and collect conservative conflict diagnostics.
pub fn plan_rename(
  pipeline : @callers.CallersPipeline,
  _source : String,
  syntax : @seam.SyntaxNode,
  offset : Int,
  new_name : String,
) -> RenamePlan {
  let (defs, calls, enclosing) = pipeline.facts()
  match locate_target(defs, syntax, offset) {
    None =>
      RenamePlan::{
        target: None,
        edits: [],
        diagnostics: [make_no_target_diagnostic(offset)],
      }
    Some(target) =>
      if new_name == target.name {
        RenamePlan::{
          target: Some(target),
          edits: [],
          diagnostics: [make_no_op_diagnostic()],
        }
      } else {
        let edits = compute_edits(
          target, defs, calls, enclosing, syntax, new_name,
        )
        let diagnostics : Array[@core.Diagnostic] = []
        match check_sibling_collision(target, new_name, defs, syntax) {
          Some(d) => diagnostics.push(d)
          None => ()
        }
        match
          check_forward_capture(
            target, new_name, defs, calls, enclosing, syntax,
          ) {
          Some(d) => diagnostics.push(d)
          None => ()
        }
        match
          check_converse_capture(target, new_name, calls, enclosing, syntax) {
          Some(d) => diagnostics.push(d)
          None => ()
        }
        match check_shadow(target, new_name, defs, enclosing, syntax) {
          Some(d) => diagnostics.push(d)
          None => ()
        }
        RenamePlan::{ target: Some(target), edits, diagnostics }
      }
  }
}

///|
fn compute_edits(
  target : @callers.Def,
  defs : Array[@callers.Def],
  calls : Array[@callers.Call],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
  new_name : String,
) -> Array[TextEdit] {
  let edits : Array[TextEdit] = []
  let (name_start, name_end) = name_range_of(target, syntax)
  edits.push(TextEdit::{ start: name_start, end: name_end, new_text: new_name })
  for c in calls {
    if c.callee == target.name {
      let (call_start, call_end) = call_name_range_of(c, syntax)
      if call_resolves_to_target(target, defs, enclosing, syntax, c, call_start) {
        edits.push(TextEdit::{
          start: call_start,
          end: call_end,
          new_text: new_name,
        })
      }
    }
  }
  edits
}

///|
fn call_resolves_to_target(
  target : @callers.Def,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
  call : @callers.Call,
  call_start : Int,
) -> Bool {
  if call.callee != target.name {
    return false
  }
  match resolve_call_binding(defs, enclosing, syntax, call.callee, call_start) {
    Some(d) => d == target
    None => false
  }
}

///|
fn resolve_call_binding(
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  syntax : @seam.SyntaxNode,
  name : String,
  call_start : Int,
) -> @callers.Def? {
  let lexical_scope = lexical_scope_at(defs, enclosing, call_start)
  let visited : @hashset.HashSet[@callers.ScopeId] = @hashset.HashSet([])
  resolve_binding_from(
    lexical_scope, name, defs, enclosing, syntax, call_start, visited,
  )
}

///|
fn resolve_binding_from(
  scope : @callers.ScopeId,
  name : String,
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
  match nearest_completed_let(scope, name, defs, syntax, call_start) {
    Some(d) => return Some(d)
    None => ()
  }
  match scope_binding_def(scope, name, defs) {
    Some(d) => return Some(d)
    None => ()
  }
  match parent_scope_of(scope, enclosing) {
    Some(parent) =>
      resolve_binding_from(
        parent, name, defs, enclosing, syntax, call_start, visited,
      )
    None => None
  }
}

///|
fn nearest_completed_let(
  scope : @callers.ScopeId,
  name : String,
  defs : Array[@callers.Def],
  syntax : @seam.SyntaxNode,
  call_start : Int,
) -> @callers.Def? {
  let mut winner : @callers.Def? = None
  let mut winner_end = -1
  for d in defs {
    if d.scope == scope &&
      d.name == name &&
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
fn scope_binding_def(
  scope : @callers.ScopeId,
  name : String,
  defs : Array[@callers.Def],
) -> @callers.Def? {
  let mut winner : @callers.Def? = None
  for d in defs {
    if d.scope == scope && d.name == name && is_scope_binding_def(d) {
      winner = Some(d)
    }
  }
  winner
}

///|
fn is_scope_binding_def(def : @callers.Def) -> Bool {
  match def.scope {
    @callers.TopScope => false
    @callers.LambdaScope(start, end) => def.start == start && def.end == end
  }
}

///|
fn let_container_contains(
  def : @callers.Def,
  syntax : @seam.SyntaxNode,
  offset : Int,
) -> Bool {
  match find_def_node(syntax, def) {
    Some(node) =>
      match nearest_let_container_range(node) {
        Some((start, end)) => offset >= start && offset < end
        None => false
      }
    None => false
  }
}

///|
fn find_def_node(
  node : @seam.SyntaxNode,
  def : @callers.Def,
) -> @seam.SyntaxNode? {
  if node.end() <= def.start || node.start() >= def.end {
    return None
  }
  if node.start() == def.start &&
    node.end() == def.end &&
    @syntax.SyntaxKind::from_raw(node.kind()) == @syntax.LetDef {
    return Some(node)
  }
  for child in node.children() {
    match find_def_node(child, def) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
fn nearest_let_container_range(node : @seam.SyntaxNode) -> (Int, Int)? {
  let mut current = node.parent()
  while current is Some(parent) {
    let kind = @syntax.SyntaxKind::from_raw(parent.kind())
    if kind == @syntax.SourceFile || kind == @syntax.BlockExpr {
      return Some((parent.start(), parent.end()))
    }
    current = parent.parent()
  }
  None
}

///|
fn lexical_scope_at(
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  offset : Int,
) -> @callers.ScopeId {
  let mut best = @callers.TopScope
  let mut best_width = 2147483647
  for d in defs {
    let (next, width) = consider_scope(d.scope, offset, best, best_width)
    best = next
    best_width = width
  }
  for edge in enclosing {
    let (next_child, child_width) = consider_scope(
      edge.0,
      offset,
      best,
      best_width,
    )
    best = next_child
    best_width = child_width
    let (next_parent, parent_width) = consider_scope(
      edge.1,
      offset,
      best,
      best_width,
    )
    best = next_parent
    best_width = parent_width
  }
  best
}

///|
fn consider_scope(
  candidate : @callers.ScopeId,
  offset : Int,
  current : @callers.ScopeId,
  current_width : Int,
) -> (@callers.ScopeId, Int) {
  match candidate {
    @callers.TopScope => (current, current_width)
    @callers.LambdaScope(start, end) => {
      let width = end - start
      if offset >= start && offset < end && width < current_width {
        (candidate, width)
      } else {
        (current, current_width)
      }
    }
  }
}

///|
fn make_no_target_diagnostic(offset : Int) -> @core.Diagnostic {
  @core.Diagnostic::Diagnostic(
    source=@core.DiagnosticSource::DiagnosticSource("rename"),
    severity=severity_error(),
    message="No binding identifier at offset \{offset}",
    code=Some(
      @core.DiagnosticCode::DiagnosticCode("rename.no_target_at_offset"),
    ),
  )
}

///|
fn make_no_op_diagnostic() -> @core.Diagnostic {
  @core.Diagnostic::Diagnostic(
    source=@core.DiagnosticSource::DiagnosticSource("rename"),
    severity=severity_info(),
    message="new_name equals existing name; nothing to do",
    code=Some(@core.DiagnosticCode::DiagnosticCode("rename.no_op")),
  )
}

///|
fn severity_info() -> @core.DiagnosticSeverity {
  @core.DiagnosticSeverity::all()[2]
}
