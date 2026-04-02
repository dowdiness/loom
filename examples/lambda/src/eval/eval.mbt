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
    If(cond, then_branch, else_branch) => {
      let vc = eval(env, cond, fuel=fuel - 1)
      match vc {
        VInt(0) => eval(env, else_branch, fuel=fuel - 1)
        VInt(_) => eval(env, then_branch, fuel=fuel - 1)
        _ => raise TypeMismatch("if: expected integer condition")
      }
    }
    App(func, arg) => {
      let vf = eval(env, func, fuel=fuel - 1)
      let va = eval(env, arg, fuel=fuel - 1)
      match vf {
        VClosure(closure_env, param, body) => {
          let ext = closure_env.extend(param, va)
          eval(ext, body, fuel=fuel - 1)
        }
        _ => raise TypeMismatch("app: expected function")
      }
    }
    _ => raise TypeMismatch("not yet implemented")
  }
}
