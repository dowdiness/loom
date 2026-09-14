# Last-good Semantic Document Attachment

Use `Parser::attach_semantic` when current parser diagnostics must remain
available while a semantic document, identity baseline or reuse artifact advances
only after a trusted candidate succeeds. Core owns publication; the language owns
projection, diagnostics and the model's snapshot contract.

The production example is [`examples/json-settings/`](../../examples/json-settings/).
It reuses JSON projection and `SettingsDoc`, and chooses eager settlement in its
compatibility facade. See the [ownership ADR](../decisions/2026-09-12-semantic-publication-ownership.md)
for the publication and lifetime decisions, and the
[authoring-only integration guide](authoring-only-integration.md) for runtime
package isolation.

## Two independent timelines

- **Parser:** `source()`, `syntax_tree()`, `ast()` and `diagnostics()` describe the
  current accepted parser snapshot, including recovered syntax and diagnostics.
- **Semantic analysis:** `SemanticAccepted[M]` contains one trusted value and its
  matching `SemanticSnapshot`. A rejected or faulted current input retains that
  entire accepted value; initial failure has no last-good value.

Put the document, `ProjectionIdentityBaseline` and correctness-bearing reuse
state in one language-owned `M`. Build a fresh candidate; do not mutate a previous
accepted model or commit a tracker separately. Core publishes `M` and its source
snapshot only after the callback returns `Accept(M)`.

Neither the model nor language rejection data needs `Eq`. Both must remain
observationally stable. Use the domain's existing opaque/copying or persistent
APIs, including protection against mutable constructor inputs and returned
collections. A candidate may use mutable scratch storage; core cannot undo
arbitrary mutation through aliases to an earlier result.

## Register once, choose when to settle

Create the parser outside reactive closures. Register a callback with
`parser.attach_semantic`; it receives previous acceptance, current snapshot and
pending `SemanticChange`. Registration primes its own persistent parser watch
but does not run the callback.

The callback checks `snapshot.diagnostics()`, projects `snapshot.syntax()`, and
returns `SemanticDecision::Accept(model)` or `Reject(language_reason)`. Use a
language-owned rejection type to distinguish parser diagnostics from projection
rejection. A candidate exception is not an expected rejection.

For eager behavior, the update boundary is simply:

```mbt nocheck
parser.apply_edit(edit, new_source)
let observation = analysis.read()
```

The snippet assumes an existing parser and its registered analysis. Construction
also calls `read()` once when the facade promises an initial settled result.
`set_source` and `apply_changes` use the same sequence. Parser updates record
metadata but never call candidate code. Different analyses on one parser settle
independently and may have different last-good baselines.

`analysis.observation()` returns the last completed observation without
re-evaluation, or `None` before the first read. Its source and revision identify
that observation, not necessarily the latest parser source. `read()` settles the
latest registered transition. Current and rejected results are cached for that
transition; another explicit read retries a fault. There is no automatic retry
loop.

Candidate code must not update, register or settle the same parser reentrantly.
Such operations fail before changing the parser. Previously completed
observations remain available for read-only inspection.

## Preserve the domain's identity policy

`SemanticChange::edit()` provides trustworthy baseline-relative explicit edit
evidence, or `None` for source-diff fallback. Pass it to the existing immutable
`ProjectionIdentityBaseline::advance` operation; store its resulting baseline
with the newly lowered document in the candidate. Keep allocation baseline-local
when that is the domain's existing rule.

The evidence is a conservative edit envelope, not a lossless list of changes.
It shares the existing projection validation/composition helpers. Source-only or
non-composable transitions lose exact provenance until acceptance establishes a
new baseline. An explicit equal-text replacement retains semantic edit intent
even if reactive parser views compare equal. Equal-text `set_source` and empty
change sets remain no-ops.

Do not manually mirror parser edits into another pending-change cache. The parser
already delivers successful transitions to each registered analysis, including
edits after a semantic failure.

## Separate outcomes and continue after faults

| Core outcome | Meaning | JSON settings state |
|---|---|---|
| `Current` | Complete candidate accepted | `Current` |
| `Rejected(R)` | Language rejected parser/projection input | `ParserBlocked` or `ProjectionBlocked` |
| `GraphFailed(ReadError)` | Actual parser watch read failed | `GraphBlocked` |
| `CandidateFailed(Error)` | Candidate code raised before publication | `CandidateBlocked` |

A parser update can succeed while a semantic read faults. In JSON settings the
update returns normally; `state()` and `current_result()` expose the semantic
fault while `last_good()` retains the old document. `retry()` explicitly reads
again. Alternatively, apply the next edit normally: settlement uses the newest
source and the failed analysis's retained baseline, not the obsolete candidate.

A compatibility `Result[Doc, String]` must report rejected/faulted current input
as `Err`, never stale last-good as `Ok`. Expose stale content explicitly under
`last_good` or an equivalent name. `CandidateBlocked` is an added enum variant;
consumers must update exhaustive `SettingsState` matches.

Ordinary eager edits retain the existing settings ID behavior. If a fault skips
an intermediate acceptance, the final ID history need not equal a fault-free run.
The guarantee is coherent publication and continuation, not replay of skipped
acceptances.

## Lifetime

An analysis owns its scope and primed watch on `parser.runtime()`. Call
`dispose()` to release its registration and GC root; this does not dispose the
parser or caller-owned runtime. Disposal is idempotent.

Already returned observations and `observation()` remain readable after disposal.
A new `read()` raises `Failure` before touching the closed watch. Disposing during
candidate construction cancels publication with a lifecycle failure, preserving
the completed observation. A closed watch is not a disposed-cell `ReadError`.
JSON settings' cached `state`, `current_result` and `last_good` reads remain usable
after disposal without reevaluating the closed analysis.

If other parser views must survive `Runtime::gc()`, give those consumers their
own persistent roots. See [runtime ownership](choosing-a-parser.md#runtime-ownership-and-attachments).

## Regression contracts

The production core/settings tests cover:

- independent siblings accepting, rejecting or faulting from different baselines;
- ordinary eager rename and explicit equal-text key replacement;
- parser and projection rejection, including later recovery;
- a fault after candidate/ID construction, followed by explicit retry or a newer
  edit without retrying the obsolete source;
- non-`Eq` models, primed graph anchors, reentrant-update rejection and disposal;
- retained documents, identity baselines, snapshots and returned collection
  copies remaining unchanged after later updates, failures or closure.
