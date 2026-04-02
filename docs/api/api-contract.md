# `seam` API Contract

**Module:** `dowdiness/seam`
**Version target:** `0.1.0`
**Generated from:** `seam/pkg.generated.mbti`

Every public symbol is listed below with its stability level and key invariants.
Symbols not listed here are package-private and subject to change without notice.

---

## Stability levels

- **Stable** — frozen for the 0.x series; breaking changes require a major version bump
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
pub(all) struct CstToken { kind : RawKind; text : String; hash : Int }
```

**Stable.** Immutable leaf token. All three fields are public for read access.

**Invariant:** `hash` equals `combine_hash(kind.inner, string_hash(text))` and is frozen at construction. Never mutate fields directly; doing so invalidates `Eq` and `Hash` semantics.

| Symbol | Stability | Notes |
|---|---|---|
| `CstToken::new(RawKind, StringView) -> Self` | Stable | Computes and caches `hash`; calls `.to_string()` internally for owned `text` field |
| `CstToken::text_len(Self) -> Int` | Stable | Returns `text.length()` |
| `Eq` | Stable | Hash fast-path rejection, then `kind` + `text` deep check |
| `Hash` | Stable | Feeds cached `hash` field into hasher |
| `Show` | Stable | Debug representation; format not guaranteed stable |

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

**Invariant:** A valid event stream is balanced — every `StartNode` has a matching `FinishNode`. `Tombstone` slots are silently skipped. `String` auto-coerces to `StringView` for `Token` construction.

| Symbol | Stability | Notes |
|---|---|---|
| All five variants | Stable | |
| `Eq`, `Show` | Stable | |

---

## `EventBuffer`

```moonbit
pub struct EventBuffer { /* private fields */ }
```

**Stable.** Accumulates parse events; exposes `mark`/`start_at` for retroactive node wrapping. The backing array is private.

| Symbol | Stability | Notes |
|---|---|---|
| `EventBuffer::new() -> Self` | Stable | |
| `EventBuffer::push(Self, ParseEvent) -> Unit` | Stable | Append any event directly |
| `EventBuffer::mark(Self) -> Int` | Stable | Reserve a `Tombstone` slot; returns its index |
| `EventBuffer::start_at(Self, Int, RawKind) -> Unit` | Stable | Fill a `Tombstone` with `StartNode`; aborts if out-of-bounds or non-Tombstone |
| `EventBuffer::build_tree(Self, RawKind, trivia_kind? : RawKind?) -> CstNode` | Stable | Builds CST from accumulated events; equivalent to calling `build_tree(events, ...)` |
| `EventBuffer::build_tree_interned(Self, RawKind, Interner, trivia_kind? : RawKind?) -> CstNode` | Stable | Interns tokens; deduplicates `CstToken` by `(kind, text)` |
| `EventBuffer::build_tree_fully_interned(Self, RawKind, Interner, NodeInterner, trivia_kind? : RawKind?) -> CstNode` | **Deferred** | Interns both tokens and nodes; requires `NodeInterner` (planned) |

---

## `Interner`

```moonbit
pub struct Interner { /* private fields */ }
```

**Stable.** Session-scoped token intern table. Deduplicates `CstToken` by `(kind, text)`.

| Symbol | Stability | Notes |
|---|---|---|
| `Interner::new() -> Self` | Stable | |
| `Interner::intern_token(Self, RawKind, StringView) -> CstToken` | Stable | Returns cached token on repeat calls; zero-alloc on hit path |
| `Interner::size(Self) -> Int` | Stable | Count of distinct `(kind, text)` pairs |
| `Interner::clear(Self) -> Unit` | Stable | Reset; safe to reuse after clear |

---

## `SyntaxToken`

```moonbit
pub struct SyntaxToken { /* private fields */ }
```

**Stable.** Ephemeral positioned view over a `CstToken`. Mirrors `SyntaxNode` for leaf tokens.

**Invariant:** `start()` is the absolute byte offset of the token's first byte. `end() == start() + cst.text_len()`.

| Symbol | Stability | Notes |
|---|---|---|
| `SyntaxToken::new(CstToken, Int) -> Self` | Stable | Full constructor; `offset` is the absolute start byte |
| `SyntaxToken::start(Self) -> Int` | Stable | Absolute byte start |
| `SyntaxToken::end(Self) -> Int` | Stable | Absolute byte end |
| `SyntaxToken::kind(Self) -> RawKind` | Stable | Token kind |
| `SyntaxToken::text(Self) -> String` | Stable | Token text |
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

**Invariant:** `offset` is the absolute byte offset of this node's start in the source. `offset + cst.text_len` is the end (accessible via `end()`).

| Symbol | Stability | Notes |
|---|---|---|
| `SyntaxNode::from_cst(CstNode) -> Self` | Stable | Creates a root node (offset = 0, no parent) |
| `SyntaxNode::new(CstNode, Self?, Int) -> Self` | Stable | Full constructor; `parent` may be `None` for roots |
| `SyntaxNode::start(Self) -> Int` | Stable | Returns `offset` |
| `SyntaxNode::end(Self) -> Int` | Stable | Returns `offset + cst.text_len` |
| `SyntaxNode::kind(Self) -> RawKind` | Stable | |
| `SyntaxNode::children(Self) -> Array[Self]` | Stable | Child `SyntaxNode`s with computed offsets; skips leaf tokens |
| `SyntaxNode::all_children(Self) -> Array[SyntaxElement]` | Stable | All children including leaf tokens, in source order |
| `SyntaxNode::tokens(Self) -> Array[SyntaxToken]` | Stable | All leaf tokens in subtree, in source order |
| `SyntaxNode::find_token(Self, RawKind) -> SyntaxToken?` | Stable | First token of the given kind in this node |
| `SyntaxNode::tokens_of_kind(Self, RawKind) -> Array[SyntaxToken]` | Stable | All tokens of the given kind in this node |
| `SyntaxNode::tight_span(Self, trivia_kind? : RawKind?) -> (Int, Int)` | Stable | Start/end skipping leading/trailing trivia tokens |
| `SyntaxNode::find_at(Self, Int) -> Self` | Stable | Deepest descendant whose span contains the byte offset; falls back to `self` |
| `SyntaxNode::cst_node(Self) -> CstNode` | Stable | **Advanced use only.** Returns the underlying `CstNode` for infrastructure that requires it (e.g. reuse cursors). Prefer SyntaxNode API for all navigation. |
| `Show` | Stable | `"NodeKind@[start,end)"` format |
| `Debug` | Stable | |
| `SyntaxNode::node_at(Int) -> Self?` | **Deferred** | Find deepest node at a byte position; edge-case semantics (boundary, trivia) unresolved |

---

## Standalone functions

| Symbol | Stability | Notes |
|---|---|---|
| `build_tree(Array[ParseEvent], RawKind, trivia_kind? : RawKind?) -> CstNode` | Stable | Use `EventBuffer::build_tree` when building through `EventBuffer` |
| `build_tree_interned(Array[ParseEvent], RawKind, Interner, trivia_kind? : RawKind?) -> CstNode` | Stable | Interned variant |
| `combine_hash(Int, Int) -> Int` | Stable | FNV-based mixing function used for structural hashes |
| `string_hash(String) -> Int` | Stable | FNV hash of a string; used by `CstToken::new` |

---

## Deferred API summary

Decisions recorded here; may be revisited for `0.2.0`:

| Symbol | Reason deferred |
|---|---|
| `CstNode::width()` | Redundant alias for the already-public `text_len` field |
| `SyntaxNode::node_at(Int) -> Self?` | No current callers; position-on-boundary and trivia semantics need design before freeze |
| `EventBuffer::build_tree_fully_interned` | Requires `NodeInterner` (planned, not yet implemented) |
| `NodeInterner` | Planned — deduplicates `CstNode` by structural identity, parallel to `Interner` for tokens |
