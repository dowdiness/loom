// Tier 0 prototype: Datalog-style "show callers" projection.
//
// Walks a SyntaxNode tree extracting two relations:
//   Def  — each LetDef binds a name at a source position.
//   Call — each VarRef references a name at a source position.
//
// `CallersPipeline` wraps the extraction in an @incr.Memo chain so the
// derived index re-derives automatically when the source SyntaxNode changes.
//
// Known Tier 0 limitations (intentional, to be revisited):
//   1. Byte offsets are the only identity. Edits shift offsets and there is
//      no cross-edit fact identity.
//   2. Any VarRef counts as a use, including those passed as data rather
//      than called. A strict call-site filter would require parent-pointer
//      checks on AppExpr.func.
//   3. Lambda parameter bindings are not modelled — a parameter named `f`
//      shadows a top-level `let f = ...` in scope, but this projection
//      returns the union of both.

///|
pub struct Def {
  name : String
  start : Int
  end : Int
} derive(Eq, Debug)

///|
pub impl Show for Def with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub struct Call {
  callee : String
  start : Int
  end : Int
} derive(Eq, Debug)

///|
pub impl Show for Call with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Recursively walk the tree, appending Def/Call facts as they are found.
/// Nodes that have lost their IdentToken to error recovery are skipped
/// rather than emitted as empty-name ghost facts.
fn collect(
  node : @seam.SyntaxNode,
  defs : Array[Def],
  calls : Array[Call],
) -> Unit {
  let kind = @syntax.SyntaxKind::from_raw(node.kind())
  match kind {
    @syntax.LetDef =>
      match node.find_token(@syntax.IdentToken.to_raw()) {
        Some(tok) =>
          defs.push({ name: tok.text(), start: node.start(), end: node.end() })
        None => ()
      }
    @syntax.VarRef =>
      match node.find_token(@syntax.IdentToken.to_raw()) {
        Some(tok) =>
          calls.push({
            callee: tok.text(),
            start: node.start(),
            end: node.end(),
          })
        None => ()
      }
    _ => ()
  }
  for child in node.children() {
    collect(child, defs, calls)
  }
}

///|
/// Pure extraction. Used directly in tests and inside the Memo body.
pub fn extract_facts(root : @seam.SyntaxNode) -> (Array[Def], Array[Call]) {
  let defs : Array[Def] = []
  let calls : Array[Call] = []
  collect(root, defs, calls)
  (defs, calls)
}

///|
/// Group calls by callee name for O(1) lookup.
pub fn build_callers_index(
  calls : Array[Call],
) -> @hashmap.HashMap[String, Array[Call]] {
  let index : @hashmap.HashMap[String, Array[Call]] = @hashmap.HashMap([])
  for c in calls {
    match index.get(c.callee) {
      Some(bucket) => bucket.push(c)
      None => index.set(c.callee, [c])
    }
  }
  index
}

///|
/// The reactive pipeline: facts (joint defs + calls) plus a derived
/// name->[Call] index, each as an @incr.Memo cell that re-derives when
/// the input SyntaxNode changes. Fields are private so callers cannot
/// read raw Memo handles and bypass the rt-anchored read path.
pub struct CallersPipeline {
  priv rt : @incr.Runtime
  priv facts : @incr.Memo[(Array[Def], Array[Call])]
  priv index : @incr.Memo[@hashmap.HashMap[String, Array[Call]]]
}

///|
/// Build a CallersPipeline rooted at a Memo[SyntaxNode]. The pipeline
/// reads from `syntax` and exposes derived views via callers_of/defs_of.
///
/// `facts` walks the tree once per snapshot change; `index` derives the
/// callee->calls map from facts. Merging defs+calls into a single Memo
/// avoids double-walking the tree on every edit.
pub fn CallersPipeline::CallersPipeline(
  rt : @incr.Runtime,
  syntax : @incr.Memo[@seam.SyntaxNode],
) -> CallersPipeline {
  let facts = @incr.Memo::new(rt, fn() { extract_facts(syntax.get()) })
  let index = @incr.Memo::new(rt, fn() {
    let (_, calls) = facts.get()
    build_callers_index(calls)
  })
  { rt, facts, index }
}

///|
/// Read all callers of `name`. Returns a defensive copy of the cached
/// bucket so callers cannot mutate the memoized index out from under
/// @incr's change-tracking. Returns [] when the name is undefined or unused.
pub fn CallersPipeline::callers_of(
  self : CallersPipeline,
  name : String,
) -> Array[Call] {
  match self.rt.read(self.index).get(name) {
    Some(bucket) => bucket.copy()
    None => []
  }
}

///|
/// Read all definitions named `name`. Useful for diagnostics — a name
/// with zero defs and many calls is an undefined reference; many defs is
/// an ambiguity / shadow.
pub fn CallersPipeline::defs_of(
  self : CallersPipeline,
  name : String,
) -> Array[Def] {
  let (defs, _) = self.rt.read(self.facts)
  let result : Array[Def] = []
  for d in defs {
    if d.name == name {
      result.push(d)
    }
  }
  result
}
