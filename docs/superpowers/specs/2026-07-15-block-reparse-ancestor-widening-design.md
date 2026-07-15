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

For a candidate, the core extracts its new text and lexes it before asking the
language whether isolated reparse is allowed. The language hook receives:

- the old candidate `SyntaxNode` for stable context;
- the candidate's new source text; and
- the candidate's re-lexed `TokenInfo` stream.

The hook returns a reparser only when the candidate can preserve root-parse
semantics. `None` is an explicit request to try the next eligible parent.

### Failure boundary

Only an explicit language rejection widens selection. Once a language returns
a reparser, balance failure, isolated parse failure, tree-build failure, splice
failure, or diagnostic merge failure returns the existing `None` result. These
are execution failures, not evidence that a parent has the same semantics.

No eligible candidate or no successful candidate preserves the present normal
incremental/full-parse fallback.

### Markdown policy

Markdown's list-item selector examines the candidate's **new** token stream.
It rejects a `ListItemNode` when a continuation contains an indentation prefix
followed by a compatible list marker at the list's nesting threshold: the
prefix can turn an old sibling into a nested child, changing ownership outside
the isolated item. The enclosing `UnorderedListNode` is then considered by the
core and is parsed with the normal list parser.

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
3. The first selected candidate whose isolated parse succeeds is the only
   spliced replacement.
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
