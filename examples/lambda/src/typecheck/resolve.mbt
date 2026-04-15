// Name resolution on TypedTerm trees.
//
// Walks the term building an environment of bound names.
// Variables found in env stay as Var(name); variables not found
// become Unbound(name). Module defs are scoped sequentially.

///|
/// Resolve variable names in a TypedTerm tree, returning a
/// ResolvedModule with free variables rewritten to Unbound.
pub fn resolve_typed(term : TypedTerm) -> ResolvedModule {
  match term {
    Module(defs, body) => {
      let env : Map[String, Bool] = {}
      let resolved_defs : Array[(String, TypedTerm)] = []
      for def in defs {
        let resolved = resolve_walk(def.1, env)
        env[def.0] = true
        resolved_defs.push((def.0, resolved))
      }
      { defs: resolved_defs, body: resolve_walk(body, env) }
    }
    _ => { defs: [], body: resolve_walk(term, {}) }
  }
}

///|
fn resolve_walk(term : TypedTerm, env : Map[String, Bool]) -> TypedTerm {
  match term {
    Var(name) => if env.contains(name) { term } else { Unbound(name) }
    Lam(x, annot, body) => {
      let new_env = Map::from_iter(env.iter())
      new_env[x] = true
      Lam(x, annot, resolve_walk(body, new_env))
    }
    App(f, arg) => App(resolve_walk(f, env), resolve_walk(arg, env))
    Bop(op, l, r) => Bop(op, resolve_walk(l, env), resolve_walk(r, env))
    If(c, t, e) =>
      If(resolve_walk(c, env), resolve_walk(t, env), resolve_walk(e, env))
    Module(defs, body) => {
      let new_env = Map::from_iter(env.iter())
      let resolved_defs : Array[(String, TypedTerm)] = []
      for def in defs {
        let resolved = resolve_walk(def.1, new_env)
        new_env[def.0] = true
        resolved_defs.push((def.0, resolved))
      }
      Module(resolved_defs, resolve_walk(body, new_env))
    }
    _ => term // Int, Unit, Unbound, Error, Hole unchanged
  }
}
