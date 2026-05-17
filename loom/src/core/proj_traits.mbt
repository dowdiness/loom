// Capability traits for projectional editing over arbitrary AST types.
// Language AST packages implement these; the editor framework consumes them
// via trait bounds without depending on any specific AST type.

///|
/// Tree structure capability — structural access for reconciliation and traversal.
pub(open) trait TreeNode {
  children(Self) -> Array[Self]
  same_kind(Self, Self) -> Bool
}

///|
/// Rendering + text capability — display and serialization for projectional editors.
pub(open) trait Renderable {
  kind_tag(Self) -> String
  label(Self) -> String
  placeholder(Self) -> String
  unparse(Self) -> String
}

///|
/// Canonical-instance capability — return a representative `Self` value for
/// each kind ("kind" = same equivalence class as `TreeNode::same_kind`).
///
/// Use cases:
/// 1. Default a `Renderable::placeholder` impl by composing with
///    `@pretty.Pretty` via `default_placeholder_via_canonical`. This keeps
///    the placeholder string and the canonical instance in sync by
///    construction for variants where the placeholder is a pretty-print of
///    the canonical instance.
/// 2. Structural-edit primitive: an editor inserting a fresh node of a given
///    kind can take the typed `Self` directly instead of round-tripping
///    `placeholder -> parser -> Self`. No consumer exists yet — documented
///    for direction.
///
/// Laws (none are compile-checked by MoonBit's type system; all three are
/// caller-enforced via property tests on a per-implementor basis):
///
/// 1. **`same_kind`-preservation** — `same_kind(canonical(t), t)` for all
///    `t`. The minimum baseline: canonicalization stays within the same
///    variant family.
/// 2. **Idempotence** — `canonical(canonical(t)) == canonical(t)`. Applying
///    the operation twice equals applying it once.
/// 3. **Preserves operationally-relevant discriminators** — the implementor
///    decides which internal fields are part of the "kind" and must be
///    preserved by canonicalization, vs. which are auxiliary and can be
///    normalized away. Not expressible as a generic law; lives in the
///    implementor's doc comment and is sanity-checked by a per-implementor
///    drift detector against a frozen reference (see Task 3 plan).
pub(open) trait Canonical {
  canonical(Self) -> Self
}

///|
/// Free function — derive a `placeholder` string by pretty-printing the
/// canonical instance of the value. Use this to default
/// `Renderable::placeholder` for variants whose placeholder is the
/// pretty-print of `canonical(self)`.
///
/// The two-trait bound (`Canonical + @pretty.Pretty`) is intentional: the
/// pattern only fits when the implementor has both capabilities and the
/// placeholder semantics align with the pretty-printed canonical form.
/// Variants that don't fit (diagnostic kinds, layout-incompatible kinds)
/// should keep a hand-written `placeholder` branch.
pub fn[T : Canonical + @pretty.Pretty] default_placeholder_via_canonical(
  t : T,
) -> String {
  @pretty.pretty_unparse(Canonical::canonical(t))
}
