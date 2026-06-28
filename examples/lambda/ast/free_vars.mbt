// free_vars.mbt — free-variable analysis as a TermSym interpretation.
//
// A worked example of adding a new interpretation by REUSING the existing
// fold (`replay`, ast/sym.mbt) and the `TermSym` tagless algebra. There is no
// new recursion here: each method is a per-constructor combine over the
// already-folded children that `replay` hands in.
//
// Representation: an immutable hash set. A free-variable set is semantically
// unordered, so we model it as a set and sort only at the `free_vars`
// boundary, where ordering is a presentation concern.

///|
/// The free variables of a subterm, accumulated bottom-up by `replay`.
struct FreeVars {
  set : @immut_hashset.HashSet[VarName]
}

///|
fn FreeVars::empty() -> FreeVars {
  { set: @immut_hashset.HashSet::new() }
}

///|
fn FreeVars::single(name : VarName) -> FreeVars {
  { set: @immut_hashset.HashSet::new().add(name) }
}

///|
fn FreeVars::union(self : FreeVars, other : FreeVars) -> FreeVars {
  { set: self.set.union(other.set) }
}

///|
/// Discharge a bound name: it is not free in the term that binds it.
fn FreeVars::without(self : FreeVars, name : VarName) -> FreeVars {
  { set: self.set.remove(name) }
}

// ── TermSym interpretation ─────────────────────────────────────────────
// Leaves contribute nothing or a single reference; branches union their
// already-folded children; binders discharge the names they bind.

///|
impl TermSym for FreeVars with fn int_lit(_n) {
  FreeVars::empty()
}

///|
impl TermSym for FreeVars with fn variable(x) {
  FreeVars::single(x)
}

///|
impl TermSym for FreeVars with fn unit() {
  FreeVars::empty()
}

///|
/// `Lam` binds `x` in `body` — the worked example of binder discharge.
/// The `mod` case below applies the same idea to a set of names.
impl TermSym for FreeVars with fn lam(x, body) {
  body.without(x)
}

///|
impl TermSym for FreeVars with fn app(f, a) {
  f.union(a)
}

///|
impl TermSym for FreeVars with fn bop(_op, l, r) {
  l.union(r)
}

///|
impl TermSym for FreeVars with fn if_then_else(c, t, e) {
  c.union(t).union(e)
}

///|
/// A standalone `LetDef`'s name is bound by its enclosing module, not within
/// its own init, so the init's free set passes through unchanged.
impl TermSym for FreeVars with fn let_def(_name, init) {
  init
}

///|
/// An unbound name is still a free reference — no binder discharges it.
impl TermSym for FreeVars with fn unbound(x) {
  FreeVars::single(x)
}

///|
impl TermSym for FreeVars with fn error_term(_msg) {
  FreeVars::empty()
}

///|
impl TermSym for FreeVars with fn hole(_n) {
  FreeVars::empty()
}

///|
impl TermSym for FreeVars with fn mod(defs, body) {
  // Module scoping (mutually-recursive): a definition's name is in scope
  // across every def and the body, so we discharge it from the *full*
  // combined free set. Two phases keep `union` (order-independent) separate
  // from `without` (order-sensitive) — otherwise a later def's union could
  // re-introduce a name an earlier step already removed.
  let combined = defs.fold(init=body, (acc, d) => acc.union(d.1))
  defs.fold(init=combined, (acc, d) => acc.without(d.0))
}

///|
/// Free variables of `term`, sorted for a deterministic, presentation-stable
/// result. Internally, `replay` folds the term into a `FreeVars` set.
pub fn free_vars(term : Term) -> Array[VarName] {
  let names = (replay(term) : FreeVars).set.iter().to_array()
  names.sort()
  names
}
