// resolve.mbt — Name resolution for lambda calculus Terms.
// Maps each Var node to Bound(depth) or Free, keyed by pre-order traversal index.

///|
pub(all) enum VarStatus {
  Bound(depth~ : Int)
  Free
} derive(Show, Eq)

///|
pub(all) struct Resolution {
  vars : Map[Int, VarStatus]
} derive(Show, Eq)

///|
pub fn resolve(term : @ast.Term) -> Resolution {
  let res : Map[Int, VarStatus] = {}
  let env : Map[String, Int] = {}
  let counter = Ref::new(0)
  resolve_walk(term, env, 0, counter, res)
  { vars: res }
}

///|
fn resolve_walk(
  term : @ast.Term,
  env : Map[String, Int],
  depth : Int,
  counter : Ref[Int],
  res : Map[Int, VarStatus],
) -> Unit {
  let node_id = counter.val
  counter.val = counter.val + 1
  match term {
    @ast.Term::Var(x) =>
      match env.get(x) {
        Some(bind_depth) => res[node_id] = Bound(depth=depth - bind_depth)
        None => res[node_id] = Free
      }
    @ast.Term::Lam(x, body) => {
      let new_env = Map::from_iter(env.iter())
      new_env[x] = depth
      resolve_walk(body, new_env, depth + 1, counter, res)
    }
    @ast.Term::Let(x, val, body) => {
      resolve_walk(val, env, depth, counter, res)
      let new_env = Map::from_iter(env.iter())
      new_env[x] = depth
      resolve_walk(body, new_env, depth + 1, counter, res)
    }
    @ast.Term::App(f, a) => {
      resolve_walk(f, env, depth, counter, res)
      resolve_walk(a, env, depth, counter, res)
    }
    @ast.Term::Bop(_, l, r) => {
      resolve_walk(l, env, depth, counter, res)
      resolve_walk(r, env, depth, counter, res)
    }
    @ast.Term::If(c, t, e) => {
      resolve_walk(c, env, depth, counter, res)
      resolve_walk(t, env, depth, counter, res)
      resolve_walk(e, env, depth, counter, res)
    }
    _ => () // Int, Unit, Error — no children, no vars
  }
}
