// Tests for `Canonical for Term` and the canonical/placeholder drift
// detector.
//
// IMPORTANT: `hand_written_placeholder_reference` below MUST NOT call
// `@loomcore.Renderable::placeholder` (directly or indirectly). After
// rewiring in proj_traits.mbt, `placeholder` delegates to
// `default_placeholder_via_canonical` for fitting variants, so calling it
// from this reference would make the drift test trivially circular. The
// whole point of the test is to verify that `canonical(t) |> pretty_unparse`
// equals the *frozen pre-change* placeholder mapping declared here as
// string literals.

///|
/// Frozen, pre-change placeholder mapping. Returns `Some` for the 9
/// fitting variants and `None` for the 3 carve-outs (Module/Unbound/Error).
/// Carve-outs are excluded from the drift check.
fn hand_written_placeholder_reference(t : Term) -> String? {
  match t {
    Int(_) => Some("0")
    Var(_) => Some("x")
    Lam(_, _) => Some("λx. x")
    App(_, _) => Some("f x")
    Bop(Plus, _, _) => Some("0 + 0")
    Bop(Minus, _, _) => Some("0 - 0")
    If(_, _, _) => Some("if 0 then 0 else 0")
    Unit => Some("()")
    Hole(_) => Some("_")
    Module(_, _) | Unbound(_) | Error(_) => None
  }
}

// --- Property tests ----------------------------------------------------

///|
/// Law 1: `same_kind(canonical(t), t)` for all `t`.
fn prop_canonical_same_kind(t : Term) -> Bool {
  @loomcore.TreeNode::same_kind(t, @loomcore.Canonical::canonical(t))
}

///|
test "property: Canonical preserves kind" {
  @qc.quick_check_fn(prop_canonical_same_kind)
}

///|
/// Law 2: `canonical(canonical(t)) == canonical(t)` (idempotence).
fn prop_canonical_idempotent(t : Term) -> Bool {
  let c = @loomcore.Canonical::canonical(t)
  @loomcore.Canonical::canonical(c) == c
}

///|
test "property: Canonical is idempotent" {
  @qc.quick_check_fn(prop_canonical_idempotent)
}

///|
/// Drift detector: `default_placeholder_via_canonical(t)` matches the
/// frozen reference for fitting variants. If this fails, either
/// `canonical` was changed in a way that drops an operationally-relevant
/// discriminator, or the `Pretty` impl's layout changed for a canonical
/// instance. Both are real drift conditions; update the carve-out
/// declaration or fix the regression, do not suppress the test.
fn prop_default_placeholder_matches_reference(t : Term) -> Bool {
  match hand_written_placeholder_reference(t) {
    None => true // carve-out: not asserted
    Some(ref_str) => @loomcore.default_placeholder_via_canonical(t) == ref_str
  }
}

///|
test "property: default_placeholder_via_canonical matches frozen reference" {
  @qc.quick_check_fn(prop_default_placeholder_matches_reference)
}

// --- Per-variant inspect coverage --------------------------------------
//
// The @qc generator (see term_arbitrary.mbt) produces Int/Var/Lam/App/Bop/
// If/Module at all depths plus Unit at leaf depth — but never Unbound,
// Error, or Hole. Cover all 11 variants explicitly so a change to
// `canonical` is caught even for variants the generator can't reach.

///|
test "canonical: Int" {
  inspect(
    @loomcore.Canonical::canonical(Term::Int(42)),
    content=(
      #|Int(0)
    ),
  )
}

///|
test "canonical: Var" {
  inspect(
    @loomcore.Canonical::canonical(Term::Var("foo")),
    content=(
      #|Var("x")
    ),
  )
}

///|
test "canonical: Lam (param name discarded)" {
  inspect(
    @loomcore.Canonical::canonical(Term::Lam("y", Term::Var("y"))),
    content=(
      #|Lam("x", Var("x"))
    ),
  )
}

///|
test "canonical: App" {
  inspect(
    @loomcore.Canonical::canonical(Term::App(Term::Var("g"), Term::Int(3))),
    content=(
      #|App(Var("f"), Var("x"))
    ),
  )
}

///|
test "canonical: Bop preserves op (Plus)" {
  inspect(
    @loomcore.Canonical::canonical(Term::Bop(Plus, Term::Int(1), Term::Int(2))),
    content=(
      #|Bop(Plus, Int(0), Int(0))
    ),
  )
}

///|
test "canonical: Bop preserves op (Minus)" {
  inspect(
    @loomcore.Canonical::canonical(Term::Bop(Minus, Term::Int(1), Term::Int(2))),
    content=(
      #|Bop(Minus, Int(0), Int(0))
    ),
  )
}

///|
test "canonical: If" {
  inspect(
    @loomcore.Canonical::canonical(
      Term::If(Term::Int(1), Term::Int(2), Term::Int(3)),
    ),
    content=(
      #|If(Int(0), Int(0), Int(0))
    ),
  )
}

///|
test "canonical: Module pinned to Var(\"x\") body" {
  inspect(
    @loomcore.Canonical::canonical(
      Term::Module([("a", Term::Int(1))], Term::Var("a")),
    ),
    content=(
      #|Module([("x", Int(0))], Var("x"))
    ),
  )
}

///|
test "canonical: Unit" {
  inspect(
    @loomcore.Canonical::canonical(Term::Unit),
    content=(
      #|Unit
    ),
  )
}

///|
test "canonical: Unbound (arg discarded)" {
  inspect(
    @loomcore.Canonical::canonical(Term::Unbound("foo")),
    content=(
      #|Unbound("x")
    ),
  )
}

///|
test "canonical: Error (arg discarded)" {
  inspect(
    @loomcore.Canonical::canonical(Term::Error("oops")),
    content=(
      #|Error("?")
    ),
  )
}

///|
test "canonical: Hole (arg discarded)" {
  inspect(
    @loomcore.Canonical::canonical(Term::Hole(42)),
    content=(
      #|Hole(0)
    ),
  )
}

// --- Per-variant placeholder snapshots ---------------------------------
//
// Lock the current placeholder string for every variant. Carve-outs
// (Module/Unbound/Error) bypass the canonical path; fitting variants go
// through `default_placeholder_via_canonical`. Both should produce the
// strings in `hand_written_placeholder_reference` (for fitting) or the
// hand-written branches (for carve-outs).

///|
test "placeholder: all variants match expected strings" {
  let cases : Array[(Term, String)] = [
    (Int(7), "0"),
    (Var("y"), "x"),
    (Lam("y", Var("y")), "λx. x"),
    (App(Var("g"), Int(3)), "f x"),
    (Bop(Plus, Int(1), Int(2)), "0 + 0"),
    (Bop(Minus, Int(1), Int(2)), "0 - 0"),
    (If(Int(1), Int(2), Int(3)), "if 0 then 0 else 0"),
    (Module([("a", Int(1))], Var("a")), "let x = 0"),
    (Unit, "()"),
    (Unbound("foo"), "x"),
    (Error("oops"), "?"),
    (Hole(42), "_"),
  ]
  for case in cases {
    let (t, expected) = case
    let actual = @loomcore.Renderable::placeholder(t)
    if actual != expected {
      fail("placeholder(\{t}) = \{actual}, expected \{expected}")
    }
  }
}
