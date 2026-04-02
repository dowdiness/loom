# Seam Module — CST Infrastructure

The `seam` package (`seam/`) implements a language-agnostic Concrete Syntax Tree (CST) infrastructure modelled after [rowan](https://github.com/rust-analyzer/rowan), the Rust library used by rust-analyzer. Understanding this model is required to work with `CstNode`, `SyntaxNode`, and the event stream.

## Two-Tree Model

The infrastructure separates structure from position through two complementary tree types:

| `seam` type | rowan equivalent | Role |
|---|---|---|
| `RawKind` | `SyntaxKind` | Language-specific node/token kind, newtype over `Int` |
| `CstNode` | `GreenNode` | Immutable, position-independent, content-addressed CST node |
| `CstToken` | `GreenToken` | Immutable leaf token with kind and text |
| `SyntaxNode` | `SyntaxNode` | Ephemeral positioned view; adds absolute offsets |

### CstNode

`CstNode` stores structure and content but has no knowledge of where in the source file it appears. Key properties:

- `hash` — a structural content hash enabling efficient equality checks and structural sharing
- `text_len` — cumulative text length of all descendant tokens
- `token_count` — count of leaf tokens in the subtree
- `children` — ordered list of child nodes and tokens

Once constructed, `children` must not be mutated — `text_len`, `hash`, and `token_count` are cached at construction time. Structural sharing is safe because `CstNode` is position-independent: two subtrees with identical structure and content have the same hash and can be aliased.

### SyntaxNode

`SyntaxNode` is a thin wrapper that adds a source offset. It is created on demand and walks the `CstNode` tree to compute child positions by accumulating text lengths. It is not stored persistently — create one when you need positioned access, discard it when done.

Key methods:

```moonbit
syntax.start()     // absolute byte offset of first token
syntax.end()       // absolute byte offset after last token
syntax.kind()      // RawKind of the underlying CstNode
syntax.children()  // positioned child SyntaxNodes
```

## Event Stream → CST Model

`CstNode` trees are not built directly. Instead, a parser emits a flat sequence of `ParseEvent`s into an `EventBuffer`, then `build_tree()` replays the buffer to construct the immutable tree.

Three event types drive tree construction:

```moonbit
StartNode(RawKind)     // push a new node frame
FinishNode             // pop frame, wrap children into a CstNode
Token(RawKind, StringView) // attach a leaf token (zero-copy view into source)
```

## Tombstone and Retroactive Wrapping

A fourth event, `Tombstone`, enables retroactive wrapping. The parser can reserve a slot with `mark()` before it knows the node kind, then fill it with `start_at(mark, kind)` after parsing enough context to determine the kind.

This pattern is essential for left-associative constructs like binary expressions and function application, where the outer node kind is not known until after the first operand is already parsed.

Example — binary expression `1 + 2`, where the `BinaryExpr` wrapper is decided after both operands are parsed:

```moonbit
let buf = EventBuffer::new()
let m = buf.mark()               // reserve slot; buf contains [Tombstone]
buf.push(Token(IntLit, "1"))
buf.push(Token(Plus, "+"))
buf.push(Token(IntLit, "2"))
buf.start_at(m, BinaryExpr)     // retroactively fill: [StartNode(BinaryExpr), ...]
buf.push(FinishNode)
let cst = build_tree(buf.to_events(), SourceFile)
```

## Traversal Example

```moonbit
let cst = parse_cst("λx.x + 1")
let syntax = @seam.SyntaxNode::from_cst(cst)
inspect(syntax.start())  // 0
inspect(syntax.end())    // 8
for child in syntax.children() {
  // child.start(), child.end(), child.kind()
}
```

`SyntaxNode::from_cst(cst)` constructs a root `SyntaxNode` at offset 0. Each call to `children()` returns a fresh iterator that computes child offsets by summing text lengths, so positions are computed lazily and never stored in the `CstNode`.

## Non-Goals

The `seam` module is deliberately language-agnostic:

- It does not know about lambda calculus, `SyntaxKind`, or any parser-specific concerns — those live in `src/examples/lambda/`.
- It does not define what node kinds mean; kind interpretation is the parser's responsibility.
- The only language-specific hook is `RawKind`, which each language maps to/from its own kind enum via the `LanguageSpec` in `loom/src/core/`.

This separation keeps `seam` reusable across any language that wants a lossless, structurally-shareable CST.
