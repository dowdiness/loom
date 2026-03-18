# Flat AST: Replace `Term::Let` with `Term::Module` — Design Document

**Date:** March 18, 2026
**Status:** Draft
**Scope:** `examples/lambda/src/` (loom submodule), `editor/` and `projection/` (parent crdt repo)

## Goal

Replace the right-recursive `Term::Let(VarName, Term, Term)` encoding with a flat `Term::Module(Array[(VarName, Term)], Term)` variant, so that the CstFold SourceFile algebra produces O(1) AST construction instead of O(n) right-fold allocations.

## Motivation

### The Right-Fold Bottleneck

The CST is flat — LetDef nodes are siblings under SourceFile. But the SourceFile fold algebra right-folds them into nested `Let` terms:

```text
CST:  SourceFile → [LetDef(x0, e0), LetDef(x1, e1), ..., LetDef(x79, e79), Expr]
AST:  Let("x0", e0, Let("x1", e1, ... Let("x79", e79, body)))
```

Editing the last LetDef changes the body of every outer `Let`, requiring 80 fresh `Term::Let` allocations even though 79 definitions are unchanged. The CstFold cache reuses the individual LetDef results at O(1), but the right-fold loop is always O(n).

### Encoding Mismatch

`Term::Let` is not a lambda calculus let-expression parsed from syntax. There is no `let...in` expression in the current parser — `Term::Let` is purely an artifact of the right-fold encoding. The flat CST structure should produce a flat AST structure.

If inline `let...in` expressions are added later, `Term::Let` can be re-introduced with well-defined semantics.

## Design

### Term Enum Change

```moonbit
// REMOVE:
Let(VarName, Term, Term)

// ADD:
Module(Array[(VarName, Term)], Term)   // (definitions, body)
```

- `defs` is an array of `(name, initializer)` pairs, in source order
- `body` is the final expression, or `Unit` if no final expression exists

### SourceFile Fold Algebra Change

The SourceFile algebra **always** produces `Module`, even for bare expressions (`Module([], expr)`). This ensures the top-level node is always `Module`, simplifying consumers.

```moonbit
// BEFORE (O(n) right-fold):
let mut result = final_term
for i = defs.length() - 1; i >= 0; i = i - 1 {
  result = Term::Let(name, init, result)
}
result

// AFTER (O(1) construction):
Term::Module(defs, final_term)
```

### `print_term` Change

`print_term` output stays identical. `Debug`/`Show` derived output (used by `inspect()` snapshots) will change — `Module([...], ...)` instead of `Let(...)`.

```moonbit
// BEFORE:
Let(x, init, body) => "let " + x + " = " + go(init) + "\n" + go(body)

// AFTER:
Module(defs, body) => {
  let parts = []
  for def in defs {
    parts.push("let " + def.0 + " = " + go(def.1))
  }
  if body != Unit || defs.is_empty() {
    parts.push(go(body))
  }
  parts.join("\n")
}
```

### `resolve` Change

Sequential env binding with depth increments — preserves exact scoping semantics:

```moonbit
// BEFORE:
Let(x, val, body) => {
  let new_val = resolve_walk(val, env, depth, counter, res)
  new_env[x] = depth
  let new_body = resolve_walk(body, new_env, depth + 1, counter, res)
  Let(x, new_val, new_body)
}

// AFTER:
Module(defs, body) => {
  let new_defs = []
  let cur_env = Map::from_iter(env.iter())
  let mut cur_depth = depth
  for (name, init) in defs {
    let new_init = resolve_walk(init, cur_env, cur_depth, counter, res)
    cur_env[name] = cur_depth
    cur_depth = cur_depth + 1
    new_defs.push((name, new_init))
  }
  let new_body = resolve_walk(body, cur_env, cur_depth, counter, res)
  Module(new_defs, new_body)
}
```

Each definition's initializer sees only previous definitions (non-recursive). Each binding increments depth for subsequent definitions. Body sees all definitions. Identical scoping semantics to nested Lets.

### Pre-order Index Change

`resolve()` assigns pre-order indices as it walks. The numbering changes:

```text
// BEFORE (nested Let, 3 defs):
0=Let(x0), 1=e0, 2=Let(x1), 3=e1, 4=Let(x2), 5=e2, 6=body

// AFTER (Module, 3 defs):
0=Module, 1=e0, 2=e1, 3=e2, 4=body
```

Module counts as 1 node instead of n Let nodes. Tests that assert specific node IDs need updating. Semantics (Bound/Free) are unchanged.

**DOT rendering alignment:** `build_term_tree` and `resolve_walk` must assign the same pre-order IDs for Module nodes — 1 ID for the Module itself, then IDs for each def initializer, then the body.

### DOT Renderer Change

- `label`: `Module(defs, _) => "Module"` (or list def names)
- `build_term_tree`: children are all init terms + body (flat, not nested)
- `node_attrs`: no coloring needed (Module is not a variable)

### Edge Cases

- Empty SourceFile: `Module([], Unit)`
- Defs only, no expression: `Module([(x, e1)], Unit)` — body is `Unit`
- Single expression, no defs: `Module([], expr)` — always wrapped in Module for uniformity
- `syntax_node_to_term` wrapper: delegates to `lambda_fold_node`, produces `Module` automatically

### JSON Serialization

`Term` derives `ToJson`. The wire format changes: `Module([...], ...)` replaces `Let(...)`. If any downstream consumer persists or deserializes Term values, it must be updated. Currently the web frontend uses `print_term` for display (unaffected) — verify no JSON serialization dependency exists before implementing.

## Performance Impact

| Metric | Before (nested Let) | After (Module) |
|--------|-------------------|----------------|
| AST construction per fold | n separate Let allocations | 1 Module + 1 array allocation |
| Structural change on 1-def edit | All n Let nodes differ | 1 Module node differs |
| Fold cache benefit | Cache hits but O(n) rebuild | Cache hits + O(1) wrap |

The O(n) child iteration in the algebra is unavoidable (each child's `recurse()` call is needed). The improvement is constant-factor: 1 allocation instead of n. The stronger win is that the Module node's structural identity changes less — only the array reference differs, not a chain of n nested term constructors.

## Cross-Repository Impact

`Term` is defined in `examples/lambda/src/ast/` (loom submodule) but consumed by `editor/` and `projection/` in the parent crdt repo. Removing `Term::Let` is a cross-module breaking change.

**Parent repo files that match on `Term::Let`:**

| File | Sites | Change needed |
|------|-------|---------------|
| `projection/proj_node.mbt` | `rebuild_kind`, `to_proj_node`, `same_kind_tag` | Replace `Let(name, _, _)` with `Module(defs, _)` |
| `projection/reconcile_ast.mbt` | reconciliation match | Update for `Module` |
| `projection/flat_proj.mbt` | `to_proj_node`, `from_proj_node` | Update for `Module` |
| `projection/tree_editor.mbt` | shape extraction, label rendering | Replace `Let(name)` shape with `Module` shape |
| `projection/tree_lens.mbt` | `placeholder_text_for_kind` | Update match |
| `editor/sync_editor_parser.mbt` | (indirect — uses `resolve()`) | No match-site changes |
| Test files in `projection/` | Various | Update constructors |

**Migration strategy:** Same as the semantic error variants PR — implement in loom worktree first, then update parent repo after submodule bump. The parent repo changes are a separate commit.

## Files to Modify

**Loom submodule (`examples/lambda/`):**

| File | Change |
|------|--------|
| `ast/ast.mbt` | Replace `Let` with `Module` in enum + `print_term` |
| `term_convert.mbt` | Simplify SourceFile algebra — always produce `Module` |
| `resolve.mbt` | Replace `Let` case with `Module` case |
| `dot_node.mbt` | Update `label`, `build_term_tree` for `Module` |
| `parser_properties_test.mbt` | Update `check_well_formed` |
| `resolve_wbtest.mbt` | Update test constructors + node ID expectations |
| `views_test.mbt` | Update test constructors |
| `ast/debug_wbtest.mbt` | Update test constructors + snapshot expectations |
| `parser_test.mbt` | Snapshot updates (via `moon test --update`) |

**Parent crdt repo (after submodule bump):**

| File | Change |
|------|--------|
| `projection/proj_node.mbt` | Update `Term::Let` matches to `Term::Module` |
| `projection/reconcile_ast.mbt` | Update reconciliation match |
| `projection/flat_proj.mbt` | Update proj node conversion |
| `projection/tree_editor.mbt` | Update shape and label for Module |
| `projection/tree_lens.mbt` | Update placeholder text |
| Projection test files | Update constructors |

## What Stays the Same

- `print_term` human-readable output (identical formatted strings)
- `resolve()` scoping semantics (sequential, non-recursive)
- CstFold framework (no changes to `loom/`)
- CST structure (LetDef nodes unchanged)
- All other Term variants (Int, Var, Lam, App, Bop, If, Unit, Unbound, Error)

**What changes:**
- `Debug`/`Show`/`inspect` snapshot output — `Module([...], ...)` replaces `Let(...)`
- Pre-order node IDs in `resolve()` — Module is 1 node, not n
- `ToJson` wire format — if consumed anywhere

## References

- [Memoized CST Fold design](2026-03-08-memoized-cst-fold.md) — the fold cache this change optimizes
- [Multi-expression files design](../archive/completed-phases/2026-03-04-multi-expression-files-design.md) — original right-fold encoding decision
