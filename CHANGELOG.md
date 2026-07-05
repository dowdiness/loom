# Changelog

Notable user-facing changes to Loom and its sibling modules.

## Unreleased

### Changed

- `examples/markdown`: improved CommonMark tab handling for list and
  blockquote indentation, including tab-expanded nested list markers and
  container-relative indented code blocks.

- **`dowdiness/loom/core` — `@core` package surface reduction (Stage A1):**
  `ProjectionIdentityBaseline`, `ProjectionIdentityTracker`, `ProjectionLeaf`,
  `StableProjectionLeaf`, `ProjectionStringIdAllocator`, and the four
  `realign_projection_*` functions are removed from the `@core` package's
  public `.mbti`. They are now in the new `dowdiness/loom/projection` package
  and continue to be re-exported unchanged by the `dowdiness/loom` facade.
  **No change required for code that imports via `@loom.*`** — the facade
  surface is identical. Direct `@core.ProjectionIdentity*` importers must
  switch to `@loom.*` or `@projection.*`.

- `dowdiness/seam`: hardened source-span/reuse APIs before stabilization.
  `CstToken::is_source_backed` is the stable token-provenance predicate;
  `CstToken::unsafe_backing_source`,
  `EventBuffer::push_parser_reuse_node_rebased*`, and
  `EventBuffer::push_parser_synthetic_zero_width_token` carry explicit
  unstable, parser-owned naming. The older `CstToken::source`,
  `EventBuffer::push_reuse_node_at*`, and
  `EventBuffer::push_synthetic_zero_width_token` names are deprecated
  compatibility aliases.

### Added


- **`dowdiness/loomgen` — M16 EBNF subset: `~` (Emit), `!` (EmitOr), `@until` (ErrorUntil):**
  Postfix `Token~` lowers to `Expr::Emit(token, kind)` — silently skip if absent.
  Postfix `Token!` lowers to `Expr::EmitOr(token, kind, msg)` — emit diagnostic + placeholder if absent.
  `@until(Token)` / `@until(T1 | T2)` lowers to `Expr::ErrorUntil(Pred::IsToken/OneOf, msg)` — consume until synchronization point.
  All three syntaxes available in `#loom.rule` annotations and `.loomgrammar` files.
  Golden fixture + parity test added under `fixtures/rule_emit_fixture.*`.

### Fixed

- **`dowdiness/loom/grammar` — `@until` no longer emits spurious diagnostic when already at sync point (#636):**
  `ErrorUntil(stop, msg)` now guards `ctx.error(msg)` behind
  `if !stop.matches(ctx.peek())` — when the current token already satisfies the
  stop predicate (e.g. `@until(RBrace)` with `peek = RBrace`), no diagnostic is
  emitted and `skip_until` is skipped. Fix applied to both the interpreter and
  the compiled emission path.

- **`dowdiness/loom/core` — `ParserContext::expect` and `expect_adjacent` no longer emit "emit_token: unexpected EOF" diagnostic:**
  Both functions now skip `emit_token` when at EOF — EOF has no source text to
  emit as a CST token, so attempting to do so produced a spurious diagnostic on
  every well-formed parse that uses `Expect(EOF, ...)` (e.g. every grammar with
  a trailing `EOF` in its root rule). The diagnostic was harmless but added
  noise, obscuring real recovery diagnostics.

### Added

- `dowdiness/loom`: added `ParserContext` grammar-author helpers:
  `emit_current_token`, `current_token_text`, `current_token_range`, and
  `too_many_errors`.
- `dowdiness/loom`: added `ParserContext` node-introspection helpers:
  `current_node_kind()` (returns `K?` — the kind of the most recently opened
  node), `peek_index(n)` (trivia-inclusive token-buffer access), and
  `finish_nodes_until(kind)` (auto-close nodes above a target kind, used for
  HTML-style optional closing tags).
- `dowdiness/loom`: added `finish_nodes_until_inclusive(kind)` —
  like `finish_nodes_until` but also closes the matching node.
  Eliminates the two-step pattern
  (`if ctx.finish_nodes_until(K) { ctx.finish_node() }`).

- **`dowdiness/loom/projection`** — new package containing the stable
  semantic projection-identity subsystem extracted from `loom/core` (Stage A1).
  Depends on `loom/core` data types and `text_change`; the engine
  (`loom/core` parser, `loom/incremental`, `loom/pipeline`) is structurally
  prohibited from depending on it. All projection-identity symbols remain
  accessible via the `dowdiness/loom` facade unchanged.

- `dowdiness/loom`: added `SyntaxGrammar`, `SyntaxParser`,
  `SyntaxSnapshot`, and `new_syntax_parser` for reactive CST/diagnostics
  consumers that do not have an AST fold or whose AST is not naturally `Eq`.
- `dowdiness/loom`: added stable semantic projection identity helpers
  (`ProjectionIdentityBaseline`, `ProjectionIdentityTracker`, `ProjectionLeaf`,
  `StableProjectionLeaf`, `ProjectionStringIdAllocator`,
  `realign_projection_identities`, and `realign_projection_items`) for
  preserving domain IDs across editor edits and malformed-input recovery.
- `dowdiness/seam`: added projection-friendly direct CST query helpers on
  `SyntaxNode`: `direct_token_of_kind`, `direct_tokens_of_kind`, and
  `direct_children_of_kind`. These make direct argument-shape validation more
  obvious for library users and help avoid accidentally accepting nested tokens
  during semantic projection.
- `dowdiness/seam`: added `CstNode::direct_elements_iter` for lazy direct
  visible-child traversal with transparent `RepeatGroup` flattening.
- `dowdiness/seam`: added `SyntaxNode::direct_elements_iter` for lazy
  positioned direct-child traversal as `SyntaxElement`s, reusing the same
  transparent `RepeatGroup` flattening semantics.
