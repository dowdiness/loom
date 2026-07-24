#!/usr/bin/env python3
"""Tests for the Task 1 Markdown prepass measurement protocol."""

from __future__ import annotations

import unittest

from measure_markdown_prepass import (
    alternating_orders,
    bootstrap_median_interval,
    parse_duration_ns,
    parse_pair_means,
)


class MeasurementProtocolTest(unittest.TestCase):
    def test_parse_duration_normalizes_bench_units_to_nanoseconds(self) -> None:
        self.assertEqual(parse_duration_ns("400 ns"), 400.0)
        self.assertEqual(parse_duration_ns("4.00 µs"), 4_000.0)
        self.assertEqual(parse_duration_ns("1.5 ms"), 1_500_000.0)

    def test_parse_duration_accepts_all_repository_benchmark_units(self) -> None:
        self.assertEqual(parse_duration_ns("4.00 us"), 4_000.0)
        self.assertEqual(parse_duration_ns("4.00 μs"), 4_000.0)
        self.assertEqual(parse_duration_ns("1.5 s"), 1_500_000_000.0)

    def test_parse_pair_means_accepts_alternate_microseconds_and_seconds(self) -> None:
        transcript = """
time (mean ± σ)         range (min … max)
   4.00 us ± 178.80 ns     3.80 us …   4.26 us  in 10 × 25131 runs
  53.71 s ±   7.93 s    39.61 s …  65.91 s  in 10 × 3190 runs
"""
        self.assertEqual(parse_pair_means(transcript), (4_000.0, 53_710_000_000.0))

    def test_parse_pair_means_reads_both_benchmark_means(self) -> None:
        transcript = """
time (mean ± σ)         range (min … max)
   4.00 µs ± 178.80 ns     3.80 µs …   4.26 µs  in 10 × 25131 runs
  53.71 µs ±   7.93 µs    39.61 µs …  65.91 µs  in 10 × 3190 runs
"""
        self.assertEqual(parse_pair_means(transcript), (4_000.0, 53_710.0))

    def test_alternating_orders_counterbalance_sixteen_pairs(self) -> None:
        self.assertEqual(
            alternating_orders(16),
            ["prepass-first", "cst-first"] * 8,
        )

    def test_bootstrap_interval_uses_the_fixed_seed_and_percentiles(self) -> None:
        self.assertEqual(
            bootstrap_median_interval([1.0, 2.0, 3.0, 4.0]),
            (2.5, 1.0, 4.0),
        )


if __name__ == "__main__":
    unittest.main()
