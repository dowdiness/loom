# `dowdiness/moonbit-example`

Skeleton integration for making the official MoonBit parser incremental with
[`dowdiness/loom`](../../loom/).

This example is intentionally small: it wires the official
`moonbitlang/parser` lexer into Loom and emits a token-precise, reusable CST
skeleton. It is a starting point for porting the real MoonBit grammar, not a
complete MoonBit parser.

## What exists now

- `lex_moonbit` adapts `moonbitlang/parser/lexer` output to
  `@core.LexResult[MoonToken]` through `@core.LexResult::from_located_tokens`.
- `moonbit_grammar` is a real `@loom.Grammar` value that can be passed to
  `@loom.new_parser` or `@loom.new_imperative_parser`.
- `MoonToken` stores the official `@tokens.TokenKind` and maps every official
  token kind to a stable `MoonbitSyntaxKind` token variant while keeping Loom's
  synthetic trivia/error/EOF kinds separate.
- The internal root parser creates coarse top-level item nodes (`LetItemNode`,
  `FunctionItemNode`, `StructItemNode`, `EnumItemNode`, `TypeItemNode`, or
  fallback `SourceItemNode`) split by official ASI semicolon tokens while
  keeping block-local semicolons inside balanced delimiter groups. Known item
  nodes now contain a coarse item-header child node before the remaining body or
  initializer tokens.
- Top-level fixture tests compare official `moonbitlang/parser` `parse_string`
  accept/reject and AST item kinds with the skeleton item nodes, then snapshot
  skeleton-only header/body token boundaries and layout/comment placement.
- `MoonbitParseShell` is a placeholder `Eq` AST so the parser can participate in
  Loom's reactive API today.

## Intended milestones

1. Port the official handrolled parser rules to `@core.ParserContext` methods.
2. Add a CST-to-official-AST fold and docstring attachment pass.
3. Extend the differential suite from top-level item summaries to real MoonBit
   source fixtures and, once available, CST-to-official-AST projection checks.
4. Add edit-sequence tests that assert stable diagnostics and non-zero CST reuse.

## Quick check

```mbt nocheck
let parser = @loom.new_parser("let x = 1\n", moonbit_grammar)
let shell = parser.ast().read_or_abort()
inspect(shell.item_count, content="1")
```
