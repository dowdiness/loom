// Canonical implementation for JsonValue. See @core.Canonical doc-comment
// for trait-level laws.
//
// Per-implementor contract:
//
// - `Bool`'s payload is normalized to `false`; placeholder is invariant in
//   the boolean value.
// - `Number`'s payload is normalized to `0.0`; canonical pretty-prints to
//   `"0"` (`pretty_traits.mbt` `Number` strips the `".0"` suffix).
// - `String`'s payload is normalized to `""`.
// - `Array` and `Object` are normalized to empty containers; children are
//   not part of the kind.
// - `Error`'s payload is normalized to `"?"` (matches Term's `Error`).
//   This is a deliberate carve-out from the placeholder-rewire path —
//   see the carve-out comment in `proj_traits.mbt`'s `placeholder` impl.
//
// The drift-detector property test in proj_traits_canonical_test.mbt
// enforces alignment between `default_placeholder_via_canonical(self)` and
// the frozen pre-change placeholder mapping for the 6 fitting variants.

///|
pub impl @core.Canonical for JsonValue with fn canonical(self) {
  match self {
    Null => Null
    Bool(_) => Bool(false)
    Number(_) => Number(0.0)
    String(_) => String("")
    Array(_) => Array([])
    Object(_) => Object([])
    Error(_) => Error("?")
  }
}
