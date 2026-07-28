#!/usr/bin/env python3
"""Validate the fail-closed ``ready-for-agent`` issue certification.

The validator is deliberately limited to Markdown structure and GitHub issue
metadata.  It never interprets or executes text from an issue body.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REQUIRED_HEADINGS = (
    "Deliverable",
    "Scope",
    "Non-goals",
    "Dependencies",
    "Acceptance criteria",
    "Validation",
    "Existing API candidates",
    "API and documentation impact",
    "Stop and escalate if",
)
REJECTED_STATE_LABELS = frozenset(
    {"blocked", "needs-triage", "needs-human-decision", "in-progress"}
)
IMPACT_CHOICES = frozenset(
    {
        "None — no public API or documentation change",
        "Documentation only",
        "Public API or generated .mbti",
    }
)
HEADING_RE = re.compile(r"^###\s+(.+?)\s*$")
ISSUE_REF_RE = re.compile(r"(?<![A-Za-z0-9_./-])#([0-9]+)\b")
CROSS_REPO_REF_RE = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+")
URL_RE = re.compile(r"https?://\S+", re.IGNORECASE)
BULLET_RE = re.compile(r"^\s*[-*+]\s+(.+?)\s*$")
FENCE_OPEN_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})(?:[^\n]*)$")
UNCHECKED_RE = re.compile(r"^\s*[-*+]\s+\[ \]\s+\S", re.MULTILINE)


class OperationalError(RuntimeError):
    """A failure that means the audit could not safely reach a decision."""


@dataclass(frozen=True)
class ValidationResult:
    errors: tuple[str, ...]
    dependency_numbers: tuple[int, ...] = ()

    @property
    def ok(self) -> bool:
        return not self.errors


class IssueFetcher(Protocol):
    def fetch_issue(self, number: int) -> dict[str, Any]: ...


class GitHubIssueFetcher:
    """Small stdlib-only GitHub REST client used for dependency resolution."""

    def __init__(self, repo: str, token: str | None = None) -> None:
        self.repo = repo
        self.token = token

    def fetch_issue(self, number: int) -> dict[str, Any]:
        url = f"https://api.github.com/repos/{self.repo}/issues/{number}"
        headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": "canopy-agent-readiness",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        request = Request(url, headers=headers)
        try:
            with urlopen(request, timeout=20) as response:
                payload = json.load(response)
        except HTTPError as error:
            if error.code == 404:
                raise LookupError(f"dependency #{number} does not exist") from error
            raise OperationalError(
                f"GitHub API returned HTTP {error.code} for dependency #{number}"
            ) from error
        except (URLError, TimeoutError, OSError, json.JSONDecodeError) as error:
            raise OperationalError(
                f"could not resolve dependency #{number}: {error}"
            ) from error
        if not isinstance(payload, dict):
            raise OperationalError(f"GitHub returned invalid JSON for dependency #{number}")
        return payload


def _labels(issue: dict[str, Any]) -> set[str]:
    labels = issue.get("labels", [])
    if not isinstance(labels, list):
        return set()
    result: set[str] = set()
    for label in labels:
        if isinstance(label, str):
            result.add(label)
        elif isinstance(label, dict) and isinstance(label.get("name"), str):
            result.add(label["name"])
    return result


def _fence_open(line: str) -> tuple[str, int] | None:
    match = FENCE_OPEN_RE.match(line)
    if not match:
        return None
    delimiter = match.group(1)
    return delimiter[0], len(delimiter)


def _fence_close(line: str, character: str, minimum: int) -> bool:
    return re.fullmatch(
        rf" {{0,3}}{re.escape(character)}{{{minimum},}}[ \t]*", line
    ) is not None


def _has_fenced_block(content: str) -> bool:
    fence: tuple[str, int] | None = None
    for line in content.splitlines():
        if fence is None:
            fence = _fence_open(line)
        elif _fence_close(line, *fence):
            return True
    return False


def _body_sections(body: str) -> tuple[dict[str, str], list[str]]:
    """Return H3 sections, ignoring headings inside CommonMark fences."""
    headings: list[tuple[str, int]] = []
    fence: tuple[str, int] | None = None
    lines = body.splitlines()
    for index, line in enumerate(lines):
        if fence is not None:
            if _fence_close(line, *fence):
                fence = None
            continue
        fence = _fence_open(line)
        if fence is None:
            match = HEADING_RE.match(line)
            if match:
                headings.append((match.group(1), index))

    sections: dict[str, str] = {}
    duplicates: list[str] = []
    for position, (title, start) in enumerate(headings):
        end = headings[position + 1][1] if position + 1 < len(headings) else len(lines)
        content = "\n".join(lines[start + 1 : end]).strip()
        if title in sections:
            duplicates.append(title)
        else:
            sections[title] = content
    return sections, duplicates


def _dependency_numbers(content: str, issue_number: int) -> tuple[list[int], list[str]]:
    if content.strip() == "None":
        return [], []
    if not content.strip():
        return [], ["Dependencies must be exactly `None` or one or more bullets"]

    numbers: list[int] = []
    errors: list[str] = []
    for line in content.splitlines():
        if not line.strip():
            continue
        bullet = BULLET_RE.match(line)
        if not bullet:
            errors.append("Dependencies must contain bullets only")
            continue
        text = bullet.group(1)
        if CROSS_REPO_REF_RE.search(text) or URL_RE.search(text):
            errors.append("Dependencies may contain same-repository `#N` references only")
        refs = [int(value) for value in ISSUE_REF_RE.findall(text)]
        if not refs:
            errors.append("Each Dependencies bullet must contain a same-repository `#N` reference")
        numbers.extend(refs)

    unique = list(dict.fromkeys(numbers))
    if issue_number in unique:
        errors.append("Dependencies cannot reference the issue itself")
    return unique, errors


def validate_issue(
    issue: dict[str, Any],
    repo: str,
    fetcher: IssueFetcher | None = None,
) -> ValidationResult:
    """Validate one issue; policy failures are returned, API failures are raised."""
    errors: list[str] = []
    issue_number = issue.get("number")
    if not isinstance(issue_number, int):
        errors.append("Issue JSON must contain an integer `number`")
        issue_number = -1
    if issue.get("state") != "open":
        errors.append("Issue must be open")

    labels = _labels(issue)
    if "kind:implementation" not in labels:
        errors.append("Missing required label `kind:implementation`")
    if "ready-for-agent" not in labels:
        errors.append("Missing required label `ready-for-agent`")
    rejected = sorted(labels & REJECTED_STATE_LABELS)
    if rejected:
        errors.append("Rejected state label(s): " + ", ".join(rejected))

    body = issue.get("body")
    if not isinstance(body, str):
        errors.append("Issue body must be a string")
        body = ""
    sections, duplicates = _body_sections(body)
    for title in duplicates:
        if title in REQUIRED_HEADINGS:
            errors.append(f"Duplicate required H3 heading: {title}")
    for title in REQUIRED_HEADINGS:
        if title not in sections:
            errors.append(f"Missing required H3 heading: {title}")

    if errors and not all(title in sections for title in REQUIRED_HEADINGS):
        # Keep metadata/heading diagnostics useful, while avoiding assumptions
        # about missing sections in the remaining structural checks.
        return ValidationResult(tuple(errors))

    for title in ("Deliverable", "Scope", "Non-goals"):
        if not sections[title].strip():
            errors.append(f"{title} must be non-empty")

    dependencies, dependency_errors = _dependency_numbers(sections["Dependencies"], issue_number)
    errors.extend(dependency_errors)
    acceptance = sections["Acceptance criteria"]
    if not UNCHECKED_RE.search(acceptance):
        errors.append("Acceptance criteria must contain at least one unchecked checkbox")
    if not _has_fenced_block(sections["Validation"]):
        errors.append("Validation must contain a fenced code block")

    candidates = [line for line in sections["Existing API candidates"].splitlines() if BULLET_RE.match(line)]
    if len(candidates) < 2:
        errors.append("Existing API candidates must contain at least two bullets")
    if sections["API and documentation impact"].strip() not in IMPACT_CHOICES:
        errors.append("API and documentation impact must be one of the exact choices")
    stop_bullets = [line for line in sections["Stop and escalate if"].splitlines() if BULLET_RE.match(line)]
    if not stop_bullets:
        errors.append("Stop and escalate if must contain at least one bullet")

    if errors:
        return ValidationResult(tuple(errors), tuple(dependencies))

    if fetcher is not None:
        for number in dependencies:
            try:
                dependency = fetcher.fetch_issue(number)
            except LookupError as error:
                errors.append(str(error))
                continue
            if "pull_request" in dependency:
                errors.append(f"Dependency #{number} is a pull request")
            elif dependency.get("state") != "closed":
                errors.append(f"Dependency #{number} must be closed")

    return ValidationResult(tuple(errors), tuple(dependencies))


def render_report(issue: dict[str, Any], result: ValidationResult, repo: str) -> str:
    number = issue.get("number", "?")
    status = "CERTIFIED" if result.ok else "NOT CERTIFIED"
    lines = [
        "# Agent-readiness audit",
        "",
        f"- Repository: `{repo}`",
        f"- Issue: `#{number}`",
        f"- Result: **{status}**",
    ]
    if result.dependency_numbers:
        lines.append("- Dependencies resolved: " + ", ".join(f"`#{n}`" for n in result.dependency_numbers))
    if result.errors:
        lines.extend(["", "## Findings", ""])
        lines.extend(f"- {error}" for error in result.errors)
    else:
        lines.extend(["", "The issue satisfies the agent-readiness certification policy."])
    return "\n".join(lines) + "\n"


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--issue-json", required=True, type=Path)
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--report-file", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    try:
        with args.issue_json.open(encoding="utf-8") as handle:
            issue = json.load(handle)
        if not isinstance(issue, dict):
            raise ValueError("issue JSON must be an object")
        result = validate_issue(issue, args.repo, GitHubIssueFetcher(args.repo, os.environ.get("GH_TOKEN")))
        report = render_report(issue, result, args.repo)
        args.report_file.parent.mkdir(parents=True, exist_ok=True)
        args.report_file.write_text(report, encoding="utf-8")
        print(report, end="")
        return 0 if result.ok else 2
    except (OSError, json.JSONDecodeError, ValueError, OperationalError) as error:
        report = "# Agent-readiness audit\n\n- Result: **OPERATIONAL FAILURE**\n\n- " + str(error) + "\n"
        try:
            args.report_file.parent.mkdir(parents=True, exist_ok=True)
            args.report_file.write_text(report, encoding="utf-8")
        except OSError:
            pass
        print(report, end="")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
