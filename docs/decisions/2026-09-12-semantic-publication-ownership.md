# ADR: Generic semantic publication and domain-local snapshots

**Date:** 2026-09-12
**Status:** Accepted
**Implementation:** `loom/pipeline/semantic.mbt`, `loom/pipeline/semantic_updates.mbt`, and `examples/json-settings/settings_attachment.mbt`
**Amends:** [Last-good semantic projection](2026-05-28-authoring-last-good-semantic-projection.md), specifically its language-owned coordination implementation
**Related:** [Core collection ownership](2026-08-05-core-collection-ownership-boundary.md), [Markdown source-bound reads](2026-08-10-markdown-semantic-read.md)

## Context

The coordination prototype established that heterogeneous semantic models do not
need equality to publish a model with its source baseline. The real settings
prototype (`e0fa130e`, eager integration `ffa3eb43`) exercised existing JSON
projection and stable-ID rules. Its full-source session parser and per-character
edit provenance were experimental machinery, not the production integration.

Production already has one `Parser[Ast]` backed by an incremental engine and a
coherent snapshot input. JSON settings separately held a tracker, watch, current
result and last-good result, advancing them in a language-owned settlement
procedure. This duplicated the publication policy and made candidate failure
between construction and baseline commit a language responsibility.

A generic transaction cannot undo mutation through an arbitrary model alias.
An author can mutate an earlier model and then throw. An `Immutable` marker or
ordinary copying trait does not prove otherwise. Publication ownership and
observational stability therefore need separate contracts.

## Decision

### Publication unit and ownership

`Parser::attach_semantic` registers a `SemanticAnalysis[M, R]`. The callback
receives its previous `SemanticAccepted[M]`, the current `SemanticSnapshot`, and
an immutable `SemanticChange`. It returns `Accept(M)` or `Reject(R)` and may
raise a candidate error. Neither `M` nor `R` needs `Eq`.

Core owns the only accepted frame. A successful read publishes the candidate and
its matching parser snapshot, and clears pending edit evidence, in one frame
replacement. Authors put the semantic document, identity baseline and any
correctness-bearing reuse state together in `M`; they do not separately advance
those artifacts. Rejection or fault retains the whole previously accepted frame.

JSON settings uses one private value containing its existing `SettingsDoc` and
`ProjectionIdentityBaseline[String]`. Its projection, document API, defensive
copies and baseline-local allocator remain unchanged. Its facade now owns only
the parser and analysis, not another tracker or last-good cache.

### Existing parser boundary and edit evidence

No second parser is introduced. Registration primes a scope-owned watch of the
existing parser snapshot. Parser update methods deliver transition metadata only
after the engine succeeds, with the existing batched snapshot publication. They
do not execute semantic callbacks.

The parser lazily creates a semantic transition sequence on first registration.
This revision is shared by that parser's analyses, not the Incr runtime revision.
It distinguishes explicit equal-text edits even when reactive views backdate.
Equal-text `set_source` and empty change sets remain no-ops. Nonempty equal-text
change sets retain explicit semantic intent without reparsing.

Each analysis retains its own baseline-relative `SemanticChange`. It reuses the
existing projection edit validation/composition helpers. Exact evidence is a
conservative edit envelope, not a lossless multi-edit history. Source-only or
non-composable transitions degrade to source-diff alignment; a later explicit
edit cannot reconstruct missing provenance. No per-character provenance array
or duplicate identity algorithm is introduced.
The composition helpers live in `loom/internal/semantic_change`, shared by
pipeline and projection. The public `SemanticChange` type belongs to pipeline;
engine packages do not import projection, and internal helpers are not exposed
through the facade.

### Partial success and eager timing

Parser success and semantic success are distinct. One analysis may accept while
a sibling rejects or faults; neither can erase the other's accepted value.
`SemanticStatus` distinguishes `Current`, language-owned `Rejected(R)`, actual
watch `GraphFailed(ReadError)`, and `CandidateFailed(Error)`. Candidate exceptions
are caught only at the author-code boundary, not relabeled as graph errors or
parser/projection diagnostics.

The integration chooses eager settlement by calling `analysis.read()` after a
successful parser update. JSON settings does this during construction and after
each update. Core does not impose eager timing on other analyses or run a retry
loop. Successful and rejected observations are cached for the current transition;
a subsequent explicit read retries a fault.

After a candidate fault, the parser can accept another edit immediately. Either
an explicit retry or a read following the next edit analyzes the latest source
from the failed analysis's last accepted baseline. It does not replay an obsolete
candidate. Normal eager settings edits retain existing ID behavior. Skipping a
faulted intermediate acceptance need not produce the same ID history as a
fault-free execution.

Same-parser mutation, registration or settlement during candidate evaluation is
rejected before it can change the parser. Read-only access to previously completed
observations remains possible. This is a synchronous publication boundary, not a
sandbox for arbitrary callback effects.

### Lifetime and returned values

Each analysis owns a primed `Scope`/`Watch` on `parser.runtime()`. Disposal removes
its parser registration and graph anchor, not the parser or caller-owned runtime.
It is idempotent. `observation()` remains a cached read after disposal; values
already returned are not rewritten. A new `read()` after disposal raises
`Failure` before touching the closed watch. Closing during candidate construction
cancels publication with the same lifecycle failure and preserves the completed
observation. A closed watch is not a disposed-cell `ReadError`; only actual
watch-read errors become `GraphFailed`.

Authors and consumers must keep published model and rejection values
observationally stable. Native readonly collections, persistent collections or
opaque domain-owned storage can provide that boundary. Fresh candidate builders
may mutate. Private deterministic caches are allowed if they do not change prior
observations or invalidate later computations. Core does not add a universal
freeze/copy hook, mandatory arena or `Immutable` marker. Existing Loom-owned CST
and diagnostic isolation guarantees are not weakened.

### API compatibility and scope

Existing `Parser` update/read/runtime signatures remain unchanged. The new
semantic APIs are additive. Existing `Setting`, `SettingsDoc` and
`SettingsAttachment` methods retain their signatures. JSON settings adds
`retry()` and `SettingsState::CandidateBlocked`; the latter intentionally requires
updating exhaustive state matches. A candidate fault after parser success returns
normally from the update, while `state()` and `current_result()` report the fault
and `last_good()` retains the old document.

Only JSON settings is migrated. This decision does not change Markdown's eager
one-shot lowering, migrate other attachments, or update dependency versions.

The hardening review leaves the additive API unchanged. In particular, the public
`SemanticChange` constructor and `advance` remain available; `edit()` validates
their evidence against the endpoints. A second attachment is not migrated merely
to justify or reshape that API. Another real consumer is still needed before
claiming that the interface is broadly sufficient.

### Failed edits and measured pending-edit cost

`ImperativeParser::edit` commits its source only after parsing succeeds, including
the full-parse path before its first snapshot. A failed edit must not make a later
`set_source` of the already-published source fabricate a semantic transition.

A release microbenchmark on the pinned MoonBit 0.10.8 toolchain measured eight
exact pending replacements followed by final evidence validation, with strings
prepared outside the timed body. For one analysis and 65,537 UTF-16 code units,
the mean was 5.00 ms on JS and 0.603 ms on native. At 1,048,577 units it was
78.98 ms and 9.80 ms respectively. These are local WSL measurements of
`SemanticChange` composition, not parser latency or ordinary eager settings
updates. Multiple pending analyses repeat the source comparisons; this cost
remains linear in source length per validation.

A small `StringView` comparison prototype improved ASCII timings but aborted
when an edit boundary split a surrogate pair. It was rejected: edit evidence is
defined in UTF-16 code units, not character boundaries. The code-unit comparison
remains, with a differential boundary regression. Performance work must preserve
that contract and demonstrate an end-to-end need before adding more machinery.

## Rationale

The existing parser is already the authority for successful source transitions.
Putting metadata delivery there prevents edits from bypassing an attachment's
pending evidence. Keeping settlement explicit avoids adding language failures to
parser update methods and lets siblings make independent progress.

One opaque accepted value removes the separate document/baseline commit hazard
without prescribing a universal semantic representation. Domain-local snapshot
APIs protect the representations they actually own; a generic marker would not
protect nested mutable aliases or arbitrary callback side effects.

## Consequences

- Candidate rejection/failure retains a coherent previous publication under the
  stated model contract. It is not rollback of arbitrary external mutation.
- Callers explicitly choose settlement order, retry and disposal. The parser does
  not automatically retry failing language code.
- Cached observations can be older than the current parser; their source and
  semantic revision identify what was observed. `read()` settles the latest
  registered transition.
- Regressions cover eager renames, explicit equal-text intent, rejection/recovery,
  faults after candidate construction, retry and next-edit continuation, sibling
  independence, non-`Eq` models, graph lifetime and retained returned values.
- No plan is archived by this change. This ADR records the production ownership
  and public API decision rather than treating it as mechanical documentation.
