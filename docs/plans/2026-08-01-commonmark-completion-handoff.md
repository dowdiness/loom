# CommonMark 0.31.2 Completion Handoff

**Status:** Active
**Decision record:** [ADR 2026-08-01](../decisions/2026-08-01-commonmark-completion-contract.md)
**Tracker:** [#723](https://github.com/dowdiness/loom/issues/723)
**Wayfinder:** [#797](https://github.com/dowdiness/loom/issues/797)

## Objective

Move from the measured 437/652 CommonMark 0.31.2 baseline to a clean 652/652
semantic pipeline while keeping every implementation PR bounded, reversible,
and independently verifiable.

## Invariants for every slice

- Preserve existing public parser and editor-projection APIs.
- Keep deterministic classification, lowering, and state transitions in a
  private functional core; keep parser mutation and I/O in the shell.
- Do not add a feature without fresh-versus-incremental parity for its edit
  boundaries.
- Do not count `Unsupported`, malformed `Raw`, `Recovered`, diagnostics, skips,
  or xfails as conformance.
- Use explicit raw HTML policy; product default is `Escape`, conformance selects
  `Passthrough`.
- Add or widen reuse only after semantic parity; fallback is always valid.

## Ordered delivery graph

### Phase 0 — Make the gate truthful

Split the audit's opaque failure bucket into parser diagnostics,
`Unsupported`, malformed `Raw`, `Recovered`, adapter-policy rejection, and HTML
mismatch. Pin the completion assertion without changing current feature output.
This is [#807](https://github.com/dowdiness/loom/issues/807), the initial
unblocked implementation frontier.

Exit gate: the existing 437/652 baseline still reproduces, but every residual
has exactly one machine-readable category and one owner.

### Phase 1 — Establish the private block seam

Introduce the private `BlockContainerState + BlockLineFacts -> Decision` core.
Characterize existing top-level, blockquote, and list-item dispatch before
migrating one path at a time. The parser shell retains CST emission and may
fallback whenever facts are insufficient. This foundation is
[#808](https://github.com/dowdiness/loom/issues/808) under the #327 tracker.

Exit gate: migrated cases preserve direct CST/diagnostic/IR/HTML output and
incremental parity; no public `.mbti` change; duplicated container-by-block
dispatch stops growing.

### Phase 2 — Complete block-owned semantics

After the seam is stable, block slices may proceed independently where their
fixtures do not overlap:

- list child flow, indentation, tabs, and lazy continuation;
- blockquote continuation;
- indented and fenced code interactions;
- HTML blocks and remaining atomic block cases;
- typed link-reference definition recognition and document-level collection in
  [#811](https://github.com/dowdiness/loom/issues/811).

Reference definitions are collected before inline lowering. Setext/thematic
work is already complete and its stale follow-up is closed rather than reopened.

Exit gate per slice: promoted official examples pass cleanly and the slice's
incremental matrix passes construction, destruction, boundary, and content
edits.

### Phase 3 — Complete inline-owned semantics

The independent entity and ordinary-escape lanes may proceed in parallel.
Implement explicit soft/hard break semantics and explicit autolink/inline-HTML
nodes through #467 and [#810](https://github.com/dowdiness/loom/issues/810).
Once the block definition table exists, resolve inline links, images, and
reference forms in [#812](https://github.com/dowdiness/loom/issues/812), with
#397 retaining category-level conformance tracking.

Raw HTML adapter policy can land independently of parser recognition, provided
both valid `HtmlBlock`/`InlineHtml` and malformed recovery `Raw` are tested as
different inputs. [#809](https://github.com/dowdiness/loom/issues/809) owns that
policy implementation.

Exit gate per slice: MarkdownIR is sufficient for HTML and mdast adapters;
adapters do not inspect CST tokens or rediscover reference definitions.

### Phase 4 — Integrate and close conformance

Run the full direct corpus and the checked-in representative incremental matrix.
Close only when all 652 official examples pass with clean diagnostics and no
opaque/recovery assistance. Record the exact commands, fixture checksum,
section totals, and main commit in #721.

## Native dependency frontier

```text
#807 completion-grade audit taxonomy
  ├─ #808 private block-container core
  │    ├─ #392 #394 #478 #479 #481 block feature slices
  │    ├─ #480 HTML blocks (also waits for #809)
  │    └─ #811 definition recognition/collection
  │          └─ #812 link/image/reference resolution
  ├─ #809 explicit raw HTML adapter policy
  │    └─ #810 Autolink and InlineHtml semantics
  ├─ #395 entity references
  └─ #467 explicit soft/hard break semantics

#810 + #812 -> #397 link/image/reference conformance tracker
M5/M6 trackers + #397 -> #721 final 652/652 exit audit
```

Until #807 closes, it is the sole new unassigned, unblocked implementation
issue. After it closes, #808, #809, #395, and #467 form independent bounded
frontiers. Native GitHub dependencies are authoritative; `blocked` labels only
mirror them for list readability.

## Pull-request sizing and rollback

One PR owns one interface change or one fixture family. A PR that must change
both the container core and a feature proves the core change first in a separate
commit and keeps feature fixtures separable. Rollback is always a normal revert:
no PR may require a repository-wide flag day.

The following changes require a new decision before proceeding:

- public Loom parser-core or `ParserContext` expansion;
- a new cache, reuse heuristic, or performance threshold;
- a broad Markdown package split;
- a change to the `Block` / `Inline` compatibility contract;
- product sanitizer or trust-policy selection.

## Validation matrix

For every feature PR:

1. Direct parse the old and edited source.
2. Apply the same edit incrementally and fresh-parse the edited source.
3. Compare CST kind/shape and source text.
4. Compare diagnostic identity, source IDs, labels, and ranges.
5. Compare MarkdownIR semantic fields and origins.
6. Compare HTML under the explicitly selected raw-HTML policy.
7. Assert fallback for boundary-changing edits; assert reuse only for selected
   safe fast paths.

Feature-specific edit families:

| Owner | Required edit families |
|---|---|
| Containers | indent/outdent, blank-line insertion/removal, lazy continuation, marker/fence damage |
| Definitions | add/remove/change/duplicate definition, normalized-label change, paragraph fallback |
| Links/images | inline/full/collapsed/shortcut conversion, destination/title/label edits, unresolved fallback |
| Breaks | newline insertion/removal, trailing-space count, backslash damage, neighboring inline syntax |
| Autolink/HTML | delimiter damage, URI/email boundary, inline/block HTML boundary, raw policy modes |

## Existing issue disposition

- #327, #329, and #330 remain milestone trackers, not single implementation PRs.
- #397 becomes the links/images/reference conformance tracker after bounded
  definition-collection and resolution issues are created.
- #467 is narrowed to the residual hard/soft-break examples; inline HTML examples
  move to the inline-HTML owner.
- #430 is closed as stale because the current audit passes all thematic-break and
  setext-heading examples.
- #721 replaces its obsolete 50%/abort language with the 652/652 exit contract.
- #723 and the M5/M6/M7 descriptions carry this order as the canonical tracker.

## Out of scope

Canonical formatter conformance, editor/Canopy integration, GFM extensions,
loomgen inline parsing, HTML sanitization, broad package restructuring, and
unmeasured caching or reuse optimization remain separate work.
