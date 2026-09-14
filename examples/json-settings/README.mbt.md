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

- **Parser-owned semantic layer.** `SettingsAttachment` attaches one
  `@loom.SemanticAnalysis` to the existing JSON parser. The callback consumes
  the captured `SemanticSnapshot`, performs parser-diagnostic gating and the
  real settings projection, then returns one complete accepted model or a
  language-owned rejection. It never reparses or mutates retained state.
- **Last-good ownership.** The semantic analysis owns accepted observations,
  pending edit metadata, identity baselines, and graph lifetime. The example
  facade translates those observations to `SettingsState`, `current_result()`,
  and `last_good()`; it does not maintain a parallel tracker or cache.
- **Honest failure split.** Parser/projection failures are language rejections,
  candidate exceptions become `CandidateBlocked`, and a boundary
  `@incr.ReadError` remains a distinct `GraphBlocked` state. Every failed
  candidate retains the last accepted document.
- **Stable identity across edits.** Each accepted model owns an immutable
  `@loom.ProjectionIdentityBaseline`. A baseline-local allocator reuses
  unchanged setting IDs while allocating fresh IDs for changed-window leaves.
  Failed candidates do not commit a baseline or consume IDs; `retry()` can
  settle the same revision again.
- **Explicit semantic intent.** Incremental edits, including nonempty
  same-text replacements, are delivered through the parser's semantic
  transition metadata. `set_source` remains a source replacement and a
  same-text no-op.

## Public API

```mbt nocheck
pub fn SettingsAttachment::SettingsAttachment(
  @core.SourceId,
  String,
) -> SettingsAttachment raise Failure
pub fn SettingsAttachment::state(Self) -> SettingsState
pub fn SettingsAttachment::current_result(Self) -> Result[SettingsDoc, String]
pub fn SettingsAttachment::last_good(Self) -> SettingsDoc?
pub fn SettingsAttachment::apply_edit(
  Self,
  @core.Edit,
  String,
) -> Unit raise Failure
pub fn SettingsAttachment::set_source(Self, String) -> Unit raise Failure
pub fn SettingsAttachment::retry(Self) -> Unit raise Failure
pub fn SettingsAttachment::dispose(Self) -> Unit

pub enum SettingsState {
  Current
  ParserBlocked
  ProjectionBlocked
  CandidateBlocked
  GraphBlocked
}
pub struct Setting { id : String; key : String; value : Double } // read-only fields
pub struct SettingsDoc { /* settings() -> Array[Setting] */ }
```

Full signatures: [`pkg.generated.mbti`](pkg.generated.mbti).

`SourceId` is a stable identity owned by the caller for the source being parsed.
It is distinct from both source text and diagnostic-producer identity.

## Valid input projects to `Current`

```mbt check
///|
test "valid settings object is Current" {
  let source_id = @core.SourceId("json-settings-readme-valid")
  let settings = SettingsAttachment::SettingsAttachment(
    source_id, "{\"gain\":1,\"cutoff\":2}",
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
  let source_id = @core.SourceId("json-settings-readme-parser-retention")
  let settings = SettingsAttachment::SettingsAttachment(
    source_id, "{\"gain\":1}",
  )
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
  let source_id = @core.SourceId("json-settings-readme-projection-retention")
  let settings = SettingsAttachment::SettingsAttachment(
    source_id, "{\"gain\":1}",
  )
  settings.set_source("{\"gain\":\"loud\"}") // parses, but value is not a number
  inspect(settings.state(), content="ProjectionBlocked")
  inspect(settings.last_good() is Some(_), content="true")
}
```

## Recovery returns to `Current`

```mbt check
///|
test "recovery after a failure returns to Current" {
  let source_id = @core.SourceId("json-settings-readme-recovery")
  let settings = SettingsAttachment::SettingsAttachment(
    source_id, "{\"gain\":1}",
  )
  settings.set_source("{\"gain\":}") // fail
  settings.set_source("{\"gain\":5}") // recover
  inspect(settings.state(), content="Current")
}
```

## Running

```bash
cd examples/json-settings
moon test    # behavior matrix + semantic-coordination regressions + doctests
```

## Learn More

- [Last-good semantic attachment](../../docs/api/last-good-semantic-attachment.md)
  — the pattern this example checks.
- [Projection guide](../../docs/api/projection-guide.md#stable-identity-across-edits)
  — `ProjectionIdentityBaseline` and the shared alignment policy.
- [`examples/lambda`](../lambda/) — the canonical parser-attached pipeline
  (`TypecheckAttachment`), the shape reference for this example.
