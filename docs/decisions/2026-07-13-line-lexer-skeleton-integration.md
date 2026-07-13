# ADR: Line-mode lexer skeleton integration

**Date:** 2026-07-13  
**Status:** Accepted  
**Implementation plan:** [docs/archive/completed-phases/2026-07-13-line-lexer-skeleton-integration.md](../archive/completed-phases/2026-07-13-line-lexer-skeleton-integration.md)  
**Design specification:** [docs/superpowers/specs/2026-07-13-line-lexer-skeleton-design.md](../superpowers/specs/2026-07-13-line-lexer-skeleton-design.md)

## Context

`--line-lexer` previously emitted functions named `lex_<mode>`, which collided with the persistent `lexer_skeleton.g.mbt` stubs using the same names. Users had to delete generated stubs manually before the line lexer could compile with the skeleton. Replacing the whole skeleton would solve the collision but could delete handwritten mode implementations.

## Decision

`line_lexer.g.mbt` emits deterministic `generated_lex_<mode>` helpers. `lexer_skeleton.g.mbt` owns the public `lex` dispatcher and its `lex_<mode>` override points. New and explicitly forced skeletons delegate every generated line mode to its helper while retaining aborting stubs for non-line modes.

During `--line-lexer` generation, Loom migrates an existing skeleton only by replacing the exact historical generated abort-stub text for each line mode. A non-identical body is treated as a handwritten override and is not changed. The migration is idempotent.

## Rationale

Layered delegation makes generated behavior available without treating user code as disposable. The `lex_<mode>` function remains the stable override boundary; a user can replace one generated delegate without forking the dispatcher or unrelated modes. Exact textual migration recognizes only code Loom demonstrably owns, avoiding unsafe function-name rewrites.

## Consequences

- `generated_lex_<mode>` is the generated-file helper contract; `lex_<mode>` is the skeleton override contract.
- A valid `--line-lexer` request creates or upgrades a compatible skeleton automatically, including when syntax output is otherwise skipped for a fixture.
- Existing handwritten overrides survive regeneration; `--force-lexer` remains the explicit full-skeleton replacement operation.
- Fixture regeneration now compiles the generated dispatcher and line helper together, with a handwritten non-line fallback retained in the skeleton.
- Consumers depending on the old duplicate `lex_<mode>` functions must use the generated helper names or the skeleton override points instead.
