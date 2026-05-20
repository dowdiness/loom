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
fn compute_edits(
  target : @callers.Def,
  calls : Array[@callers.Call],
  syntax : @seam.SyntaxNode,
  new_name : String,
) -> Array[TextEdit] {
  let edits : Array[TextEdit] = []
  let (name_start, name_end) = name_range_of(target, syntax)
  edits.push(TextEdit::{ start: name_start, end: name_end, new_text: new_name })
  for c in calls {
    if c.callee == target.name && c.resolved_scope == target.scope {
      edits.push(TextEdit::{ start: c.start, end: c.end, new_text: new_name })
    }
  }
  edits
}
