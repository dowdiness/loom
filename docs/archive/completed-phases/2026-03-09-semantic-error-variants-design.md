# Semantic Error Variants: `Term::Unbound` — Design Document

**Date:** March 9, 2026
**Status:** Complete
**Scope:** `examples/lambda/src/ast/`, `examples/lambda/src/resolve.mbt`, `examples/lambda/src/dot_node.mbt`

## Goal

Add `Term::Unbound(VarName)` variant so that free variables are represented as values within the Term tree, satisfying the uniform error representation law at Boundary ③.

## Motivation

Currently, name resolution produces a side-channel (`Resolution { vars: Map[Int, VarStatus] }`) that maps pre-order index → `Bound(depth)` or `Free`. Free variables are detected but their status lives outside the Term — consumers must cross-reference the Resolution map to know a variable is unbound.

The anamorphism discipline requires uniform error representation: errors should be values within the structure, not a separate channel. `Term::Error(msg)` already handles parse errors. `Term::Unbound(name)` extends this to semantic errors.

## Design

### Term Enum Change

Add `Unbound(VarName)` to `Term`:

```
pub(all) enum Term {
  ...
  Unbound(VarName)    // Free variable — semantic error
  Error(String)       // Parse error
}
```

### `print_term` Change

```
Unbound(x) => "<unbound: " + x + ">"
```

### `resolve` Signature Change

```
Before: pub fn resolve(term : Term) -> Resolution
After:  pub fn resolve(term : Term) -> (Term, Resolution)
```

Returns a rewritten tree where free `Var(name)` → `Unbound(name)`, plus the existing Resolution map with binding depths for bound vars.

### DOT Renderer Change

- `label`: add `Unbound(x) => "Unbound(" + x + ")"` case
- `node_attrs`: color `Unbound` nodes red (same as current `Free` coloring)
- `build_term_tree`: handle `Unbound` as a leaf (no children)

### Consumers

`get_ast_dot_resolved` and any other call sites of `resolve()` update for the `(Term, Resolution)` return type.

### What Stays the Same

- `Resolution` struct and `VarStatus` enum unchanged
- Resolution map still tracks `Bound(depth)` and `Free` by pre-order index
- The rewritten tree and the Resolution map serve different consumers

## Anamorphism Discipline Impact

| Law | Before | After |
|-----|--------|-------|
| Uniform error representation | Free variables in side-channel only | `Unbound(name)` in the Term tree |

## References

- [Anamorphism Discipline Guide](../architecture/anamorphism-discipline.md) — Boundary ③ audit
- [Term::Error variant](../archive/completed-phases/2026-03-05-term-error-variant.md) — prior art for error-in-tree pattern
