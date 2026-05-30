# seam

Language-agnostic concrete syntax tree (CST) infrastructure for incremental parsers in MoonBit.
Modelled after [rowan](https://github.com/rust-analyzer/rowan).

## Installation

Add to your `moon.mod.json`:

```json
"deps": {
  "dowdiness/seam": "0.1.0"
}
```

Or as a path dependency during local development:

```json
"deps": {
  "dowdiness/seam": { "path": "../seam" }
}
```

Then import in `moon.pkg`:

```
import { "dowdiness/seam" @seam }
```

## Quick start

A parser emits `ParseEvent`s into an `EventBuffer`, then calls `build_tree` once to
produce an immutable `CstNode` tree:

```mbt nocheck
// 1. Define your language's kinds as a newtype over Int
let EXPR  = @seam.RawKind(0)
let PLUS  = @seam.RawKind(1)
let NUM   = @seam.RawKind(2)

// 2. Emit events while parsing "1+2"
let buf = @seam.EventBuffer::new()
buf.push(@seam.ParseEvent::StartNode(EXPR))
buf.push(@seam.ParseEvent::Token(NUM, "1"))
buf.push(@seam.ParseEvent::Token(PLUS, "+"))
buf.push(@seam.ParseEvent::Token(NUM, "2"))
buf.push(@seam.ParseEvent::FinishNode)

// 3. Build the immutable CST (raises EventStreamError on malformed events)
let root : @seam.CstNode = buf.build_tree!(EXPR)

// root.text_len  == 3
// token text is available as zero-copy StringView via CstToken::text()
```

`CstToken::text()` is the application-facing content API. The backing source
buffer is an unstable storage detail; `unsafe_backing_source()` exists only for
parser/source-retention white-box checks.

### Retroactive node wrapping with `mark`/`start_at`

Use `mark` when you don't know the node kind yet at the start of parsing:

```mbt nocheck
let buf = @seam.EventBuffer::new()
let m = buf.mark()                          // reserve a Tombstone slot
buf.push(@seam.ParseEvent::Token(NUM, "1"))
buf.push(@seam.ParseEvent::Token(PLUS, "+"))
buf.push(@seam.ParseEvent::Token(NUM, "2"))
buf.start_at(m, EXPR)                       // retroactively wrap as EXPR
buf.push(@seam.ParseEvent::FinishNode)
let root = buf.build_tree!(FILE)
```

## Traversal with SyntaxNode

`SyntaxNode` is an ephemeral, positioned view over a `CstNode`. It adds an absolute UTF-16 code-unit
offset to every node without modifying the underlying `CstNode`:

```mbt nocheck
let syntax_root = @seam.SyntaxNode::from_cst(root)

// syntax_root.start()  == 0
// syntax_root.end()    == root.text_len
// syntax_root.kind()   == root.kind
```

### Walking the tree

```mbt nocheck
fn print_tree(node : @seam.SyntaxNode, depth : Int) -> Unit {
  let pad = String::make(depth * 2, ' ')
  println("\{pad}\{node.kind()} [\{node.start()}:\{node.end()}]")
  for child in node.children() {
    print_tree(child, depth + 1)
  }
}

// Usage:
print_tree(@seam.SyntaxNode::from_cst(root), 0)
// EXPR [0:3]
//   (tokens are skipped — only interior CstNode children appear)
```

### Direct shape checks for projections

Projection code often needs to validate the immediate CST shape before lowering
into a semantic model. Prefer the explicit direct-child helpers for that work:

- `direct_token_of_kind(kind)` / `direct_tokens_of_kind(kind)` inspect direct
  token children only.
- `direct_child_of_kind(kind)` / `direct_children_of_kind(kind)` inspect direct
  node children only.
- `nodes_and_tokens()` keeps the direct node/token sequence available when
  order matters, such as binary operator + operand pairs.
- `required_direct_*`, `optional_direct_*`, `required_direct_*s`, and
  `expect_no_direct_*s` helpers validate zero/optional/one/many cardinality and
  return `ProjectionShapeError` with the projection-supplied message plus source
  range and actual count.
- `children()`, `all_children()`, `tokens()`, `find_token()`, and
  `tokens_of_kind()` also operate on direct visible children. `RepeatGroup`
  nodes are transparent, but ordinary nested nodes are not searched.

This distinction matters for callback or nested argument syntax: validating
`.fast(2)` should look for a direct `NumberToken` on the method-call node;
`.fast(slow(2))` must not be accepted just because a descendant callback node
contains a `NumberToken`. Recursive walks are safe for display, indexing, or
intentionally whole-subtree analyses; they are unsafe for validating a direct
semantic slot unless the projection names that recursion explicitly.

A typical projection pipeline is:

1. create a parser with `@loom.new_parser(source, grammar)`,
2. share `parser.runtime()` for downstream reactive cells,
3. stop semantic projection when parser diagnostics are present,
4. validate direct CST shape into a private projection IR, and
5. lower that IR into the target semantic model.

The private IR can stay package-private; it is a boundary for recovery policy,
missing-slot errors, and semantic lowering, not a new public API requirement.
See the full [CST projection guide](../docs/api/projection-guide.md) for the
CST → private IR → semantic model workflow and review checklist.

## Two-tree model

| Concept | `seam` type | Rowan equivalent |
|---|---|---|
| Immutable content node; offsets are external | `CstNode` | `GreenNode` |
| Ephemeral positioned view | `SyntaxNode` | `SyntaxNode` |
| Language-agnostic kind | `RawKind` | `SyntaxKind` |
| Event-driven builder | `EventBuffer` + `ParseEvent` | `GreenNodeBuilder` |

**Why two trees?** `CstNode`s can be structurally shared and content-addressed.
Tokens store source spans; parser-owned reuse uses the explicitly unstable
`EventBuffer::push_parser_reuse_node_rebased*` hooks to rebase validated reused
token spans onto the current source buffer, while public `ReuseNode` and
interner APIs canonicalize or copy token text to avoid retaining old full source
buffers. Rebasing rebuilds current-source tokens/nodes rather than
direct-splicing old subtrees, so stable physical identity across parses is not
part of the generic parser contract. `SyntaxNode`s are cheap to create on demand and carry position
information without polluting the shared layer.

## Token interning

Use `build_tree_interned` when you explicitly want to deduplicate identical tokens
with canonical owned token text:

```mbt nocheck
let interner = @seam.Interner::new()
let root1 = buf1.build_tree_interned!(FILE, interner)
let root2 = buf2.build_tree_interned!(FILE, interner)
// Tokens with the same (kind, text) in root1 and root2 share the same CstToken.
```

## Non-goals

- **Language semantics** — `seam` knows nothing about your grammar or AST
- **Mutable trees** — there are no in-place edit operations; rebuild with new events

## API reference

See [`pkg.generated.mbti`](pkg.generated.mbti) for the full interface and
[`docs/design.md`](docs/design.md) for the three-layer API design principles
(total functions, checked functions, error information).
