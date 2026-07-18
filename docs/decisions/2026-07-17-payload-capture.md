# ADR: Regex Capture Payload Annotations

**Date:** 2026-07-17
**Status:** Accepted
**Implementation plan:** [2026-07-17-payload-capture.md](../archive/completed-phases/2026-07-17-payload-capture.md)

## Context

Pattern-based lexer variants previously required hand-written payload extraction. This duplicated capture slicing logic and made generated lexers unable to construct payload-bearing tokens directly.

## Decision

Add private `#loom.payload` annotations. Ordered expressions construct payload fields from regex captures. Placeholder rewriting remains private to loomgen, and generated character- and line-level lexers use it only when all payload fields are annotation-driven. Partial annotations retain the custom lexer fallback.

Markdown uses a private generated helper package while retaining its hand-written mode/state machine.

## Rationale

This removes mechanical payload extraction without expanding the public parser or runtime API. The helper package preserves Markdown-specific state transitions and allows generated capture construction to be tested independently and end to end.

## Consequences

Payload expressions are validated during generation. Existing patterns without payload annotations retain their generated behavior. Generated fixtures may require formatter-output inspection because generated source is not formatter-normalized.
