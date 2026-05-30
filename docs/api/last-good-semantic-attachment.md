# Last-good Semantic Document Attachment

Use this pattern when an editor needs diagnostics for the current source text
immediately, but a semantic document, stable-ID table, or reuse cache must only
advance after a trusted projection succeeds.

This guide complements the [authoring-only integration guide](authoring-only-integration.md)
and the [CST projection guide](projection-guide.md). It is a state policy for a
language-owned authoring facade, not a new Loom parser API.

## State contract

Keep two kinds of authoring state separate:

1. **Current parser state** — `parser.source()`, `parser.syntax_tree()`, and
   `parser.diagnostics()` advance on every `apply_edit` or `set_source` call.
   Parser diagnostics describe the current text.
2. **Last-good semantic state** — the last semantic document whose parser and
   projection stages both succeeded. It may include reuse artifacts such as
   stable IDs, atom tables, symbol indexes, or the source text used as the reuse
   baseline.

Malformed input must not replace the last-good semantic state. The current
operation may fail, and callers should see that failure, but the attachment keeps
the previous successful document available for the next successful projection.

Track projection errors separately from parser diagnostics. Parser diagnostics
answer "is the current CST syntactically trusted?" Projection diagnostics answer
"did my language-owned CST → private IR → semantic lowering succeed?"

## Update policy

For each editor edit:

1. Drive the parser through the unified surface: construct it with
   `@loom.new_parser`, then update it with `parser.apply_edit(edit, new_source)`
   or `parser.set_source(new_source)`.
2. Record a pending semantic change relative to the last-good source baseline.
   If exact edit composition is available, keep the composed edit. Otherwise
   keep a full-replace sentinel or enough source text to compute a later diff.
   This pending change is independent of the parser engine's current baseline.
3. Publish parser diagnostics for the current text immediately.
4. If parser diagnostics are non-empty, skip semantic projection for the current
   text, keep the last-good document unchanged, and keep the pending semantic
   change for a future recovery.
5. If parser diagnostics are empty, run projection from the current
   `syntax_tree()` into a private IR and semantic document.
6. On projection success, replace the last-good semantic state, store the
   current source as its new baseline, clear the pending semantic change, and
   expose the new document as current.
7. On projection failure, keep the last-good semantic state and pending semantic
   change unchanged, and expose projection diagnostics separately from parser
   diagnostics.

For stable leaf IDs, store a `@loom.ProjectionIdentityBaseline` in the
last-good semantic state, or use `@loom.ProjectionIdentityTracker` when the
facade wants Loom to own the baseline plus pending identity edit. On projection
success, call `baseline.advance` / `tracker.realign_success` with a
baseline-relative `edit` when available, or omit it to fall back to source
diffing after `set_source` or malformed intermediate input. When using the
tracker, `realign_success` is preview-only; call `commit_success` only after
semantic lowering succeeds.

The default policy for semantic projection failures is retention: a failed
projection does not replace the last-good document even when parser diagnostics
are empty. This includes language-owned failures such as mode-incompatible atoms
or invalid cross-reference shapes. If a language can build a deliberately partial
but trusted semantic document, model that as a successful document with warning
diagnostics, not as a projection error.

If the first source snapshot is malformed, the attachment has no last-good
document yet. It should expose current parser or projection diagnostics and a
`None` last-good value until the first successful projection.

## Attachment template

The attachment is language-owned because the semantic document, reuse artifacts,
projection diagnostics, and edit-composition policy are language-specific. The
canonical Loom/incr shape is still fixed:

- build the parser outside the reactive closure with `@loom.new_parser`;
- root downstream cells on `parser.runtime()`;
- read parser views with `.get_or_abort()` inside `scope.derived` closures;
- hold a persistent `Watch` on the terminal derived state; and
- optionally expose compatibility helpers at the facade edge.

Expose parser diagnostics directly from `parser.diagnostics()` or through a
separate facade method/watch. Do not make current diagnostics wait for semantic
projection to succeed.

```mbt nocheck
// Language-owned public diagnostics. Do not force editor callers to depend on
// Loom internals unless the authoring API intentionally exposes them.
pub struct AuthoringDiagnostic { ... }
pub struct ProjectionDiagnostic { ... }

// Project-specific pending baseline. Use an exact composed edit when possible;
// fall back to FullReplace when the next successful projection should diff
// last-good source against current source.
priv enum PendingSemanticChange {
  NoChange
  ExactEdit(@core.Edit)
  FullReplace
}

priv struct LastGood[Doc, Reuse, Id] {
  source : String
  document : Doc
  reuse : Reuse
  identity_baseline : @loom.ProjectionIdentityBaseline[Id]
}

pub(all) enum SemanticState[Doc] {
  Current(document~ : Doc)
  ParserBlocked(
    parser_diagnostics~ : Array[AuthoringDiagnostic],
    last_good~ : Doc?,
  )
  ProjectionBlocked(
    projection_diagnostics~ : Array[ProjectionDiagnostic],
    last_good~ : Doc?,
  )
}

pub(all) struct SemanticAttachment[Ast, Doc, Reuse, Id] {
  parser : @loom.Parser[Ast]
  scope : @incr.Scope
  last_good : Ref[LastGood[Doc, Reuse, Id]?]
  pending_change : Ref[PendingSemanticChange]
  state_watch : @incr.Watch[SemanticState[Doc]]
}

pub fn SemanticAttachment::SemanticAttachment(
  initial_source : String,
  grammar : @loom.Grammar[Token, Kind, Ast],
) -> SemanticAttachment[Ast, SemanticDoc, ReuseState, PublicId] {
  let parser = @loom.new_parser(initial_source, grammar)
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  let last_good : Ref[LastGood[SemanticDoc, ReuseState, PublicId]?] = Ref(None)
  let pending_change = Ref(PendingSemanticChange::NoChange)
  let state = scope.derived(
    fn() {
      let source = parser.source().get_or_abort()
      let parse_diags = parser.diagnostics().get_or_abort()
      if !parse_diags.is_empty() {
        SemanticState::ParserBlocked(
          parser_diagnostics=lower_parser_diagnostics(parse_diags),
          last_good=last_good_document(last_good.val),
        )
      } else {
        let syntax = parser.syntax_tree().get_or_abort()
        match project_semantic_document(
          syntax,
          previous=last_good.val,
          pending_change=pending_change.val,
        ) {
          Ok((document, reuse, identity_baseline)) => {
            last_good.val = Some({ source, document, reuse, identity_baseline })
            pending_change.val = PendingSemanticChange::NoChange
            SemanticState::Current(document~)
          }
          Err(projection_diagnostics) =>
            SemanticState::ProjectionBlocked(
              projection_diagnostics~,
              last_good=last_good_document(last_good.val),
            )
        }
      }
    },
    label="semantic_document_state",
  )
  let state_watch = scope.add_watch(state.watch())
  // Prime the terminal watch once so dependency edges to parser views are
  // recorded before an eager Runtime::gc() can sweep unobserved interior cells.
  let _ = state_watch.read_or_abort()
  { parser, scope, last_good, pending_change, state_watch }
}
```

The helper that applies edits should be part of the same facade, or editor code
must mirror every parser edit into the attachment before the next read. Do not
let current-text updates bypass the pending-baseline state.

```mbt nocheck
pub fn SemanticAttachment::apply_edit(
  self : SemanticAttachment[Ast, Doc, Reuse, Id],
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  self.pending_change.val = extend_pending_change(
    self.last_good.val,
    self.pending_change.val,
    edit,
    new_source,
  )
  self.parser.apply_edit(edit, new_source)
}

pub fn SemanticAttachment::set_source(
  self : SemanticAttachment[Ast, Doc, Reuse, Id],
  new_source : String,
) -> Unit {
  self.pending_change.val = PendingSemanticChange::FullReplace
  self.parser.set_source(new_source)
}

pub fn SemanticAttachment::state(
  self : SemanticAttachment[Ast, Doc, Reuse, Id],
) -> SemanticState[Doc] {
  self.state_watch.read_or_abort()
}

pub fn SemanticAttachment::dispose(
  self : SemanticAttachment[Ast, Doc, Reuse, Id],
) -> Unit {
  self.scope.dispose()
}
```

Use `parser.syntax_tree()` rather than `parser.ast()` when the semantic layer
needs to gate on diagnostics. `parser.ast()` is a current parse view and may be
computed from a recovered tree; the last-good policy belongs in the downstream
semantic attachment.

## Compatibility `Result[..., String]` adapter

A project that has not chosen a public diagnostic type can adapt the richer state
at its authoring facade boundary:

```mbt nocheck
pub fn SemanticAttachment::current_result(
  self : SemanticAttachment[Ast, Doc, Reuse, Id],
) -> Result[Doc, String] {
  match self.state() {
    Current(document~) => Ok(document)
    ParserBlocked(parser_diagnostics~, ..) =>
      Err(format_authoring_diagnostics(parser_diagnostics))
    ProjectionBlocked(projection_diagnostics~, ..) =>
      Err(format_projection_diagnostics(projection_diagnostics))
  }
}
```

This adapter reports whether the current source has a trusted semantic document.
It should not silently return the stale last-good document as `Ok`, because that
makes malformed current text look semantically valid. If an editor also needs the
stale document for rendering or reuse, expose it under an explicit `last_good` or
`stale_document` name.

## Regression matrix

Downstream integrations should cover at least these transitions:

- initial valid input has zero parser diagnostics and produces a current
  semantic document;
- malformed input has current parser diagnostics, the compatibility result is
  `Err`, and the last-good semantic document is retained;
- parser-valid but projection-invalid input has zero parser diagnostics,
  projection diagnostics, an `Err` compatibility result, and retained last-good
  semantic state;
- recovered valid input has zero parser diagnostics and replaces last-good with a
  new current semantic document; and
- when exact reuse is supported, recovered document IDs match the production
  authoring pipeline by reusing the last-good baseline plus the pending semantic
  change.
