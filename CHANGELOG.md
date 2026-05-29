# Changelog

Notable user-facing changes to Loom and its sibling modules.

## Unreleased

### Added

- `dowdiness/loom`: added stable semantic projection identity helpers
  (`ProjectionIdentityBaseline`, `ProjectionLeaf`, `StableProjectionLeaf`, and
  `realign_projection_identities`) for preserving domain IDs across editor
  edits and malformed-input recovery.
- `dowdiness/seam`: added projection-friendly direct CST query helpers on
  `SyntaxNode`: `direct_token_of_kind`, `direct_tokens_of_kind`, and
  `direct_children_of_kind`. These make direct argument-shape validation more
  obvious for library users and help avoid accidentally accepting nested tokens
  during semantic projection.
