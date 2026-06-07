# `dowdiness/moonbit-example`

Skeleton integration for making the official MoonBit parser incremental with
[`dowdiness/loom`](../../loom/).

This example is intentionally small: it wires the official
`moonbitlang/parser` lexer into Loom and emits a coarse, reusable CST. It is a
starting point for porting the real MoonBit grammar, not a complete MoonBit
parser.

## What exists now

- `lex_moonbit` adapts `moonbitlang/parser/lexer` output to
  `@core.LexResult[MoonToken]` through `@core.LexResult::from_located_tokens`.
- `moonbit_grammar` is a real `@loom.Grammar` value that can be passed to
  `@loom.new_parser` or `@loom.new_imperative_parser`.
- The internal root parser creates coarse top-level item nodes (`LetItemNode`,
  `FunctionItemNode`, `StructItemNode`, `EnumItemNode`, `TypeItemNode`, or
  fallback `SourceItemNode`) split by official ASI semicolon tokens while
  keeping block-local semicolons inside balanced delimiter groups.
- `MoonbitParseShell` is a placeholder `Eq` AST so the parser can participate in
  Loom's reactive API today.

## Intended milestones

1. Replace coarse token classes with the full MoonBit syntax-kind table.
2. Port the official handrolled parser rules to `@core.ParserContext` methods.
3. Add a CST-to-official-AST fold and docstring attachment pass.
4. Differential-test against `moonbitlang/parser.parse_string` on real MoonBit
   sources.
5. Add edit-sequence tests that assert stable diagnostics and non-zero CST reuse.

## Quick check

```mbt nocheck
let parser = @loom.new_parser("let x = 1\n", moonbit_grammar)
let shell = parser.ast().read_or_abort()
inspect(shell.item_count, content="1")
```
