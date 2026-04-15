// Name resolution on TypedTerm trees.
//
// Walks the term building an environment of bound names.
// Variables found in env stay as Var(name); variables not found
// become Unbound(name). Module defs are scoped sequentially.

///|
/// Immutable set of bound names. Persistent linked list — extending
/// creates a new head node without copying, so nested scopes are O(1).
priv enum ResolveEnv {
  Empty
  Bind(ResolveEnv, String)
}

///|
fn ResolveEnv::contains(self : ResolveEnv, name : String) -> Bool {
  match self {
    Empty => false
    Bind(parent, n) => if n == name { true } else { parent.contains(name) }
  }
}

///|
fn ResolveEnv::extend(self : ResolveEnv, name : String) -> ResolveEnv {
  Bind(self, name)
}

///|
/// Resolve variable names in a TypedTerm tree, returning a
/// ResolvedModule with free variables rewritten to Unbound.
pub fn resolve_typed(term : TypedTerm) -> ResolvedModule {
  match term {
    Module(defs, body) => {
      let mut env : ResolveEnv = Empty
      let resolved_defs : Array[(String, TypedTerm)] = []
      for def in defs {
        let resolved = resolve_walk(def.1, env)
        env = env.extend(def.0)
        resolved_defs.push((def.0, resolved))
      }
      { defs: resolved_defs, body: resolve_walk(body, env) }
    }
    _ => { defs: [], body: resolve_walk(term, Empty) }
  }
}

///|
fn resolve_walk(term : TypedTerm, env : ResolveEnv) -> TypedTerm {
  match term {
    Var(name) => if env.contains(name) { term } else { Unbound(name) }
    Lam(x, annot, body) => Lam(x, annot, resolve_walk(body, env.extend(x)))
    App(f, arg) => App(resolve_walk(f, env), resolve_walk(arg, env))
    Bop(op, l, r) => Bop(op, resolve_walk(l, env), resolve_walk(r, env))
    If(c, t, e) =>
      If(resolve_walk(c, env), resolve_walk(t, env), resolve_walk(e, env))
    Module(defs, body) => {
      let mut inner_env = env
      let resolved_defs : Array[(String, TypedTerm)] = []
      for def in defs {
        let resolved = resolve_walk(def.1, inner_env)
        inner_env = inner_env.extend(def.0)
        resolved_defs.push((def.0, resolved))
      }
      Module(resolved_defs, resolve_walk(body, inner_env))
    }
    _ => term // Int, Unit, Unbound, Error, Hole unchanged
  }
}
