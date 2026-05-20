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
        let edits = compute_edits(target, defs, calls, syntax, new_name)
        let diagnostics : Array[@core.Diagnostic] = []
        match check_sibling_collision(target, new_name, defs, syntax) {
          Some(d) => diagnostics.push(d)
          None => ()
        }
        match check_forward_capture(target, new_name, defs, enclosing, syntax) {
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
  syntax : @seam.SyntaxNode,
  new_name : String,
) -> Array[TextEdit] {
  let edits : Array[TextEdit] = []
  let (name_start, name_end) = name_range_of(target, syntax)
  edits.push(TextEdit::{ start: name_start, end: name_end, new_text: new_name })
  for c in calls {
    if c.callee == target.name && c.resolved_scope == target.scope {
      let (call_start, call_end) = call_name_range_of(c, syntax)
      if call_resolves_to_target(target, defs, c, call_start) {
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
  call : @callers.Call,
  call_start : Int,
) -> Bool {
  if call.callee != target.name || call.resolved_scope != target.scope {
    return false
  }
  match target.scope {
    @callers.TopScope =>
      top_scope_call_resolves_to_target(target, defs, call, call_start)
    @callers.LambdaScope(_, _) => true
  }
}

///|
fn top_scope_call_resolves_to_target(
  target : @callers.Def,
  defs : Array[@callers.Def],
  call : @callers.Call,
  call_start : Int,
) -> Bool {
  let mut winner : @callers.Def? = None
  let mut winner_end = -1
  for d in defs {
    if d.scope == @callers.TopScope && d.name == call.callee {
      if d.end <= call_start && d.end >= winner_end {
        winner = Some(d)
        winner_end = d.end
      }
    }
  }
  match winner {
    Some(d) => d == target
    None => false
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
