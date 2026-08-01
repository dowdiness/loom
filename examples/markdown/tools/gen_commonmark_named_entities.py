#!/usr/bin/env python3
"""Regenerate the private CommonMark HTML5 named-entity lookup."""

from __future__ import annotations

import argparse
import hashlib
import html.entities
from pathlib import Path


EXPECTED_ENTITY_COUNT = 2_125
EXPECTED_ENTITY_SHA256 = "7d79fafaef218de3df2cb20cb4ddbf0790460477c3bc7df7af7f65776f2750db"


def parse_args() -> argparse.Namespace:
    tools_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=tools_dir.parent / "commonmark_named_entities.mbt",
        help="MoonBit source to generate",
    )
    return parser.parse_args()


def selected_entities() -> list[tuple[str, str]]:
    return sorted(
        (name[:-1], replacement)
        for name, replacement in html.entities.html5.items()
        if name.endswith(";")
    )


def verify_entities(entities: list[tuple[str, str]]) -> None:
    payload = "".join(f"{name}\0{replacement}\n" for name, replacement in entities)
    actual_sha256 = hashlib.sha256(payload.encode("utf-8")).hexdigest()
    if len(entities) != EXPECTED_ENTITY_COUNT or actual_sha256 != EXPECTED_ENTITY_SHA256:
        raise SystemExit(
            "unexpected Python html.entities.html5 snapshot: "
            f"expected {EXPECTED_ENTITY_COUNT} entries/{EXPECTED_ENTITY_SHA256}, "
            f"got {len(entities)} entries/{actual_sha256}"
        )


def moonbit_string(value: str) -> str:
    escaped: list[str] = []
    for character in value:
        codepoint = ord(character)
        if character == '"':
            escaped.append('\\"')
        elif character == "\\":
            escaped.append("\\\\")
        elif character == "\n":
            escaped.append("\\n")
        elif character == "\r":
            escaped.append("\\r")
        elif character == "\t":
            escaped.append("\\t")
        elif 0x20 <= codepoint <= 0x7E:
            escaped.append(character)
        else:
            escaped.append(f"\\u{{{codepoint:X}}}")
    return '"' + "".join(escaped) + '"'


def render(entities: list[tuple[str, str]]) -> str:
    entries = [
        f"  ({moonbit_string(name)}, {moonbit_string(replacement)}),"
        for name, replacement in entities
    ]
    return "\n".join(
        [
            "// AUTO-GENERATED from Python html.entities.html5.",
            "// DO NOT EDIT BY HAND.",
            "// CommonMark 0.31.2 authoritative source: https://html.spec.whatwg.org/entities.json",
            "// Generation follows commonmark/cmark 0.31.1 tools/make_entities_inc.py:",
            "// only the 2,125 semicolon-terminated HTML5 names are retained.",
            f"// Canonical name/replacement SHA-256: {EXPECTED_ENTITY_SHA256}",
            "",
            "///|",
            "let commonmark_named_entities : Map[String, String] = Map([",
            *entries,
            "])",
            "",
            "///|",
            "fn commonmark_named_entity(name : String) -> String? {",
            "  commonmark_named_entities.get(name)",
            "}",
            "",
        ]
    )


def main() -> None:
    args = parse_args()
    entities = selected_entities()
    verify_entities(entities)
    args.output.write_text(render(entities), encoding="utf-8")


if __name__ == "__main__":
    main()
