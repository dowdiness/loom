# `dowdiness/json-settings`

A **tested, copyable** example of the *last-good semantic projection attachment*
pattern for [`dowdiness/loom`](../../loom/). It is the checked counterpart of the
`nocheck` template in
[`docs/api/last-good-semantic-attachment.md`](../../docs/api/last-good-semantic-attachment.md).

It reuses [`@json.json_grammar`](../json/) and layers a small **settings
document** on top: a flat JSON object mapping string keys to numbers, enforcing
three rules the grammar cannot —

1. the document root is an object,
2. every value is a number,
3. keys are unique.

## What this example demonstrates

- **Pure reactive layer.** The `@incr.Derived` cell is a *pure* function of the
  parser's published views (`source`, `diagnostics`, `syntax_tree`). It reifies
  domain failure into its value (`ParseFailed` / `ProjectionFailed` / `Projected`)
  and mutates nothing — no tracker, no last-good document, no cached state. The
  antipattern this example exists to refute is mutating retention state *inside*
  a derived closure (see the `loom` / `incr` skills).
- **Imperative last-good policy.** All retention and identity bookkeeping lives
  in a `settle` step that reads the pure attempt at the graph boundary
  (`Watch::read()`), then advances cached state.
- **Honest read-error split** (per
  [`incr/.../2026-05-28-honest-read-error-ownership.md`](../../incr/docs/design/specs/2026-05-28-honest-read-error-ownership.md)).
  Parse/projection failures are *values*; a boundary `ReadError` is a distinct
  `GraphBlocked` state, never folded into a parser or projection diagnostic.
- **Stable identity across edits.** It reuses
  [`@loom.ProjectionIdentityTracker`](../../loom/projection/projection_identity.mbt):
  ids are opaque and allocation-order based, so an unchanged setting keeps its id
  even when keys are inserted/removed around it, and the baseline only advances
  on a *successful* projection.

## Public API

```mbt nocheck
pub fn SettingsAttachment::SettingsAttachment(String) -> SettingsAttachment
pub fn SettingsAttachment::state(Self) -> SettingsState
pub fn SettingsAttachment::current_result(Self) -> Result[SettingsDoc, String]
pub fn SettingsAttachment::last_good(Self) -> SettingsDoc?
pub fn SettingsAttachment::apply_edit(Self, @core.Edit, String) -> Unit
pub fn SettingsAttachment::set_source(Self, String) -> Unit
pub fn SettingsAttachment::dispose(Self) -> Unit

pub enum SettingsState { Current; ParserBlocked; ProjectionBlocked; GraphBlocked }
pub struct Setting { id : String; key : String; value : Double } // read-only fields
pub struct SettingsDoc { /* settings() -> Array[Setting] */ }
```

Full signatures: [`pkg.generated.mbti`](pkg.generated.mbti).

## Valid input projects to `Current`

```mbt check
///|
test "valid settings object is Current" {
  let settings = SettingsAttachment::SettingsAttachment(
    "{\"gain\":1,\"cutoff\":2}",
  )
  inspect(settings.state(), content="Current")
  let doc = match settings.current_result() {
    Ok(doc) => doc
    Err(_) => abort("expected Ok")
  }
  inspect(doc.settings().length(), content="2")
}
```

## Malformed input blocks at the parser, last-good is retained

```mbt check
///|
test "malformed input retains the last good document" {
  let settings = SettingsAttachment::SettingsAttachment("{\"gain\":1}")
  settings.set_source("{\"gain\":}") // syntactically broken
  inspect(settings.state(), content="ParserBlocked")
  inspect(settings.current_result() is Err(_), content="true")
  inspect(settings.last_good() is Some(_), content="true")
}
```

## Projection-invalid input blocks at the projection, last-good is retained

```mbt check
///|
test "projection-invalid input retains the last good document" {
  let settings = SettingsAttachment::SettingsAttachment("{\"gain\":1}")
  settings.set_source("{\"gain\":\"loud\"}") // parses, but value is not a number
  inspect(settings.state(), content="ProjectionBlocked")
  inspect(settings.last_good() is Some(_), content="true")
}
```

## Recovery returns to `Current`

```mbt check
///|
test "recovery after a failure returns to Current" {
  let settings = SettingsAttachment::SettingsAttachment("{\"gain\":1}")
  settings.set_source("{\"gain\":}") // fail
  settings.set_source("{\"gain\":5}") // recover
  inspect(settings.state(), content="Current")
}
```

## Running

```bash
cd examples/json-settings
moon test    # behavior matrix + whitebox identity invariant + this README's doctests
```

## Learn More

- [Last-good semantic attachment](../../docs/api/last-good-semantic-attachment.md)
  — the pattern this example checks.
- [Projection guide](../../docs/api/projection-guide.md#stable-identity-across-edits)
  — `ProjectionIdentityBaseline` / `ProjectionIdentityTracker` usage.
- [`examples/lambda`](../lambda/) — the canonical parser-attached pipeline
  (`TypecheckAttachment`), the shape reference for this example.
