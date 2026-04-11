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

```moonbit
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
// root.children  == [Token(NUM,"1"), Token(PLUS,"+"), Token(NUM,"2")]
```

### Retroactive node wrapping with `mark`/`start_at`

Use `mark` when you don't know the node kind yet at the start of parsing:

```moonbit
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

`SyntaxNode` is an ephemeral, positioned view over a `CstNode`. It adds an absolute byte
offset to every node without modifying the underlying `CstNode`:

```moonbit
let syntax_root = @seam.SyntaxNode::from_cst(root)

// syntax_root.start()  == 0
// syntax_root.end()    == root.text_len
// syntax_root.kind()   == root.kind
```

### Walking the tree

```moonbit
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

## Two-tree model

| Concept | `seam` type | Rowan equivalent |
|---|---|---|
| Immutable, position-independent node | `CstNode` | `GreenNode` |
| Ephemeral positioned view | `SyntaxNode` | `SyntaxNode` |
| Language-agnostic kind | `RawKind` | `SyntaxKind` |
| Event-driven builder | `EventBuffer` + `ParseEvent` | `GreenNodeBuilder` |

**Why two trees?** `CstNode`s can be structurally shared and content-addressed
(the same subtree in two parse results shares the same allocation). `SyntaxNode`s
are cheap to create on demand and carry position information without polluting the
shared layer.

## Token interning

For incremental parsing, use `build_tree_interned` to deduplicate identical tokens
across parses:

```moonbit
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
