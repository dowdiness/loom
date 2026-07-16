# Markdown Projection Identity Design

**Date:** 2026-07-15  
**Issue:** [#341](https://github.com/dowdiness/loom/issues/341)  
**Status:** Approved — 2026-07-15

## Goal

Define editor-facing identity for the future `SyntaxNode -> MarkdownIR ->
Block/Inline -> ProjNode` pipeline without making MarkdownIR, `ProjNode`, or
source offsets into interchangeable identity systems.

The policy must preserve an editor authoring unit through surface-only Markdown
syntax edits, reset or reclassify identity for selected semantic changes, retain
last-good identity across malformed intermediate source, and make it explicit
that `ProjNode` IDs are view-local.

## Scope

### Included

- MarkdownIR-to-editor identity leaves and their anchor/key contract.
- The distinction among Markdown domain IDs, current view IDs, and
  `TreeNode::same_kind`.
- Field-level decisions for headings, lists, code blocks, links, inline content,
  and malformed/raw projections.
- Behavior-level tests that establish the policy before MarkdownIR is wired into
  projection memos.

### Excluded

- Replacing the editor-facing `Block` / `Inline` model.
- Changing `ProjNode`, `SourceMap`, generic `ProjectionIdentityTracker`, or
  parser-core APIs.
- Introducing a generic semantic-ID abstraction for all languages.
- Thematic-break editor projection, which remains #425 after #332.
- New Markdown syntax or formatter/rewrite behavior.

## Existing Responsibilities

MarkdownIR owns semantic fields, source origins, selected transform-relevant
surface metadata, and explicit raw/recovered nodes. It does not own editor ID
allocation or alignment.

`Block` / `Inline` remain the compact editor model. Their `TreeNode::same_kind`
implementation classifies whether a current view node has the same replacement
kind; it is not a durable semantic identity relation.

Loom's generic `ProjectionIdentityTracker` owns edit-window realignment of
caller-supplied leaves. It preserves matching leaves outside the changed source
window and mints fresh IDs inside it. It retains a last-good baseline across
failed input.

`ProjNode` and `SourceMap` are projection-view concerns. Their IDs and paths
are not durable Markdown semantic IDs.

## Decision

### Domain-owned Markdown IDs

The Markdown adapter owns an opaque, domain-scoped `MarkdownNodeId`. A
Markdown-local identity-alignment layer proves old/new authoring-unit
correspondence; it uses Loom's generic tracker for unambiguous edit-window
realignment and fresh-ID allocation.

A logical Markdown baseline contains only:

```text
MarkdownIdentityLeaf {
  anchor: MarkdownIROrigin
  key: MarkdownSemanticKey
  id: MarkdownNodeId
}
```

`anchor` is a narrow semantic source range. `key` is a typed semantic
classification. `id` is the stable authoring identity.

The generic tracker boundary stays unchanged. The Markdown adapter encodes each
typed key into `ProjectionLeaf.key` with an injective, component-length-prefixed
format that includes the variant tag and every key field. The tracker persists
that encoded string; the adapter decodes it only for diagnostics. Delimited
source text, `kind_tag()`, paths, and source offsets are never used as the
encoding.

A successful projection builds an ephemeral mapping from `MarkdownNodeId` to
its current `Block` / `Inline` and `ProjNode` path. That attachment mapping is
rebuilt every successful projection. It is not stored in the tracker baseline,
not compared during realignment, and not used as a durable identity component:
a sibling insertion or structural projection change may change every path while
leaving the underlying Markdown authoring identity intact.

### Anchor rule

A surface-only delimiter must never be included in the identity anchor. The
tracker mints fresh IDs for leaves inside its edit window, so whole-node origins
would incorrectly churn IDs when an author changes a marker but not its
semantic payload.

| Authoring unit | Identity anchor | Excluded from anchor |
|---|---|---|
| Heading | heading content origin | ATX hashes, closing hashes, setext underline/form |
| Paragraph | paragraph content origin and its inline leaves | indentation and soft-break spelling |
| Unordered list item | item content origin | marker spelling and marker padding |
| Code block | code content origin | fence character, width, and indentation |
| Inline code/text | value/content origin | backticks or other delimiters |
| Link label | label content origin | brackets and inline/reference spelling |
| Link destination | destination origin | parentheses/reference syntax |
| Container-only node | no independent identity leaf | container punctuation and trivia |

When a node lacks a contiguous semantic content origin, it must not pretend that
its full origin is a content anchor. The future adapter either derives a
separate safe anchor from a contiguous child or treats that node as having no
independent durable identity leaf.

`MarkdownIR::Link` must gain a distinct optional `label_origin` alongside its
existing `destination_origin`. Lowering derives it from the contiguous source
range between the link brackets; it is `None` when structural continuation makes
that payload discontinuous. The adapter emits a link-label identity leaf only
when this origin is present. It must not derive a label range from child
origins, which can overlap formatting delimiters or omit discontinuous content.

`label_origin` is source attachment only. Link-label correspondence compares a
normalized fingerprint of the label's lowered inline children, not the raw
bytes sliced by `label_origin`: formatting-only rewrites such as
`[plain](url)` to `[*plain*](url)` retain the link-label ID when the child
semantics are unchanged. A changed normalized child sequence receives a fresh
label ID.

The normalized fingerprint erases only `Bold` and `Italic` wrapper nodes.
It retains child order and the semantic payload and kind of every remaining
node: text value, inline-code value, hard-break presence, and nested-link
destination. Thus `[plain](url)` and `[*plain*](url)` compare equal, while
`[changed](url)`, ``[`plain`](url)``, or a label containing a changed nested
link target do not.

### Extraction order

Identity anchors may overlap: a paragraph anchor can contain inline anchors,
and a link-label anchor can contain text-child anchors. The adapter emits one
deterministic tracker sequence by traversing MarkdownIR in preorder:

1. emit the current node's editor-facing identity leaf, if it has one;
2. visit children in MarkdownIR child-array order; and
3. for leaves with equal anchor starts on the same node, emit roles in this
   fixed order: block payload, inline container, scalar payload.

The role is represented by the typed semantic key's variant tag, not by a
projection path. Old and new projections must use this exact traversal and
tie-break order before local matching or generic tracker preview. Neither a
source-range sort nor a `ProjNode` walk is permitted because equal or nested
ranges would otherwise change indices without a semantic change.

### Alignment rule

Content-only anchors prevent a marker-only exact edit from damaging a leaf, but
they do not solve a logical style conversion expressed as a multi-range edit or
as `set_source`: a text diff may cover unchanged heading content between the
removed ATX prefix and inserted setext underline. Therefore #341 requires a
Markdown-local alignment layer between MarkdownIR and the generic tracker.

For every successful projection, the layer creates a one-to-one set of local
matches in source order only when all of the following are true:

1. their typed identity classes match;
2. their containing already-matched semantic context, when any, matches;
3. their semantic anchors carry the same unchanged semantic payload; and
4. their correspondence is unique in that ordered context.

The layer first previews the complete new leaf array through
`ProjectionIdentityTracker::realign_success_with_optional_edit`. This is the
only generic realignment call: it preserves the tracker's private pending-edit
composition after malformed input. Its domain allocator is seeded with every
ID in the current full baseline, so generic fresh allocation cannot collide
with an existing ID.

The local layer then considers each one-to-one match as an override of that
full preview. It applies an override only when the matched old ID is absent
from every other preview index. This preserves the generic result whenever it
already claimed that old ID for a different leaf, preventing a local match from
stealing or duplicating an ID. Ambiguous candidates receive the preview ID,
which is fresh whenever the generic pass could not preserve one.

The adapter verifies that the combined full preview has one leaf per new index
and one unique `MarkdownNodeId` per leaf. If an override violates either
invariant, it discards all local overrides, retains the generic full preview,
and commits that known whole-baseline result. It then calls
`ProjectionIdentityTracker::commit_success` exactly once with the selected
full result; it never filters a baseline or bypasses pending recovery state.

This surface-normalized match may preserve an ID even when the source diff
window covers the anchor. The one-to-one merge is a language-specific adapter
rule, not a generic Loom projection algorithm. It exists because Markdown
surface forms may rewrite disjoint source ranges around unchanged semantic
content.


### Semantic-key rule

Keys are typed semantic tuples. They are not `kind_tag()` strings, serialized
source text, paths, source offsets, or `same_kind` results.

| Unit | Semantic key | Identity result |
|---|---|---|
| Heading | `(Heading, depth)` | Changing depth resets/reclassifies the heading; ATX/setext form does not. |
| Paragraph | `(Paragraph)` | Surface whitespace preserves identity. |
| Unordered item | `(UnorderedListItem, spread)` | Marker spelling preserves identity; spread change resets/reclassifies. |
| Ordered item | `(OrderedListItem, list semantics)` | Marker spelling alone preserves identity; a semantic list-kind change resets/reclassifies. |
| Code block | `(CodeBlock, language)` | Fence style preserves identity; changing language resets/reclassifies the whole code-block authoring unit. |
| Text | `(Text)` | Delimiter/spelling changes outside content preserve identity. |
| Inline code | `(InlineCode)` | Backtick run spelling preserves identity. |
| Link label | `(LinkLabel)` | Link syntax spelling preserves identity. |
| Link destination | `(LinkDestination, normalized destination)` | Target change resets the destination leaf only. |

Identity classes capture the semantic fields whose change replaces or
reclassifies an authoring unit. The local alignment rule additionally requires
identical semantic anchor payload. Therefore a heading-title edit receives a
fresh ID even when `(Heading, depth)` is unchanged; #341 guarantees continuity
only for unchanged payload under surface-only rewrites. Changing a code language
resets the enclosing code-block unit. Payload-edit continuity is explicitly
out of scope for #341 and must not be inferred by an implementation.

### Malformed, raw, and recovered input

`Raw`, `Recovered`, and `Unsupported` projections receive no durable
`MarkdownNodeId`. A malformed intermediate result may render an error
placeholder, but cannot steal a prior semantic ID or establish a baseline.

On parser or semantic-lowering failure, the adapter records the failed source
with `ProjectionIdentityTracker::record_failed_input` and retains its last
successful baseline. On the next successful projection, it realigns only the
new valid semantic leaves against that retained baseline, then commits the new
baseline.

### View-local IDs and source maps

`ProjNode` IDs are view-local allocations. A re-projection may assign different
`ProjNode` IDs while an unchanged `MarkdownNodeId` remains stable. Source maps
associate the current projection with the current source snapshot; they do not
become durable semantic identities and must be rebuilt after a successful
projection.

`TreeNode::same_kind` remains a local view replacement classifier. It may be
stricter or coarser than a Markdown semantic key and must not decide tracker
continuity.

## Data Flow

```text
SyntaxNode + diagnostics
  -> MarkdownIR
  -> Markdown identity leaves { anchor, key }
  -> Markdown-local identity alignment
  -> ProjectionIdentityTracker<MarkdownNodeId> for unmatched leaves
  -> stable leaves { anchor, key, id }
  -> Block / Inline plus ephemeral id-to-view attachment
  -> ProjNode<Block> and SourceMap for the current snapshot
```

The policy is implemented at the MarkdownIR-to-editor adapter boundary. It does
not add identity fields to MarkdownIR or move Markdown surface syntax knowledge
into generic Loom projection code.

## Required Behavior Tests

The future implementation must add behavior-level tests that observe durable
`MarkdownNodeId` continuity separately from current `ProjNode` allocation.

1. **ATX/setext conversion:** a single logical source replacement changing
   `# Title` to `Title\n=====` preserves the heading's content-attached
   `MarkdownNodeId` even when the text-diff window includes `Title` and the
   current view path changes.
2. **Unordered-marker spelling:** changing `- item` to `* item` preserves the
   list item's content-attached ID.
3. **Fence style:** changing backtick to tilde fences preserves the code-block ID.
4. **Heading semantic change:** changing heading depth resets or reclassifies
   the heading according to `(Heading, depth)`.
4a. **Heading payload edit:** changing `Title` to `Renamed` receives a fresh
    heading ID even though the depth remains unchanged.
5. **Code-language semantic change:** changing the code info language resets or
   reclassifies the whole code-block ID. #341 introduces no separate code-info
   leaf because current MarkdownIR has no info-string origin.
6. **Link target:** changing only a link destination resets the destination leaf
   while preserving the label leaf.
7. **Malformed round trip:** valid source, malformed intermediate source, then
   valid source preserves eligible last-good IDs and never assigns a durable ID
   to an error placeholder.
8. **View-local proof:** force/rebuild the projection view and show that a
   stable `MarkdownNodeId` can remain equal while `ProjNode` IDs or paths differ.
9. **Duplicate-content reorder:** reorder two identical semantic siblings and
   prove the matcher never assigns one old ID twice or steals an ID from a
   generically preserved sibling; ambiguous duplicate candidates receive fresh
   IDs while unrelated unique siblings retain theirs.
10. **Nested equal-range order:** a paragraph containing a link label whose
    text child shares its anchor start preserves each distinct ID across an
    unchanged projection; the test asserts preorder role ordering and proves no
    ID transfers when equal-range leaves are re-extracted.

Tests must use real Markdown parsing and exact `Edit` spans where available.
They must exercise both the Markdown-local alignment layer and the generic
tracker rather than mocked replacement behavior.

## Consequences

- #332 may wire MarkdownIR into editor projection only after these tests prove
  the adapter contract.
- The Markdown adapter gains a bounded, language-specific identity-leaf
  extractor and ephemeral attachment map.
- No `Block` / `Inline` public API change is needed for this policy alone.
- Container nodes without a safe contiguous semantic anchor deliberately do not
  gain invented durable IDs.
- #425 retains ownership of thematic-break projection once the #341 -> #332
  boundary is established.

## Rejected Alternatives

- **Use `ProjNode` IDs as persistent editor IDs:** rejected because view
  allocation and tree shape are implementation details.
- **Use full MarkdownIR origins as anchors:** rejected because surface marker
  edits lie inside those ranges and force tracker churn.
- **Use `TreeNode::same_kind` as durable identity:** rejected because it is a
  current view replacement classifier, not a source-aligned semantic identity
  contract.
- **Add editor identity to MarkdownIR:** rejected because allocation,
  realignment, and view lifetime are editor-adapter concerns, not semantic IR
  facts.
