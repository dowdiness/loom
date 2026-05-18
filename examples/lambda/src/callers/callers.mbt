// Tier 1 "show callers" projection: scope-aware extraction with strict
// call-site filtering.
//
// Walks a SyntaxNode tree once, emitting two relations on a stack of
// lexical scopes:
//   Def   — each LetDef name, lambda parameter, and let-paren parameter,
//           tagged with the ScopeId that binds it (TopScope or
//           LambdaScope(start, end)).
//   Call  — each VarRef, tagged with the ScopeId it resolves to via
//           lexical lookup, plus a Boolean `is_call_position` true iff
//           the parent (transparently through ParenExpr) is an AppExpr
//           in function position.
//
// `CallersPipeline` wraps the extraction in an @incr.Memo chain so the
// derived index re-derives automatically when the source SyntaxNode
// changes.
//
// Known limitations (deferred — none of them block current consumers):
//   1. Byte offsets are the only identity. Edits shift offsets and
//      there is no cross-edit fact identity. ScopeId inherits this
//      limitation since it is keyed on enclosing node byte ranges.
//   2. BlockExpr does not open a new scope: `{ let f = 2; f x }` reports
//      a top-level caller of `f` even when a block-local `f` would
//      shadow it. Only LambdaExpr and let-paren parameters introduce
//      scopes here.
//   3. "Resolved to top-level" means "not shadowed by a modeled lambda
//      or let-paren scope" — not "definitely points at an existing
//      top-level Def." An unbound name still resolves to TopScope. A
//      future projection that wants this distinction can read the
//      unfiltered `facts` Memo.

///|
/// Lexical scope identity.
///
/// `TopScope` is the global/source-file scope where top-level LetDefs
/// live. `LambdaScope(start, end)` identifies an enclosing
/// parameter-binding scope by its opening node's byte range — either a
/// `LambdaExpr` (for `\x. body`) or a `LetDef` carrying a `ParamList`
/// (for `let f(x, y) = body`).
pub(all) enum ScopeId {
  TopScope
  LambdaScope(Int, Int)
} derive(Eq, Debug)

///|
pub impl Show for ScopeId with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub struct Def {
  name : String
  scope : ScopeId
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
  resolved_scope : ScopeId
  is_call_position : Bool
  start : Int
  end : Int
} derive(Eq, Debug)

///|
pub impl Show for Call with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Lexical scope frame: a ScopeId paired with the names bound by it.
/// Param lists are small (typically ≤ 5) so linear scan beats hashing.
priv struct Frame {
  id : ScopeId
  names : Array[String]
}

///|
/// Look up `name` in the scope stack innermost-first. Returns the
/// ScopeId of the binding frame, or `TopScope` if no modeled scope
/// binds it.
fn resolve_in_stack(name : String, stack : Array[Frame]) -> ScopeId {
  for i = stack.length() - 1; i >= 0; i = i - 1 {
    let frame = stack[i]
    for bound in frame.names {
      if bound == name {
        return frame.id
      }
    }
  }
  TopScope
}

///|
/// Find the IdentToken in the slot immediately after `lead_kind`,
/// skipping only trivia. Returns `None` when:
///   - the lead token is absent (malformed input), or
///   - the first non-trivia element after the lead is anything other
///     than an IdentToken (e.g. an ErrorToken placeholder, the next
///     punctuation, or an interior node).
///
/// Used for LambdaExpr (lead=LambdaToken, returns the param) and LetDef
/// (lead=LetKeyword, returns the let-bound name). `find_token` would
/// return the same value on today's recovery paths because it does not
/// descend into interior nodes, but the intent is clearer here and the
/// extraction is robust against future recovery shifts that might leave
/// a stray IdentToken at a non-slot direct position.
fn ident_after_lead(
  node : @seam.SyntaxNode,
  lead_kind : @syntax.SyntaxKind,
) -> @seam.SyntaxToken? {
  let mut seen_lead = false
  for elem in node.all_children() {
    match elem {
      @seam.SyntaxElement::Token(tok) => {
        let k = @syntax.SyntaxKind::from_raw(tok.kind())
        if k.is_trivia() {
          continue
        }
        if seen_lead {
          if k == @syntax.IdentToken {
            return Some(tok)
          }
          return None
        }
        if k == lead_kind {
          seen_lead = true
        }
      }
      @seam.SyntaxElement::Node(_) =>
        if seen_lead {
          return None
        }
    }
  }
  None
}

///|
/// True iff `node` is the function-position child of an enclosing
/// AppExpr, transparently climbing through ParenExpr wrappers. ParenExpr
/// has a single inner-expression child plus paren tokens — wrapping a
/// callee in parens does not change its call-position status.
fn is_call_position_of(node : @seam.SyntaxNode) -> Bool {
  let mut current_kind = node.kind()
  let mut current_start = node.start()
  let mut current_end = node.end()
  let mut parent_opt = node.parent()
  while parent_opt is Some(parent) {
    let pkind = @syntax.SyntaxKind::from_raw(parent.kind())
    if pkind == @syntax.ParenExpr {
      // Transparent wrapper — recheck against ParenExpr's own parent.
      current_kind = parent.kind()
      current_start = parent.start()
      current_end = parent.end()
      parent_opt = parent.parent()
    } else if pkind == @syntax.AppExpr {
      match parent.first_child() {
        Some(first) =>
          return first.kind() == current_kind &&
            first.start() == current_start &&
            first.end() == current_end
        None => return false
      }
    } else {
      return false
    }
  }
  false
}

///|
/// Recursively walk the tree, appending Def/Call facts as they are
/// found, maintaining a lexical scope stack.
fn collect_in(
  node : @seam.SyntaxNode,
  defs : Array[Def],
  calls : Array[Call],
  stack : Array[Frame],
) -> Unit {
  let kind = @syntax.SyntaxKind::from_raw(node.kind())
  match kind {
    @syntax.LambdaExpr => {
      let frame_id = LambdaScope(node.start(), node.end())
      let names : Array[String] = []
      match ident_after_lead(node, @syntax.LambdaToken) {
        Some(tok) => {
          let name = tok.text()
          names.push(name)
          defs.push({
            name,
            scope: frame_id,
            start: node.start(),
            end: node.end(),
          })
        }
        None => ()
      }
      stack.push({ id: frame_id, names })
      for child in node.children() {
        collect_in(child, defs, calls, stack)
      }
      let _ = stack.pop()
    }
    @syntax.LetDef => {
      let outer_scope = stack[stack.length() - 1].id
      match ident_after_lead(node, @syntax.LetKeyword) {
        Some(tok) =>
          defs.push({
            name: tok.text(),
            scope: outer_scope,
            start: node.start(),
            end: node.end(),
          })
        None => ()
      }
      // Single pass over children. When a ParamList is seen, install a
      // new scope frame whose lifetime extends through the rest of the
      // children (the body). ParamList has no VarRef/LetDef/LambdaExpr
      // descendants, so its own children don't need recursion.
      let mut pushed = false
      for child in node.children() {
        if @syntax.SyntaxKind::from_raw(child.kind()) == @syntax.ParamList {
          let frame_id = LambdaScope(node.start(), node.end())
          let names : Array[String] = []
          for tok in child.tokens() {
            if @syntax.SyntaxKind::from_raw(tok.kind()) == @syntax.IdentToken {
              let name = tok.text()
              names.push(name)
              defs.push({
                name,
                scope: frame_id,
                start: node.start(),
                end: node.end(),
              })
            }
          }
          stack.push({ id: frame_id, names })
          pushed = true
        } else {
          collect_in(child, defs, calls, stack)
        }
      }
      if pushed {
        let _ = stack.pop()
      }
    }
    @syntax.VarRef =>
      match node.find_token(@syntax.IdentToken.to_raw()) {
        Some(tok) => {
          let name = tok.text()
          calls.push({
            callee: name,
            resolved_scope: resolve_in_stack(name, stack),
            is_call_position: is_call_position_of(node),
            start: node.start(),
            end: node.end(),
          })
        }
        None => ()
      }
    _ =>
      for child in node.children() {
        collect_in(child, defs, calls, stack)
      }
  }
}

///|
/// Pure extraction. Used directly in tests and inside the Memo body.
/// The returned arrays include EVERY VarRef and EVERY binding —
/// downstream filters (see `callers_of`) narrow to "callers of name"
/// using the `resolved_scope` and `is_call_position` fields.
pub fn extract_facts(root : @seam.SyntaxNode) -> (Array[Def], Array[Call]) {
  let defs : Array[Def] = []
  let calls : Array[Call] = []
  let stack : Array[Frame] = [{ id: TopScope, names: [] }]
  collect_in(root, defs, calls, stack)
  (defs, calls)
}

///|
/// Group calls by callee name for O(1) lookup. Pure utility — the
/// caller decides what subset of calls to index (e.g. `CallersPipeline`
/// indexes only the strict-call, top-resolved subset).
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
/// name->[Call] index of the strict-filtered subset (top-scope-resolved
/// calls in function position), each owned by a private @incr.Scope. A
/// persistent Observer on the index anchors the whole chain as a GC
/// root — without it, Runtime::gc() would sweep the (otherwise
/// unobserved) interior cells and subsequent reads would abort. The
/// Observer also gives ergonomic untracked reads via Observer::get().
///
/// Call `dispose()` to release the GC root and tear down the owned
/// cells. The input `syntax` Memo and the runtime are unaffected.
pub struct CallersPipeline {
  priv rt : @incr.Runtime
  priv scope : @incr.Scope
  priv observer : @incr.Observer[@hashmap.HashMap[String, Array[Call]]]
  priv facts : @incr.Memo[(Array[Def], Array[Call])]
}

///|
/// Build a CallersPipeline rooted at a Memo[SyntaxNode]. Cells are
/// created on a fresh Scope owned by this pipeline, and the derived
/// index is observed so the reactive chain survives `Runtime::gc()`.
/// Merging defs+calls into a single `facts` Memo avoids double-walking
/// the tree on every edit.
///
/// Precondition: `syntax` must have been constructed on `rt`. Passing a
/// Memo from a different Runtime is undefined behavior — incr's
/// cross-runtime guard catches some but not all paths. (`@incr.Memo`
/// does not currently expose a `.runtime()` accessor that would let us
/// derive `rt` and remove this footgun.)
pub fn CallersPipeline::CallersPipeline(
  rt : @incr.Runtime,
  syntax : @incr.Memo[@seam.SyntaxNode],
) -> CallersPipeline {
  let scope = @incr.Scope::new(rt)
  let facts = scope.memo(
    fn() { extract_facts(syntax.get()) },
    label="callers_facts",
  )
  let index = scope.memo(
    fn() {
      let (_, calls) = facts.get()
      let buckets : @hashmap.HashMap[String, Array[Call]] = @hashmap.HashMap([])
      for c in calls {
        if c.is_call_position && c.resolved_scope == TopScope {
          match buckets.get(c.callee) {
            Some(bucket) => bucket.push(c)
            None => buckets.set(c.callee, [c])
          }
        }
      }
      buckets
    },
    label="callers_index",
  )
  let observer = scope.add_observer(index.observe())
  { rt, scope, observer, facts }
}

///|
/// Release the GC root and tear down the owned cells. Idempotent.
/// Subsequent calls to `callers_of` / `defs_of` after dispose() are
/// undefined.
pub fn CallersPipeline::dispose(self : CallersPipeline) -> Unit {
  self.scope.dispose()
}

///|
/// Read all top-scope callers of `name`. Returns a defensive copy of the
/// cached bucket so callers cannot mutate the memoized index out from
/// under @incr's change-tracking. Returns [] when the name is undefined
/// at the top scope or has no call-position references.
pub fn CallersPipeline::callers_of(
  self : CallersPipeline,
  name : String,
) -> Array[Call] {
  match self.observer.get().get(name) {
    Some(bucket) => bucket.copy()
    None => []
  }
}

///|
/// Read all definitions named `name`, including lambda parameters and
/// let-paren parameters. Consumers wanting top-level bindings only can
/// filter on `d.scope == TopScope`. The `facts` cell stays reachable
/// via the observer on `index` (which depends on `facts`), so no second
/// observer is needed.
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
