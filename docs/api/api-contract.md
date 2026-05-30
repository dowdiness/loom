# `seam` API Contract

**Module:** `dowdiness/seam`
**Version target:** `0.1.0`
**Generated from:** `seam/pkg.generated.mbti`

Every public symbol is listed below with its stability level and key invariants.
Symbols not listed here are package-private and subject to change without notice.

---

## Stability levels

- **Stable** — frozen for the 0.x series; breaking changes require a major version bump
- **Unstable** — public only for current implementation boundaries; may change before stabilization
- **Deprecated** — present for compatibility; will be removed in a future version
- **Deferred** — not included in 0.1.0; may be added in a later release

---

## `RawKind`

```moonbit
pub(all) struct RawKind(Int)
```

**Stable.** Language-agnostic node/token kind. Newtype over `Int`; each language defines its own kind enum and converts via its own `to_raw()`/`from_raw()`.

| Symbol | Stability | Notes |
|---|---|---|
| `RawKind(Int)` constructor | Stable | Direct construction; value is opaque to `seam` |
| `Eq`, `Hash`, `Compare`, `Show` | Stable | Delegated to the inner `Int` |
| `RawKind::inner(Self) -> Int` | **Deprecated** | Access the inner `Int` via pattern `let RawKind(n) = kind` |

---

## `CstToken`

```moonbit
pub struct CstToken {
  kind : RawKind
  // private source-span and hash fields
}
```

**Stable content API, unstable backing-storage API.** Immutable leaf token. Token text is represented as a source span; use `text()` for the zero-copy content view. The backing source buffer is intentionally not part of the stable application contract.

**Invariant:** the private cached hash equals `combine_hash(kind.inner, string_hash(text()))` and is frozen at construction. Public callers cannot mutate the backing source span or hash fields.

| Symbol | Stability | Notes |
|---|---|---|
| `CstToken.kind : RawKind` | Stable | Read-only token kind |
| `CstToken::CstToken(RawKind, StringView) -> Self` | Stable | Computes and caches the private hash; records the input view's backing source and offsets without copying |
| `CstToken::new(RawKind, StringView) -> Self` | **Deprecated** | Alias for `CstToken::CstToken`; retained for compatibility |
| `CstToken::text(Self) -> StringView` | Stable | Zero-copy token-content view |
| `CstToken::unsafe_backing_source(Self) -> String` | **Unstable** | Exposes backing storage identity for parser/source-retention white-box checks only; not application API |
| `CstToken::source(Self) -> String` | **Deprecated** | Compatibility alias for `unsafe_backing_source`; use `text()` for content |
| `CstToken::start_offset(Self) -> Int` | Stable | Start UTF-16 code-unit offset within the backing source |
| `CstToken::end_offset(Self) -> Int` | Stable | Exclusive UTF-16 code-unit end offset within the backing source |
| `CstToken::text_len(Self) -> Int` | Stable | Returns `end_offset() - start_offset()` |
| `Eq` | Stable | Hash fast-path rejection, then `kind` + `text()` deep check |
| `Hash` | Stable | Feeds the private cached structural hash into hasher |
| `Debug` | Stable | Debug representation; format not guaranteed stable |

---

## `CstElement`

```moonbit
pub(all) enum CstElement { Token(CstToken); Node(CstNode) }
```

**Stable.** Union of a leaf token and an interior node.

| Symbol | Stability | Notes |
|---|---|---|
| `Token(CstToken)` / `Node(CstNode)` | Stable | |
| `CstElement::kind(Self) -> RawKind` | Stable | |
| `CstElement::text_len(Self) -> Int` | Stable | |
| `Eq`, `Hash`, `Show` | Stable | `Hash` adds a variant tag to reduce cross-variant collisions |

---

## `CstNode`

```moonbit
pub(all) struct CstNode {
  kind        : RawKind
  children    : Array[CstElement]
  text_len    : Int
  hash        : Int
  token_count : Int
}
```

**Stable.** Immutable interior node. All five fields are public for read access.

**Invariants:**
- `children` is **frozen after construction**. Mutating it externally invalidates `text_len`, `hash`, and `token_count`, which are all cached at construction time and never recomputed.
- `hash` is a structural content hash derived recursively from `kind` and each child's hash via `combine_hash`. Stable as long as `combine_hash` is stable.
- `text_len` equals the sum of `child.text_len()` for all children.
- `token_count` equals the number of non-trivia leaf tokens (see `CstNode::new` for `trivia_kind` semantics).

| Symbol | Stability | Notes |
|---|---|---|
| `CstNode::new(RawKind, Array[CstElement], trivia_kind? : RawKind?) -> Self` | Stable | `trivia_kind` controls what counts as trivia for `token_count` |
| `CstNode::kind(Self) -> RawKind` | Stable | Accessor for the `kind` field |
| `CstNode::has_errors(Self, RawKind, RawKind) -> Bool` | Stable | Language-agnostic; caller supplies error kind values |
| `Eq` | Stable | Hash fast-path rejection, then deep structural check |
| `Hash` | Stable | Feeds cached `hash` field into hasher |
| `Show` | Stable | Debug representation; format not guaranteed stable |
| `CstNode::width()` | **Deferred** | Alias for `text_len`; redundant while `text_len` is a public field |

---

## `ParseEvent`

```moonbit
pub(all) enum ParseEvent {
  StartNode(RawKind)
  FinishNode
  Token(RawKind, StringView)
  Tombstone
  ReuseNode(CstNode)
}
```

**Stable.** Event stream type consumed by `build_tree` / `build_tree_interned`.

**Invariant:** A valid event stream is balanced — every `StartNode` has a matching `FinishNode`. `Tombstone` slots are silently skipped. `String` auto-coerces to `StringView` for `Token` construction. Public `ReuseNode` rebuilds the subtree and copies token text into per-token backing strings to avoid retaining old full source buffers.

| Symbol | Stability | Notes |
|---|---|---|
| All five variants | Stable | `ReuseNode(CstNode)` skips parse-time re-emission but does not direct-splice source-backed tokens |
| `Eq`, `Debug` | Stable | |

---

## `EventBuffer`

```moonbit
pub struct EventBuffer { /* private fields */ }
```

**Stable.** Accumulates parse events; exposes `mark`/`start_at` for retroactive node wrapping. The backing array is private.

| Symbol | Stability | Notes |
|---|---|---|
| `EventBuffer::new() -> Self` | Stable | |
| `EventBuffer::push(Self, ParseEvent) -> Unit` | Stable | Append any public event directly; application reuse should use `ParseEvent::ReuseNode` |
| `EventBuffer::push_parser_reuse_node_rebased(Self, CstNode, String, Int) -> Unit` | **Unstable** | Trusted parser-owned source-span rebase path; rebases reused token spans onto the provided current source when text matches, otherwise falls back to owned token text |
| `EventBuffer::push_parser_reuse_node_rebased_unchecked(Self, CstNode, String, Int) -> Unit` | **Unstable** | Parser-validated source-span rebase path; skips redundant text validation, rebases before normal tree-builder handling, and never direct-splices the old subtree |
| `EventBuffer::push_reuse_node_at(Self, CstNode, String, Int) -> Unit` | **Deprecated** | Compatibility alias for `push_parser_reuse_node_rebased` |
| `EventBuffer::push_reuse_node_at_unchecked(Self, CstNode, String, Int) -> Unit` | **Deprecated** | Compatibility alias for `push_parser_reuse_node_rebased_unchecked` |
| `EventBuffer::mark(Self) -> Int` | Stable | Reserve a `Tombstone` slot; returns its index |
| `EventBuffer::start_at(Self, Int, RawKind) -> Unit` | Stable | Fill a `Tombstone` with `StartNode`; aborts if out-of-bounds or non-Tombstone |
| `EventBuffer::build_tree(Self, RawKind, trivia_kind? : RawKind?, error_kind? : RawKind?, incomplete_kind? : RawKind?) -> CstNode raise EventStreamError` | Stable | Builds CST from accumulated events; preserves token source spans for `Token` and parser-owned rebase hooks; raises on malformed event streams |
| `EventBuffer::build_tree_interned(Self, RawKind, Interner, trivia_kind? : RawKind?, error_kind? : RawKind?, incomplete_kind? : RawKind?) -> CstNode raise EventStreamError` | Stable | Interns tokens; deduplicates `CstToken` by `(kind, text)` using canonical owned token text |
| `EventBuffer::build_tree_fully_interned(Self, RawKind, Interner, NodeInterner, trivia_kind? : RawKind?, error_kind? : RawKind?, incomplete_kind? : RawKind?) -> CstNode raise EventStreamError` | Stable | Interns both tokens and nodes |

---

## `Interner`

```moonbit
pub struct Interner(HashMap[RawKind, HashMap[StringView, CstToken]])
```

**Stable.** Session-scoped token intern table. Deduplicates `CstToken` by `(kind, text)`.
Tuple struct — single-field wrapper is unboxed at runtime (no wrapper allocation on JS target).

| Symbol | Stability | Notes |
|---|---|---|
| `Interner::new() -> Self` | Stable | |
| `Interner::intern_token(Self, RawKind, StringView) -> CstToken` | Stable | Returns cached token on repeat calls; zero-alloc on hit path; miss path owns one canonical copy so source-backed views do not keep full source buffers alive |
| `Interner::size(Self) -> Int` | Stable | Count of distinct `(kind, text)` pairs |
| `Interner::clear(Self) -> Unit` | Stable | Reset; safe to reuse after clear |

---

## `NodeInterner`

```moonbit
pub struct NodeInterner(HashMap[CstNode, CstNode])
```

**Stable.** Session-scoped node intern table. Deduplicates `CstNode` by structural identity.
Tuple struct — single-field wrapper is unboxed at runtime.

**Critical invariant:** All `CstNode::new` calls feeding this interner MUST use the same `trivia_kind`. See doc comment in `seam/node_interner.mbt`.

| Symbol | Stability | Notes |
|---|---|---|
| `NodeInterner::new() -> Self` | Stable | |
| `NodeInterner::intern_node(Self, CstNode) -> CstNode` | Stable | Returns first-seen reference for equal structure; O(children) per call with `physical_equal` fast-path |
| `NodeInterner::size(Self) -> Int` | Stable | Count of distinct structures |
| `NodeInterner::clear(Self) -> Unit` | Stable | Reset; safe to reuse after clear |

---

## `SyntaxToken`

```moonbit
pub struct SyntaxToken { /* private fields */ }
```

**Stable.** Ephemeral positioned view over a `CstToken`. Mirrors `SyntaxNode` for leaf tokens.

**Invariant:** `start()` is the absolute UTF-16 code-unit offset of the token. `end() == start() + cst.text_len()`.

| Symbol | Stability | Notes |
|---|---|---|
| `SyntaxToken::new(CstToken, Int) -> Self` | Stable | Full constructor; `offset` is the absolute start code-unit offset |
| `SyntaxToken::start(Self) -> Int` | Stable | Absolute code-unit start |
| `SyntaxToken::end(Self) -> Int` | Stable | Absolute code-unit end |
| `SyntaxToken::kind(Self) -> RawKind` | Stable | Token kind |
| `SyntaxToken::text(Self) -> String` | Stable | Owned token text (compatibility/display helper) |
| `SyntaxToken::text_view(Self) -> StringView` | Stable | Zero-copy token text view |
| `Show` | Stable | `"TokenKind@[start,end)"` format |
| `Debug` | Stable | |

---

## `SyntaxElement`

```moonbit
pub(all) enum SyntaxElement { Node(SyntaxNode); Token(SyntaxToken) }
```

**Stable.** Positioned union of a child node or leaf token. Returned by `SyntaxNode::all_children`.

| Symbol | Stability | Notes |
|---|---|---|
| `Node(SyntaxNode)` / `Token(SyntaxToken)` | Stable | |
| `SyntaxElement::start(Self) -> Int` | Stable | |
| `SyntaxElement::end(Self) -> Int` | Stable | |
| `Show`, `Debug` | Stable | |

---

## `SyntaxNode`

```moonbit
pub struct SyntaxNode {
  // priv cst : CstNode
  parent : SyntaxNode?
  offset : Int
}
```

**Stable.** Ephemeral positioned view over a `CstNode`. `cst` is private; use `cst_node()` only when raw `CstNode` access is required (e.g. reuse cursors). `parent` and `offset` are public read-only fields.

**Invariant:** `offset` is the absolute UTF-16 code-unit offset of this node's start in the source. `offset + cst.text_len` is the end (accessible via `end()`).

| Symbol | Stability | Notes |
|---|---|---|
| `SyntaxNode::from_cst(CstNode) -> Self` | Stable | Creates a root node (offset = 0, no parent) |
| `SyntaxNode::new(CstNode, Self?, Int) -> Self` | Stable | Full constructor; `parent` may be `None` for roots |
| `SyntaxNode::start(Self) -> Int` | Stable | Returns `offset` |
| `SyntaxNode::end(Self) -> Int` | Stable | Returns `offset + cst.text_len` |
| `SyntaxNode::kind(Self) -> RawKind` | Stable | |
| `SyntaxNode::children(Self) -> Array[Self]` | Stable | Direct child `SyntaxNode`s with computed offsets; skips leaf tokens |
| `SyntaxNode::all_children(Self) -> Array[SyntaxElement]` | Stable | Direct children including leaf tokens, in source order |
| `SyntaxNode::tokens(Self) -> Array[SyntaxToken]` | Stable | Direct leaf tokens only; skips child nodes |
| `SyntaxNode::direct_children_of_kind(Self, RawKind) -> Array[Self]` | Stable | Direct child nodes matching the given kind |
| `SyntaxNode::direct_token_of_kind(Self, RawKind) -> SyntaxToken?` | Stable | First direct token of the given kind; explicit projection-validation helper |
| `SyntaxNode::direct_tokens_of_kind(Self, RawKind) -> Array[SyntaxToken]` | Stable | All direct tokens of the given kind; explicit projection-validation helper |
| `SyntaxNode::find_token(Self, RawKind) -> SyntaxToken?` | Stable | First direct token of the given kind in this node |
| `SyntaxNode::tokens_of_kind(Self, RawKind) -> Array[SyntaxToken]` | Stable | All direct tokens of the given kind in this node |
| `SyntaxNode::token_text(Self, RawKind) -> String` | Stable | Display-oriented shortcut for first direct token text, returning `""` when absent; prefer `direct_token_of_kind` for semantic validation |
| `SyntaxNode::tight_span(Self, trivia_kind? : RawKind?) -> (Int, Int)` | Stable | Start/end skipping leading/trailing trivia tokens |
| `SyntaxNode::find_at(Self, Int) -> Self` | Stable | Deepest descendant whose span contains the UTF-16 code-unit offset; falls back to `self` |
| `SyntaxNode::cst_node(Self) -> CstNode` | Stable | **Advanced use only.** Returns the underlying `CstNode` for infrastructure that requires it (e.g. reuse cursors). Prefer SyntaxNode API for all navigation. |
| `Show` | Stable | `"NodeKind@[start,end)"` format |
| `Debug` | Stable | |
| `SyntaxNode::node_at(Int) -> Self?` | **Deferred** | Find deepest node at a UTF-16 code-unit position; edge-case semantics (boundary, trivia) unresolved |

---

## Projection identity helpers

Stable authoring-projection helpers for preserving domain-owned leaf IDs across
editor edits and malformed-input recovery. They are language-neutral: downstream
code chooses the projected leaves, public ID type, and allocator.

| Symbol | Stability | Notes |
|---|---|---|
| `ProjectionLeaf::new(Int, Int, String) -> Self` | Stable | User-facing projected leaf range plus domain key, in source order |
| `StableProjectionLeaf::new(Int, Int, String, Id) -> Self[Id]` | Stable | Projected leaf paired with a domain-owned stable ID |
| `ProjectionIdentityBaseline::new(String, Array[StableProjectionLeaf[Id]]) -> Self[Id]` | Stable | Last successful semantic source plus stable leaves; copies the leaves array |
| `ProjectionIdentityBaseline::source(Self[Id]) -> String` | Stable | Last-good source baseline |
| `ProjectionIdentityBaseline::leaves(Self[Id]) -> Array[StableProjectionLeaf[Id]]` | Stable | Returns a copy of the stable leaves |
| `ProjectionIdentityBaseline::advance(Self[Id], String, Array[ProjectionLeaf], (ProjectionLeaf) -> Id, edit? : Edit) -> Self[Id]` | Stable | Realign leaves and return a new committed baseline |
| `ProjectionIdentityBaseline::advance_with_optional_edit(Self[Id], String, Array[ProjectionLeaf], (ProjectionLeaf) -> Id, Edit?) -> Self[Id]` | Stable | Value-shaped optional-edit counterpart |
| `ProjectionIdentityTracker::new() -> Self[Id]` | Stable | Empty tracker for integrations whose first valid projection may arrive later |
| `ProjectionIdentityTracker::from_baseline(ProjectionIdentityBaseline[Id]) -> Self[Id]` | Stable | Seed tracker from an existing last-good identity baseline |
| `ProjectionIdentityTracker::baseline(Self[Id]) -> ProjectionIdentityBaseline[Id]?` | Stable | Inspect current committed identity baseline |
| `ProjectionIdentityTracker::record_failed_input(Self[Id], String, source_before_edit? : String, edit? : Edit) -> Unit` | Stable | Retain a baseline-relative failed-input edit when valid, otherwise use source-diff fallback |
| `ProjectionIdentityTracker::record_failed_input_with_optional_edit(Self[Id], String, String?, Edit?) -> Unit` | Stable | Value-shaped optional-edit counterpart |
| `ProjectionIdentityTracker::realign_success(Self[Id], String, Array[ProjectionLeaf], (ProjectionLeaf) -> Id, edit? : Edit) -> Array[StableProjectionLeaf[Id]]` | Stable | Preview realignment only; does not mutate baseline or clear pending state |
| `ProjectionIdentityTracker::realign_success_with_optional_edit(Self[Id], String, Array[ProjectionLeaf], (ProjectionLeaf) -> Id, Edit?) -> Array[StableProjectionLeaf[Id]]` | Stable | Value-shaped optional-edit counterpart |
| `ProjectionIdentityTracker::commit_success(Self[Id], String, Array[StableProjectionLeaf[Id]]) -> Unit` | Stable | Only tracker operation that advances the committed baseline and clears pending state |
| `ProjectionStringIdAllocator::new((String, Int) -> String) -> Self` | Stable | Unseeded string-ID allocator with caller-supplied formatter |
| `ProjectionStringIdAllocator::from_baseline(ProjectionIdentityBaseline[String], (String, Int) -> String) -> Self` | Stable | Seeded allocator that skips IDs already present in the baseline |
| `ProjectionStringIdAllocator::allocate(Self, ProjectionLeaf) -> String` | Stable | Allocate a fresh string ID for the leaf key |
| `realign_projection_identities(ProjectionIdentityBaseline[Id], String, Array[ProjectionLeaf], (ProjectionLeaf) -> Id, edit? : Edit) -> Array[StableProjectionLeaf[Id]]` | Stable | Preserve matching prefix/suffix IDs around an edit window |
| `realign_projection_identities_with_optional_edit(ProjectionIdentityBaseline[Id], String, Array[ProjectionLeaf], (ProjectionLeaf) -> Id, Edit?) -> Array[StableProjectionLeaf[Id]]` | Stable | Value-shaped optional-edit counterpart |
| `realign_projection_items(...)` | Stable | Adapter that extracts leaves from domain items and zips stable IDs back onto caller-owned item shapes |
| `realign_projection_items_with_optional_edit(...)` | Stable | Value-shaped optional-edit counterpart |

---

## Standalone functions

| Symbol | Stability | Notes |
|---|---|---|
| `build_tree(Array[ParseEvent], RawKind, trivia_kind? : RawKind?, error_kind? : RawKind?, incomplete_kind? : RawKind?) -> CstNode raise EventStreamError` | Stable | Use `EventBuffer::build_tree` when building through `EventBuffer` |
| `build_tree_interned(Array[ParseEvent], RawKind, Interner, trivia_kind? : RawKind?, error_kind? : RawKind?, incomplete_kind? : RawKind?) -> CstNode raise EventStreamError` | Stable | Interned variant |
| `build_tree_fully_interned(Array[ParseEvent], RawKind, Interner, NodeInterner, trivia_kind? : RawKind?, error_kind? : RawKind?, incomplete_kind? : RawKind?) -> CstNode raise EventStreamError` | Stable | Fully interned variant |
| `combine_hash(Int, Int) -> Int` | Stable | FNV-based mixing function used for structural hashes |
| `string_hash(StringView) -> Int` | Stable | FNV hash of a string view; used by `CstToken::CstToken` |

---

## Deferred API summary

Decisions recorded here; may be revisited for `0.2.0`:

| Symbol | Reason deferred |
|---|---|
| `CstNode::width()` | Redundant alias for the already-public `text_len` field |
| `SyntaxNode::node_at(Int) -> Self?` | No current callers; position-on-boundary and trivia semantics need design before freeze |
