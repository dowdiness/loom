#!/usr/bin/env python3
"""Measure Task 1's Markdown delimiter-prepass stop gate on wasm-gc."""

from __future__ import annotations

import argparse
import json
import platform
import random
import re
import statistics
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from typing import Final

ROOT: Final = Path(__file__).resolve().parent.parent
MARKDOWN_DIR: Final = ROOT / "examples" / "markdown"
TARGET: Final = "wasm-gc"
SEED: Final = 0xC0FFEE
RESAMPLES: Final = 10_000
LOWER_INDEX: Final = 250
UPPER_INDEX: Final = 9749
UNIT_TO_NS: Final = {"ns": 1.0, "µs": 1_000.0, "ms": 1_000_000.0}
MEAN_RE: Final = re.compile(
    r"^\s*(?P<value>\d+(?:\.\d+)?)\s+(?P<unit>ns|µs|ms)\s+±",
    re.MULTILINE,
)
FIXTURE_INDICES: Final = {
    "root": {"prepass-first": 0, "cst-first": 1},
    "block-quote": {"prepass-first": 2, "cst-first": 3},
    "list-item": {"prepass-first": 4, "cst-first": 5},
}


def parse_duration_ns(text: str) -> float:
    """Convert one Moon bench duration such as ``4.00 µs`` to nanoseconds."""
    value, unit = text.split()
    return float(value) * UNIT_TO_NS[unit]


def parse_pair_means(transcript: str) -> tuple[float, float]:
    """Read the two benchmark means emitted by one ordered pair fixture."""
    means = [
        parse_duration_ns(f"{match.group('value')} {match.group('unit')}")
        for match in MEAN_RE.finditer(transcript)
    ]
    if len(means) != 2:
        raise ValueError(f"expected exactly two benchmark means, found {len(means)}")
    return means[0], means[1]


def alternating_orders(pair_count: int) -> list[str]:
    if pair_count < 1:
        raise ValueError("pair count must be positive")
    return ["prepass-first" if pair % 2 == 0 else "cst-first" for pair in range(pair_count)]


def bootstrap_median_interval(values: list[float]) -> tuple[float, float, float]:
    if not values:
        raise ValueError("cannot bootstrap an empty sample")
    rng = random.Random(SEED)
    medians = sorted(
        statistics.median([rng.choice(values) for _ in values])
        for _ in range(RESAMPLES)
    )
    return statistics.median(values), medians[LOWER_INDEX], medians[UPPER_INDEX]


def git_revision() -> str:
    return subprocess.run(
        ["rtk", "proxy", "git", "rev-parse", "HEAD"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def run_fixture(index: int) -> tuple[float, float]:
    completed = subprocess.run(
        [
            "rtk",
            "proxy",
            "moon",
            "bench",
            "--release",
            "--package",
            "dowdiness/markdown",
            "--file",
            "prepass_benchmark_wbtest.mbt",
            "--target",
            TARGET,
            "--index",
            str(index),
        ],
        cwd=MARKDOWN_DIR,
        check=True,
        capture_output=True,
        text=True,
    )
    return parse_pair_means(completed.stdout)


def measure_fixture(name: str, pair_count: int, warmups: int) -> dict[str, object]:
    indices = FIXTURE_INDICES[name]
    for order in ("prepass-first", "cst-first"):
        for _ in range(warmups):
            run_fixture(indices[order])

    observations: list[dict[str, object]] = []
    for pair, order in enumerate(alternating_orders(pair_count), start=1):
        first_ns, second_ns = run_fixture(indices[order])
        if order == "prepass-first":
            prepass_ns, cst_ns = first_ns, second_ns
        else:
            cst_ns, prepass_ns = first_ns, second_ns
        ratio_percent = prepass_ns / cst_ns * 100.0
        observations.append(
            {
                "pair": pair,
                "order": order,
                "prepass_ns": prepass_ns,
                "cst_ns": cst_ns,
                "ratio_percent": ratio_percent,
            }
        )

    ratios = [float(observation["ratio_percent"]) for observation in observations]
    median, lower, upper = bootstrap_median_interval(ratios)
    return {
        "fixture": name,
        "warmups_per_order": warmups,
        "observations": observations,
        "median_ratio_percent": median,
        "bootstrap_95_percent_interval": [lower, upper],
        "passes_stop_gate": lower > 3.0,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pairs", type=int, default=16)
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "docs/performance/2026-07-24-markdown-prepass-stop-gate.json",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.warmups < 0:
        raise ValueError("warmup count must not be negative")
    measurements = [
        measure_fixture(name, args.pairs, args.warmups) for name in FIXTURE_INDICES
    ]
    result = {
        "schema": 1,
        "timestamp_utc": datetime.now(UTC).isoformat(),
        "commit": git_revision(),
        "target": TARGET,
        "command": "rtk proxy moon bench --release --package dowdiness/markdown --file prepass_benchmark_wbtest.mbt --target wasm-gc --index <index>",
        "pairs_per_fixture": args.pairs,
        "bootstrap": {
            "resamples": RESAMPLES,
            "seed": SEED,
            "lower_index": LOWER_INDEX,
            "upper_index": UPPER_INDEX,
            "statistic": "median ratio_percent",
        },
        "host": {
            "platform": platform.platform(),
            "python": platform.python_version(),
        },
        "fixtures": measurements,
        "decision": "proceed"
        if any(fixture["passes_stop_gate"] for fixture in measurements)
        else "stop",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
