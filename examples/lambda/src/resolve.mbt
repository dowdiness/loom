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
pub fn resolve(term : @ast.Term) -> (@ast.Term, Resolution) {
  let res : Map[Int, VarStatus] = {}
  let env : Map[String, Int] = {}
  let counter = Ref::new(0)
  let new_term = resolve_walk(term, env, 0, counter, res)
  (new_term, { vars: res })
}

///|
fn resolve_walk(
  term : @ast.Term,
  env : Map[String, Int],
  depth : Int,
  counter : Ref[Int],
  res : Map[Int, VarStatus],
) -> @ast.Term {
  let node_id = counter.val
  counter.val = counter.val + 1
  match term {
    @ast.Term::Var(x) =>
      match env.get(x) {
        Some(bind_depth) => {
          res[node_id] = Bound(depth=depth - bind_depth)
          term // bound — keep as Var
        }
        None => {
          res[node_id] = Free
          @ast.Term::Unbound(x) // free — rewrite to Unbound
        }
      }
    @ast.Term::Lam(x, body) => {
      let new_env = Map::from_iter(env.iter())
      new_env[x] = depth
      let new_body = resolve_walk(body, new_env, depth + 1, counter, res)
      @ast.Term::Lam(x, new_body)
    }
    @ast.Term::Let(x, val, body) => {
      let new_val = resolve_walk(val, env, depth, counter, res)
      let new_env = Map::from_iter(env.iter())
      new_env[x] = depth
      let new_body = resolve_walk(body, new_env, depth + 1, counter, res)
      @ast.Term::Let(x, new_val, new_body)
    }
    @ast.Term::App(f, a) => {
      let new_f = resolve_walk(f, env, depth, counter, res)
      let new_a = resolve_walk(a, env, depth, counter, res)
      @ast.Term::App(new_f, new_a)
    }
    @ast.Term::Bop(op, l, r) => {
      let new_l = resolve_walk(l, env, depth, counter, res)
      let new_r = resolve_walk(r, env, depth, counter, res)
      @ast.Term::Bop(op, new_l, new_r)
    }
    @ast.Term::If(c, t, e) => {
      let new_c = resolve_walk(c, env, depth, counter, res)
      let new_t = resolve_walk(t, env, depth, counter, res)
      let new_e = resolve_walk(e, env, depth, counter, res)
      @ast.Term::If(new_c, new_t, new_e)
    }
    _ => term // Int, Unit, Error, Unbound — return unchanged
  }
}
