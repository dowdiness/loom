///|
pub(all) enum Value {
  VInt(Int)
  VClosure(Env, @ast.VarName, @ast.Term)
  VUnit
} derive(Show, Eq, Debug)

///|
pub(all) suberror StuckReason {
  Unbound(@ast.VarName)
  TypeMismatch(String)
  Incomplete
  ParseError
  Divergence
} derive(Show)

///|
pub(all) struct Env {
  bindings : Map[String, Value]
} derive(Show, Eq, Debug)

///|
pub fn Env::empty() -> Env {
  { bindings: {} }
}

///|
pub fn Env::lookup(self : Env, name : String) -> Value? {
  self.bindings.get(name)
}

///|
pub fn Env::extend(self : Env, name : String, value : Value) -> Env {
  let new_bindings = self.bindings
  new_bindings[name] = value
  { bindings: new_bindings }
}

///|
pub fn eval(
  env : Env,
  term : @ast.Term,
  fuel? : Int = 1000,
) -> Value raise StuckReason {
  if fuel <= 0 {
    raise Divergence
  }
  match term {
    Int(n) => VInt(n)
    Unit => VUnit
    Var(x) =>
      match env.lookup(x) {
        Some(v) => v
        None => raise Unbound(x)
      }
    Hole(_) => raise Incomplete
    Error(_) => raise ParseError
    Unbound(x) => raise Unbound(x)
    Lam(x, body) => VClosure(env, x, body)
    Bop(op, a, b) => {
      let va = eval(env, a, fuel=fuel - 1)
      let vb = eval(env, b, fuel=fuel - 1)
      match (op, va, vb) {
        (Plus, VInt(na), VInt(nb)) => VInt(na + nb)
        (Minus, VInt(na), VInt(nb)) => VInt(na - nb)
        (Plus, _, _) => raise TypeMismatch("add: expected integer")
        (Minus, _, _) => raise TypeMismatch("minus: expected integer")
      }
    }
    _ => raise TypeMismatch("not yet implemented")
  }
}
