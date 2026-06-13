// Canonical implementation for Term — returns a representative Term value
// per kind. See @loomcore.Canonical doc-comment for trait-level laws.
//
// Per-implementor contract for Term (the "preserves operationally-relevant
// discriminators" law from the trait):
//
// - `Bop`'s `op` field IS a discriminator: `Bop(Plus)` and `Bop(Minus)`
//   pretty-print differently (`"0 + 0"` vs `"0 - 0"`), so canonical must
//   preserve `op`.
// - `Lam`'s param name is NOT a discriminator: every `Lam` canonicalizes to
//   `(x) => x`. The placeholder is invariant in the param name.
// - `LetDef`'s name is NOT a discriminator: every standalone binding row
//   canonicalizes to `let x = 0`, mirroring the module placeholder row.
// - `Module`'s defs/body are NOT discriminators: every `Module`
//   canonicalizes to a single-binding module with body `Var("x")`. Pinned
//   to `Var("x")` rather than "any" for determinism of future
//   structural-edit consumers.
// - `Unbound`, `Error`, `Hole`: argument is not a discriminator; canonical
//   uses a fixed representative (`"x"`, `"?"`, `0`).
//
// The drift-detector property test in proj_traits_canonical_wbtest.mbt
// enforces alignment between `default_placeholder_via_canonical(self)` and
// the frozen pre-change placeholder mapping for the 9 fitting variants.

///|
pub impl @loomcore.Canonical for Term with fn canonical(self) {
  match self {
    Int(_) => Int(0)
    Var(_) => Var("x")
    Lam(_, _) => Lam("x", Var("x"))
    App(_, _) => App(Var("f"), Var("x"))
    Bop(op, _, _) => Bop(op, Int(0), Int(0))
    If(_, _, _) => If(Int(0), Int(0), Int(0))
    LetDef(_, _) => LetDef("x", Int(0))
    Module(_, _) => Module([("x", Int(0))], Var("x"))
    Unit => Unit
    Unbound(_) => Unbound("x")
    Error(_) => Error("?")
    Hole(_) => Hole(0)
  }
}
