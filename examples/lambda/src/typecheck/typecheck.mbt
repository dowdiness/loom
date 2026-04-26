// Incremental typecheck pipeline wiring.
//
// Creates a Scope-managed chain of Memos for per-def type checking.
// For a module with N defs, the chain is:
//   env_memo[0] → type_memo[0] → env_memo[1] → type_memo[1] → ... → body_memo
//
// When module structure changes (defs added/removed), the old chain
// scope is disposed and a new one is built. When only def bodies change,
// the corresponding term signals are updated and memos recompute.

///|
/// Mutable pipeline state, held inside the top-level Memo closure.
priv struct PipelineState {
  intern_table : @incr.InternTable[DefEntry]
  mut chain_scope : @incr.Scope?
  mut prev_def_names : Array[String]
  // Name → position of the FIRST occurrence in `prev_def_names` /
  // `type_memos`. Rebuilt from scratch on every structural change in
  // `rebuild_chain`, left untouched during `update_terms` (structure is
  // unchanged). Under first-wins, a `DefId` minted for a given name
  // always routes to the original declaration's slot — never to a later
  // shadowing one — so caches keyed on `DefId` identity stay coherent.
  // Every subsequent duplicate is flagged by a diagnostic in
  // `duplicate_diags` below.
  mut name_to_idx : @hashmap.HashMap[String, Int]
  // Diagnostics produced by duplicate-name detection in `rebuild_chain`.
  // Concatenated into `ModuleTypeResult::all_diagnostics` by
  // `collect_results`. Rebuilt atomically with `name_to_idx`.
  mut duplicate_diags : Array[TypeDiagnostic]
  // Raw (unresolved) def body signals. `resolve_memos[i]` reads
  // `term_signals[i]` and runs `resolve_walk` on that raw body with
  // the def's captured `ResolveEnv`. Editing one def body only
  // invalidates that def's `resolve_memo`.
  mut term_signals : Array[@incr.Signal[TypedTerm]]
  mut resolve_memos : Array[@incr.Memo[TypedTerm]]
  // env_memos kept alive so closures that captured them don't dangle
  mut env_memos : Array[@incr.Memo[TypeEnv]]
  mut type_memos : Array[@incr.Memo[TypeResult]]
  mut body_term_signal : @incr.Signal[TypedTerm]?
  mut body_resolve_memo : @incr.Memo[TypedTerm]?
  mut body_memo : @incr.Memo[TypeResult]?
  // Accumulator for per-def diagnostics. Allocated in `rebuild_chain`
  // bound to the current `chain_scope`, so it is disposed automatically
  // when the chain is torn down on structural rebuild.
  mut diags : @incr.Accumulator[TypeDiagnostic]?
}

///|
fn PipelineState::new() -> PipelineState {
  {
    intern_table: @incr.InternTable::new(),
    chain_scope: None,
    prev_def_names: [],
    name_to_idx: @hashmap.new(),
    duplicate_diags: [],
    term_signals: [],
    resolve_memos: [],
    env_memos: [],
    type_memos: [],
    body_term_signal: None,
    body_resolve_memo: None,
    body_memo: None,
    diags: None,
  }
}

///|
/// Build the incremental typecheck pipeline.
///
/// Takes a `Memo[TypedTerm]` that produces the (already converted and resolved)
/// module term. Returns a `Memo[ModuleTypeResult]` that recomputes incrementally
/// when the input changes.
///
/// The caller (in `src/` or in tests) is responsible for creating the input memo
/// from parsed source. This avoids circular dependencies.
pub fn build_typecheck_pipeline(
  rt : @incr.Runtime,
  parent_scope : @incr.Scope,
  source_term : @incr.Memo[TypedTerm],
) -> @incr.Memo[ModuleTypeResult] {
  let (memo, _state) = build_typecheck_pipeline_internal(
    rt, parent_scope, source_term,
  )
  memo
}

///|
/// Internal variant returning the `PipelineState` alongside the memo
/// for whitebox tests that need to observe per-def cell state
/// (e.g. `resolve_memos[i].changed_at()`). Not part of the public API.
fn build_typecheck_pipeline_internal(
  rt : @incr.Runtime,
  parent_scope : @incr.Scope,
  source_term : @incr.Memo[TypedTerm],
) -> (@incr.Memo[ModuleTypeResult], PipelineState) {
  let state = PipelineState::new()
  ignore(rt)
  let memo = parent_scope.memo(
    () => {
      let term = source_term.get()
      let (defs, body) = split_defs(term)
      let def_names = defs.map(fn(d) { d.0 })
      // Detect structural change: first run or different def names
      let needs_rebuild = match state.chain_scope {
        None => true
        Some(_) => def_names != state.prev_def_names
      }
      if needs_rebuild {
        rebuild_chain(state, parent_scope, defs, body)
      } else {
        update_terms(state, defs, body)
      }
      collect_results(state)
    },
    label="typecheck_pipeline",
  )
  (memo, state)
}

///|
/// Build the incremental typecheck pipeline and return a query index.
///
/// Like `build_typecheck_pipeline`, but also returns a `TypecheckIndex` that
/// lets callers query type results by `InternId` (stable across edits).
///
/// The `MemoMap` in the index computes by looking up the type memo for the
/// given `InternId` in the current `PipelineState`. Reads inside the MemoMap
/// compute function ARE tracked — changing a type_memo will invalidate the
/// entry. Calling `memo_map.get(id)` outside a tracked context is untracked.
pub fn build_typecheck_pipeline_with_index(
  rt : @incr.Runtime,
  parent_scope : @incr.Scope,
  source_term : @incr.Memo[TypedTerm],
) -> (@incr.Memo[ModuleTypeResult], TypecheckIndex) {
  let state = PipelineState::new()
  let memo_map = @incr.MemoMap::new(
    rt,
    fn(def_id : @incr.InternId) -> TypeResult {
      let entry = state.intern_table.get(def_id)
      // Route name → current position via `name_to_idx`, which is
      // rebuilt from scratch on every structural rebuild. An InternId for
      // a name that is no longer in the module hits the `None` arm and
      // returns an error sentinel; the `is_disposed()` check is defensive
      // for stale handles that outlive a rebuild window.
      match state.name_to_idx.get(entry.name) {
        Some(idx) =>
          if !state.type_memos[idx].is_disposed() {
            state.type_memos[idx].get()
          } else {
            { typ: TError, had_error: true }
          }
        None => { typ: TError, had_error: true }
      }
    },
    label="typecheck_index",
  )
  let result_memo = parent_scope.memo(
    () => {
      let term = source_term.get()
      let (defs, body) = split_defs(term)
      let def_names = defs.map(fn(d) { d.0 })
      let needs_rebuild = match state.chain_scope {
        None => true
        Some(_) => def_names != state.prev_def_names
      }
      if needs_rebuild {
        // Wrapper memos in `memo_map` captured references to the previous
        // chain's `type_memos` slots. After `rebuild_chain` replaces those
        // slots (and their chain scope is disposed), every cached wrapper
        // reads through a dangling pointer. Dispose them up front —
        // `memo_map` is Runtime-owned, so chain-scope disposal can't
        // reach it.
        memo_map.clear()
        rebuild_chain(state, parent_scope, defs, body)
      } else {
        update_terms(state, defs, body)
      }
      collect_results(state)
    },
    label="typecheck_pipeline",
  )
  let index : TypecheckIndex = { intern_table: state.intern_table, memo_map }
  (result_memo, index)
}

///|
/// Split a (possibly non-Module) `TypedTerm` into its top-level defs and
/// body without running resolution. O(top-level defs), not O(module AST).
/// This is the lightweight replacement for `resolve_typed` at the parent
/// memo boundary — per-def resolve happens inside `resolve_memos[i]`.
fn split_defs(term : TypedTerm) -> (Array[(String, TypedTerm)], TypedTerm) {
  match term {
    Module(defs, body) => (defs, body)
    _ => ([], term)
  }
}

///|
/// Dispose old chain and build a new Memo chain for the raw module.
/// Takes unresolved `defs` and `body`; name resolution runs inside the
/// per-def `resolve_memos[i]` built here, keyed on the fixed env at
/// each def's position.
fn rebuild_chain(
  state : PipelineState,
  parent_scope : @incr.Scope,
  defs : Array[(String, TypedTerm)],
  body : TypedTerm,
) -> Unit {
  // Dispose previous chain scope if it exists. Disposing the scope also
  // disposes any accumulator allocated on it, so `state.diags` becomes
  // stale here and is replaced below.
  match state.chain_scope {
    Some(old_scope) => old_scope.dispose()
    None => ()
  }
  let chain_scope = parent_scope.child()
  state.chain_scope = Some(chain_scope)
  // Allocate a fresh diagnostics accumulator bound to the new chain scope.
  let diags : @incr.Accumulator[TypeDiagnostic] = chain_scope.accumulator(
    label="typecheck_diags",
  )
  state.diags = Some(diags)
  let def_names = defs.map(fn(d) { d.0 })
  state.prev_def_names = def_names
  // Rebuild the name → position map and intern every def's identity.
  // `DefEntry` hashes on `name` only, so re-interning the same name from
  // a prior chain returns the same `InternId` — that is the stability
  // property downstream consumers of `TypecheckIndex` rely on. For each
  // name we keep the FIRST occurrence in `name_to_idx` so a cached
  // `DefId` always routes to the original declaration; subsequent
  // same-named defs get flagged in `duplicate_diags` instead of silently
  // aliasing into a later slot.
  let name_to_idx : @hashmap.HashMap[String, Int] = @hashmap.new()
  let duplicate_diags : Array[TypeDiagnostic] = []
  for i, def in defs {
    match name_to_idx.get(def.0) {
      Some(_) =>
        duplicate_diags.push({
          message: "duplicate top-level definition: \{def.0}",
          def_name: Some(def.0),
          range: None,
        })
      None => name_to_idx.set(def.0, i)
    }
    let _id = state.intern_table.intern({ name: def.0 })
  }
  state.name_to_idx = name_to_idx
  state.duplicate_diags = duplicate_diags
  // Create raw-body term signals for each def.
  let term_signals : Array[@incr.Signal[TypedTerm]] = []
  for def in defs {
    let sig = chain_scope.signal(def.1, label="def_term_\{def.0}")
    term_signals.push(sig)
  }
  state.term_signals = term_signals
  // Build per-def ResolveEnv values. Names are fixed for this chain's
  // lifetime (any name change triggers a full rebuild), so these are
  // plain values captured by closures rather than reactive memos.
  //   resolve_envs[i] = env visible to def[i]'s body (names [0..i-1])
  //   body_env        = env visible to the module body (all def names)
  let resolve_envs : Array[ResolveEnv] = []
  let mut rolling_env : ResolveEnv = ResolveEnv::Empty
  for def in defs {
    resolve_envs.push(rolling_env)
    rolling_env = rolling_env.extend(def.0)
  }
  let body_env = rolling_env
  // Per-def resolve memos: resolve_walk(raw_body, env_i). Backdates via
  // TypedTerm Eq — a source edit that leaves the resolved form unchanged
  // stops propagation here.
  let resolve_memos : Array[@incr.Memo[TypedTerm]] = []
  for i = 0; i < defs.length(); i = i + 1 {
    let def_name = defs[i].0
    let term_sig = term_signals[i]
    let env_i = resolve_envs[i]
    let rm = chain_scope.memo(
      () => resolve_walk(term_sig.get(), env_i),
      label="resolve_\{def_name}",
    )
    resolve_memos.push(rm)
  }
  state.resolve_memos = resolve_memos
  // Build env_memo and type_memo chains. type_memo[i] reads
  // resolve_memos[i].get() — raw bodies stay off the type_memo's dep
  // set so unchanged resolves short-circuit typechecking too.
  let env_memos : Array[@incr.Memo[TypeEnv]] = []
  let type_memos : Array[@incr.Memo[TypeResult]] = []
  for i = 0; i < defs.length(); i = i + 1 {
    let def_name = defs[i].0
    let resolve_memo = resolve_memos[i]
    // env_memo[i]: extends previous env with previous def's type
    let env_memo = if i == 0 {
      chain_scope.memo(() => TypeEnv::Empty, label="env_\{def_name}")
    } else {
      let prev_env_memo = env_memos[i - 1]
      let prev_type_memo = type_memos[i - 1]
      let prev_name = defs[i - 1].0
      chain_scope.memo(
        () => {
          let env = prev_env_memo.get()
          let prev_result = prev_type_memo.get()
          let prev_type = if prev_result.had_error {
            TError
          } else {
            prev_result.typ
          }
          env.extend(prev_name, prev_type)
        },
        label="env_\{def_name}",
      )
    }
    env_memos.push(env_memo)
    // type_memo[i]: infer resolved body in env_memo[i]. Diagnostics
    // pushed from within `infer_impl` land in the chain-scope
    // accumulator, tagged with this def's name.
    let ctx : DiagCtx = { def_name: Some(def_name), diags: Some(diags) }
    let type_memo = chain_scope.memo(
      () => {
        let env = env_memo.get()
        let resolved_body = resolve_memo.get()
        infer_impl(env, resolved_body, ctx)
      },
      label="type_\{def_name}",
    )
    type_memos.push(type_memo)
  }
  state.env_memos = env_memos
  state.type_memos = type_memos
  // Body: raw signal → resolve memo → type memo.
  let body_sig = chain_scope.signal(body, label="body_term")
  state.body_term_signal = Some(body_sig)
  let body_resolve_memo = chain_scope.memo(
    () => resolve_walk(body_sig.get(), body_env),
    label="resolve_body",
  )
  state.body_resolve_memo = Some(body_resolve_memo)
  // Body diagnostics are untagged (no def_name).
  let body_ctx : DiagCtx = { def_name: None, diags: Some(diags) }
  // Build the final type env for the body (extends last env with
  // last def's type).
  let body_memo = if defs.length() == 0 {
    chain_scope.memo(
      () => {
        let body_term = body_resolve_memo.get()
        infer_impl(TypeEnv::Empty, body_term, body_ctx)
      },
      label="body_type",
    )
  } else {
    let last_idx = defs.length() - 1
    let last_env_memo = env_memos[last_idx]
    let last_type_memo = type_memos[last_idx]
    let last_name = defs[last_idx].0
    chain_scope.memo(
      () => {
        let env = last_env_memo.get()
        let last_result = last_type_memo.get()
        let last_type = if last_result.had_error {
          TError
        } else {
          last_result.typ
        }
        let body_type_env = env.extend(last_name, last_type)
        let body_term = body_resolve_memo.get()
        infer_impl(body_type_env, body_term, body_ctx)
      },
      label="body_type",
    )
  }
  state.body_memo = Some(body_memo)
}

///|
/// Update raw-body term signals when structure is unchanged. Per-def
/// resolve runs lazily inside `resolve_memos[i]`; same-value optimization
/// on `Signal::set` means only the edited def's resolve fires.
fn update_terms(
  state : PipelineState,
  defs : Array[(String, TypedTerm)],
  body : TypedTerm,
) -> Unit {
  for i, def in defs {
    state.term_signals[i].set(def.1)
  }
  match state.body_term_signal {
    Some(sig) => sig.set(body)
    None => ()
  }
}

///|
/// Collect results from the Memo chain into a ModuleTypeResult.
///
/// Reads all type_memos inside the parent memo's tracked context, so the
/// parent memo depends on every def. This is intentional: the aggregation
/// must incorporate all results regardless. Per-def incrementality is at
/// the type_memo level — each only recomputes when its own inputs change.
/// The collection here is O(n) reads, not O(n) type-checks.
///
/// Diagnostics are read via `accumulated`, which records a synthetic dep
/// on each per-def buffer. This makes the parent pipeline memo invalidate
/// when a def's diagnostic set changes, independent of whether the def's
/// ordinary output (the `TypeResult`) changed.
fn collect_results(state : PipelineState) -> ModuleTypeResult raise Failure {
  let def_types : Array[(String, TypeResult)] = []
  let all_diagnostics : Array[TypeDiagnostic] = []
  // Module-structure diagnostics (e.g. duplicate top-level defs) are
  // produced in `rebuild_chain` before any per-def compute runs, so
  // surface them first; per-def diagnostics follow in source order.
  for d in state.duplicate_diags {
    all_diagnostics.push(d)
  }
  let diags = match state.diags {
    Some(acc) => acc
    None => fail("collect_results called before rebuild_chain")
  }
  for i, name in state.prev_def_names {
    let type_memo = state.type_memos[i]
    def_types.push((name, type_memo.get()))
    for d in type_memo.accumulated(diags) {
      all_diagnostics.push(d)
    }
  }
  // env_memos, resolve_memos, body_resolve_memo are never read directly
  // from state, but must be kept alive: type_memo and env_memo closures
  // captured references to env_memos[i]; type_memos captured resolve_memos[i];
  // body_memo captured body_resolve_memo. If the arrays/options were
  // collected, those closures would dangle.
  ignore(state.env_memos)
  ignore(state.resolve_memos)
  ignore(state.body_resolve_memo)
  let body_type = match state.body_memo {
    Some(memo) => {
      let r = memo.get()
      for d in memo.accumulated(diags) {
        all_diagnostics.push(d)
      }
      r
    }
    None => { typ: TUnit, had_error: false }
  }
  { body_type, def_types, all_diagnostics }
}
