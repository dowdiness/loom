# Agent Documentation Protocol

This protocol turns the ADR rule into operational steps for coding agents.
Follow it whenever a task touches `docs/plans/`, `docs/archive/`, or
`docs/decisions/`.

## Plan States

Active plans live in `docs/plans/`.

Completed plans live in `docs/archive/completed-phases/`.

Decision records live in `docs/decisions/`.

## Completing Or Archiving A Plan

When a plan is complete:

1. Mark it `**Status:** Complete`.
2. Add a completion note with PR/issue links when available.
3. Decide whether an ADR is required.
4. Add a `Decision record:` section that links the ADR or says
   `No ADR needed:` with a one-sentence reason.
5. Move the plan to `docs/archive/completed-phases/`.
6. Update `docs/README.md` in the same change.
7. Update memory if the closure changes likely future work.

## When An ADR Is Required

Create a new ADR, update an existing ADR, or mark an older ADR superseded when
the closed work:

- changes public API or public contracts
- deprecates or removes a package, subsystem, parser path, or documented
  workflow
- resolves a large GitHub issue or multi-PR effort whose rationale should
  remain discoverable
- establishes a reusable design policy or maintenance rule
- reverses, supersedes, or materially qualifies an earlier ADR
- chooses not to implement something after investigation

## When No ADR Is Needed

Do not create a new ADR for mechanical work:

- archiving a plan that only implements an already accepted ADR
- small bug fixes with local rationale captured by tests and commit messages
- typo fixes, doc index updates, or generated-interface refreshes
- follow-up patches that do not change the prior decision

In those cases, add:

```md
Decision record:

- No ADR needed: <short reason>.
```

## ADR Shape

Use this minimum structure:

```md
# ADR: <Decision Title>

**Date:** YYYY-MM-DD
**Status:** Proposed | Accepted | Superseded
**Implementation plan:** [docs/archive/completed-phases/<plan>.md](../archive/completed-phases/<plan>.md)

## Context

## Decision

## Rationale

## Consequences
```

If the ADR supersedes another ADR, add a `**Supersedes:**` line.

If it is superseded later, update `**Status:**` and add a `**Superseded by:**`
line.

## Final Response Requirement

When a task completes or archives a plan, the agent's final response must state
which decision-record path was used:

- linked ADR
- updated ADR
- `No ADR needed` reason
