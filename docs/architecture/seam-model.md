# Seam Module — CST Infrastructure

The `seam` package (`seam/`) implements a language-agnostic Concrete Syntax Tree (CST) infrastructure modelled after [rowan](https://github.com/rust-analyzer/rowan), the Rust library used by rust-analyzer. Understanding this model is required to work with `CstNode`, `SyntaxNode`, and the event stream.

## Two-Tree Model

The infrastructure separates structure from position through two complementary tree types:

| `seam` type | rowan equivalent | Role |
|---|---|---|
| `RawKind` | `SyntaxKind` | Language-specific node/token kind, newtype over `Int` |
| `CstNode` | `GreenNode` | Immutable, content-addressed CST node (node offsets are external) |
| `CstToken` | `GreenToken` | Immutable leaf token with kind, text length, and backing source span |
| `SyntaxNode` | `SyntaxNode` | Ephemeral positioned view; adds absolute UTF-16 offsets |

### CstNode

`CstNode` stores structure and content. It does not store node start offsets; leaf `CstToken`s keep source spans so token text can be viewed without copying. Key properties:

- `hash` — a structural content hash enabling efficient equality checks and structural sharing
- `text_len` — cumulative text length of all descendant tokens
- `token_count` — count of leaf tokens in the subtree
- `children` — ordered list of child nodes and tokens

Once constructed, `children` must not be mutated — `text_len`, `hash`, and `token_count` are cached at construction time. Structural equality is content-based: two subtrees with identical structure and token text have the same hash even if their token spans point into different source strings. Incremental parsing emits parser-owned reuse events for unchanged regions; tree building rebases those reused token spans onto the current source buffer.

`RepeatGroup` nodes are physical balancing wrappers for long repeated sibling
runs. They are transparent to visible traversal: callers see the contained nodes
and tokens in source order, not the wrapper itself.

The wrapper layout is canonical. When an incremental parse reuses part of an old
balanced run, tree building flattens the old wrappers into the current event
frame and balances the frame again. This keeps the raw CST shape equal to a full
reparse while preserving visible child order.

### CstToken

`CstToken` is a green-tree leaf. It records token kind, text length, text
content, and provenance:

- Source-backed tokens come from lexer/source `StringView`s. `is_source_backed()`
  is true, and `start_offset()` / `end_offset()` name the token's backing span
  in that source buffer.
- Parser-synthetic tokens are placeholders emitted by the parser, such as
  zero-width error or incomplete-token recovery leaves. `is_source_backed()` is
  false; these leaves are not lexer context.

`is_source_backed()` is stable token-provenance vocabulary; it does not expose
backing-buffer ownership or structural position.

A token's backing span is not its structural position or ownership range inside a
`CstNode`. Structural position is computed from the containing node's start plus
the accumulated `text_len` of preceding children. This distinction matters for
zero-width and interned tokens: an interned empty source-backed token may carry a
canonical backing span that differs from a later tree position, while a
parser-synthetic zero-width placeholder has no lexer span to advance.

Use `SyntaxNode` / `SyntaxToken` or explicit accumulated child offsets when you
need positioned access. Use `CstToken::start_offset()` / `end_offset()` only for
the token's backing source span.

### SyntaxNode

`SyntaxNode` is a thin wrapper that adds a source offset. It is created on demand and walks the `CstNode` tree to compute child positions by accumulating text lengths. It is not stored persistently — create one when you need positioned access, discard it when done.

Key methods:

```moonbit
syntax.start()     // absolute UTF-16 code-unit offset of first token
syntax.end()       // absolute UTF-16 code-unit offset after last token
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
