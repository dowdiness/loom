# ADR: Markdown Full-Parse Performance Contract

**Date:** 2026-08-03
**Status:** Accepted
**Implementation plan:** [completed plan](../archive/completed-phases/2026-08-03-markdown-full-parse-performance-contract.md)

## Context

Loom's Markdown incremental edit path is already editor-grade on the measured
corpora, while cold parsing is slower than several established JavaScript
parsers. Existing benchmarks exposed tokenize, CST, full AST, and isolated fold
times, but did not isolate production token ownership from pretokenized grammar
and CST work. The stage rows were also absent from the scheduled detector's
baseline and explicit eligibility policy.

A single absolute latency gate would be misleading: Moon Bench results vary by
target and shared-runner load, and simple paragraphs do not represent mixed
Markdown structure. Conversely, leaving every timing informational would allow
a persistent cold-path regression to pass unnoticed.

## Decision

Use two complementary contracts:

1. A stable 51,410-byte paragraph corpus isolates tokenization, token-buffer
   construction, pretokenized grammar+CST work, production CST, AST folding,
   and end-to-end source-to-`Block` parsing.
2. Mixed 2,005-line source-to-`Block` and mixed 9,999-line CST rows guard shape
   sensitivity and large syntax-only parsing.

Make those wasm-gc rows explicit gated entries in the existing weekly
three-run, greater-than-15% persistent-regression detector. Keep JavaScript as
the deployment-target optimization objective and require same-runner base/head
evidence for performance PRs rather than an absolute PR timing gate.

Set directional JavaScript objectives of 10 ms for the 51,410-byte paragraph
full parse and 50 ms for the 2,005-line mixed full parse. The objectives are
deliberately unmet today: they define the next optimization frontier without
misrepresenting current performance.

Preserve CST fidelity, AST/diagnostic behavior, direct/incremental parity, and
the pinned CommonMark conformance contract as hard correctness boundaries.

## Rationale

The end-to-end objectives express user-visible cold latency. Stage rows locate
work but do not constrain implementation or invite invalid subtraction across
independent benchmark runs. A representative mixed corpus prevents optimizing
only a friendly paragraph shape. The existing persistence-filtered detector is
already the project's calibrated response to shared-runner noise, so extending
it is simpler and more maintainable than adding another timing framework.

## Consequences

- Cold-path optimization starts from a reproduced dominant stage.
- Persistent stage or end-to-end wasm-gc regressions enter the existing issue
  workflow.
- JavaScript improvements require recorded base/head measurements before a
  speedup claim is accepted.
- The 10 ms and 50 ms objectives remain visible as unmet work rather than being
  weakened to match today's implementation.
- Any future output-contract change requires an ADR update before benchmark rows
  are redefined.
