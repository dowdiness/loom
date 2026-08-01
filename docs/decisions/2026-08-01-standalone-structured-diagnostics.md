# ADR: Standalone Structured Diagnostics Boundary

**Date:** 2026-08-01
**Status:** Accepted
**Qualifies:** [ADR: Structured Parser Diagnostics Boundary](2026-05-14-structured-parser-diagnostics-boundary.md)
**Implementation spec:** [Issue #830](https://github.com/dowdiness/loom/issues/830)

## Context

Loom's structured diagnostic model grew useful parser-independent behavior:
validated UTF-16 ranges, source-qualified labels, defensive values, deterministic
plain rendering, and atomic fixes. Keeping that model inside the parser module
forced unrelated tools to depend on Loom and overloaded “source” to mean both a
diagnostic producer and source text.

The earlier structured-parser decision also described public token evidence.
PR #825 removed that evidence after the parser stopped needing it at the public
boundary. The remaining portable model therefore no longer requires token,
grammar, CST, or incremental-runtime types.

## Decision

Create `dowdiness/diagnostic` as an independent module whose production code
depends only on MoonBit core packages. It owns diagnostic values, validated
offsets and ranges, source identities and snapshots, line indexing, fixes,
plain rendering, and the open `SourceResolver` and `ToDiagnostic` traits.

Use unambiguous domain names:

- `DiagnosticOrigin` identifies the subsystem that produced a diagnostic.
- `SourceId` identifies source text.
- `SourceSnapshot` is one coherent name/text/line-index rendering view.
- `SourceResolver` is the caller-owned capability for retrieving snapshots.

Keep `Diagnostic` concrete. `ToDiagnostic` is a small fixed projection from an
application-defined `Self` to that canonical value; it is not a generic
conversion framework. Resolver invocation is the imperative shell. Conversion,
validation, fix application, grouping, and rendering remain deterministic core
logic.

Loom continues to own `DiagnosticSet`, lexer/parser convenience construction,
`SourceEdit`, replay deduplication, rollback, relex invalidation, and recovery.
`LexError` is the first production `ToDiagnostic` implementation. Loom re-exports
portable names where MoonBit permits it, while consumers that call methods on
the defining types must also load the standalone package as required by MoonBit
package visibility.

## Rationale

The boundary follows actual ownership. Diagnostic values and rendering do not
need parsing, while collection mutation and edit-lifecycle decisions encode
Loom-specific policy. A concrete value keeps renderers and integrations simple;
two small capability traits let unknown applications provide source storage and
domain-error conversion without inheriting parser abstractions.

Separating producer identity from source identity removes the ambiguity in the
former `DiagnosticSource` name. Snapshot resolution supports files, virtual
documents, and in-memory buffers without placing I/O or persistence in the
library.

## Consequences

Users may depend on `dowdiness/diagnostic` without depending on Loom. Existing
Loom users retain the portable types through Loom's public facade, subject to
MoonBit's defining-package visibility rule.

The renames from `DiagnosticSource`, `DiagnosticSourceFile`, and `SourceProvider`
to `DiagnosticOrigin`, `SourceSnapshot`, and `SourceResolver` are intentional
breaking changes. `Diagnostic` construction and access use `origin` rather than
`source`.

Token evidence is not part of the current public diagnostic model. The earlier
ADR remains authoritative for structured, total parser snapshots and parser
recovery, but its token-evidence statements describe superseded history.

Generic range ownership, semantic attachment, parser replay, and multi-source
fix application remain outside the standalone package until multiple real
consumers demonstrate shared semantics.
