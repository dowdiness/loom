// Tier 1+ "show callers" projection: scope-aware extraction with strict
// call-site filtering plus visibility queries.
//
// Walks a SyntaxNode tree once, emitting three relations on a stack of
// lexical scopes:
//   Def       — each LetDef name, lambda parameter, and let-paren
//               parameter, tagged with the ScopeId that binds it
//               (TopScope or LambdaScope(start, end)).
//   Call      — each VarRef, tagged with the ScopeId it resolves to via
//               lexical lookup, plus a Boolean `is_call_position` true
//               iff the parent (transparently through ParenExpr) is an
//               AppExpr in function position.
//   Enclosing — `(child_scope, parent_scope)` edges emitted at each
//               LambdaScope frame push, so `build_visibility` can walk
//               the parent chain. TopScope is the implicit root of
//               every chain (never a child).
//
// `CallersPipeline` wraps the extraction in an @incr.Memo chain — three
// derived Memos (facts, callers_index, visibility) each rooted by a
// persistent Observer — so the derived state re-derives automatically
// when the source SyntaxNode changes and survives `Runtime::gc()`.
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
//      future projection that wants this distinction can share the
//      unfiltered facts memo inside the pipeline.

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
} derive(Eq, Hash, Debug)

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
  name_start : Int
  name_end : Int
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
      @seam.SyntaxElement::Node(_) => if seen_lead { return None }
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
/// found, maintaining a lexical scope stack. Emits an Enclosing edge
/// `(frame_id, parent_id)` immediately before pushing each LambdaScope
/// frame, so the visibility builder can walk the parent chain.
fn collect_in(
  node : @seam.SyntaxNode,
  defs : Array[Def],
  calls : Array[Call],
  enclosing : Array[(ScopeId, ScopeId)],
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
            name_start: tok.start(),
            name_end: tok.end(),
          })
        }
        None => ()
      }
      if stack.length() > 0 {
        enclosing.push((frame_id, stack[stack.length() - 1].id))
      }
      stack.push({ id: frame_id, names })
      for child in node.children() {
        collect_in(child, defs, calls, enclosing, stack)
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
            name_start: tok.start(),
            name_end: tok.end(),
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
                name_start: tok.start(),
                name_end: tok.end(),
              })
            }
          }
          if stack.length() > 0 {
            enclosing.push((frame_id, stack[stack.length() - 1].id))
          }
          stack.push({ id: frame_id, names })
          pushed = true
        } else {
          collect_in(child, defs, calls, enclosing, stack)
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
        collect_in(child, defs, calls, enclosing, stack)
      }
  }
}

///|
/// Pure extraction including Enclosing edges. Used by the pipeline's
/// `facts` Memo. The returned `enclosing` array carries `(child, parent)`
/// tuples for every LambdaScope frame pushed during the walk. TopScope is
/// never a child of an edge (it's the implicit root of every chain).
///
/// Package-private: the consumer-facing surface is the pipeline
/// (`callers_of` / `defs_of` / `visible_from`). The wrapper
/// `extract_facts` stays public for backward compatibility with existing
/// 2-tuple consumers and tests.
fn extract_facts_full(
  root : @seam.SyntaxNode,
) -> (Array[Def], Array[Call], Array[(ScopeId, ScopeId)]) {
  let defs : Array[Def] = []
  let calls : Array[Call] = []
  let enclosing : Array[(ScopeId, ScopeId)] = []
  let stack : Array[Frame] = [{ id: TopScope, names: [] }]
  collect_in(root, defs, calls, enclosing, stack)
  (defs, calls, enclosing)
}

///|
/// Backward-compatible 2-tuple shape: defs and calls only. The Tier 1
/// tests at this signature continue to compile unchanged.
pub fn extract_facts(root : @seam.SyntaxNode) -> (Array[Def], Array[Call]) {
  let (defs, calls, _enclosing) = extract_facts_full(root)
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
/// Compute the full set of names visible at scope `s`. Walks the parent
/// chain upward, unioning each ancestor's own bindings. Memoized via
/// `memo` to avoid quadratic re-walks along shared chains.
fn visible_names_at(
  s : ScopeId,
  parent : @hashmap.HashMap[ScopeId, ScopeId],
  own : @hashmap.HashMap[ScopeId, Array[String]],
  memo : @hashmap.HashMap[ScopeId, @hashset.HashSet[String]],
) -> @hashset.HashSet[String] {
  match memo.get(s) {
    Some(set) => set
    None => {
      let result : @hashset.HashSet[String] = @hashset.HashSet([])
      match own.get(s) {
        Some(arr) =>
          for n in arr {
            result.add(n)
          }
        None => ()
      }
      match parent.get(s) {
        Some(p) => {
          let inherited = visible_names_at(p, parent, own, memo)
          for n in inherited {
            result.add(n)
          }
        }
        None => () // root or unparented
      }
      memo.set(s, result)
      result
    }
  }
}

///|
/// Build the (scope, name) -> Unit visibility map from extracted defs +
/// enclosing edges. Membership in the map means "binding `name` exists
/// in `scope` or any enclosing scope." Does NOT model shadowing.
///
/// Precondition: `enclosing` describes an acyclic parent graph. Edges
/// produced by `extract_facts_full` are acyclic by construction (each
/// edge points from a newly pushed frame to its existing parent on the
/// stack). Synthetic cyclic input would cause `visible_names_at` to
/// recurse without bound.
pub fn build_visibility(
  defs : Array[Def],
  enclosing : Array[(ScopeId, ScopeId)],
) -> @hashmap.HashMap[(ScopeId, String), Unit] {
  // 1. Collect every scope mentioned in defs OR enclosing, plus TopScope.
  let scopes : @hashset.HashSet[ScopeId] = @hashset.HashSet([])
  scopes.add(TopScope)
  for d in defs {
    scopes.add(d.scope)
  }
  for edge in enclosing {
    scopes.add(edge.0)
    scopes.add(edge.1)
  }
  // 2. parent[child] = parent_scope. First edge wins (defensive against
  //    malformed input that emits duplicate parents).
  let parent : @hashmap.HashMap[ScopeId, ScopeId] = @hashmap.HashMap([])
  for edge in enclosing {
    match parent.get(edge.0) {
      None => parent.set(edge.0, edge.1)
      Some(_) => ()
    }
  }
  // 3. own[scope] = [name, ...] for bindings introduced by that scope.
  let own : @hashmap.HashMap[ScopeId, Array[String]] = @hashmap.HashMap([])
  for d in defs {
    match own.get(d.scope) {
      Some(arr) => arr.push(d.name)
      None => own.set(d.scope, [d.name])
    }
  }
  // 4. For each scope, materialize its visibility name set (memoized).
  let memo : @hashmap.HashMap[ScopeId, @hashset.HashSet[String]] = @hashmap.HashMap([],
  )
  // 5. Flatten into (scope, name) -> Unit.
  let result : @hashmap.HashMap[(ScopeId, String), Unit] = @hashmap.HashMap([])
  for s in scopes {
    let names = visible_names_at(s, parent, own, memo)
    for n in names {
      result.set((s, n), ())
    }
  }
  result
}

///|
/// The reactive pipeline. Three derived Memos:
///   facts            — `extract_facts_full(syntax)` (defs + calls +
///                      enclosing edges).
///   callers_index    — `name -> [Call]` over the strict-filtered subset
///                      (top-scope-resolved calls in function position).
///   visibility       — `build_visibility(defs, enclosing)` flattened
///                      to `(ScopeId, String) -> Unit`.
///
/// Each Memo is observed by a persistent `Observer` registered with a
/// single private `@incr.Scope`. Without those observers, `Runtime::gc()`
/// would sweep the (otherwise unobserved) interior cells and subsequent
/// reads would abort. The observers also give ergonomic untracked reads
/// via `Observer::get()`.
///
/// Call `dispose()` to release the GC roots and tear down the owned
/// cells. The input `syntax` Memo and the runtime are unaffected.
pub struct CallersPipeline {
  priv scope : @incr.Scope
  priv facts_observer : @incr.Observer[
    (Array[Def], Array[Call], Array[(ScopeId, ScopeId)]),
  ]
  priv callers_observer : @incr.Observer[@hashmap.HashMap[String, Array[Call]]]
  priv visibility_observer : @incr.Observer[
    @hashmap.HashMap[(ScopeId, String), Unit],
  ]
}

///|
/// Build a CallersPipeline rooted at a Memo[SyntaxNode]. Cells are
/// created on a fresh Scope owned by this pipeline, and three derived
/// Memos (facts, callers_index, visibility) are each observed so the
/// reactive chain survives `Runtime::gc()`. Merging defs+calls+enclosing
/// into a single `facts` Memo avoids double-walking the tree on every
/// edit; downstream Memos read facts via `.get()` inside their tracked
/// closures.
///
/// Precondition: `syntax` must have been constructed on `rt`. Passing a
/// Memo from a different Runtime is undefined behavior — incr's
/// cross-runtime guard catches some but not all paths.
pub fn CallersPipeline::CallersPipeline(
  rt : @incr.Runtime,
  syntax : @incr.Memo[@seam.SyntaxNode],
) -> CallersPipeline {
  let scope = @incr.Scope::new(rt)
  let facts = scope.memo(
    fn() { extract_facts_full(syntax.get()) },
    label="callers_facts",
  )
  let callers_index = scope.memo(
    fn() {
      let (_, calls, _) = facts.get()
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
  let visibility = scope.memo(
    fn() {
      let (defs, _, enclosing) = facts.get()
      build_visibility(defs, enclosing)
    },
    label="callers_visibility",
  )
  let facts_observer = scope.add_observer(facts.observe())
  let callers_observer = scope.add_observer(callers_index.observe())
  let visibility_observer = scope.add_observer(visibility.observe())
  // Prime facts_observer so the dependency edge `facts -> syntax` is
  // recorded before this constructor returns. Without priming,
  // `facts_observer` anchors `facts` but `facts`'s `gc_dependencies`
  // are empty until the closure runs at least once — a caller-side
  // `rt.gc()` issued before any read would sweep the upstream
  // `syntax_tree` Memo. Costs one tree walk; one-time per pipeline.
  let _ = facts_observer.get()
  { scope, facts_observer, callers_observer, visibility_observer }
}

///|
/// Release the GC root and tear down the owned cells. Idempotent.
/// Subsequent calls to `callers_of` / `defs_of` / `visible_from` after
/// dispose() are undefined.
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
  match self.callers_observer.get().get(name) {
    Some(bucket) => bucket.copy()
    None => []
  }
}

///|
/// Read all definitions named `name`, including lambda parameters and
/// let-paren parameters. Consumers wanting top-level bindings only can
/// filter on `d.scope == TopScope`.
pub fn CallersPipeline::defs_of(
  self : CallersPipeline,
  name : String,
) -> Array[Def] {
  let (defs, _, _) = self.facts_observer.get()
  let result : Array[Def] = []
  for d in defs {
    if d.name == name {
      result.push(d)
    }
  }
  result
}

///|
/// Read the cached `(defs, calls, enclosing)` facts as defensive copies.
/// Returned arrays are independent from the cached Memo state — callers
/// may mutate them without affecting subsequent reads. Use this when a
/// consumer needs access to unfiltered fact relations.
pub fn CallersPipeline::facts(
  self : CallersPipeline,
) -> (Array[Def], Array[Call], Array[(ScopeId, ScopeId)]) {
  let (defs, calls, enclosing) = self.facts_observer.get()
  (defs.copy(), calls.copy(), enclosing.copy())
}

///|
/// True iff a binding named `name` is visible from `scope` — meaning it
/// exists in `scope` itself or in any enclosing scope. Does NOT model
/// shadowing (cannot answer "which binding wins"). Consumer-facing for
/// rename + conflict detection. Returns false for unknown ScopeIds.
pub fn CallersPipeline::visible_from(
  self : CallersPipeline,
  scope : ScopeId,
  name : String,
) -> Bool {
  self.visibility_observer.get().get((scope, name)) is Some(_)
}
