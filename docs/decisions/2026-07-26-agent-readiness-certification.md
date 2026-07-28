# ADR: Fail-closed agent-readiness certification

**Date:** 2026-07-26
**Status:** Accepted

## Context

Implementation issues need a repeatable handoff contract without treating an
agent assignment as priority. A stale or incomplete issue must not retain a
signal that an autonomous implementation can safely begin. The check also
needs to be auditable and safe around untrusted issue text.

## Decision

Use `ready-for-agent` as a separate, revocable implementation certification.
The issue form supplies `kind:implementation` and `needs-triage`, while a
workflow applies certification only after the validator accepts the required
H3 sections, labels, exact impact choice, unchecked acceptance criterion,
validation fence, API candidates, escalation bullet, and closed same-repository
issue dependencies.

The validator is dependency-free Python stdlib code. It returns exit code 0 for
certification, 2 for policy failure, and 1 for operational failure. It treats
pull requests, missing/open/self dependencies, closed target issues, rejected
state labels, and malformed structure as policy failures. GitHub API failures
are operational failures and never authorize label mutation.

Issue events audit the event issue only while it carries the certification
label; unrelated issue events are inert. Daily and manually dispatched audits
paginate all open and closed issues carrying the certification label. A fresh
fetch and second validation pass for every candidate completes before any
mutation begins. Open policy failures remove certification, add `needs-triage`,
and create or update one marker comment;
closed failures only remove certification. Successful audits create or update
the marker comment.

## Rationale

Separating triage from certification makes the state transition explicit and
prevents a priority label from being mistaken for implementation authorization.
Fail-closed API handling avoids destructive changes based on incomplete remote
state. Structure-only validation and JSON-based API transport prevent issue
content from becoming executable shell input. Pagination prevents a scheduled
audit from silently certifying only the first page of issues.

## Consequences

Issue authors must provide a bounded, self-contained implementation brief and
maintainers must remove incompatible state before certification. Certification
can be revoked automatically after edits, label changes, dependency changes,
or closure. The workflow requires write access to issue labels/comments and
therefore must remain restricted to the repository's own workflow and token.
The exact policy is covered by deterministic stdlib unit tests and the CI
self-test job.
