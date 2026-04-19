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
  mut term_signals : Array[@incr.Signal[TypedTerm]]
  // env_memos kept alive so closures that captured them don't dangle
  mut env_memos : Array[@incr.Memo[TypeEnv]]
  mut type_memos : Array[@incr.Memo[TypeResult]]
  mut body_term_signal : @incr.Signal[TypedTerm]?
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
    term_signals: [],
    env_memos: [],
    type_memos: [],
    body_term_signal: None,
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
  let state = PipelineState::new()
  ignore(rt)
  parent_scope.memo(
    () => {
      let term = source_term.get()
      let resolved = resolve_typed(term)
      let def_names = resolved.defs.map(fn(d) { d.0 })
      // Detect structural change: first run or different def names
      let needs_rebuild = match state.chain_scope {
        None => true
        Some(_) => def_names != state.prev_def_names
      }
      if needs_rebuild {
        rebuild_chain(state, parent_scope, resolved)
      } else {
        // Same structure — update term signals with new terms
        update_terms(state, resolved)
      }
      collect_results(state)
    },
    label="typecheck_pipeline",
  )
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
      let idx = entry.encounter_order
      // Guard: after a structural rebuild, an old InternId's encounter_order
      // may index a slot that now holds a different def, or the old type_memo
      // may be disposed. Verify bounds, name match, and liveness before reading.
      if idx < state.type_memos.length() &&
        idx < state.prev_def_names.length() &&
        state.prev_def_names[idx] == entry.name &&
        !state.type_memos[idx].is_disposed() {
        state.type_memos[idx].get()
      } else {
        { typ: TError, had_error: true }
      }
    },
    label="typecheck_index",
  )
  let result_memo = parent_scope.memo(
    () => {
      let term = source_term.get()
      let resolved = resolve_typed(term)
      let def_names = resolved.defs.map(fn(d) { d.0 })
      let needs_rebuild = match state.chain_scope {
        None => true
        Some(_) => def_names != state.prev_def_names
      }
      if needs_rebuild {
        // All wrapper memos in `memo_map` key on InternIds from the previous
        // chain; after rebuild their encounter_order slots are re-assigned, so
        // every existing entry is stale. Dispose them up front — `memo_map`
        // is Runtime-owned, so chain-scope disposal can't reach it.
        memo_map.clear()
        rebuild_chain(state, parent_scope, resolved)
      } else {
        update_terms(state, resolved)
      }
      collect_results(state)
    },
    label="typecheck_pipeline",
  )
  let index : TypecheckIndex = { intern_table: state.intern_table, memo_map }
  (result_memo, index)
}

///|
/// Dispose old chain and build a new Memo chain for the resolved module.
fn rebuild_chain(
  state : PipelineState,
  parent_scope : @incr.Scope,
  resolved : ResolvedModule,
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
  let def_names = resolved.defs.map(fn(d) { d.0 })
  state.prev_def_names = def_names
  // Intern all def names
  for i, def in resolved.defs {
    let _id = state.intern_table.intern({ name: def.0, encounter_order: i })
  }
  // Create term signals for each def
  let term_signals : Array[@incr.Signal[TypedTerm]] = []
  for def in resolved.defs {
    let sig = chain_scope.signal(def.1, label="def_term_\{def.0}")
    term_signals.push(sig)
  }
  state.term_signals = term_signals
  // Build env_memo and type_memo chains
  let env_memos : Array[@incr.Memo[TypeEnv]] = []
  let type_memos : Array[@incr.Memo[TypeResult]] = []
  for i = 0; i < resolved.defs.length(); i = i + 1 {
    let def_name = resolved.defs[i].0
    let term_sig = term_signals[i]
    // env_memo[i]: extends previous env with previous def's type
    let env_memo = if i == 0 {
      chain_scope.memo(() => TypeEnv::Empty, label="env_\{def_name}")
    } else {
      let prev_env_memo = env_memos[i - 1]
      let prev_type_memo = type_memos[i - 1]
      let prev_name = resolved.defs[i - 1].0
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
    // type_memo[i]: infer def body in env_memo[i]. Diagnostics pushed
    // from within `infer_impl` land in the chain-scope accumulator,
    // tagged with this def's name.
    let ctx : DiagCtx = { def_name: Some(def_name), diags: Some(diags) }
    let type_memo = chain_scope.memo(
      () => {
        let env = env_memo.get()
        let body = term_sig.get()
        infer_impl(env, body, ctx)
      },
      label="type_\{def_name}",
    )
    type_memos.push(type_memo)
  }
  state.env_memos = env_memos
  state.type_memos = type_memos
  // Body signal and memo
  let body_sig = chain_scope.signal(resolved.body, label="body_term")
  state.body_term_signal = Some(body_sig)
  // Body diagnostics are untagged (no def_name).
  let body_ctx : DiagCtx = { def_name: None, diags: Some(diags) }
  // Build the final env for the body (extends last env with last def's type)
  let body_memo = if resolved.defs.length() == 0 {
    chain_scope.memo(
      () => {
        let body = body_sig.get()
        infer_impl(TypeEnv::Empty, body, body_ctx)
      },
      label="body_type",
    )
  } else {
    let last_idx = resolved.defs.length() - 1
    let last_env_memo = env_memos[last_idx]
    let last_type_memo = type_memos[last_idx]
    let last_name = resolved.defs[last_idx].0
    chain_scope.memo(
      () => {
        let env = last_env_memo.get()
        let last_result = last_type_memo.get()
        let last_type = if last_result.had_error {
          TError
        } else {
          last_result.typ
        }
        let body_env = env.extend(last_name, last_type)
        let body = body_sig.get()
        infer_impl(body_env, body, body_ctx)
      },
      label="body_type",
    )
  }
  state.body_memo = Some(body_memo)
}

///|
/// Update term signals when structure is unchanged.
fn update_terms(state : PipelineState, resolved : ResolvedModule) -> Unit {
  for i, def in resolved.defs {
    state.term_signals[i].set(def.1)
  }
  match state.body_term_signal {
    Some(sig) => sig.set(resolved.body)
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
  let diags = match state.diags {
    Some(acc) => acc
    None => abort("collect_results called before rebuild_chain")
  }
  for i, name in state.prev_def_names {
    let type_memo = state.type_memos[i]
    def_types.push((name, type_memo.get()))
    for d in type_memo.accumulated(diags) {
      all_diagnostics.push(d)
    }
  }
  // env_memos are never read directly, but must be kept alive: type_memo
  // and env_memo closures captured references to the env_memos array
  // elements. If the array were collected, those closures would dangle.
  ignore(state.env_memos)
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
