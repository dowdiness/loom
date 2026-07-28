# Agent-readiness certification

`ready-for-agent` is a revocable implementation certification, not a priority or
classification label. The issue form applies `kind:implementation` and
`needs-triage`; it never applies `ready-for-agent`.

## Two-step certification

1. Remove incompatible state first. The issue must be open, have
   `kind:implementation`, and have none of `blocked`, `needs-triage`,
   `needs-human-decision`, or `in-progress`.
2. Separately add `ready-for-agent`. The readiness workflow validates the
   complete issue body and dependency graph before accepting the certification.

The body must have one each of these H3 sections: Deliverable, Scope, Non-goals,
Dependencies, Acceptance criteria, Validation, Existing API candidates, API and
documentation impact, and Stop and escalate if. Deliverable, Scope, and
Non-goals are non-empty. Acceptance criteria has an unchecked checkbox,
Validation has a fenced block, API candidates has at least two bullets, impact
is one of the exact issue-form choices, and Stop and escalate has a bullet.
Dependencies is exactly `None` or bullets with same-repository `#N` references.
Every referenced issue is resolved through the GitHub REST API and must be a
closed issue, not a pull request; missing, open, self, or pull-request
references fail certification.

The validator checks Markdown structure only. It never executes commands or
other content copied into an issue body.

## Failure modes and exit codes

`scripts/validate-agent-ready-issue.py` accepts `--issue-json`, `--repo
owner/name`, and `--report-file`. It prints and writes a Markdown report.

- `0`: certified.
- `2`: policy failure. The workflow revokes `ready-for-agent`; for an open
  issue it also adds `needs-triage` and creates or updates one bot-marker
  comment. A closed issue only loses `ready-for-agent`.
- `1`: operational failure, such as an unavailable or malformed GitHub API
  response. No labels are mutated.

For issue events, the workflow audits the event issue only while it carries
`ready-for-agent`; unrelated issue events are inert. Scheduled and manual full
audits paginate every open and closed issue carrying `ready-for-agent`. The
workflow validates once, refetches every candidate, and completes a second
validation pass before any mutation begins. An operational failure therefore
cannot leave a partially reconciled audit batch. A daily schedule and
`workflow_dispatch` provide manual recovery/audit paths.

## Manual audit and security

Run the validator locally with a saved issue JSON:

```sh
GH_TOKEN="$GH_TOKEN" python scripts/validate-agent-ready-issue.py \
  --issue-json issue.json --repo owner/name --report-file audit.md
```

A maintainer can perform a full audit by dispatching **Agent readiness** from
the Actions tab. The workflow uses only `gh api`, `jq`, and the checked-in
stdlib Python validator. Issue text is passed as JSON or an API request body;
it is never evaluated as shell code. Tokens are supplied through `GH_TOKEN`,
and the workflow grants only `issues: write` and `contents: read`.

Certification is intentionally revocable: editing the body, changing labels,
closing the issue, or making a dependency ineligible causes the next event or
full audit to remove the certification.
