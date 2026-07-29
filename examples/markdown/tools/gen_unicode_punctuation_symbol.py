#!/usr/bin/env python3
"""Regenerate Loom's Unicode punctuation/symbol interval table."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


UNICODE_VERSION = "16.0.0"
SOURCE_NAME = f"DerivedGeneralCategory-{UNICODE_VERSION}.txt"
SOURCE_SHA256 = "7676ab755a41ef82108460238569e60ad65c191ddafe61b36c6765ec1353f293"
CATEGORIES = frozenset({"Pc", "Pd", "Pe", "Pf", "Pi", "Po", "Ps", "Sc", "Sk", "Sm", "So"})
EXPECTED_RANGE_COUNT = 349
EXPECTED_CODEPOINT_COUNT = 9_369


def parse_args() -> argparse.Namespace:
    tools_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        type=Path,
        default=tools_dir / SOURCE_NAME,
        help="pinned DerivedGeneralCategory input",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=tools_dir.parent / "unicode_punctuation_symbol.mbt",
        help="MoonBit source to generate",
    )
    return parser.parse_args()


def verify_source(path: Path) -> None:
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != SOURCE_SHA256:
        raise SystemExit(
            f"unexpected SHA-256 for {path}: expected {SOURCE_SHA256}, got {actual}"
        )


def selected_ranges(path: Path) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        data = raw_line.split("#", 1)[0].strip()
        if not data:
            continue
        codepoints, category = (part.strip() for part in data.split(";", 1))
        if category not in CATEGORIES:
            continue
        if ".." in codepoints:
            start_text, end_text = codepoints.split("..", 1)
        else:
            start_text = end_text = codepoints
        ranges.append((int(start_text, 16), int(end_text, 16)))

    merged: list[tuple[int, int]] = []
    for start, end in sorted(ranges):
        if merged and start <= merged[-1][1] + 1:
            previous_start, previous_end = merged[-1]
            merged[-1] = (previous_start, max(previous_end, end))
        else:
            merged.append((start, end))
    return merged


def render(ranges: list[tuple[int, int]]) -> str:
    codepoint_count = sum(end - start + 1 for start, end in ranges)
    if len(ranges) != EXPECTED_RANGE_COUNT or codepoint_count != EXPECTED_CODEPOINT_COUNT:
        raise SystemExit(
            "unexpected Unicode P/S table size: "
            f"expected {EXPECTED_RANGE_COUNT} ranges/{EXPECTED_CODEPOINT_COUNT} code points, "
            f"got {len(ranges)} ranges/{codepoint_count} code points"
        )

    values = [value for interval in ranges for value in interval]
    lines = []
    for offset in range(0, len(values), 12):
        lines.append("  " + ", ".join(f"0x{value:X}" for value in values[offset : offset + 12]) + ",")
    categories = ", ".join(sorted(CATEGORIES))
    source_url = (
        f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/extracted/"
        "DerivedGeneralCategory.txt"
    )
    return "\n".join(
        [
            f"// AUTO-GENERATED interval data from Unicode {UNICODE_VERSION} UCD DerivedGeneralCategory.txt.",
            "// DO NOT EDIT BY HAND.",
            f"// Source: {source_url}",
            "// Unicode data license: tools/UNICODE-LICENSE.txt",
            f"// Includes General_Category P* or S*: {codepoint_count:,} code points in {len(ranges)} inclusive ranges.",
            f"// Categories: {categories}.",
            "// Ranges are sorted, non-overlapping `[start, end, ...]` code-point pairs.",
            "",
            "///|",
            "let unicode_punctuation_symbol_ranges : Array[Int] = [",
            *lines,
            "]",
            "",
            "///|",
            "fn is_unicode_punctuation_or_symbol_codepoint(codepoint : Int) -> Bool {",
            "  let range_count = unicode_punctuation_symbol_ranges.length() / 2",
            "  let mut low = 0",
            "  let mut high = range_count",
            "  while low < high {",
            "    let middle = (low + high) / 2",
            "    if unicode_punctuation_symbol_ranges[2 * middle] > codepoint {",
            "      high = middle",
            "    } else {",
            "      low = middle + 1",
            "    }",
            "  }",
            "  guard low > 0 else { return false }",
            "  codepoint <= unicode_punctuation_symbol_ranges[(low - 1) * 2 + 1]",
            "}",
            "",
            "///|",
            "fn is_unicode_punctuation_or_symbol(ch : Char) -> Bool {",
            "  is_unicode_punctuation_or_symbol_codepoint(ch.to_int())",
            "}",
            "",
        ]
    )


def main() -> None:
    args = parse_args()
    verify_source(args.input)
    args.output.write_text(render(selected_ranges(args.input)), encoding="utf-8")


if __name__ == "__main__":
    main()
