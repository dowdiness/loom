// Benchmarks for layout-heavy source-backed zero-width boundary-token reuse.
//
// Run: cd loom && NEW_MOON_MOD=0 moon bench --release -p dowdiness/loom/core
//
// These cases reuse the zero-width property fixture grammar but keep the timed
// body to parser-event production only: each iteration creates a fresh
// ReuseCursor/ParserContext, drives the incremental grammar, and skips CST
// rebuilding so the measured work is boundary validation plus reuse advance.

///|
struct ZeroWidthBoundaryBenchmarkFixture {
  shape : ZeroWidthReuseShape
  mode : ZeroWidthOldTreeMode
  item_count : Int
  boundary_count : Int
  source : String
  old_tree : @seam.CstNode
  edit : Edit
  tokens : Array[TokenInfo[TestTok]]
  starts : Array[Int]
  cache : OldTokenCache
  use_repeat_groups : Bool
}

///|
fn zero_width_bench_summary(
  fixture : ZeroWidthBoundaryBenchmarkFixture,
) -> String {
  "shape=" +
  @debug.to_string(fixture.shape) +
  " mode=" +
  @debug.to_string(fixture.mode) +
  " items=" +
  fixture.item_count.to_string() +
  " boundary_count=" +
  fixture.boundary_count.to_string()
}

///|
fn zero_width_bench_warm_cache(
  old_tree : @seam.CstNode,
  edit : Edit,
  tokens : Array[TokenInfo[TestTok]],
  starts : Array[Int],
  source : String,
  spec : LanguageSpec[TestTok, TestKind],
) -> OldTokenCache {
  let cache = OldTokenCache::empty()
  cache.apply_source_edit(edit)
  let cursor = ReuseCursor::new_with_edit(
    old_tree,
    edit,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { starts[i] },
    fn(i) {
      source.view(start_offset=starts[i], end_offset=starts[i] + tokens[i].len)
    },
    spec,
    old_token_cache=cache,
  )
  let _ = cursor.old_zero_width_tokens_at_boundary(source.length())
  cache
}

///|
fn zero_width_bench_case(
  shape : ZeroWidthReuseShape,
  mode : ZeroWidthOldTreeMode,
  item_count : Int,
  boundary_count : Int,
) -> ZeroWidthBoundaryCase {
  guard item_count > 0 else {
    abort("zero-width boundary benchmark requires at least one item")
  }
  guard boundary_count >= 0 else {
    abort("zero-width boundary benchmark count must be non-negative")
  }
  let old_values = zero_width_default_values(item_count)
  let new_values = old_values.copy()
  new_values[0] = (old_values[0] + 8) % 10
  let old_gaps = zero_width_default_gaps(item_count, 1)
  let old_boundary_counts = Array::make(item_count, boundary_count)
  let case = {
    shape,
    old_tree_mode: mode,
    edit_kind: EditItemDigit,
    item_count,
    edit_index: 0,
    synthetic_count: 0,
    old_values,
    new_values,
    old_gaps,
    new_gaps: old_gaps.copy(),
    old_boundary_counts,
    new_boundary_counts: old_boundary_counts.copy(),
  }
  zero_width_validate_case(case)
  case
}

///|
fn zero_width_bench_fixture(
  shape : ZeroWidthReuseShape,
  mode : ZeroWidthOldTreeMode,
  item_count : Int,
  boundary_count : Int,
) -> ZeroWidthBoundaryBenchmarkFixture {
  let case = zero_width_bench_case(shape, mode, item_count, boundary_count)
  let old_src = zero_width_source(case.old_values, case.old_gaps)
  let new_src = zero_width_source(case.new_values, case.new_gaps)
  let edit = zero_width_edit_from_sources(old_src, new_src)
  let use_repeat_groups = zero_width_shape_uses_repeat_groups(shape)
  let old_spec = zero_width_boundary_spec(use_repeat_groups, 0)
  let old_tree = zero_width_parse_old_tree(
    old_src,
    case.old_boundary_counts,
    old_spec,
    mode,
  )
  let has_repeat_group = zero_width_contains_repeat_group(old_tree)
  match shape {
    RegularNodes =>
      if has_repeat_group {
        abort("regular benchmark unexpectedly built a RepeatGroup")
      }
    RepeatGroups =>
      if !has_repeat_group {
        abort("RepeatGroup benchmark did not build a RepeatGroup")
      }
  }
  let tokens = zero_width_tokenize_with_boundaries(
    new_src,
    case.new_boundary_counts,
  )
  let starts = build_starts(tokens)
  let cache = zero_width_bench_warm_cache(
    old_tree, edit, tokens, starts, new_src, old_spec,
  )
  {
    shape,
    mode,
    item_count,
    boundary_count,
    source: new_src,
    old_tree,
    edit,
    tokens,
    starts,
    cache,
    use_repeat_groups,
  }
}

///|
fn zero_width_bench_cursor(
  fixture : ZeroWidthBoundaryBenchmarkFixture,
  spec : LanguageSpec[TestTok, TestKind],
) -> ReuseCursor[TestTok, TestKind] {
  ReuseCursor::new_with_edit(
    fixture.old_tree,
    fixture.edit,
    fixture.tokens.length(),
    fn(i) { fixture.tokens[i].token },
    fn(i) { fixture.starts[i] },
    fn(i) {
      fixture.source.view(
        start_offset=fixture.starts[i],
        end_offset=fixture.starts[i] + fixture.tokens[i].len,
      )
    },
    spec,
    old_token_cache=fixture.cache,
  )
}

///|
fn zero_width_bench_parse_events(
  fixture : ZeroWidthBoundaryBenchmarkFixture,
) -> (Int, Int, Int) {
  let repeat_group_hits = [0]
  let spec = zero_width_boundary_spec(
    fixture.use_repeat_groups,
    0,
    repeat_group_hits=Some(repeat_group_hits),
  )
  let ctx = ParserContext::new_indexed(
    fixture.tokens.length(),
    fn(i) { fixture.tokens[i].token },
    fn(i) { fixture.starts[i] },
    fn(i) { fixture.starts[i] + fixture.tokens[i].len },
    fixture.source,
    spec,
  )
  ctx.set_reuse_cursor(zero_width_bench_cursor(fixture, spec))
  (spec.parse_root)(ctx)
  ctx.flush_trivia()
  if ctx.open_nodes != 0 {
    abort("zero-width boundary benchmark left nodes open")
  }
  if !ctx.at_eof() {
    abort("zero-width boundary benchmark did not consume the token stream")
  }
  (ctx.reuse_count, repeat_group_hits[0], ctx.events.length())
}

///|
fn zero_width_bench_boundary_reuse(
  b : @bench.T,
  shape : ZeroWidthReuseShape,
  mode : ZeroWidthOldTreeMode,
  item_count : Int,
  boundary_count : Int,
) -> Unit {
  let fixture = zero_width_bench_fixture(
    shape, mode, item_count, boundary_count,
  )
  let summary = zero_width_bench_summary(fixture)
  let expected_min_reuse = match fixture.shape {
    RegularNodes => fixture.item_count - 1
    RepeatGroups => 1
  }
  let expected_min_repeat_hits = match fixture.shape {
    RegularNodes => 0
    RepeatGroups => 1
  }
  b.bench(fn() {
    let (reuse_count, repeat_group_hits, event_count) = zero_width_bench_parse_events(
      fixture,
    )
    if reuse_count < expected_min_reuse {
      abort("expected reuse in zero-width benchmark: " + summary)
    }
    if repeat_group_hits < expected_min_repeat_hits {
      abort("expected RepeatGroup reuse in zero-width benchmark: " + summary)
    }
    b.keep(reuse_count + repeat_group_hits + event_count)
  })
}

///|
test "bench: zero-width boundary reuse regular items=8 old=plain zw=0" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RegularNodes, PlainOldTree, 8, 0)
}

///|
test "bench: zero-width boundary reuse regular items=8 old=plain zw=1" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RegularNodes, PlainOldTree, 8, 1)
}

///|
test "bench: zero-width boundary reuse regular items=8 old=plain zw=2" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RegularNodes, PlainOldTree, 8, 2)
}

///|
test "bench: zero-width boundary reuse regular items=8 old=plain zw=4" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RegularNodes, PlainOldTree, 8, 4)
}

///|
test "bench: zero-width boundary reuse regular items=8 old=plain zw=8" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RegularNodes, PlainOldTree, 8, 8)
}

///|
test "bench: zero-width boundary reuse regular items=8 old=plain zw=16" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RegularNodes, PlainOldTree, 8, 16)
}

///|
test "bench: zero-width boundary reuse repeat items=64 old=plain zw=0" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RepeatGroups, PlainOldTree, 64, 0)
}

///|
test "bench: zero-width boundary reuse repeat items=64 old=plain zw=1" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RepeatGroups, PlainOldTree, 64, 1)
}

///|
test "bench: zero-width boundary reuse repeat items=64 old=plain zw=2" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RepeatGroups, PlainOldTree, 64, 2)
}

///|
test "bench: zero-width boundary reuse repeat items=64 old=plain zw=4" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RepeatGroups, PlainOldTree, 64, 4)
}

///|
test "bench: zero-width boundary reuse repeat items=64 old=plain zw=8" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RepeatGroups, PlainOldTree, 64, 8)
}

///|
test "bench: zero-width boundary reuse repeat items=64 old=plain zw=16" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RepeatGroups, PlainOldTree, 64, 16)
}

///|
test "bench: zero-width boundary reuse regular items=4 old=plain zw=8" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RegularNodes, PlainOldTree, 4, 8)
}

///|
test "bench: zero-width boundary reuse repeat items=16 old=plain zw=8" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RepeatGroups, PlainOldTree, 16, 8)
}

///|
test "bench: zero-width boundary reuse regular items=8 old=token-interned zw=16" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RegularNodes, TokenInternedOldTree, 8, 16)
}

///|
test "bench: zero-width boundary reuse regular items=8 old=fully-interned zw=16" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RegularNodes, FullyInternedOldTree, 8, 16)
}

///|
test "bench: zero-width boundary reuse repeat items=64 old=token-interned zw=16" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RepeatGroups, TokenInternedOldTree, 64, 16)
}

///|
test "bench: zero-width boundary reuse repeat items=64 old=fully-interned zw=16" (
  b : @bench.T,
) {
  zero_width_bench_boundary_reuse(b, RepeatGroups, FullyInternedOldTree, 64, 16)
}
