// Mechanical TreeNode and Renderable implementations for Term.
//
// "Mechanical" = derivable from the enum definition alone, no human judgment.
// These impls delegate to sym.mbt (children_of) or pattern-match on
// constructor shape (same_kind, kind_tag).
//
// Semantic impls (label, placeholder, unparse) require human judgment
// and live in proj_traits.mbt.
//
// Do NOT add display logic here — that belongs in proj_traits.mbt.

///|
pub impl @loomcore.TreeNode for Term with children(self) {
  children_of(self)
}

///|
pub impl @loomcore.TreeNode for Term with same_kind(self, other) {
  match (self, other) {
    (Int(_), Int(_)) => true
    (Var(_), Var(_)) => true
    (Lam(_, _), Lam(_, _)) => true
    (App(_, _), App(_, _)) => true
    (Bop(_, _, _), Bop(_, _, _)) => true
    (If(_, _, _), If(_, _, _)) => true
    (Module(_, _), Module(_, _)) => true
    (Unit, Unit) => true
    (Error(_), Error(_)) => true
    (Unbound(_), Unbound(_)) => true
    (Hole(_), Hole(_)) => true
    _ => false
  }
}

///|
pub impl @loomcore.Renderable for Term with kind_tag(self) {
  match self {
    Int(_) => "Int"
    Var(_) => "Var"
    Lam(_, _) => "Lam"
    App(_, _) => "App"
    Bop(_, _, _) => "Bop"
    If(_, _, _) => "If"
    Module(_, _) => "Module"
    Unit => "Unit"
    Unbound(_) => "Unbound"
    Error(_) => "Error"
    Hole(_) => "Hole"
  }
}
