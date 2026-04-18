# Parse Pipeline

A description of how source text flows through the parser to produce the final AST, including the incremental pipeline built on top of the canonical pipeline.

## Canonical Pipeline

```
Source string → Lexer → EventBuffer → CstNode (CST) → SyntaxNode → Term
                                                           (via typed views)
```

Each stage has a distinct responsibility and output type:

1. **Lexer** — tokenizes the source string into a typed token stream
2. **CST Parser** — emits `ParseEvent`s into an `EventBuffer`; `build_tree()` constructs the immutable `CstNode` tree
3. **SyntaxNode** — wraps the `CstNode` to add absolute byte positions on demand
4. **Conversion** — `syntax_node_to_term` walks `SyntaxNode` using typed view structs (`LambdaExprView`, `AppExprView`, etc.) to produce a `Term` directly; no intermediate `AstNode` type

## Incremental Pipeline

The incremental pipeline adds memoisation on top of the canonical pipeline:

```
Signal[String]
  → Memo[CstNode]   (CST stage)
  → Memo[Ast]       (AST stage — generic type parameter in Grammar[T,K,Ast])
```

- `Signal[String]` holds the current source text. When an edit arrives the signal is updated.
- `Memo[CstNode]` re-runs the Lexer + CST Parser only when the source string changes. Two equal strings produce the same `CstNode` without re-parsing.
- `Memo[Ast]` re-runs conversion only when the `CstNode` changes. Structurally identical `CstNode`s (same hash) skip conversion.

A `TokenStage` memo between Signal and CstNode went through a remove→reintroduce→remove cycle: removed 2026-02-27 as vacuous (whitespace-preserving lexer always shifts positions), reintroduced 2026-03-15 with trivia-insensitive equality, then removed again as part of the Stage 6 `ReactiveParser` consolidation on 2026-04-17. The unified `Parser[Ast]` does not use a `TokenStage`. See ADRs [`2026-02-27-remove-tokenStage-memo.md`](../decisions/2026-02-27-remove-tokenStage-memo.md), [`2026-03-15-reintroduce-token-stage-memo.md`](../decisions/2026-03-15-reintroduce-token-stage-memo.md), and the superseding [`2026-04-17-unified-parser-proposal.md`](../decisions/2026-04-17-unified-parser-proposal.md).

## Stage Details

### Lexer (`examples/lambda/src/lexer/`)

Character-by-character scanning producing `Array[TokenInfo[Token]]`:

- **Whitespace handling** — preserves whitespace as trivia tokens for lossless round-tripping
- **Keyword recognition** — identifies reserved words (`if`, `then`, `else`)
- **Number parsing** — reads multi-digit integers as a single `Integer(Int)` token
- **Identifier reading** — supports alphanumeric variable names starting with a letter
- **Unicode support** — accepts both `λ` (U+03BB) and `\` for lambda

### CST Parser (`examples/lambda/src/cst_parser.mbt`)

Produces a lossless CST using the event buffer pattern (see [seam-model.md](seam-model.md) for the event stream model):

- Grammar functions call `ctx.start_node(kind)` / `ctx.emit_token(kind)` / `ctx.finish_node()`
- `ctx.mark()` / `ctx.start_at(mark, kind)` enable retroactive wrapping for binary expressions and function application
- `build_tree()` replays the flat `EventBuffer` to construct the immutable `CstNode` tree
- All whitespace is preserved as `WhitespaceToken` nodes, keeping the CST lossless

### SyntaxNode (`seam/syntax_node.mbt`)

Ephemeral positioned view over a `CstNode`:

- Computes absolute byte offsets from the CST's cumulative text lengths by summing sibling text lengths
- Maintains parent pointers for upward traversal
- Created on demand; not stored persistently
- `children()` returns a lazy iterator; positions are never cached in the `CstNode`

### CST-to-Term Conversion (`examples/lambda/src/term_convert.mbt`)

Converts the CST to `Term` directly via typed `SyntaxNode` views — no intermediate `AstNode` type:

- `syntax_node_to_term(SyntaxNode) -> Term` — entry point for single-expression parse
- `syntax_node_to_source_file_term(SyntaxNode) -> Term` — entry point for multi-expression files; right-folds top-level `let` definitions into nested `Let` terms
- Typed view structs (`LambdaExprView`, `AppExprView`, `LetDefView`, etc.) provide structured access to child nodes without pattern-matching raw `SyntaxKind` enums
- `ParenExpr` nodes are unwrapped transparently; parentheses affect grouping but do not appear in `Term`
- Error nodes produce `Term::Error(String)` rather than sentinel values

### Pretty Printer (`examples/lambda/src/ast/`)

`print_term` traverses the `Term` AST and reconstructs source text:

- Adds parentheses for unambiguous output (may add extra parens beyond the minimum needed)
- Uses `λ` for lambda abstraction
- Infix notation for binary operations
- Natural keyword formatting for conditionals: `if … then … else …`

Example round-trip:

```moonbit
let ast = parse("λx.x + 1")
let output = print_term(ast)
// "(λx. (x + 1))"
```
