# Roadmap Separation Design

**Date:** 2026-03-03
**Status:** Approved

## Problem

`ROADMAP.md` mixes two distinct concerns:

1. **Parser framework** (`dowdiness/loom`) — the reusable incremental parser library
2. **Lambda calculus example** (`examples/lambda/`) — the demo language built on the framework

A framework user reading `ROADMAP.md` encounters Grammar Expansion plans for lambda syntax,
CRDT exploration tied to the lambda AST, and an "Honest Assessment" that references stale
lambda-specific file paths. A lambda developer has no dedicated document.

## Decision

**Option A — Hard split into two ROADMAP files.**

- `ROADMAP.md` (root) → framework only
- `examples/lambda/ROADMAP.md` (new) → lambda calculus example only

---

## Root `ROADMAP.md` — What Changes

**Remove:**
- "Honest Assessment" section — stale; references `parser.mbt:72-227`, `lexer.mbt`,
  `incremental_parser.mbt` paths from early 2026-02 before Phases 0–7 closed those gaps
- "Grammar Expansion" section — lambda concern
- "Phase 6: CRDT Exploration" section — lambda/application concern
- Per-phase full detail blocks — each phase replaced by a single-line summary with archive link

**Keep / condense:**
- Header + Goal (rewritten to be framework-focused)
- Target Architecture diagram + Architectural Principles
- Completed phases as one-liners, e.g.:
  `- Phase 0: Reckoning ✅ (2026-02-01) — [notes](docs/archive/completed-phases/phases-0-4.md)`
- Phase Summary dependency graph (framework items only)
- Milestones table (framework rows only)
- Planned: `Typed SyntaxNode views` (the one remaining framework item)
- "What This Does NOT Include", Success Criteria, References

**Target size:** ~200 lines (down from 435).

---

## `examples/lambda/ROADMAP.md` — New File

**Content (extracted from root ROADMAP.md):**
- Header: "Roadmap: Lambda Calculus Example" with its own goal
- Cross-reference: "For the parser framework, see [ROADMAP.md](../../ROADMAP.md)"
- Grammar Expansion (Partial ✅): let bindings ✅; type annotations + multi-expression files planned — with exit criteria
- CRDT Exploration (Research): full "What to Build" section — `TextDelta.to_edits()`, two-peer convergence test, green tree diff utility
- Incremental Correctness Testing note
- Milestones table for lambda-specific items only

---

## `docs/README.md` — Navigation Update

Add a link to `examples/lambda/ROADMAP.md` under a new "Example" section or alongside the
existing top-level navigation, so the lambda roadmap is discoverable from the docs index.

---

## What Does NOT Change

- `docs/archive/completed-phases/` — unchanged; `ROADMAP.md` links to it as before
- `check-docs.sh` rules — `ROADMAP.md` ≤450 lines (new target ~200 lines satisfies this)
- All architecture docs, API docs, ADRs — untouched
