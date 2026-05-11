# ADR: Record Decisions When Major Plans Close

**Date:** 2026-05-11
**Status:** Accepted

## Context

Plan documents are useful while work is in flight: they explain intended
implementation steps, verification commands, and known deferrals. After a plan
is complete, the plan becomes historical evidence of what was done, but it is
not always the best place to preserve the durable decision.

When a completed plan changes public API, removes a subsystem, closes a large
issue, or rejects an approach after investigation, future maintainers need the
"why" in a stable place. ADRs are the right format for that durable rationale.

## Decision

When completing, deleting, or archiving a plan, decide whether the closure needs
an ADR.

Create a new ADR, or update/supersede an existing ADR, when the closed work:

- changes public API or public contracts
- deprecates or removes a package, subsystem, parser path, or documented
  workflow
- resolves a large GitHub issue or multi-PR effort whose rationale will matter
  after the implementation details fade
- establishes a reusable design policy or maintenance rule
- reverses, supersedes, or materially qualifies an earlier ADR
- chooses not to implement something after investigation

Do not create a new ADR for purely mechanical work:

- archiving a plan that only implemented an already accepted ADR
- small bug fixes with local rationale captured by tests and commit messages
- typo fixes, doc index updates, or generated-interface refreshes
- follow-up patches that do not change the prior decision

Every completed plan should include a short decision-record note:

- link to the relevant ADR when one exists
- say "No ADR needed" with a one-sentence reason when the closure is mechanical

Every ADR created from plan closure should link back to the completed plan and,
when useful, the PR or issue that closed it.

## Consequences

This keeps plan archives lightweight while preserving durable rationale for
major decisions. It also prevents ADR spam: not every completed task deserves a
new decision record, but every major closure must make the decision-record
choice explicit.

## Plan Closure Checklist

1. Mark the plan `**Status:** Complete`.
2. Add a completion note with PR/issue links when available.
3. Add a decision-record note linking an ADR or explaining why none is needed.
4. Move the file to `docs/archive/completed-phases/`.
5. Update `docs/README.md` in the same commit.
6. Update memory when the closure affects likely next tasks.
