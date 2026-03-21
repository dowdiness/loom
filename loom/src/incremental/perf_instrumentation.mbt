// Optional performance instrumentation for profiling reuse cursor behavior.
//
// Usage:
//   1. Import and call perf_enable(true) before the code you want to profile
//   2. Call perf_reset() to clear counters
//   3. Run your incremental parsing operations
//   4. Call perf_report() to print results or perf_snapshot() to get stats
//
// Note: This module provides the infrastructure only. To actually collect
// stats, you need to use the instrumented cursor (ReuseCursorInstrumented)
// instead of ReuseCursor, or manually add perf_* calls to the code paths
// you want to measure.

///|
pub struct PerfStats {
  enabled : Ref[Bool]
  try_reuse_calls : Ref[Int]
  try_reuse_hits : Ref[Int]
  fast_path_skips : Ref[Int]
  size_threshold_skips : Ref[Int]
  leading_checks : Ref[Int]
  trailing_checks : Ref[Int]
  find_node_calls : Ref[Int]
  find_node_steps : Ref[Int]
  count_tokens_calls : Ref[Int]
}

///|
fn PerfStats::new() -> PerfStats {
  {
    enabled: Ref::new(false),
    try_reuse_calls: Ref::new(0),
    try_reuse_hits: Ref::new(0),
    fast_path_skips: Ref::new(0),
    size_threshold_skips: Ref::new(0),
    leading_checks: Ref::new(0),
    trailing_checks: Ref::new(0),
    find_node_calls: Ref::new(0),
    find_node_steps: Ref::new(0),
    count_tokens_calls: Ref::new(0),
  }
}

///|
pub let perf_stats : PerfStats = PerfStats::new()

///|
pub fn perf_enable(enabled : Bool) -> Unit {
  perf_stats.enabled.val = enabled
}

///|
pub fn perf_reset() -> Unit {
  perf_stats.try_reuse_calls.val = 0
  perf_stats.try_reuse_hits.val = 0
  perf_stats.fast_path_skips.val = 0
  perf_stats.size_threshold_skips.val = 0
  perf_stats.leading_checks.val = 0
  perf_stats.trailing_checks.val = 0
  perf_stats.find_node_calls.val = 0
  perf_stats.find_node_steps.val = 0
  perf_stats.count_tokens_calls.val = 0
}

///|
pub fn perf_snapshot() -> PerfStats {
  perf_stats
}

///|
pub fn perf_report() -> String {
  "PerfStats { " +
  "try_reuse_calls: " +
  perf_stats.try_reuse_calls.val.to_string() +
  ", try_reuse_hits: " +
  perf_stats.try_reuse_hits.val.to_string() +
  ", fast_path_skips: " +
  perf_stats.fast_path_skips.val.to_string() +
  ", size_threshold_skips: " +
  perf_stats.size_threshold_skips.val.to_string() +
  ", leading_checks: " +
  perf_stats.leading_checks.val.to_string() +
  ", trailing_checks: " +
  perf_stats.trailing_checks.val.to_string() +
  ", find_node_calls: " +
  perf_stats.find_node_calls.val.to_string() +
  ", find_node_steps: " +
  perf_stats.find_node_steps.val.to_string() +
  ", count_tokens_calls: " +
  perf_stats.count_tokens_calls.val.to_string() +
  " }"
}

// --- Instrumented versions of key functions for profiling ---
// These mirror the production functions but collect stats.
// Use these when profiling, swap back to production for benchmarks.

///|
/// Instrumented version of count_tokens_in_node for profiling.
/// Uses the cached `token_count` field (O(1)) rather than a recursive traversal.
pub fn count_tokens_in_node_instrumented(node : @seam.CstNode) -> Int {
  if perf_stats.enabled.val {
    perf_stats.count_tokens_calls.val = perf_stats.count_tokens_calls.val + 1
  }
  node.token_count
}

///|
/// Record that a reuse candidate was skipped because its text_len was below
/// the reuse_size_threshold. Only increments when perf instrumentation is enabled.
pub fn record_size_threshold_skip() -> Unit {
  if perf_stats.enabled.val {
    perf_stats.size_threshold_skips.val = perf_stats.size_threshold_skips.val +
      1
  }
}
