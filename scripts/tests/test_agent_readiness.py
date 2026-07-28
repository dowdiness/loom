#!/usr/bin/env python3
import importlib.util
import json
import shutil
import subprocess
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "validate-agent-ready-issue.py"
spec = importlib.util.spec_from_file_location("agent_readiness_validator", SCRIPT)
validator = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = validator
spec.loader.exec_module(validator)


BODY = """### Deliverable
Implement the bounded change.

### Scope
Only the named package and tests.

### Non-goals
No unrelated refactor.

### Dependencies
None

### Acceptance criteria
- [ ] The observable behavior is covered.

### Validation
```sh
python -m unittest discover
```

### Existing API candidates
- `ProjectApi` — checked for reuse.
- `Array` — checked for the data shape.

### API and documentation impact
None — no public API or documentation change

### Stop and escalate if
- The public boundary must change.
"""


class FakeFetcher:
    def __init__(self, values=None, error=None):
        self.values = values or {}
        self.error = error
        self.calls = []

    def fetch_issue(self, number):
        self.calls.append(number)
        if self.error is not None:
            raise self.error
        if number not in self.values:
            raise LookupError(f"dependency #{number} does not exist")
        return self.values[number]


def issue(**changes):
    result = {
        "number": 100,
        "state": "open",
        "body": BODY,
        "labels": [
            {"name": "kind:implementation"},
            {"name": "ready-for-agent"},
        ],
    }
    result.update(changes)
    return result


class AgentReadinessTests(unittest.TestCase):
    def assert_policy(self, current, text):
        result = validator.validate_issue(current, "owner/repo", FakeFetcher())
        self.assertFalse(result.ok)
        self.assertTrue(any(text in error for error in result.errors), result.errors)

    def test_valid_issue(self):
        result = validator.validate_issue(issue(), "owner/repo", FakeFetcher())
        self.assertTrue(result.ok, result.errors)

    def test_duplicate_heading_is_rejected(self):
        self.assert_policy(issue(body=BODY.replace("### Scope\n", "### Scope\n### Scope\n")), "Duplicate")

    def test_missing_heading_is_rejected(self):
        self.assert_policy(issue(body=BODY.replace("### Non-goals\nNo unrelated refactor.\n\n", "")), "Missing required H3 heading: Non-goals")

    def test_heading_inside_tilde_fence_does_not_satisfy_policy(self):
        body = BODY.replace(
            "### Dependencies\nNone\n\n",
            "~~~markdown\n### Dependencies\nNone\n~~~\n\n",
        )
        self.assert_policy(issue(body=body), "Missing required H3 heading: Dependencies")

    def test_tilde_fenced_validation_is_accepted(self):
        body = BODY.replace(
            "```sh\npython -m unittest discover\n```",
            "~~~sh\npython -m unittest discover\n~~~",
        )
        result = validator.validate_issue(issue(body=body), "owner/repo", FakeFetcher())
        self.assertTrue(result.ok, result.errors)

    def test_duplicate_unrelated_heading_is_allowed(self):
        body = "### Background\nFirst note.\n\n### Background\nSecond note.\n\n" + BODY
        result = validator.validate_issue(issue(body=body), "owner/repo", FakeFetcher())
        self.assertTrue(result.ok, result.errors)

    def test_wrong_required_labels_are_rejected(self):
        self.assert_policy(issue(labels=[{"name": "kind:feature"}, {"name": "ready-for-agent"}]), "kind:implementation")

    def test_rejected_state_label_is_rejected(self):
        self.assert_policy(issue(labels=[{"name": "kind:implementation"}, {"name": "ready-for-agent"}, {"name": "blocked"}]), "blocked")

    def test_closed_dependency_is_accepted(self):
        body = BODY.replace("None\n\n### Acceptance", "- #12 — prerequisite\n\n### Acceptance")
        result = validator.validate_issue(issue(body=body), "owner/repo", FakeFetcher({12: {"state": "closed"}}))
        self.assertTrue(result.ok, result.errors)

    def test_open_dependency_is_rejected(self):
        body = BODY.replace("None\n\n### Acceptance", "- #12 — prerequisite\n\n### Acceptance")
        self.assert_policy_with_fetcher(issue(body=body), FakeFetcher({12: {"state": "open"}}), "must be closed")

    def test_pull_request_dependency_is_rejected(self):
        body = BODY.replace("None\n\n### Acceptance", "- #12 — prerequisite\n\n### Acceptance")
        self.assert_policy_with_fetcher(issue(body=body), FakeFetcher({12: {"state": "closed", "pull_request": {}}}), "pull request")

    def test_missing_dependency_is_rejected(self):
        body = BODY.replace("None\n\n### Acceptance", "- #12 — prerequisite\n\n### Acceptance")
        self.assert_policy_with_fetcher(issue(body=body), FakeFetcher(), "does not exist")

    def test_dependency_api_failure_is_operational(self):
        body = BODY.replace("None\n\n### Acceptance", "- #12 — prerequisite\n\n### Acceptance")
        with self.assertRaises(validator.OperationalError):
            validator.validate_issue(issue(body=body), "owner/repo", FakeFetcher(error=validator.OperationalError("rate limited")))

    def test_self_dependency_is_rejected(self):
        body = BODY.replace("None\n\n### Acceptance", "- #100 — itself\n\n### Acceptance")
        self.assert_policy(issue(body=body), "itself")

    def test_foreign_dependency_reference_is_rejected(self):
        body = BODY.replace("None\n\n### Acceptance", "- other/repo#12\n\n### Acceptance")
        self.assert_policy(issue(body=body), "same-repository")

    def test_exact_impact_choices_are_enforced(self):
        body = BODY.replace("None — no public API or documentation change", "No public API change")
        self.assert_policy(issue(body=body), "exact choices")

    def test_unchecked_acceptance_criterion_is_required(self):
        body = BODY.replace("- [ ] The observable behavior is covered.", "- [x] The observable behavior is covered.")
        self.assert_policy(issue(body=body), "unchecked checkbox")

    def test_two_api_candidates_are_required(self):
        body = BODY.replace("- `Array` — checked for the data shape.\n", "")
        self.assert_policy(issue(body=body), "at least two")

    def test_closed_issue_is_rejected(self):
        self.assert_policy(issue(state="closed"), "Issue must be open")

    def test_stop_section_requires_a_bullet(self):
        body = BODY.replace("- The public boundary must change.\n", "The public boundary must change.\n")
        self.assert_policy(issue(body=body), "at least one bullet")

    def test_workflow_serializes_markdown_comment_as_raw_text(self):
        workflow = SCRIPT.parents[1] / ".github/workflows/agent-readiness.yml"
        self.assertIn("jq -Rs --arg marker", workflow.read_text())
        if shutil.which("jq") is None:
            self.skipTest("jq is not installed")
        report = "# Agent-readiness audit\n\n- Result: **CERTIFIED**\n"
        completed = subprocess.run(
            [
                "jq",
                "-Rs",
                "--arg",
                "marker",
                "<!-- agent-readiness-bot -->",
                '{body: ($marker + "\\n\\n" + .)}',
            ],
            input=report,
            text=True,
            check=True,
            capture_output=True,
        )
        payload = json.loads(completed.stdout)
        self.assertEqual(
            payload["body"],
            "<!-- agent-readiness-bot -->\n\n" + report,
        )

    def assert_policy_with_fetcher(self, current, fetcher, text):
        result = validator.validate_issue(current, "owner/repo", fetcher)
        self.assertFalse(result.ok)
        self.assertTrue(any(text in error for error in result.errors), result.errors)


if __name__ == "__main__":
    unittest.main()
