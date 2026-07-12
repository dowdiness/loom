#!/usr/bin/env python3
"""Verify backtick @pkg.Symbol mentions against committed pkg.generated.mbti files."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DOC_EXCLUDE_PREFIXES = (
    "_build",
    ".claude",
    "docs/archive",
    "docs/decisions",
    "incr",
    "egglog",
    "egraph",
    "event-graph-walker",
    ".mooncakes",
    ".worktrees",
)
DOC_EXCLUDE_FILES = frozenset(
    {"docs/performance/benchmark_history.md", "ROADMAP.md"}
)

PKG_SKIP_PREFIXES = ("/_build/", "/.mooncakes/", "/.claude/", "/.worktrees/")

PROPOSED_START = "<!-- docs:proposed-api -->"
PROPOSED_END = "<!-- /docs:proposed-api -->"
LINE_SKIP = "<!-- docs:skip-symbol-check -->"

BACKTICK_RE = re.compile(r"`(@[A-Za-z_][A-Za-z0-9_]*\.[^`]+)`")
IMPORT_RE = re.compile(r'"([^"]+)"(?:\s+@([A-Za-z_][A-Za-z0-9_]*))?')


def default_alias(package_path: str) -> str:
    tail = package_path.strip().split("/")[-1]
    return tail.split("@")[0]


def package_dir_for_path(package_path: str) -> Path | None:
    rel = package_path
    if rel.startswith("dowdiness/"):
        rel = rel[len("dowdiness/") :]

    candidates: list[Path] = []
    if package_path.startswith("dowdiness/loom/"):
        candidates.append(ROOT / "loom" / package_path[len("dowdiness/loom/") :])
    if rel.startswith("lambda/"):
        candidates.append(ROOT / "examples" / rel)
    if rel.startswith("json/"):
        candidates.append(ROOT / "examples" / rel)
    if rel.startswith("markdown/"):
        candidates.append(ROOT / "examples" / rel)
    if rel.startswith("html/"):
        candidates.append(ROOT / "examples" / rel)
    if rel == "incr":
        candidates.append(ROOT / "incr" / "incr")
    elif rel.startswith("incr/"):
        candidates.append(ROOT / "incr" / rel)

    candidates.append(ROOT / rel)

    for candidate in candidates:
        if (candidate / "pkg.generated.mbti").is_file():
            return candidate
    return None


def build_alias_map() -> dict[str, list[Path(),
    Path]]:
    alias_map: dict[str, list[Path]] = {}

    def add(alias: str, directory: Path) -> None:
        mbti = directory / "pkg.generated.mbti"
        if not mbti.is_file():
            return
        paths = alias_map.setdefault(alias, [])
        if mbti not in paths:
            paths.append(mbti)

    for moon_pkg in ROOT.rglob("moon.pkg"):
        if any(skip in moon_pkg.as_posix() for skip in PKG_SKIP_PREFIXES):
            continue
        text = moon_pkg.read_text(encoding="utf-8")
        for match in IMPORT_RE.finditer(text):
            package_path, explicit = match.group(1), match.group(2)
            alias = explicit or default_alias(package_path)
            directory = package_dir_for_path(package_path)
            if directory is not None:
                add(alias, directory)

    for moon_mod in ROOT.rglob("moon.mod"):
        if any(skip in moon_mod.as_posix() for skip in PKG_SKIP_PREFIXES):
            continue
        directory = moon_mod.parent
        for line in moon_mod.read_text(encoding="utf-8").splitlines():
            if line.startswith('name = "'):
                package_path = line.split('"')[1]
                add(default_alias(package_path), directory)
                break

    for mbti in ROOT.rglob("pkg.generated.mbti"):
        if any(skip in mbti.as_posix() for skip in PKG_SKIP_PREFIXES):
            continue
        directory = mbti.parent
        package_line = next(
            (
                line
                for line in mbti.read_text(encoding="utf-8").splitlines()
                if line.startswith('package "')
            ),
            None,
        )
        if package_line:
            package_path = package_line.split('"')[1]
            add(default_alias(package_path), directory)
        elif directory != ROOT:
            add(directory.name, directory)

    return alias_map


def load_allowlist() -> set[str]:
    path = ROOT / "docs" / "symbol-check-allowlist.txt"
    if not path.is_file():
        return set()
    entries: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        entries.add(stripped)
    return entries


def should_scan_doc(path: Path) -> bool:
    rel = path.relative_to(ROOT).as_posix()
    if rel in DOC_EXCLUDE_FILES:
        return False
    # Prefix-based exclusion (root-level directories)
    for prefix in DOC_EXCLUDE_PREFIXES:
        if rel == prefix or rel.startswith(prefix + "/"):
            return False
    # Component-aware exclusion: reject .worktrees at any depth
    if "/.worktrees/" in rel:
        return False
    return True


def strip_generics(text: str) -> str:
    while "[" in text:
        start = text.find("[")
        depth = 0
        for index, char in enumerate(text[start:], start=start):
            if char == "[":
                depth += 1
            elif char == "]":
                depth -= 1
                if depth == 0:
                    text = text[:start] + text[index + 1 :]
                    break
        else:
            break
    return text


def normalize_symbol(raw: str) -> str | None:
    symbol = raw.strip()
    if not symbol or "*" in symbol:
        return None
    if " for " in symbol:
        symbol = symbol.split(" for ", 1)[0].strip()
    if "(" in symbol:
        symbol = symbol[: symbol.index("(")].strip()
    symbol = strip_generics(symbol)
    if symbol.endswith("..."):
        symbol = symbol[:-3].strip()
    # Member/method chains like lambda_grammar.spec or Type::method — verify root.
    if "." in symbol and "::" not in symbol.split(".", 1)[0]:
        symbol = symbol.split(".", 1)[0]
    if not symbol or "*" in symbol:
        return None
    return symbol


def parse_token(token: str) -> tuple[str, str] | None:
    if not token.startswith("@") or "." not in token:
        return None
    pkg, _, rest = token[1:].partition(".")
    symbol = normalize_symbol(rest)
    if not symbol:
        return None
    return pkg, symbol


def proposed_mask(lines: list[str]) -> list[bool]:
    skip = [False] * len(lines)
    in_proposed = False
    for index, line in enumerate(lines):
        if PROPOSED_START in line:
            in_proposed = True
        if in_proposed:
            skip[index] = True
        if PROPOSED_END in line:
            in_proposed = False
    return skip


def line_skipped(lines: list[str], line_index: int) -> bool:
    if LINE_SKIP in lines[line_index]:
        return True
    if line_index > 0 and LINE_SKIP in lines[line_index - 1]:
        return True
    return False


def symbol_exists(symbol: str, mbti_text: str) -> bool:
    if symbol in mbti_text:
        return True

    if "::" in symbol:
        type_name, method = symbol.split("::", 1)
        if re.search(rf"\b{re.escape(type_name)}::{re.escape(method)}\b", mbti_text):
            return True
        if re.search(rf"\btrait {re.escape(type_name)}\b", mbti_text) and re.search(
            rf"\bfn {re.escape(method)}\b", mbti_text
        ):
            return True
        symbol = type_name

    patterns = [
        rf"\bstruct {re.escape(symbol)}\b",
        rf"\benum {re.escape(symbol)}\b",
        rf"\btrait {re.escape(symbol)}\b",
        rf"\bsuberror {re.escape(symbol)}\b",
        rf"\btype {re.escape(symbol)}\b",
        rf"\bfn {re.escape(symbol)}\b",
        rf"\bfn\[.*?]\s+{re.escape(symbol)}\b",
        rf"\blet {re.escape(symbol)}\b",
        rf"\{{type {re.escape(symbol)}\}}",
        rf"\{{trait {re.escape(symbol)}\}}",
    ]
    return any(re.search(pattern, mbti_text) for pattern in patterns)


def main() -> int:
    allowlist = load_allowlist()
    alias_map = build_alias_map()
    mbti_texts = {
        path: path.read_text(encoding="utf-8")
        for paths in alias_map.values()
        for path in paths
    }

    checked = 0
    skipped_unknown_pkg = 0
    skipped_hatch = 0
    failures: list[str] = []

    for doc in sorted(ROOT.rglob("*.md")):
        if not should_scan_doc(doc):
            continue
        rel = doc.relative_to(ROOT).as_posix()
        lines = doc.read_text(encoding="utf-8").splitlines()
        proposed = proposed_mask(lines)

        for line_index, line in enumerate(lines):
            if proposed[line_index] or line_skipped(lines, line_index):
                for _match in BACKTICK_RE.finditer(line):
                    skipped_hatch += 1
                continue

            for match in BACKTICK_RE.finditer(line):
                token = match.group(1)
                if token in allowlist:
                    skipped_hatch += 1
                    continue

                parsed = parse_token(token)
                if parsed is None:
                    continue

                pkg, symbol = parsed
                mbti_paths = alias_map.get(pkg)
                if not mbti_paths:
                    skipped_unknown_pkg += 1
                    continue

                checked += 1
                if any(symbol_exists(symbol, mbti_texts[path]) for path in mbti_paths):
                    continue

                failures.append(f"{rel}:{line_index + 1} — {token} (pkg @{pkg})")

    if failures:
        print("  Backtick symbol misses:")
        for failure in failures:
            print(f"  ✗ {failure}")
        print(
            f"  ({checked} checked, {skipped_unknown_pkg} unknown-pkg skips, "
            f"{skipped_hatch} allowlisted/marked)"
        )
        return 1

    print(
        f"  ✓ All backtick @pkg.Symbol mentions resolve "
        f"({checked} checked, {skipped_unknown_pkg} unknown-pkg skips, "
        f"{skipped_hatch} allowlisted/marked)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
