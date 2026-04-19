// Bidirectional type inference and checking.
//
// Two mutually recursive functions:
//   - infer: synthesizes a type for a term (bottom-up)
//   - check: verifies a term has an expected type (top-down)
//
// Diagnostics are emitted via a side-channel `Accumulator[TypeDiagnostic]`
// plumbed through `DiagCtx`. Public `infer` / `check` entry points take no
// accumulator (type-only callers such as unit tests); the incremental
// pipeline calls `infer_impl` / `check_impl` with `ctx.diags = Some(acc)`.
// When `ctx.diags = None`, diagnostic pushes are silently dropped so
// signatures remain uniform.
//
// Error propagation: TError with had_error=true poisons upward. Parents
// check had_error and suppress secondary diagnostics to avoid cascading
// noise.

///|
/// Internal context threaded through inference. `def_name` tags each
/// emitted `TypeDiagnostic`; `diags` is the optional side-channel into
/// which error paths push. When `diags` is `None`, pushes are no-ops.
priv struct DiagCtx {
  def_name : String?
  diags : @incr.Accumulator[TypeDiagnostic]?
}

///|
fn DiagCtx::empty() -> DiagCtx {
  { def_name: None, diags: None }
}

///|
/// Emit a diagnostic message via `ctx.diags` when present. No-op otherwise.
fn emit(ctx : DiagCtx, message : String) -> Unit raise Failure {
  match ctx.diags {
    Some(acc) => acc.push({ message, def_name: ctx.def_name })
    None => ()
  }
}

///|
/// Extract the result type, replacing with TError if had_error.
fn result_type(r : TypeResult) -> Type {
  if r.had_error {
    TError
  } else {
    r.typ
  }
}

///|
fn ok(typ : Type) -> TypeResult {
  { typ, had_error: false }
}

///|
fn err(ctx : DiagCtx, msg : String) -> TypeResult raise Failure {
  emit(ctx, msg)
  { typ: TError, had_error: true }
}

///|
/// Synthesize a type for the given term. Public entry point for callers
/// that don't care about diagnostics (e.g. unit tests). Internally
/// delegates to `infer_impl` with an empty `DiagCtx`; since `diags` is
/// `None`, no `Accumulator::push` executes and `raise Failure` is never
/// triggered in practice.
pub fn infer(env : TypeEnv, term : TypedTerm) -> TypeResult raise Failure {
  infer_impl(env, term, DiagCtx::empty())
}

///|
/// Check that `term` has type `expected`. Public entry point (see `infer`).
pub fn check(
  env : TypeEnv,
  term : TypedTerm,
  expected : Type,
) -> TypeResult raise Failure {
  check_impl(env, term, expected, DiagCtx::empty())
}

///|
fn infer_impl(
  env : TypeEnv,
  term : TypedTerm,
  ctx : DiagCtx,
) -> TypeResult raise Failure {
  match term {
    Int(_) => ok(TInt)
    Unit => ok(TUnit)
    Var(name) =>
      match env.lookup(name) {
        Some(t) => ok(t)
        None => err(ctx, "unbound variable: \{name}")
      }
    Unbound(name) => err(ctx, "unbound variable: \{name}")
    Lam(x, Some(annot), body) =>
      if annot == TError {
        err(ctx, "malformed type annotation")
      } else {
        let ext_env = env.extend(x, annot)
        let body_result = infer_impl(ext_env, body, ctx)
        {
          typ: TArrow(annot, result_type(body_result)),
          had_error: body_result.had_error,
        }
      }
    Lam(_, None, _) => err(ctx, "missing type annotation")
    App(f, arg) => {
      let f_result = infer_impl(env, f, ctx)
      if f_result.had_error {
        // Propagate the function error without secondary diagnostics.
        let _ = infer_impl(env, arg, ctx)
        { typ: TError, had_error: true }
      } else {
        match f_result.typ {
          TArrow(param_t, ret_t) => {
            let arg_result = check_impl(env, arg, param_t, ctx)
            if arg_result.had_error {
              { typ: TError, had_error: true }
            } else {
              { typ: ret_t, had_error: false }
            }
          }
          _ => {
            let _ = infer_impl(env, arg, ctx)
            emit(ctx, "not a function: got \{f_result.typ}")
            { typ: TError, had_error: true }
          }
        }
      }
    }
    Bop(_, l, r) => {
      let l_result = check_impl(env, l, TInt, ctx)
      let r_result = check_impl(env, r, TInt, ctx)
      let had_error = l_result.had_error || r_result.had_error
      { typ: TInt, had_error }
    }
    If(cond, then_branch, else_branch) => {
      let cond_result = check_impl(env, cond, TInt, ctx)
      let then_result = infer_impl(env, then_branch, ctx)
      if then_result.had_error {
        let else_result = infer_impl(env, else_branch, ctx)
        {
          typ: TError,
          had_error: cond_result.had_error ||
          then_result.had_error ||
          else_result.had_error,
        }
      } else {
        let else_result = check_impl(env, else_branch, then_result.typ, ctx)
        {
          typ: then_result.typ,
          had_error: cond_result.had_error ||
          then_result.had_error ||
          else_result.had_error,
        }
      }
    }
    Module(defs, body) => {
      let mut had_error = false
      let mut current_env = env
      for def in defs {
        let (name, expr) = def
        let def_result = infer_impl(current_env, expr, ctx)
        if def_result.had_error {
          had_error = true
        }
        current_env = current_env.extend(name, result_type(def_result))
      }
      let body_result = infer_impl(current_env, body, ctx)
      {
        typ: result_type(body_result),
        had_error: had_error || body_result.had_error,
      }
    }
    Hole(_) => err(ctx, "incomplete expression")
    Error(msg) => err(ctx, msg)
  }
}

///|
fn check_impl(
  env : TypeEnv,
  term : TypedTerm,
  expected : Type,
  ctx : DiagCtx,
) -> TypeResult raise Failure {
  match (term, expected) {
    (Lam(x, None, body), TArrow(param_t, ret_t)) => {
      let ext_env = env.extend(x, param_t)
      let body_result = check_impl(ext_env, body, ret_t, ctx)
      let typ = if body_result.had_error {
        TError
      } else {
        TArrow(param_t, ret_t)
      }
      { typ, had_error: body_result.had_error }
    }
    (Lam(x, Some(annot), body), TArrow(param_t, ret_t)) =>
      if annot != param_t {
        emit(ctx, "annotation mismatch: expected \{param_t}, got \{annot}")
        let ext_env = env.extend(x, param_t)
        let _ = check_impl(ext_env, body, ret_t, ctx)
        { typ: TError, had_error: true }
      } else {
        let ext_env = env.extend(x, annot)
        let body_result = check_impl(ext_env, body, ret_t, ctx)
        let typ = if body_result.had_error {
          TError
        } else {
          TArrow(param_t, ret_t)
        }
        { typ, had_error: body_result.had_error }
      }
    (Lam(_, _, _), _) => err(ctx, "expected \{expected}, got function")
    // Hole / Error in check mode intentionally stay silent: infer_impl
    // emits "incomplete expression" for the same variants, so a parent
    // that routes through infer (e.g. ambiguous contexts) surfaces the
    // diagnostic. Bop/If paths that call check_impl directly rely on
    // had_error alone here — matching pre-accumulator behavior to keep
    // this migration semantics-preserving.
    (Hole(_), _) => { typ: TError, had_error: true }
    (Error(_), _) => { typ: TError, had_error: true }
    _ => {
      let result = infer_impl(env, term, ctx)
      if result.had_error {
        result
      } else if result.typ != expected {
        emit(ctx, "expected \{expected}, got \{result.typ}")
        { typ: TError, had_error: true }
      } else {
        result
      }
    }
  }
}
