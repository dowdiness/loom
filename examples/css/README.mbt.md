# `dowdiness/css-example`

CSS declaration-list grammar exercising the three EBNF operators
implemented in M16 (`#598` – `#600`): postfix `~` (unconditional consume),
postfix `!` (expect-or-continue with diagnostic), and `@until(Token)`
(consume until synchronization point).

## What it demonstrates

The `#loom.rule` annotations on `term_kind.mbt` define four productions
that together exercise all three operators in a realistic declarative
grammar:

```text
Stylesheet = Rule* EOF                    # RepeatWhile over Ident-gated rule
Rule      = Ident~ LBrace Decls RBrace    # ~ → Emit (safe gated by FIRST)
Decls     = Decl* @until(RBrace)          # @until → ErrorUntil trailing recovery
Decl      = Ident! Colon! (Ident|Number)* Semicolon!  # ! → EmitOr on three terminals
```

## Verification

A parity test (`css_parity_wbtest.mbt`) compares the loomgen-generated
`GrammarIr` (from `#loom.rule` annotations) against a hand-authored
`GrammarIr` (`css_ir.mbt`) — both interpreted through `@grammar.interpret`
must produce identical parse trees and diagnostics for the same input.

Three acceptance tests exercise error-recovery behavior:

- **missing-property-name** — `Ident!` and `Colon!` produce placeholder
  tokens instead of aborting when a declaration starts with `;`
- **@until recovery** — `@until(RBrace)` consumes garbage after a valid
  declaration until the closing brace
- **missing-semicolon-recovery** — `Semicolon!` emits a diagnostic and
  placeholder, then the next declaration starts normally

## Generation

Run from the repo root to regenerate `css_grammar_ir.g.mbt`,
`token_impls.g.mbt`, and `syntax_kind.mbt`:

```bash
moon build loomgen --target native
moon run loomgen --target native -- \
  examples/css/token/token.mbt \
  --term examples/css/term_kind.mbt \
  --grammar-ir examples/css/css_grammar_ir.g.mbt \
  --language css \
  examples/css/token examples/css/syntax
```

## Learn More

- [`#loom.rule` subset contract](../../docs/grammar_ir_contract.md) —
  alternation semantics, left-recursion rejection, fragment escape hatch
- [`loomgen` README](../../loomgen/README.md) — annotation reference,
  file-format spec, generation pipeline
- [`examples/lambda`](../lambda/) — reference grammar with the full
  loom feature surface (views, projections, incremental reuse)
