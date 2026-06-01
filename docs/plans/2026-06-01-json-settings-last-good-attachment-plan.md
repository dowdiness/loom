# Plan: Tested last-good semantic projection attachment example (issue #202)

**Status:** Active

**Issue:** [#202](https://github.com/dowdiness/loom/issues/202) — Add a tested
authoring attachment example for last-good semantic projections.

**Authored by:** Codex (plan/HOW), under the "Opus orchestrates, Codex plans"
workflow; design (WHAT) converged in the main session.

## Context (the WHAT)

`docs/api/last-good-semantic-attachment.md` documents the last-good semantic
projection attachment pattern, but as an unchecked (`nocheck`) template. This
plan turns it into a small **checked, tested** example that downstream
authoring integrations (notably moondsp's audio DSL) can copy.

Design decisions already settled (do not redesign during execution):

- **Fixture:** reuse `@json.json_grammar` from `examples/json`; the semantic
  layer is a "settings document" — a flat JSON object mapping string keys to
  numbers — enforcing three rules the grammar cannot: root is an object, every
  value is a number, no duplicate keys. This yields all three failure channels
  (syntactic, projection-only, recovery).
- **No incr antipattern:** the `@incr.Derived` is a *pure* function of parser
  inputs; the last-good retention + identity-commit policy lives in an
  imperative facade layer (`settle`), never inside the derived closure.
- **Read-error discipline** (per `incr/docs/design/specs/2026-05-28-honest-read-error-ownership.md`):
  domain failures (parse/projection) are reified into the derived *value*;
  upstream reads *inside the compute* use `get_or_abort` (failure there is a
  lifecycle defect); the boundary read in `settle` uses `Watch::read()` and
  handles `Err(ReadError)` as a distinct graph-health outcome.
- **Reuse** the identity primitives in `loom/src/core/projection_identity.mbt`
  (`ProjectionIdentityTracker`, `ProjectionStringIdAllocator`, `ProjectionLeaf`,
  `StableProjectionLeaf`) — do not invent parallels.

Canonical attachment shape reference: `examples/lambda/src/typed_parser.mbt`
(Scope on `parser.runtime()`, bridge derived reading
`parser.syntax_tree().get_or_abort()`, persistent `Watch` primed once as a GC
root, `dispose()`).

## Steps (the HOW)

Run `NEW_MOON_MOD=0 moon check` after every file edit (Incremental Edit Rule).

### 1. Create the new example module
Files: `examples/json-settings/moon.mod.json`, `examples/json-settings/src/moon.pkg`.

Module `dowdiness/json-settings`, `source: "src"`. Path deps: `dowdiness/json`
→ `../json`, `dowdiness/loom` → `../../loom`, `dowdiness/seam` → `../../seam`,
`dowdiness/incr` → `../../incr`. `dowdiness/incr` must be a **direct** dep —
the package owns `@incr.Scope`/`@incr.Watch`/`@incr.ReadError`, and transitive
loom deps are not enough for `moon.pkg` imports. Mirror `examples/json` for the
import list (add `@incr`, drop json-only deps not needed here).

Verify: `NEW_MOON_MOD=0 moon check` from the new module establishes the scaffold
without triggering moon.mod migration.

### 2. Add the red tests first (TDD)
Files: `examples/json-settings/src/settings_attachment_test.mbt` (blackbox),
`examples/json-settings/src/settings_attachment_wbtest.mbt` (whitebox), plus a
minimal API shell in `settings_attachment.mbt` so `moon check` stays green.

Blackbox matrix (public behavior):
1. initial valid `{"gain":1,"cutoff":2}` → `Current`, two settings with IDs;
2. malformed `set_source("{\"gain\":}")` → `ParserBlocked`, `current_result` is
   `Err`, `last_good` retained;
3. projection-invalid `{"gain":"loud"}` → `ProjectionBlocked`, `Err`,
   `last_good` retained;
4. recovery → `Current`, unchanged keys keep their IDs;
5. `apply_edit` value change → IDs preserved through the exact edit;
6. `set_source` full-replace fallback → unchanged-key IDs preserved;
7. first snapshot malformed `SettingsAttachment("{")` → `last_good() == None`,
   `ParserBlocked`.

Plus the three semantic-rule cases (non-object root, non-number value,
duplicate key) → `ProjectionBlocked`.

Whitebox: after a projection-only failure, `tracker.baseline().source()` is
still the previous *successful* source (the "identity not advanced until
semantic success" criterion). Whitebox because blackbox tests must not be given
access to private tracker state.

Verify: `moon check` green (with shell), `moon test` fails on behavior. Remove
placeholders before final verification.

### 3. Semantic domain + pure CST projection
Files: `examples/json-settings/src/settings_doc.mbt`,
`examples/json-settings/src/settings_projection.mbt`.

Public copyable domain: `Setting`, `SettingsDoc` with `Type::Type` constructors
and accessors that defensively copy arrays; `derive(Debug, Eq)` (not `Show`).
Private raw item carries key text, numeric value, and the key token's UTF-16
start/end offsets.

Pure projection from `@seam.SyntaxNode`: `RootNode → ObjectNode`; iterate
`MemberNode`; read the direct key `StringToken`; require the value child to be
`NumberValue` with a direct `NumberToken`; parse the number; reject duplicate
decoded keys. Use `@json.parse_json_string` for key text. Build
`@loom.ProjectionLeaf` from key text + key-token offsets. Do **not** use
`@json.syntax_node_to_json` — it drops key-token offsets and enforces none of
the settings rules.

**Use the existing Result-returning shape-validation helpers** (verified present
in `seam/pkg.generated.mbti`, 2026-06-01): `SyntaxNode::required_direct_child_of_kind`,
`required_direct_token_of_kind`, `optional_direct_*`, and
`expect_no_direct_*_of_kind`, all returning `Result[_, @seam.ProjectionShapeError]`.
Express the three rules as composed `required_*`/`optional_*` calls rather than
hand-rolled `match` shape-checking, and map `ProjectionShapeError → String` into
the `ProjectionFailed` diagnostics. Key-token offsets come from
`SyntaxToken::start()/end()`; the key token is `MemberNode`'s direct
`StringToken` (`StringToken.to_raw()` for the `RawKind`). No traversal helper is
needed.

### 4. Pure derived attachment cell
File: `examples/json-settings/src/settings_attachment.mbt`.

Private `ProjectionAttempt` carrying the projected `source` + a
`ProjectionOutcome` = `ParseFailed(Array[String])` | `ProjectionFailed(Array[String])`
| `Projected(Array[RawSetting])`. The derived closure reads only
`parser.source()`, `parser.diagnostics()`, `parser.syntax_tree()` via
`get_or_abort` and returns a `ProjectionAttempt` — mutating no `Ref`, tracker,
`last_good`, or cached state.

Build the parser with `@loom.new_parser(initial_source, @json.json_grammar)`
*outside* the closure. `@incr.Scope::new(parser.runtime())`; create the derived
with `scope.derived`; anchor with `scope.add_watch(derived.watch())`; prime the
watch once. Comment that no `ImperativeParser` is constructed in a reactive
closure (satisfies that acceptance criterion by construction).

### 5. Imperative `settle` policy + public facade
File: `examples/json-settings/src/settings_attachment.mbt`.

Public `SettingsState` = `Current` | `ParserBlocked` | `ProjectionBlocked` |
`GraphBlocked` (the 4th variant is intentional: a boundary `ReadError` is
neither a parser nor a projection diagnostic — folding it in would violate the
honest-read-error split).

`SettingsAttachment` owns parser, scope, watch,
`@loom.ProjectionIdentityTracker[String]`, current-source cache, `last_good`,
cached state. `apply_edit` captures `source_before_edit` from the cache, calls
`parser.apply_edit`, updates the cache, then `settle` with the exact edit.
`set_source` calls `parser.set_source` then `settle` with no edit (tracker
source-diff fallback).

`settle` reads `watch.read()`:
- `Err(ReadError)` → `GraphBlocked`, retain `last_good`, do not touch tracker;
- `ParseFailed`/`ProjectionFailed` → `tracker.record_failed_input(...)`, set the
  matching blocked state, retain `last_good`;
- `Projected` → seed a `ProjectionStringIdAllocator` from `tracker.baseline()`
  when present, `tracker.realign_success` (preview), build `SettingsDoc` by
  zipping raw settings to stable leaves, then `tracker.commit_success` — **the
  only baseline-advancing call, reachable only here**.

Public surface: `state()`, `current_result() -> Result[SettingsDoc, String]`
(`Ok` only for `Current`; stale data only via `last_good()`), `last_good()`,
`apply_edit`, `set_source`, `dispose()`.

### 6. Checked README example
Files: `examples/json-settings/src/README.mbt.md` + root `README.md` symlink
(mirror existing examples). Short `mbt check` snippets: valid, parser-blocked
retention, projection-blocked retention, recovery — so `moon test` checks them.

### 7. Generate interface + format
`NEW_MOON_MOD=0 moon info` in the module; review `pkg.generated.mbti` so private
`ProjectionAttempt`/raw/tracker internals do not leak. `NEW_MOON_MOD=0 moon fmt`.

### 8. Wire docs + CI
- `docs/api/last-good-semantic-attachment.md`: add a "Tested example" link to
  `../../examples/json-settings/`, noting it is the checked version of the
  `nocheck` template (pure derived + imperative settle).
- `docs/README.md`: add `examples/json-settings` to the Examples list (required
  because a README is added).
- `.github/workflows/ci.yml`: add `examples-json-settings`
  (`examples/json-settings`) to **both** the `fmt-check` and `test-modules`
  matrices, mirroring `examples-json`.

## Final verification checklist
From `examples/json-settings`: `NEW_MOON_MOD=0 moon check`, `... moon test`,
`... moon info`, `... moon fmt --check`. From repo root: `bash check-docs.sh`.
Confirm `examples-json-settings` appears in both CI fan-outs.

**Decision record:** No ADR needed — this implements already-accepted last-good
semantic projection and stable-identity decisions; it adds an example, not a new
design.

## Open questions / assumptions to confirm during execution
1. **Key-token offset API — RESOLVED 2026-06-01.** `seam/pkg.generated.mbti`
   confirms `SyntaxNode::direct_token_of_kind(RawKind) -> SyntaxToken?` and
   `SyntaxToken::start()/end() -> Int`, plus the `required_direct_*`/`optional_direct_*`
   family returning `Result[_, ProjectionShapeError]`. No traversal helper
   needed; use the Result-returning helpers (see step 3).
2. `dowdiness/incr` uses local path `../../incr` (current `ReadError` surface),
   not lambda's older published pin.
3. Blackbox covers public behavior; one whitebox covers the private
   tracker-baseline invariant.
4. Public ID schema = deterministic strings (settings-prefixed key + occurrence
   via `ProjectionStringIdAllocator`'s `make_id`); adjust only if moondsp needs a
   specific shape.
