# Block Reparse Ancestor Widening Design

**Date:** 2026-07-15  
**Status:** Approved — 2026-07-15  
**Scope:** `loom/core` incremental block-reparse selection and Markdown list ownership

## Goal

Preserve CST parity when an edit cannot be reparsed at its smallest block
ancestor but can be reparsed correctly by a strict, reparseable parent. The
initial case is Markdown indentation that turns a sibling list marker into a
nested child.

## Problem

`reparse_block` currently selects the first strict, reparseable ancestor. A
language can return `None` from `get_reparser`, but the core then abandons
block reparse instead of trying an enclosing candidate. Further, `get_reparser`
receives only the old `SyntaxNode`; it cannot decide from the re-lexed new
source whether an edit changes the candidate's structural ownership.

For `- parent\n- child\n` edited to `- parent\n  - child\n`, replacing only
the old `ListItemNode` cannot move the second item under the first. Reusing the
old outer list therefore creates a tree that differs from a full parse.

## Decision

### Candidate selection

The core will enumerate strict, reparseable ancestors from innermost to
outermost. Each candidate retains its old `SyntaxNode`, physical path, and
old/new byte bounds.

For each candidate, the core performs this exact sequence:

1. extract its new text;
2. lex the text;
3. check `is_balanced` — failure aborts block reparse without widening;
4. call the language selector with the old node, new text, and lexed tokens;
5. on selector `None`, consider the next strict, reparseable parent;
6. on a selected reparser, parse and splice the candidate.

An isolated parse, tree-build, splice, or diagnostic merge failure after
selection aborts block reparse. It does not consider a parent: those are
execution failures, not an explicit language judgment that the parent has the
same semantics.

No eligible candidate, no selected reparser, or any failure after selection
preserves the present normal incremental/full-parse fallback.


### Markdown policy

Markdown's selector examines every candidate's **new** token stream before
choosing its isolated reparser. A candidate that contains an indentation prefix
followed by a compatible list marker may change sibling/nested ownership beyond
its replacement range and must explicitly decline. The core then tries a
strict parent when one exists; otherwise its established fallback rebuilds the
document through the normal incremental path.

Before encoding the Markdown predicate, a regression probe records the actual
strict candidate kind, bounds, old text prefix, and new token prefix for each
sibling-to-nested edit. The predicate is derived from those observations, not
from an assumption that the boundary edit selects a child `ListItemNode`.

Ordinary item-local text edits retain the existing `ListItemNode` reparser and
its reuse behavior. The policy does not add a special fresh-parser mode or
duplicate list grammar.

## Interfaces

`BlockReparseSpec` replaces the old-node-only `get_reparser` callback with a
selection callback that takes the old node plus the new candidate source and
lexed token stream. The callback returns the existing isolated parse function
or `None`.

Every `BlockReparseSpec` initializer must adopt the new callback signature.
Existing languages preserve their current behavior by ignoring the new source
and tokens unless they need them.

## Invariants

1. A selected replacement is always a strict, reparseable old-tree ancestor.
2. Parents are tried only after a language explicitly rejects a smaller
   candidate using the new candidate context.
3. A selected candidate is spliced only when its isolated parse succeeds;
   failure aborts block reparse without trying a parent.
4. Reparse execution failures never masquerade as semantic widening requests.
5. Markdown incremental CST and diagnostics match a fresh full parse for the
   sibling-to-nested indentation edit.

## Verification

Core white-box tests cover candidate ordering, explicit decline-to-parent
selection, no widening after an execution failure, and no candidate fallback.
Markdown regression tests retain list item reuse for local text changes and
assert full/incremental parity after sibling-to-nested indentation edits.

## Non-goals

- Multi-edit selection semantics.
- Parent widening after lexer, balance, parser, tree-build, splice, or
  diagnostic failures.
- A public editor-facing reparse API.
- Markdown grammar changes unrelated to incremental ownership.
