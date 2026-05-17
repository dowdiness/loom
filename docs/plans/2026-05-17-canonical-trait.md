# `Canonical` Companion Trait — Task 3 of the Show-Unification Sequence

Loom-side framework primitive: introduce a `Canonical` trait that returns
a representative `Self` value for each kind, and use it (opt-in via a
free function, not a supertrait) to default `Renderable::placeholder`
for implementor types that also implement `Pretty`.

Task 3 of the three-task sequence laid out in canopy's
`docs/plans/2026-05-16-show-unification.md` § "Sequencing context".
Tasks 1 (Show unification) and 2 (`pretty_unparse` free function)
shipped 2026-05-17.

## Status — Draft 2026-05-17

Pending Codex design validation before implementation per the canopy
project's algorithm-implementation process. The "Open Questions" section
below lists the decisions that need confirmation before steps start.

## Why

Two motivations, in order of immediacy:

1. **Remove duplication between `placeholder` and the implicit canonical
   instance.** For each implementor variant, the hand-written
   `placeholder` string is effectively a serialization of a canonical
   instance of that variant: `Bop(Plus, _, _) → "0 + 0"` is the
   pretty-printed form of `Bop(Plus, Int(0), Int(0))`. Defining
   `canonical : Self -> Self` once per variant and deriving the
   placeholder through `pretty_unparse(canonical(self))` keeps the two
   in sync by construction.

2. **Typed canonical instance as a structural-edit primitive (future).**
   When the editor inserts a fresh node of a given kind, today's path
   is `placeholder` (a string) → re-parse → typed `Self`. With a
   `Canonical` trait the editor can take the typed `Self` directly,
   bypassing the parser round-trip. No consumer exists yet, so this
   motivation is documented for direction but is not on this PR's
   acceptance criteria.

## Scope

In:

- Add `pub(open) trait Canonical { canonical(Self) -> Self }` to
  `loom/loom/src/core/proj_traits.mbt` (next to `Renderable` and
  `TreeNode`).
- Add free function in `loom/loom/src/core/proj_traits.mbt`:
  ```moonbit
  pub fn[T : Canonical + @pretty.Pretty] default_placeholder_via_canonical(
    t : T,
  ) -> String {
    @pretty.pretty_unparse(Canonical::canonical(t))
  }
  ```
- `Canonical for Term` impl in `examples/lambda/src/ast/` (new file
  `proj_traits_canonical.mbt`, sibling to `proj_traits.mbt`). Exhaustive
  match over all 11 Term variants per the table in Design Notes.
- Rewire `Renderable::placeholder for Term`: for variants where the
  canonical+pretty form matches today's placeholder, call
  `default_placeholder_via_canonical(self)`. Keep hand-written branches
  for the carve-outs (`Module`, `Unbound`, `Error`).
- `Canonical for JsonValue` impl in `examples/json/src/`. Same exercise.
- `@qc` property test per implementor: `forall t, same_kind(canonical(t),
  t)`.
- Drift-detection property test: `forall t in pretty-fitting variants,
  default_placeholder_via_canonical(t) == hand_written_placeholder(t)`
  — fails fast if `canonical` and `placeholder` ever diverge for a
  variant the plan declares aligned.
- `moon info` + `.mbti` diff per touched package.

Out:

- **Markdown `Block` and `Inline`.** No `Pretty` / `Source` impl today
  (`Renderable::placeholder` is uniform `"..."`). Adding `Pretty` to
  Markdown is its own workstream, not motivated by Task 3. The uniform
  `"..."` is a deliberate design choice, not a duplication problem
  — Markdown placeholders aren't pretty-prints of canonical instances,
  so `Canonical` would gain nothing for them.
- **`Renderable: Canonical` supertrait.** The free-function pattern
  matches the precedent set by Task 2 (`pretty_unparse[T : Pretty]` as
  a free function, *not* `Renderable: Pretty`). The rationale carries
  over verbatim — see canopy plan § "Why `Renderable: Pretty` supertrait
  was rejected".
- **Editor consumer of `canonical(template) -> Self`.** Tracked under
  motivation (2) but no code path consumes it today. Adding the
  consumer is Task 3+1, not Task 3.
- **`Show for Term` / `Show for Bop`.** Untouched; matches Task 1's
  "Out" carve-out.

## Design Notes

### Why a free function, not a supertrait

`Renderable: Canonical` would force every Renderable implementor to also
implement Canonical. Markdown has Renderable but cannot reasonably
implement Canonical (its `"..."` placeholder is not a pretty-print of
any canonical instance). The free-function pattern keeps the Renderable
trait minimal and lets each implementor opt in to the
canonical-driven placeholder when their semantics fit. Same rationale
as the canopy plan's Pattern 8 / Solution 6 analysis for the rejected
`Renderable: Pretty`.

### The `same_kind` invariant — minimum vs intended contract

`canonical(Self) -> Self` is Pattern 1 (Self-closed endomorphism) in
shape, but the *semantics* are not pure variant-tag routing. The
implementor decides which internal discriminators to preserve and
which to canonicalize. For Term:

- `canonical(Bop(op, _, _)) = Bop(op, Int(0), Int(0))` — preserves
  `op` because the placeholder differs (`"0 + 0"` vs `"0 - 0"`).
- `canonical(Lam(_, _)) = Lam("x", Var("x"))` — discards the param
  name because the placeholder is invariant in it.

The compile-checked invariant is `same_kind(canonical(self), self)` —
the *minimum* enforceable property. The load-bearing contract is
type-specific: "preserves operationally-relevant discriminators". This
lives in the trait's doc-comment and per-type property tests, not in
the trait signature.

### Per-variant analysis — Term

12 cases (Bop has two op-arms):

| Case                  | Today's placeholder       | Proposed canonical                         | `pretty_unparse(canonical)` | Fits? |
|-----------------------|---------------------------|--------------------------------------------|-----------------------------|-------|
| `Int(_)`              | `"0"`                     | `Int(0)`                                   | `"0"`                       | ✓     |
| `Var(_)`              | `"x"`                     | `Var("x")`                                 | `"x"`                       | ✓     |
| `Lam(_, _)`           | `"λx. x"`                 | `Lam("x", Var("x"))`                       | `"λx. x"`                   | ✓     |
| `App(_, _)`           | `"f x"`                   | `App(Var("f"), Var("x"))`                  | `"f x"`                     | ✓     |
| `Bop(Plus, _, _)`     | `"0 + 0"`                 | `Bop(Plus, Int(0), Int(0))`                | `"0 + 0"`                   | ✓     |
| `Bop(Minus, _, _)`    | `"0 - 0"`                 | `Bop(Minus, Int(0), Int(0))`               | `"0 - 0"`                   | ✓     |
| `If(_, _, _)`         | `"if 0 then 0 else 0"`    | `If(Int(0), Int(0), Int(0))`               | `"if 0 then 0 else 0"`      | ✓     |
| `Module(_, _)`        | `"let x = 0"`             | (any `Module([("x", Int(0))], body)`)      | `"let x = 0\n<body>"`       | ✗ carve-out (body) |
| `Unit`                | `"()"`                    | `Unit`                                     | `"()"`                      | ✓     |
| `Unbound(_)`          | `"x"`                     | `Unbound("x")`                             | `"<unbound: x>"`            | ✗ carve-out (template differs from `<unbound: …>`) |
| `Error(_)`            | `"?"`                     | `Error("?")`                               | `"<error: ?>"`              | ✗ carve-out (template differs from `<error: …>`) |
| `Hole(_)`             | `"_"`                     | `Hole(0)`                                  | `"_"`                       | ✓     |

Result: 9 / 12 cases fit. 3 carve-outs (`Module`, `Unbound`, `Error`) —
matches the canopy plan's claim. `Bop` does not need a carve-out as
long as `canonical` preserves `op`.

### Per-variant analysis — JsonValue

7 variants:

| Variant      | Today's placeholder | Proposed canonical          | `pretty_unparse(canonical)` (verify) | Fits? |
|--------------|---------------------|------------------------------|---------------------------------------|-------|
| `Null`       | `"null"`            | `Null`                       | `"null"`                              | ✓ (verify) |
| `Bool(_)`    | `"false"`           | `Bool(false)`                | `"false"`                             | ✓ (verify) |
| `Number(_)`  | `"0"`               | `Number(0.0)`                | `"0"` or `"0.0"` — **verify**         | ?     |
| `String(_)`  | `"\"\""`            | `String("")`                 | `"\"\""`                              | ✓ (verify) |
| `Array(_)`   | `"[]"`              | `Array([])`                  | `"[]"`                                | ✓ (verify) |
| `Object(_)`  | `"{}"`              | `Object([])`                 | `"{}"`                                | ✓ (verify) |
| `Error(_)`   | `"null"`            | `Error("?")`                 | depends on `@pretty.Pretty for Error` | ?     |

Two cases need verification against JSON's `Pretty` impl before
implementation: `Number` (formatting of `0.0` — does
`pretty_unparse(Number(0.0))` emit `"0"` or `"0.0"`?) and `Error` (the
current placeholder `"null"` is a carve-out hiding error from output;
either confirm `Error` stays a carve-out or align canonical with the
placeholder).

### Property test design

For each Canonical implementor `T`:

1. **`same_kind` invariant** (cheap, exhaustive over generated values):
   ```moonbit
   @qc.property("Canonical preserves kind", fn(t : T) -> Bool {
     @core.TreeNode::same_kind(t, Canonical::canonical(t))
   })
   ```

2. **Canonical-placeholder alignment** (drift detector for the
   "fitting" variants — declared per implementor):
   ```moonbit
   @qc.property("default_placeholder_via_canonical matches today's placeholder for fitting variants",
     fn(t : T) -> Bool {
       if is_fitting_variant(t) {
         default_placeholder_via_canonical(t) ==
           hand_written_placeholder_reference(t)
       } else {
         true  // carve-outs not asserted
       }
     })
   ```
   `hand_written_placeholder_reference` captures the pre-Task-3
   placeholder for each variant, so the test fails fast if either
   `canonical` or `Pretty` drifts.

### `.mbti` diff expectations

New exports:

- `loom/src/core/pkg.generated.mbti`: `pub(open) trait Canonical` +
  `pub fn[T : Canonical + Pretty] default_placeholder_via_canonical(T)
  -> String`.
- `examples/lambda/src/ast/pkg.generated.mbti`: `pub impl Canonical for
  Term`.
- `examples/json/src/pkg.generated.mbti`: `pub impl Canonical for
  JsonValue`.

No bound widening on existing traits (the `T : Renderable` bounds added
in canopy Task 1 stay as-is). Confirm with `git diff '**/*.mbti'` per
[[feedback-api-diff-check]].

## Risks

1. **API surface growth.** One trait, one free function, two impls.
   Audit `.mbti` diffs; the surface is small enough that this is a
   non-issue if Codex confirms.

2. **Canonical-vs-placeholder drift.** The entire DRY argument
   depends on `canonical` + `pretty_unparse` actually equalling the
   hand-written placeholder for the declared fitting variants. The
   drift-detection property test (item 2 above) is the safety net.
   If it false-positives during implementation, that's a signal a
   variant we thought was fitting is actually a carve-out — update the
   declaration, don't suppress the test.

3. **Pretty's textual flips don't propagate through this work.** Task
   2's optional `Term::unparse` swap was declined (see canopy plan
   post-ship status). `default_placeholder_via_canonical` uses
   `pretty_unparse`, not `print_term`. The two output formats differ
   on `Lam`/`App`/`Bop` parenthesization — `placeholder` strings
   currently match the `pretty_unparse` form (`"f x"`, `"λx. x"`,
   `"0 + 0"`), not the `print_term` form. Verified manually against
   the lambda placeholder source in
   `examples/lambda/src/ast/proj_traits.mbt:30-45`.

4. **JSON Number/Error variants.** Both need verification against
   `@pretty.Pretty for JsonValue` before implementation. May yield
   one more carve-out (Error) or require canonical's `0.0` literal to
   be chosen carefully.

## Steps

1. **Add `Canonical` trait + free function** in
   `loom/loom/src/core/proj_traits.mbt`. Include doc-comments on the
   trait pointing to the `same_kind` invariant + "preserves
   operationally-relevant discriminators" intended contract. `moon
   info` on `loom/src/core/`; diff `.mbti`.

2. **`Canonical for Term` impl** in
   `examples/lambda/src/ast/proj_traits_canonical.mbt` (new file). One
   `match` expression returning the canonical instance per the table
   above. Inspect tests per variant.

3. **Rewire `Renderable::placeholder for Term`.** For the 9 fitting
   cases (table above), call `default_placeholder_via_canonical(self)`.
   Keep hand-written branches for `Module`, `Unbound`, `Error`. Verify
   existing placeholder tests (if any) still pass; if no per-variant
   tests exist, add a small inspect suite covering each variant.

4. **`@qc` property tests for Term.** Two properties (same_kind +
   placeholder drift). Use lambda's existing `@qc.Arbitrary for Term`
   if it exists; if not, scope a small bounded generator (depth ≤ 3)
   into the test module.

5. **Verify JSON Number/Error against `@pretty.Pretty`.** Before
   writing the JsonValue impl, run a microbenchmark / inspect probe of
   `pretty_unparse(Number(0.0))` and `pretty_unparse(Error("?"))`.
   Update the table above with the verified values. Decide whether
   Error is a carve-out (most likely yes) and what literal `Number`'s
   canonical uses.

6. **`Canonical for JsonValue` impl** + rewire + property tests, same
   shape as steps 2-4.

7. **`moon info && moon fmt`** per touched package. `git diff
   '**/*.mbti'` audit.

8. **Codex review.** Hand the diff to Codex with the question "Does
   `default_placeholder_via_canonical` correctly preserve every
   fitting variant's placeholder string, and are the carve-outs
   well-motivated?" before opening the loom PR.

9. **Loom PR.** Single PR covering the trait + both implementors per
   the "Single PR" decision in Open Questions. After merge: separate
   canopy PR to bump the submodule pointer.

## Validation

```bash
# From loom repo root
moon check
moon test
cd examples/lambda && moon check && moon test
cd examples/json && moon check && moon test

# .mbti audit
moon info
git diff '**/*.mbti'

# Docs check
bash check-docs.sh
```

## Acceptance Criteria

- [ ] `Canonical` trait exists in `loom/loom/src/core/proj_traits.mbt`
  with `canonical(Self) -> Self` + doc-comment describing the intended
  contract.
- [ ] `default_placeholder_via_canonical[T : Canonical + Pretty]`
  exists in the same package.
- [ ] `Canonical for Term` impl covers all 11 variants exhaustively.
- [ ] `Renderable::placeholder for Term` delegates to the free
  function for the 9 fitting cases; carve-outs for Module/Unbound/
  Error are documented inline.
- [ ] `Canonical for JsonValue` impl covers all 7 variants
  exhaustively; carve-out for Error (or revised canonical) is
  documented.
- [ ] `@qc` property tests pass for both implementors: `same_kind`
  invariant + canonical-placeholder alignment for declared fitting
  variants.
- [ ] All existing `moon test` snapshots still pass; no `--update`
  blanket-applied.
- [ ] `.mbti` diff shows only the intended new exports.
- [ ] `bash check-docs.sh` passes (this plan is linked from
  `docs/README.md`'s Active Plans section).

## Open Questions for Codex / User

1. **Markdown scope confirmation.** Default in this plan: Markdown
   stays out (no Pretty impl → no Canonical benefit). Confirm or
   redirect.
2. **JsonValue Number / Error variants.** Step 5 verifies these
   against JSON's Pretty impl before committing to canonical
   instances. Acknowledge that the table may shift after verification.
3. **Single loom PR vs split.** Default: single PR (trait + Term +
   JsonValue + property tests). Alternative: split (trait + Term
   first; JsonValue follow-up). Single PR is the default because both
   impls share the same shape and the property-test pattern is
   reusable across them.

## Notes

- Related plan: canopy's
  `docs/plans/2026-05-16-show-unification.md` — § "Sequencing context"
  point 3 is the source spec for this work. The Task 2 post-ship
  status block in that same doc records the parallel decision made
  2026-05-17.
- Related memory: [[project-inspector-traceability-workstream]]
  (Task 3 listed under deliverable 1's open follow-ups);
  [[feedback-algorithm-process]] (Codex-first design validation);
  [[feedback-no-direct-push]] (loom is a submodule — PR workflow);
  [[feedback-api-diff-check]] (`.mbti` audit after `moon info`).
- Decision record: ADR-worthy on plan closure? Probably yes — Task 3
  introduces a new framework-level trait, which meets loom's ADR
  threshold per `docs/development/agent-docs-protocol.md`. Note for
  closure: draft an ADR alongside marking this plan complete.
