# ADR: `Canonical` Companion Trait

**Date:** 2026-05-17
**Status:** Accepted
**Implementation plan:** [docs/archive/completed-phases/2026-05-17-canonical-trait.md](../archive/completed-phases/2026-05-17-canonical-trait.md)

## Context

Two pre-existing capability traits in `dowdiness/loom/core` cover
projectional-editor needs:

- `TreeNode` — structural access (children, same_kind).
- `Renderable` — display + serialization (kind_tag, label, placeholder, unparse).

`Renderable::placeholder` returned a string template per kind — for example
`Term::Bop(Plus, _, _) → "0 + 0"`, `Term::Lam(_, _) → "(x) => x"`. For most
variants this string was the pretty-printed form of a canonical instance
(`Bop(Plus, Int(0), Int(0))`, `Lam("x", Var("x"))`), so the placeholder
duplicated information that was *implicitly* present elsewhere — the
`@pretty.Pretty` impl on the same type could produce it directly given a
canonical value. The duplication was load-bearing only because no API
exposed "give me a representative `Self` value for this kind."

This blocked a second motivation as well: a structural-edit primitive
where an editor inserting a fresh node of a given kind could take a typed
`Self` directly instead of round-tripping `placeholder → re-parse → Self`.

## Decision

Add a third capability trait in `dowdiness/loom/core`:

```moonbit
pub(open) trait Canonical {
  canonical(Self) -> Self
}
```

Three laws apply, documented on the trait but *not* compile-checked
(MoonBit's trait system has no associated types or generic methods that
could express them):

1. **`same_kind`-preservation** — `same_kind(canonical(t), t)` for all `t`.
2. **Idempotence** — `canonical(canonical(t)) == canonical(t)`.
3. **Preserves operationally-relevant discriminators** — implementor-
   specific (e.g. `Bop`'s `op` field is part of the kind for placeholder
   purposes; `Lam`'s param name is not).

Pair the trait with a free function in the same package:

```moonbit
pub fn[T : Canonical + @pretty.Pretty] default_placeholder_via_canonical(
  t : T,
) -> String {
  @pretty.pretty_unparse(Canonical::canonical(t))
}
```

Implementor types whose placeholder semantics align with the pretty-printed
canonical form can call this from `Renderable::placeholder`; variants whose
semantics don't align stay hand-written as deliberate carve-outs.

`Canonical for Term` and `Canonical for JsonValue` ship in the same change,
covering 9/12 Term variants and 6/7 JsonValue variants via the free
function. Carve-outs: Term's `Module` (Pretty's `mod` impl unconditionally
emits hardline + body), `Unbound` / `Error` (diagnostic kinds whose
placeholders are user-input templates, not pretty-prints), and JsonValue's
`Error` (intentional UX masking — placeholder `"null"` hides error nodes).

## Rationale

**Why a free function, not a `Renderable: Canonical` supertrait.** Same
*capability-minimality* argument that drove Task 2's
`pretty_unparse[T : Pretty]` free function: forcing every `Renderable`
implementor to also implement `Canonical` would either require types like
Markdown's `Block` / `Inline` (uniform `"..."` placeholder, no `Pretty`
impl, no meaningful "canonical instance") to grow a fake impl that
violates the trait's intended contract, or block Markdown from
implementing `Renderable` at all. Neither is acceptable. The free function
keeps the `Renderable` surface minimal and lets each implementor opt in
when its semantics fit.

(The Pattern-8 / defunctionalized-associated-type argument that rejected
`Renderable: Pretty` in Task 2 does *not* transfer to `Canonical` —
`canonical(Self) -> Self` has no analogous parameterization to fix. The
capability-minimality argument is load-bearing on its own.)

**Why three laws, none compile-checked.** MoonBit's Self-based trait
system has no type parameters or associated types, so even `same_kind`-
preservation can't be expressed in the trait signature. Documenting the
laws and enforcing them per-implementor via `@qc` property tests is the
realistic path; the trait doc-comment states the laws and is explicit
that none are compile-checked.

**Why a *frozen* drift detector.** The third law ("preserves
operationally-relevant discriminators") can't be generically tested. Per-
implementor drift detectors compare
`default_placeholder_via_canonical(t)` against a frozen
`hand_written_placeholder_reference(t)` defined as string literals in the
test module. The reference must *never* call `Renderable::placeholder`
(direct or indirect) — after the rewire, `placeholder` calls the free
function we're trying to validate, so any indirection through it makes
the test trivially circular. Both implementors' tests respect this.

**Why a new `dowdiness/loom -> dowdiness/pretty` dep.** The free function
needs the `@pretty.Pretty` bound. Pretty is conceptually below loom in
the stack (a generic Wadler-Lindig engine, not loom-specific), so loom
adopting it as a dep aligns the dependency graph with the layer ordering.
The .mbti diff adds only one new top-level import line plus the trait
and function declarations.

## Consequences

**Positive.**

- Eliminates placeholder/canonical duplication for the 9 + 6 = 15
  fitting variants. Future placeholder regressions caused by drift
  between `canonical` and Pretty's layout are caught by the drift
  detector at test time.
- Opens the typed-canonical structural-edit path. An editor inserting
  a fresh `Bop(Plus)` can call `Canonical::canonical(Bop(Plus, hole, hole))`
  to get a real `Bop(Plus, Int(0), Int(0))` without re-parsing the
  placeholder string. No consumer yet — tracked as a follow-up.
- Each carve-out (Term Module/Unbound/Error, JsonValue Error) is now
  *explicit and documented* rather than implicit in the placeholder
  string choice.

**Negative.**

- One more trait on the projectional-editor capability surface.
  Implementor cost is small (one match) but non-zero.
- `dowdiness/loom -> dowdiness/pretty` is a new transitive dep that
  every downstream loom consumer inherits.
- The free function's two-trait bound (`Canonical + @pretty.Pretty`) is
  slightly awkward at call sites — readable but not as fluent as a
  supertrait would be. This is the capability-minimality tradeoff.

**Neutral.**

- Markdown's `Block` / `Inline` stay on their uniform `"..."`
  placeholder unchanged. Adding `Canonical` to Markdown would require
  adding `Pretty` first — separate workstream, not motivated by this
  ADR.
- `Renderable::unparse` is untouched. The plan considered swapping
  `Term::unparse` to use `pretty_unparse` but declined that change
  separately (canopy#290).

## Implementation notes

- `Term::Module` canonical body pinned to `Var("x")` (not "any") for
  determinism of the future structural-edit consumer.
- `Bop`'s `op` field is preserved in `canonical` — without this,
  `placeholder(Bop(Plus))` and `placeholder(Bop(Minus))` would collapse
  to the same string. The drift detector catches this kind of mistake.
- Lambda's `@qc.Arbitrary for Term` generator covers most variants but
  produces only Unit at leaf depth and never Unbound/Error/Hole; the
  per-variant `inspect` tests close that coverage gap explicitly.
- JsonValue has no `@qc.Arbitrary`; the JSON tests use a deterministic
  200-trial manual loop with a depth-3 bounded generator plus
  per-variant `inspect` tests.
