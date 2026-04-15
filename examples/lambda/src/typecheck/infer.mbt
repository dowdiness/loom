// Bidirectional type inference and checking.
//
// Two mutually recursive functions:
//   - infer: synthesizes a type for a term (bottom-up)
//   - check: verifies a term has an expected type (top-down)
//
// Error propagation: TError with had_error=true poisons upward.
// Each error source emits exactly one diagnostic. Parents check
// had_error and suppress secondary diagnostics to avoid cascading noise.

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
  { typ, had_error: false, diagnostics: [] }
}

///|
fn err(msg : String) -> TypeResult {
  {
    typ: TError,
    had_error: true,
    diagnostics: [{ message: msg, def_name: None }],
  }
}

///|
fn merge_diagnostics(results : Array[TypeResult], typ : Type) -> TypeResult {
  let all_diags : Array[TypeDiagnostic] = []
  let mut had_error = false
  for r in results {
    if r.had_error {
      had_error = true
    }
    for d in r.diagnostics {
      all_diags.push(d)
    }
  }
  { typ, had_error, diagnostics: all_diags }
}

///|
/// Synthesize a type for the given term in the given environment.
pub fn infer(env : TypeEnv, term : TypedTerm) -> TypeResult {
  match term {
    Int(_) => ok(TInt)
    Unit => ok(TUnit)
    Var(name) =>
      match env.lookup(name) {
        Some(t) => ok(t)
        None => err("unbound variable: \{name}")
      }
    Unbound(name) => err("unbound variable: \{name}")
    Lam(x, Some(annot), body) =>
      if annot == TError {
        err("malformed type annotation")
      } else {
        let ext_env = env.extend(x, annot)
        let body_result = infer(ext_env, body)
        {
          typ: TArrow(annot, result_type(body_result)),
          had_error: body_result.had_error,
          diagnostics: body_result.diagnostics,
        }
      }
    Lam(_, None, _) => err("missing type annotation")
    App(f, arg) => {
      let f_result = infer(env, f)
      if f_result.had_error {
        // Propagate the function error without secondary diagnostics
        let arg_result = infer(env, arg)
        if arg_result.had_error {
          merge_diagnostics([f_result, arg_result], TError)
        } else {
          { ..f_result, typ: TError }
        }
      } else {
        match f_result.typ {
          TArrow(param_t, ret_t) => {
            let arg_result = check(env, arg, param_t)
            if arg_result.had_error {
              merge_diagnostics([f_result, arg_result], TError)
            } else {
              merge_diagnostics([f_result, arg_result], ret_t)
            }
          }
          _ => {
            let arg_result = infer(env, arg)
            let diags : Array[TypeDiagnostic] = []
            for d in f_result.diagnostics {
              diags.push(d)
            }
            for d in arg_result.diagnostics {
              diags.push(d)
            }
            diags.push({
              message: "not a function: got \{f_result.typ}",
              def_name: None,
            })
            { typ: TError, had_error: true, diagnostics: diags }
          }
        }
      }
    }
    Bop(_, l, r) => {
      let l_result = check(env, l, TInt)
      let r_result = check(env, r, TInt)
      merge_diagnostics([l_result, r_result], TInt)
    }
    If(cond, then_branch, else_branch) => {
      let cond_result = check(env, cond, TInt)
      let then_result = infer(env, then_branch)
      if then_result.had_error {
        let else_result = infer(env, else_branch)
        merge_diagnostics([cond_result, then_result, else_result], TError)
      } else {
        let else_result = check(env, else_branch, then_result.typ)
        merge_diagnostics(
          [cond_result, then_result, else_result],
          then_result.typ,
        )
      }
    }
    Module(defs, body) => {
      let all_results : Array[TypeResult] = []
      let mut current_env = env
      for def in defs {
        let (name, expr) = def
        let def_result = infer(current_env, expr)
        all_results.push(def_result)
        current_env = current_env.extend(name, result_type(def_result))
      }
      let body_result = infer(current_env, body)
      all_results.push(body_result)
      merge_diagnostics(all_results, result_type(body_result))
    }
    Hole(_) => err("incomplete expression")
    Error(msg) => err(msg)
  }
}

///|
/// Check that the given term has the expected type.
/// Uses type information from the context to guide type inference
/// (e.g., unannotated lambdas can get their parameter type from context).
pub fn check(env : TypeEnv, term : TypedTerm, expected : Type) -> TypeResult {
  match (term, expected) {
    (Lam(x, None, body), TArrow(param_t, ret_t)) => {
      let ext_env = env.extend(x, param_t)
      let body_result = check(ext_env, body, ret_t)
      let typ = if body_result.had_error {
        TError
      } else {
        TArrow(param_t, ret_t)
      }
      { ..body_result, typ, }
    }
    (Lam(x, Some(annot), body), TArrow(param_t, ret_t)) =>
      if annot != param_t {
        let diag : TypeDiagnostic = {
          message: "annotation mismatch: expected \{param_t}, got \{annot}",
          def_name: None,
        }
        let ext_env = env.extend(x, param_t)
        let body_result = check(ext_env, body, ret_t)
        let all_diags : Array[TypeDiagnostic] = [diag]
        for d in body_result.diagnostics {
          all_diags.push(d)
        }
        { typ: TError, had_error: true, diagnostics: all_diags }
      } else {
        let ext_env = env.extend(x, annot)
        let body_result = check(ext_env, body, ret_t)
        let typ = if body_result.had_error {
          TError
        } else {
          TArrow(param_t, ret_t)
        }
        { ..body_result, typ, }
      }
    (Lam(_, _, _), _) => err("expected \{expected}, got function")
    (Hole(_), _) => { typ: TError, had_error: true, diagnostics: [] }
    (Error(_), _) => { typ: TError, had_error: true, diagnostics: [] }
    _ => {
      let result = infer(env, term)
      if result.had_error {
        result
      } else if result.typ != expected {
        let diags : Array[TypeDiagnostic] = []
        for d in result.diagnostics {
          diags.push(d)
        }
        diags.push({
          message: "expected \{expected}, got \{result.typ}",
          def_name: None,
        })
        { typ: TError, had_error: true, diagnostics: diags }
      } else {
        result
      }
    }
  }
}
