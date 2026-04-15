// Term → TypedTerm conversion.
//
// A recursive 1:1 mapping from the untyped AST to the typed term
// representation. This conversion is purely structural — it does not
// perform any type inference or checking. Lambdas get a None annotation
// (no type hint yet), to be filled in by the type checker.

///|
/// Convert a raw `Term` from the AST into a `TypedTerm` suitable for
/// type checking. No type information is inferred at this stage.
pub fn convert(term : @ast.Term) -> TypedTerm {
  match term {
    Int(n) => TypedTerm::Int(n)
    Unit => TypedTerm::Unit
    Var(name) => TypedTerm::Var(name)
    Lam(name, body) => TypedTerm::Lam(name, None, convert(body))
    App(func, arg) => TypedTerm::App(convert(func), convert(arg))
    Bop(op, l, r) => TypedTerm::Bop(op, convert(l), convert(r))
    If(cond, then_branch, else_branch) =>
      TypedTerm::If(convert(cond), convert(then_branch), convert(else_branch))
    Module(defs, body) =>
      TypedTerm::Module(defs.map(fn(d) { (d.0, convert(d.1)) }), convert(body))
    Unbound(name) => TypedTerm::Unbound(name)
    Error(msg) => TypedTerm::Error(msg)
    Hole(id) => TypedTerm::Hole(id)
  }
}
