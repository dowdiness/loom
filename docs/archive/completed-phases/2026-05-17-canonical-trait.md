# `Canonical` Companion Trait — Task 3 of the Show-Unification Sequence

Loom-side framework primitive: introduce a `Canonical` trait that returns
a representative `Self` value for each kind, and use it (opt-in via a
free function, not a supertrait) to default `Renderable::placeholder`
for implementor types that also implement `Pretty`.

Task 3 of the three-task sequence laid out in canopy's
`docs/plans/2026-05-16-show-unification.md` § "Sequencing context".
Tasks 1 (Show unification) and 2 (`pretty_unparse` free function)
shipped 2026-05-17.

## Status — Complete 2026-05-17

Implementation shipped via [loom#123](https://github.com/dowdiness/loom/pull/123)
(merged 2026-05-17 as commit `51deb6e`). Canopy submodule pointer bumped
in [canopy#291](https://github.com/dowdiness/canopy/pull/291) (merged
2026-05-17 as canopy commit `643fade`).

Acceptance criteria — all met (see § "Acceptance Criteria" below).
Codex reviewed the plan (pass 1, pre-implementation) and the
implementation diff (pass 2, post-implementation); no behavioral bugs
found in either pass.

Decision record:

- ADR [docs/decisions/2026-05-17-canonical-companion-trait.md](../../decisions/2026-05-17-canonical-companion-trait.md) — Accepted: `Canonical` companion trait as a framework-level capability with opt-in `default_placeholder_via_canonical` free function.

## Why

Two motivations, in order of immediacy:

1. **Remove duplication between `placeholder` and the implicit canonical
   instance** (for the *user-input-template* variants). For variants
   where the placeholder string is genuinely a serialization of a
   canonical instance — `Bop(Plus, _, _) → "0 + 0"` is the
   pretty-printed form of `Bop(Plus, Int(0), Int(0))` — defining
   `canonical : Self -> Self` once and deriving the placeholder
   through `pretty_unparse(canonical(self))` keeps the two in sync by
   construction. Not every variant fits: Term's `Unbound`/`Error` and
   JSON's `Error` use placeholders that are *not* parseable instances
   of their own kind (e.g. Term's `Unbound(_) → "x"` would re-parse as
   `Var("x")`, not `Unbound`). Those variants are diagnostic-display
   kinds whose placeholders deliberately match a user-input shape; the
   alignment doesn't apply to them and they stay hand-written.

2. **Typed canonical instance as a structural-edit primitive (future).**
   When the editor inserts a fresh node of a given kind, today's path
   is `placeholder` (a string) → re-parse → typed `Self`. With a
   `Canonical` trait the editor can take the typed `Self` directly,
   bypassing the parser round-trip. No consumer exists yet, so this
   motivation is documented for direction but is not on this PR's
   acceptance criteria. Note that this path is *only* viable for kinds
   whose canonical instance is a real same-kind value — diagnostic
   kinds like `Unbound`/`Error` don't fit; structural insertion of
   those should remain unsupported.

## Scope

In:

- Add `pub(open) trait Canonical { canonical(Self) -> Self }` to
  `loom/src/core/proj_traits.mbt` (next to `Renderable` and
  `TreeNode`).
- Add free function in `loom/src/core/proj_traits.mbt`:
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

`Renderable: Canonical` would force every Renderable implementor to
also implement Canonical. The cleanest argument against it is
**capability minimality** — the same principle the canopy plan uses
in its `Show for ProjNode` bound discussion: the trait bound should
be the minimum capability required to produce the output. Markdown
has Renderable but cannot reasonably implement Canonical (its
`"..."` placeholder is uniform, not a pretty-print of any canonical
instance; `examples/markdown/src/proj_traits.mbt:109`+`:195`).
Forcing the supertrait would either require Markdown to grow a
Pretty impl (separate workstream, not motivated here) or accept a
fake Canonical that violates the intended contract. The free-function
pattern keeps the Renderable surface minimal and lets each implementor
opt in when its semantics fit.

The Pattern 8 / Solution 6 framing that Task 2 used to reject
`Renderable: Pretty` does *not* transfer directly to Canonical — Pretty
has a defunctionalized-associated-type shape (`Layout[A]` with
`A=SyntaxCategory` fixed), and the supertrait would have locked
implementors onto a single `A`. Canonical's signature
`canonical(Self) -> Self` has no analogous parameterization to fix, so
the Pattern 8 argument doesn't apply here. The capability-minimality
argument above is the load-bearing one.

### Laws and invariants

`canonical(Self) -> Self` is Pattern 1 (Self-closed endomorphism) in
shape. The *semantics* are not pure variant-tag routing: the
implementor decides which internal discriminators to preserve and
which to canonicalize. For Term:

- `canonical(Bop(op, _, _)) = Bop(op, Int(0), Int(0))` — preserves
  `op` because the placeholder differs (`"0 + 0"` vs `"0 - 0"`).
- `canonical(Lam(_, _)) = Lam("x", Var("x"))` — discards the param
  name because the placeholder is invariant in it.

Three laws apply, in increasing strength. None of them are compile-
checked by MoonBit's type system; all three are documented in the
trait's doc-comment and the strongest two enforceable ones go in
per-implementor `@qc` property tests.

1. **`same_kind`-preservation** — `same_kind(canonical(self), self)`
   holds for all `self`. This is the minimum baseline: the
   canonicalization stays within the same variant family. Enforced as
   a property test.

2. **Idempotence** — `canonical(canonical(t)) == canonical(t)`.
   Structurally what "canonicalization" means: applying the operation
   twice equals applying it once. Enforced as a property test for any
   type whose `Self` admits `Eq`.

3. **"Preserves operationally-relevant discriminators"** — the
   implementor's type-specific contract. For Term: `Bop`'s `op` field
   is preserved; `Lam`'s param name is not. This is *not* expressible
   as a generic law, so it lives in the doc-comment and is sanity-
   checked by the canonical-placeholder drift detector below
   (changes to `canonical` that drop the wrong discriminator will
   make `default_placeholder_via_canonical` diverge from the
   hand-written reference, which the drift test catches).

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
| `Module(_, _)`        | `"let x = 0"`             | `Module([("x", Int(0))], Var("x"))`        | `"let x = 0\nx"`            | ✗ carve-out (Pretty's `mod` impl unconditionally emits `hardline + body`, see `examples/lambda/src/ast/pretty_traits.mbt:186-192`) |
| `Unit`                | `"()"`                    | `Unit`                                     | `"()"`                      | ✓     |
| `Unbound(_)`          | `"x"`                     | `Unbound("x")`                             | `"<unbound: x>"`            | ✗ carve-out (diagnostic kind — placeholder is user-input template, pretty form is diagnostic decoration; the two are not aligned by design) |
| `Error(_)`            | `"?"`                     | `Error("?")`                               | `"<error: ?>"`              | ✗ carve-out (diagnostic kind — same reason as `Unbound`) |
| `Hole(_)`             | `"_"`                     | `Hole(0)`                                  | `"_"`                       | ✓     |

Result: 9 / 12 cases fit. 3 carve-outs (`Module`, `Unbound`, `Error`) —
matches the canopy plan's claim. `Bop` does not need a carve-out as
long as `canonical` preserves `op`.

### Per-variant analysis — JsonValue

7 variants:

| Variant      | Today's placeholder | Proposed canonical          | `pretty_unparse(canonical)`         | Fits? |
|--------------|---------------------|------------------------------|--------------------------------------|-------|
| `Null`       | `"null"`            | `Null`                       | `"null"`                             | ✓     |
| `Bool(_)`    | `"false"`           | `Bool(false)`                | `"false"`                            | ✓     |
| `Number(_)`  | `"0"`               | `Number(0.0)`                | `"0"` (strips `.0`, see `examples/json/src/pretty_traits.mbt:48-56`) | ✓ |
| `String(_)`  | `"\"\""`            | `String("")`                 | `"\"\""`                             | ✓     |
| `Array(_)`   | `"[]"`              | `Array([])`                  | `"[]"`                               | ✓     |
| `Object(_)`  | `"{}"`              | `Object([])`                 | `"{}"`                               | ✓     |
| `Error(_)`   | `"null"`            | `Error("?")`                 | `"<error: ?>"` (see `examples/json/src/pretty_traits.mbt:93-98`) | ✗ carve-out |

JSON's `Error` is a deliberate carve-out: today's placeholder `"null"`
is a **UX decision** that hides error nodes from the output stream
(this is the same `null`-masking pattern at
`examples/json/src/proj_traits.mbt:121-122` for `unparse`). Switching
to `<error: ?>` to align with Pretty would be a behavior change, not a
refactor. Leave `Error` hand-written; document the carve-out as
*intentional masking, not alignment failure*.

Result: 6 / 7 cases fit; 1 deliberate carve-out (`Error`). Verified by
reading the Pretty impl at `examples/json/src/pretty_traits.mbt`, so no
verification step is needed during implementation.

### Property test design

For each Canonical implementor `T`, two `@qc` properties plus a fixed
test-only reference function:

1. **`same_kind` invariant** (loom core trait is `@loomcore.TreeNode`
   when imported from lambda; package-name aliases vary by importer —
   adjust the qualifier per file):
   ```moonbit
   // In examples/lambda/src/ast/proj_traits_canonical_test.mbt
   @qc.property("Canonical preserves kind", fn(t : Term) -> Bool {
     @loomcore.TreeNode::same_kind(t, Canonical::canonical(t))
   })
   ```

2. **Idempotence** (where `Eq` is available — Term and JsonValue both
   `derive(Eq)`):
   ```moonbit
   @qc.property("Canonical is idempotent", fn(t : Term) -> Bool {
     let c = Canonical::canonical(t)
     Canonical::canonical(c) == c
   })
   ```

3. **Canonical-placeholder drift detector** (must NOT call
   `Renderable::placeholder` to avoid circularity after step 3 of the
   plan rewires `placeholder` to call the free function):
   ```moonbit
   // hand_written_placeholder_reference duplicates the PRE-CHANGE
   // mapping as string literals. It exists ONLY in the test module
   // and must not be unified with Renderable::placeholder.
   fn hand_written_placeholder_reference(t : Term) -> String? {
     // Returns Some(s) for fitting variants, None for carve-outs.
     // Carve-outs are excluded from this check.
     match t {
       Int(_)         => Some("0")
       Var(_)         => Some("x")
       Lam(_, _)      => Some("λx. x")
       App(_, _)      => Some("f x")
       Bop(Plus, _, _)  => Some("0 + 0")
       Bop(Minus, _, _) => Some("0 - 0")
       If(_, _, _)    => Some("if 0 then 0 else 0")
       Unit           => Some("()")
       Hole(_)        => Some("_")
       Module(_, _) | Unbound(_) | Error(_) => None  // carve-outs
     }
   }

   @qc.property(
     "default_placeholder_via_canonical matches the frozen reference for fitting variants",
     fn(t : Term) -> Bool {
       match hand_written_placeholder_reference(t) {
         None      => true  // carve-out: not asserted
         Some(ref) => default_placeholder_via_canonical(t) == ref
       }
     }
   )
   ```
   The test breaks if either (a) `canonical(t)` is changed to a
   different same-kind value whose pretty form differs, or (b) the
   `Pretty` impl changes layout. Both are real drift conditions; the
   test prevents either from silently flipping placeholder output.

### `.mbti` diff expectations

New exports:

- `loom/src/core/pkg.generated.mbti`: `pub(open) trait Canonical` +
  `pub fn[T : Canonical + @pretty.Pretty]
  default_placeholder_via_canonical(T) -> String`.
- `examples/lambda/src/ast/pkg.generated.mbti`: `pub impl Canonical for
  Term`.
- `examples/json/src/pkg.generated.mbti`: `pub impl Canonical for
  JsonValue`.

No bound widening on existing traits (the `T : Renderable` bounds added
in canopy Task 1 stay as-is). Confirm with `git diff '**/*.mbti'` per
[[feedback-api-diff-check]].

### Package alias note

Loom core is imported under different aliases across consumers:

- `examples/lambda/src/ast/moon.pkg`: `dowdiness/loom/core` → `@loomcore`
- `examples/json/src/moon.pkg`: `dowdiness/loom/core` → `@core`

When writing per-implementor impls and tests, use the alias in scope
for that file's package, not a global one. The plan's example
snippets use `@loomcore` for Term and `@core` for JsonValue
contexts; double-check actual `moon.pkg` imports during
implementation.

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
   `loom/src/core/proj_traits.mbt`. Include doc-comments on the trait
   stating all three laws (`same_kind`, idempotence, "preserves
   operationally-relevant discriminators") and explicitly noting that
   none are compile-checked. `moon info` on `loom/src/core/`; diff
   `.mbti`.

2. **`Canonical for Term` impl** in
   `examples/lambda/src/ast/proj_traits_canonical.mbt` (new file). One
   `match` expression returning the canonical instance per the table
   above. Inspect tests per variant.

3. **Rewire `Renderable::placeholder for Term`.** For the 9 fitting
   cases (table above), call `default_placeholder_via_canonical(self)`.
   Keep hand-written branches for `Module`, `Unbound`, `Error`. Verify
   existing placeholder tests (if any) still pass; if no per-variant
   tests exist, add a small inspect suite covering each variant.

4. **`@qc` property tests for Term.** Three properties: `same_kind`,
   idempotence, drift detector against the frozen
   `hand_written_placeholder_reference` (see § "Property test
   design"). Use lambda's existing `@qc.Arbitrary for Term` if it
   exists; if not, scope a small bounded generator (depth ≤ 3) into
   the test module. The drift-detector reference function must be
   defined as string literals in the test file — never call
   `Renderable::placeholder` directly or indirectly.

5. **`Canonical for JsonValue` impl** + rewire + property tests, same
   shape as steps 2-4. Per the verified table in § "Per-variant
   analysis — JsonValue": 6/7 variants fit; `Error` is a deliberate
   carve-out (UX masking, not alignment failure). No verification
   step needed — Pretty behavior is known from reading
   `examples/json/src/pretty_traits.mbt`.

6. **`moon info && moon fmt`** per touched package. `git diff
   '**/*.mbti'` audit.

7. **Codex review.** Hand the diff to Codex with the question "Does
   `default_placeholder_via_canonical` correctly preserve every
   fitting variant's placeholder string, and are the carve-outs
   well-motivated?" before opening the loom PR.

8. **Loom PR.** Single PR covering the trait + both implementors per
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

- [x] `Canonical` trait exists in `loom/src/core/proj_traits.mbt` with
  `canonical(Self) -> Self` + doc-comment stating all three laws and
  noting that none are compile-checked.
- [x] `default_placeholder_via_canonical[T : Canonical +
  @pretty.Pretty]` exists in the same package.
- [x] `Canonical for Term` impl covers all 11 variants exhaustively;
  Module canonical body is `Var("x")` (not "any").
- [x] `Renderable::placeholder for Term` delegates to the free
  function for the 9 fitting cases; carve-outs for `Module` (Pretty
  layout reason), `Unbound` and `Error` (diagnostic-kind reason) are
  documented inline.
- [x] `Canonical for JsonValue` impl covers all 7 variants
  exhaustively; `Error` carve-out is documented as *intentional UX
  masking*, not alignment failure.
- [x] `@qc` property tests pass for both implementors: `same_kind`,
  idempotence, drift detector against frozen
  `hand_written_placeholder_reference`.
- [x] Drift detector reference functions are defined as string
  literals in the test module and never call `Renderable::placeholder`
  (directly or indirectly).
- [x] All existing `moon test` snapshots still pass; no `--update`
  blanket-applied.
- [x] `.mbti` diff shows only the intended new exports.
- [x] `bash check-docs.sh` passes (this plan is linked from
  `docs/README.md`'s Active Plans section).

## Open Questions — resolved 2026-05-17

(Codex pre-review pass 1 completed 2026-05-17 — see § "Codex review
trail" below.)

1. **Markdown scope.** ✅ **Confirmed out of scope** by user 2026-05-17.
   Markdown stays on its uniform `"..."` placeholder. If Markdown
   grows a Pretty impl later, Canonical can be added then.
2. **Single loom PR vs split.** ✅ **Single PR confirmed** by user
   2026-05-17. Trait + Term + JsonValue + property tests land
   together. Both implementors share the same shape and the
   property-test pattern is reusable across them; Codex's review
   confirmed the split would be defensible for review/rollback
   isolation but is not forced by dependency uncertainty.

## Codex review trail

**Pass 1 — 2026-05-17 (this draft):**

- Fixed: file path `loom/loom/src/...` → `loom/src/...` throughout.
- Fixed: alias inconsistency (`@core` vs `@loomcore`) — added § "Package
  alias note".
- Fixed: "compile-checked" overstatement on `same_kind` — laws section
  now says explicitly none of the three laws are compile-checked.
- Added: idempotence as a documented law and property test (Codex's
  cleanest candidate for a stronger structural invariant).
- Reframed: § "Why a free function, not a supertrait" no longer leans
  on Pattern 8 / Solution 6 (Codex correctly noted the framing
  doesn't transfer — Canonical lacks Pretty's defunctionalized
  associated-type shape). Now uses *capability minimality* as the
  load-bearing argument.
- Reframed: motivation #1 no longer claims placeholder is "the
  serialization of a canonical instance" for every variant. Term's
  `Unbound`/`Error` placeholders demonstrably don't round-trip to
  their own kind (`"x"` parses as `Var`, not `Unbound`); the plan
  now calls these out as diagnostic kinds whose placeholders match a
  user-input shape by design, not duplication-by-accident.
- Resolved: JSON Number/Error Pretty behavior verified from source
  (Codex citations: `examples/json/src/pretty_traits.mbt:48-56` for
  Number→`"0"`, `:93-98` for Error→`"<error: ?>"`). Eliminated the
  pre-implementation verification step; JSON `Error` is now an
  explicit deliberate carve-out documented as UX masking.
- Resolved: Module canonical body pinned to `Var("x")` (not "any") for
  determinism of the future structural-edit consumer.
- Fixed: drift detector property test was circular (would have
  passed trivially after step 3 rewires `Renderable::placeholder`).
  Now defines a separate test-only `hand_written_placeholder_reference`
  with string-literal returns and explicitly forbids
  `Renderable::placeholder` calls.

Remaining items Codex flagged that the plan acknowledges but does NOT
solve here:

- *Placeholder re-parse claim in motivation #2.* The "fresh insertion
  via placeholder → re-parse" path is broken for `Unbound`/`Error`
  *today*, before this plan lands. Motivation #2 now scopes the
  typed-canonical-value benefit to non-diagnostic kinds explicitly,
  matching the pre-existing reality. Fixing the placeholder semantics
  for diagnostic kinds is out of scope.

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
- Decision record: ADR drafted at closure —
  [docs/decisions/2026-05-17-canonical-companion-trait.md](../../decisions/2026-05-17-canonical-companion-trait.md).
  Task 3 introduces a new framework-level trait, meeting loom's ADR
  threshold per `docs/development/agent-docs-protocol.md`.
