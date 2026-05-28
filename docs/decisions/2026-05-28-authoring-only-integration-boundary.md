# ADR: Authoring-only Integration Boundary

**Date:** 2026-05-28
**Status:** Accepted
**Issue:** [#164](https://github.com/dowdiness/loom/issues/164)
**Guide:** [Authoring-only Loom Integration](../api/authoring-only-integration.md)

## Context

Downstream projects may want Loom for editor diagnostics, CST projection,
rename facts, outlines, or other authoring features without making Loom part of
their runtime dependency graph. This comes up when a project already has a
small runtime parser, strict browser or wasm-gc constraints, or published
packages whose dependency boundary must remain stable.

Exploratory Loom spikes often use nested modules and local path dependencies.
That is useful for proving grammar and projection value, but it is not enough
evidence that a production runtime package can depend on Loom without changing
publishability or browser reachability.

## Decision

Document an optional authoring-only integration boundary:

- Loom-backed parsing and projection may live in an authoring module or package.
- Runtime one-shot parsing may remain independent and free of Loom/Seam
  dependencies.
- Editor tooling should call a language-owned authoring facade instead of
  learning Loom internals by default.
- Local path-dependency spikes are explicitly non-release artifacts.
- If Loom or Seam enters a runtime-reachable or published package, downstream
  projects must treat that as a production dependency change and run their
  publish/browser checks.

This is guidance, not a framework restriction. Projects that want Loom in their
runtime packages can still use `Parser` or `ImperativeParser` directly after
accepting and verifying that dependency.

## Rationale

Loom should be useful as authoring infrastructure before every downstream
project is ready to adopt it at runtime. A documented boundary lets teams try
Loom for diagnostics and projections while keeping existing runtime callers and
release surfaces stable.

A facade keeps editor-facing APIs language-owned. That preserves room to change
the internal parser/projection implementation without forcing all editor callers
to depend on Loom types such as `Parser` or `SyntaxNode`.

Separating exploratory path-dep spikes from production dependencies prevents a
common release mistake: a local module layout works on one machine, then leaks
into a published or browser-reachable package without versioned dependency and
wasm-gc validation.

## Consequences

Loom documentation now includes an authoring-only guide with boundary diagrams,
facade examples, and audit checks.

Downstream projects that need runtime isolation have a review checklist for
manifest imports, package imports, facade ownership, publishability, browser or
wasm-gc reachability, and runtime parser parity.

The guidance does not require a two-parser architecture for all users. It only
makes the isolation pattern explicit for projects whose runtime dependency
surface matters.
