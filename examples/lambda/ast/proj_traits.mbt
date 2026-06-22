// Semantic Renderable implementations for Term.
//
// "Semantic" = requires human judgment about how to display each variant.
// These are always hand-written — codegen cannot produce them.
//
// Mechanical impls (children, same_kind, kind_tag) are in
// proj_traits_mechanical.mbt. Structural source of truth is in sym.mbt.

///|
pub impl @loomcore.Renderable for Term with fn label(self) {
  match self {
    Int(n) => n.to_string()
    Var(name) => name
    Lam(param, _) => "(" + param + ") =>"
    App(_, _) => "App"
    Bop(op, _, _) => @debug.to_string(op)
    If(_, _, _) => "if"
    LetDef(name, _) => "let " + name
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
pub impl @loomcore.Renderable for Term with fn placeholder(self) {
  match self {
    // Carve-outs (hand-written): placeholder semantics do not align with
    // pretty-printing the canonical instance.
    //   - Module: Pretty's `mod` impl unconditionally emits `body` on a
    //     hardline (`pretty_traits.mbt` `mod`), so the canonical form
    //     `Module([("x", Int(0))], Var("x"))` pretty-prints as
    //     `"let x = 0\nx"`, not the single-line user-input template
    //     `"let x = 0"` the editor expects. Standalone `LetDef` uses
    //     the default path because it has no module body line.
    //   - Unbound/Error: diagnostic kinds whose placeholders are
    //     user-input templates (`"x"`, `"?"`), not the diagnostic-decorated
    //     pretty form (`"<unbound: x>"`, `"<error: ?>"`).
    Module(_, _) => "let x = 0"
    Unbound(_) => "x"
    Error(_) => "?"
    // Fitting variants — delegate to canonical + pretty_unparse.
    _ => @loomcore.default_placeholder_via_canonical(self)
  }
}

///|
pub impl @loomcore.Renderable for Term with fn unparse(self) {
  print_term(self)
}
