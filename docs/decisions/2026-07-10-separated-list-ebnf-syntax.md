# ADR: SeparatedList EBNF Syntax — `{Sep}`

**Date:** 2026-07-10
**Status:** Accepted
**PR:** [#667](https://github.com/dowdiness/loom/pull/667)
**Issue:** [#604](https://github.com/dowdiness/loom/issues/604)

## Context

`Expr::RepeatTopLevel` exists in the grammar IR but was unreachable from the
EBNF notation subset. Rules could only express simple repetition (`*`, `+`)
without separator awareness. This meant separated lists like
`{ "a": 1, "b": 2 }` used `RepeatWhile` on the whole list — editing a middle
member re-parsed every preceding member because `RepeatWhile` has no delimiter
boundary to reuse.

## Decision

Add `{Sep}` as a postfix operator on an atom:

    postfix := atom ('*' | '+' | '?' | '~>' atom | '~' | '!' | '{' IDENT '}')?

`Expr{Sep}` is a zero-or-more separated list: `Expr (Sep Expr)*`. It lowers to
`Expr::RepeatTopLevel`:

| Field | Source |
|---|---|
| `RuleName` (slot) | The `Expr` rule name |
| `starts` | `FIRST(Expr)` as a `Pred` |
| `delim` | `Pred::IsToken(Sep)` |
| `delim_kind` | The CST kind of `Sep` |
| `between_msg` | `"expected 'Sep' between Expr items"` |
| `after_msg` | `"expected 'Sep' or end of Expr items"` |

### Key design choices

1. **Zero-or-more semantics.** An empty separated list is valid. For one-or-more,
   wrap the list in a trailing requirement guaranteed by the enclosing rule.
   Consistent with `Star(*)`, not `Plus(+)` — `RepeatTopLevel` naturally handles
   the empty case.

2. **Simple rule name + terminal token.** The item must be a `Sym` (rule
   reference), not a compound expression. The separator must be a terminal
   token. This mirrors the `~>` operator's operand constraints and keeps the
   lowering straightforward: `RepeatTopLevel` needs a slot name (the item rule)
   and a `Pred::IsToken` (the separator).

3. **`{ }` brace syntax.** Braces visually distinguish `{Sep}` from `[ ]` (used
   by `@prec[...]`). They were already unused in the notation subset.

## Consequences

### Positive

- `RepeatTopLevel` is now reachable from the EBNF notation, enabling
  incremental list reuse
- Follows the same `Tok` → `RuleAst` → analysis → `lower` → test pattern as
  previous extensions (`@error_node`, `~>`)
- The `between_msg`/`after_msg` diagnostics give clear error messages for
  malformed lists

### Negative

- Item and separator must be simple names (no compound expressions)
- Grammar file tokenizer and `describe_gfile_tok` needed matching `{`/`}`
  support

### Neutral

- `nullable(_, _) => true` — zero-or-more, consistent with `Star(*)`
- `first_set` delegates to the item rule's FIRST set, same as `Plus(X)`

## Alternatives Considered

- **`Expr{Sep}?` for zero-or-more** — more explicit but redundant since
  `{Sep}` is already zero-or-more. Deferred until usage patterns demand it.
- **`Expr( Sep Expr )*` as inline notation** — more flexible but harder to
  parse and doesn't map cleanly to `RepeatTopLevel`'s slot model.
- **Separate `@delimited(...)` annotation** — more verbose with no additional
  expressive power.
