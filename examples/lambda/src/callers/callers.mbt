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
// `CallersPipeline` wraps the extraction in an @incr.Derived chain — three
// derived cells (facts, callers_index, visibility) each rooted by a
// persistent Watch — so the derived state re-derives automatically
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
//      unfiltered facts Derived cell inside the pipeline.

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
pub impl Show for ScopeId with fn output(self, logger) {
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
pub impl Show for Def with fn output(self, logger) {
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
pub impl Show for Call with fn output(self, logger) {
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
/// (lead=LetKeyword, returns the let-bound name). A direct token query would
/// return the same value on today's recovery paths because it does not
/// descend into interior nodes, but the slot intent is clearer here and the
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
/// Visitor state for extracting Def/Call facts in source order.
///
/// `SyntaxNode::accept_visitor` owns the recursion; this collector owns only
/// lambda-specific state. LetDef parameter lists are handled at their source
/// position: entering a `ParamList` under a `LetDef` installs a scope frame
/// that remains active until the enclosing `LetDef` exits.
priv struct FactCollector {
  defs : Array[Def]
  calls : Array[Call]
  enclosing : Array[(ScopeId, ScopeId)]
  stack : Array[Frame]
}

///|
impl @seam.SyntaxMutVisitor for FactCollector with fn enter_node(self, node) {
  let kind = @syntax.SyntaxKind::from_raw(node.kind())
  match kind {
    @syntax.LambdaExpr => {
      let frame_id = LambdaScope(node.start(), node.end())
      let names : Array[String] = []
      match ident_after_lead(node, @syntax.LambdaToken) {
        Some(tok) => {
          let name = tok.text()
          names.push(name)
          self.defs.push({
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
      if self.stack.length() > 0 {
        self.enclosing.push((frame_id, self.stack[self.stack.length() - 1].id))
      }
      self.stack.push({ id: frame_id, names })
      true
    }
    @syntax.LetDef => {
      let outer_scope = self.stack[self.stack.length() - 1].id
      match ident_after_lead(node, @syntax.LetKeyword) {
        Some(tok) =>
          self.defs.push({
            name: tok.text(),
            scope: outer_scope,
            start: node.start(),
            end: node.end(),
            name_start: tok.start(),
            name_end: tok.end(),
          })
        None => ()
      }
      true
    }
    @syntax.ParamList =>
      match node.parent() {
        Some(parent) if @syntax.SyntaxKind::from_raw(parent.kind()) ==
          @syntax.LetDef => {
          let frame_id = LambdaScope(parent.start(), parent.end())
          let names : Array[String] = []
          for tok in node.tokens() {
            if @syntax.SyntaxKind::from_raw(tok.kind()) == @syntax.IdentToken {
              let name = tok.text()
              names.push(name)
              self.defs.push({
                name,
                scope: frame_id,
                start: parent.start(),
                end: parent.end(),
                name_start: tok.start(),
                name_end: tok.end(),
              })
            }
          }
          if self.stack.length() > 0 {
            self.enclosing.push(
              (frame_id, self.stack[self.stack.length() - 1].id),
            )
          }
          self.stack.push({ id: frame_id, names })
          false
        }
        _ => true
      }
    @syntax.VarRef => {
      match node.direct_token_of_kind(@syntax.IdentToken.to_raw()) {
        Some(tok) => {
          let name = tok.text()
          self.calls.push({
            callee: name,
            resolved_scope: resolve_in_stack(name, self.stack),
            is_call_position: is_call_position_of(node),
            start: node.start(),
            end: node.end(),
          })
        }
        None => ()
      }
      true
    }
    _ => true
  }
}

///|
impl @seam.SyntaxMutVisitor for FactCollector with fn exit_node(self, node) {
  let kind = @syntax.SyntaxKind::from_raw(node.kind())
  match kind {
    @syntax.LambdaExpr | @syntax.LetDef => {
      let frame_id = LambdaScope(node.start(), node.end())
      if self.stack.length() > 0 &&
        self.stack[self.stack.length() - 1].id == frame_id {
        let _ = self.stack.pop()
      }
    }
    _ => ()
  }
}

///|
impl @seam.SyntaxMutVisitor for FactCollector with fn visit_token(_self, _token) {
  ()
}

///|
/// Pure extraction including Enclosing edges. Used by the pipeline's
/// `facts` Derived. The returned `enclosing` array carries `(child, parent)`
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
  let collector = FactCollector::{
    defs: [],
    calls: [],
    enclosing: [],
    stack: [{ id: TopScope, names: [] }],
  }
  root.accept_visitor(collector)
  (collector.defs, collector.calls, collector.enclosing)
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
/// The reactive pipeline. Three derived cells:
///   facts            — `extract_facts_full(syntax)` (defs + calls +
///                      enclosing edges).
///   callers_index    — `name -> [Call]` over the strict-filtered subset
///                      (top-scope-resolved calls in function position).
///   visibility       — `build_visibility(defs, enclosing)` flattened
///                      to `(ScopeId, String) -> Unit`.
///
/// Each Derived is watched by a persistent `Watch` registered with a
/// single private `@incr.Scope`. Without those watches, `Runtime::gc()`
/// would sweep the (otherwise unobserved) interior cells and subsequent
/// reads would abort. The watches also give ergonomic untracked reads via
/// `Watch::read_or_abort()`.
///
/// The pipeline owns only its private scope and watch roots. Call
/// `dispose()` to release those roots and tear down the owned cells. The
/// input `syntax` Derived and runtime are unaffected by disposal; when the
/// input comes from a parser, that parser is not disposed either. Their
/// longer-term GC reachability belongs to whoever still owns them.
pub struct CallersPipeline {
  priv scope : @incr.Scope
  priv facts_watch : @incr.Watch[
    (Array[Def], Array[Call], Array[(ScopeId, ScopeId)]),
  ]
  priv callers_watch : @incr.Watch[@hashmap.HashMap[String, Array[Call]]]
  priv visibility_watch : @incr.Watch[@hashmap.HashMap[(ScopeId, String), Unit]]
}

///|
/// Low-level constructor for a CallersPipeline rooted at a
/// Derived[SyntaxNode]. Prefer `CallersPipeline::from_parser(parser)` when
/// attaching to a unified lambda parser; use this constructor for advanced
/// cases that intentionally provide a custom runtime and syntax Derived.
///
/// Cells are created on a fresh Scope owned by this pipeline, and three
/// derived cells (facts, callers_index, visibility) are each watched so
/// the reactive chain survives `Runtime::gc()`. The constructor primes the
/// facts watch before returning, so a caller may run GC before the first
/// public query and still keep the parser syntax dependency reachable.
/// Merging defs+calls+enclosing into a single `facts` Derived avoids
/// double-walking the tree on every edit; downstream Derived cells read
/// facts via `.get_or_abort()` inside their tracked closures.
///
/// Precondition: `syntax` must have been constructed on `rt`. Passing a
/// Derived from a different Runtime is undefined behavior — incr's
/// cross-runtime guard catches some but not all paths.
pub fn CallersPipeline::CallersPipeline(
  rt : @incr.Runtime,
  syntax : @incr.Derived[@seam.SyntaxNode],
) -> CallersPipeline {
  let scope = @incr.Scope::new(rt)
  let facts = scope.derived(
    fn() { extract_facts_full(syntax.get_or_abort()) },
    label="callers_facts",
  )
  let callers_index = scope.derived(
    fn() {
      let (_, calls, _) = facts.get_or_abort()
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
  let visibility = scope.derived(
    fn() {
      let (defs, _, enclosing) = facts.get_or_abort()
      build_visibility(defs, enclosing)
    },
    label="callers_visibility",
  )
  let facts_watch = scope.add_watch(facts.watch())
  let callers_watch = scope.add_watch(callers_index.watch())
  let visibility_watch = scope.add_watch(visibility.watch())
  // Prime facts_watch so the dependency edge `facts -> syntax` is
  // recorded before this constructor returns. Without priming,
  // `facts_watch` anchors `facts` but `facts`'s `gc_dependencies`
  // are empty until the closure runs at least once — a caller-side
  // `rt.gc()` issued before any read would sweep the upstream
  // `syntax_tree` Derived. Costs one tree walk; one-time per pipeline.
  let _ = facts_watch.read_or_abort()
  { scope, facts_watch, callers_watch, visibility_watch }
}

///|
/// Attach the callers pipeline to a unified lambda `Parser`.
///
/// This constructor derives both the runtime and syntax view from the parser,
/// keeping the attachment in the parser's reactive graph and avoiding the
/// low-level constructor's same-runtime precondition at ordinary call sites.
/// The returned pipeline owns its scope/watch lifecycle only; `dispose()`
/// does not dispose the parser or its runtime.
pub fn CallersPipeline::from_parser(
  parser : @loom.Parser[@ast.Term],
) -> CallersPipeline {
  CallersPipeline::CallersPipeline(parser.runtime(), parser.syntax_tree())
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
  match self.callers_watch.read_or_abort().get(name) {
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
  let (defs, _, _) = self.facts_watch.read_or_abort()
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
/// Returned arrays are independent from the cached Derived state — callers
/// may mutate them without affecting subsequent reads. Use this when a
/// consumer needs access to unfiltered fact relations.
pub fn CallersPipeline::facts(
  self : CallersPipeline,
) -> (Array[Def], Array[Call], Array[(ScopeId, ScopeId)]) {
  let (defs, calls, enclosing) = self.facts_watch.read_or_abort()
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
  self.visibility_watch.read_or_abort().get((scope, name)) is Some(_)
}
