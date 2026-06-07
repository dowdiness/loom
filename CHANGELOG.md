# Changelog

Notable user-facing changes to Loom and its sibling modules.

## Unreleased

### Changed

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
