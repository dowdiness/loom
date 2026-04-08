// Semantic Renderable implementations for Term.
//
// "Semantic" = requires human judgment about how to display each variant.
// These are always hand-written — codegen cannot produce them.
//
// Mechanical impls (children, same_kind, kind_tag) are in
// proj_traits_mechanical.mbt. Structural source of truth is in sym.mbt.

///|
pub impl @loomcore.Renderable for Term with label(self) {
  match self {
    Int(n) => n.to_string()
    Var(name) => name
    Lam(param, _) => "\u{03BB}" + param
    App(_, _) => "App"
    Bop(op, _, _) => @debug.to_string(op)
    If(_, _, _) => "if"
    Module(defs, _) => {
      let names = defs.map(fn(d) { d.0 })
      "module [" + names.join(", ") + "]"
    }
    Unit => "()"
    Unbound(name) => "?" + name
    Error(msg) => "Error: " + msg
    Hole(_) => "_"
  }
}

///|
pub impl @loomcore.Renderable for Term with placeholder(self) {
  match self {
    Int(_) => "0"
    Var(_) => "x"
    Lam(_, _) => "\u{03BB}x. x"
    App(_, _) => "f x"
    Bop(Plus, _, _) => "0 + 0"
    Bop(Minus, _, _) => "0 - 0"
    If(_, _, _) => "if 0 then 0 else 0"
    Module(_, _) => "let x = 0"
    Unit => "()"
    Unbound(_) => "x"
    Error(_) => "?"
    Hole(_) => "_"
  }
}

///|
pub impl @loomcore.Renderable for Term with unparse(self) {
  print_term(self)
}
