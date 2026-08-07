// Private inline-analysis stage probes for #838.
//
// Tokenization and CST emission are excluded: the immutable analysis-token
// bank is built before timing, then code-span indexing, link recognition, and
// emphasis planning are measured independently and as one pipeline.

///|
fn perf_inline_push_token(
  tokens : Array[InlineAnalysisToken],
  kind : InlineAnalysisTokenKind,
  text : String,
  start : Int,
) -> Int {
  let end = start + text.length()
  tokens.push({
    kind,
    text,
    start,
    end,
    first: first_char_in_inline_text(text.view()),
    last: last_char_in_inline_text(text.view()),
    ends_with_odd_backslashes: text_ends_with_odd_backslashes(text.view()),
  })
  end
}

///|
fn perf_inline_analysis_tokens(
  repeat_count : Int,
) -> Array[InlineAnalysisToken] {
  guard repeat_count > 0 else {
    abort("inline-analysis performance repeat count must be positive")
  }
  let tokens : Array[InlineAnalysisToken] = []
  let mut offset = 0
  for repetition = 0; repetition < repeat_count; repetition = repetition + 1 {
    ignore(repetition)
    // Emphasis surrounding a confirmed link label and destination.
    offset = perf_inline_push_token(tokens, AnalysisAsterisk, "*", offset)
    offset = perf_inline_push_token(tokens, AnalysisOther, "outer ", offset)
    offset = perf_inline_push_token(tokens, AnalysisLeftBracket, "[", offset)
    offset = perf_inline_push_token(tokens, AnalysisAsterisk, "*", offset)
    offset = perf_inline_push_token(tokens, AnalysisOther, "inner", offset)
    offset = perf_inline_push_token(tokens, AnalysisAsterisk, "*", offset)
    offset = perf_inline_push_token(tokens, AnalysisRightBracket, "]", offset)
    offset = perf_inline_push_token(tokens, AnalysisLeftParen, "(", offset)
    offset = perf_inline_push_token(tokens, AnalysisOther, "/url", offset)
    offset = perf_inline_push_token(tokens, AnalysisRightParen, ")", offset)
    offset = perf_inline_push_token(tokens, AnalysisOther, " tail", offset)
    offset = perf_inline_push_token(tokens, AnalysisAsterisk, "*", offset)
    offset = perf_inline_push_token(tokens, AnalysisOther, " ", offset)
    // Delimiters inside a code span are opaque to emphasis planning.
    offset = perf_inline_push_token(tokens, AnalysisBacktick, "`", offset)
    offset = perf_inline_push_token(tokens, AnalysisOther, "*opaque*", offset)
    offset = perf_inline_push_token(tokens, AnalysisBacktick, "`", offset)
    offset = perf_inline_push_token(tokens, AnalysisOther, " ", offset)
    // A second marker family prevents a single-marker special case.
    offset = perf_inline_push_token(tokens, AnalysisUnderscore, "_", offset)
    offset = perf_inline_push_token(tokens, AnalysisOther, "word", offset)
    offset = perf_inline_push_token(tokens, AnalysisUnderscore, "_", offset)
    offset = perf_inline_push_token(tokens, AnalysisOther, " ", offset)
  }
  tokens
}

///|
fn bench_perf_inline_code_index(b : @bench.T, repeat_count : Int) -> Unit {
  let tokens = perf_inline_analysis_tokens(repeat_count)
  b.bench(fn() { b.keep(build_code_span_delimiter_index(tokens)) })
}

///|
fn bench_perf_inline_link_index(b : @bench.T, repeat_count : Int) -> Unit {
  let tokens = perf_inline_analysis_tokens(repeat_count)
  let code = build_code_span_delimiter_index(tokens)
  b.bench(fn() { b.keep(index_inline_links(tokens, code)) })
}

///|
fn bench_perf_inline_delimiter_plan(b : @bench.T, repeat_count : Int) -> Unit {
  let tokens = perf_inline_analysis_tokens(repeat_count)
  let code = build_code_span_delimiter_index(tokens)
  let links = index_inline_links(tokens, code)
  b.bench(fn() { b.keep(build_inline_delimiter_plan(tokens, code, links)) })
}

///|
fn bench_perf_inline_analysis_pipeline(
  b : @bench.T,
  repeat_count : Int,
) -> Unit {
  let tokens = perf_inline_analysis_tokens(repeat_count)
  b.bench(fn() {
    let code = build_code_span_delimiter_index(tokens)
    let links = index_inline_links(tokens, code)
    b.keep(build_inline_delimiter_plan(tokens, code, links))
  })
}

///|
test "perf residual: inline analysis work scales with token bank" {
  let small_tokens = perf_inline_analysis_tokens(512)
  let large_tokens = perf_inline_analysis_tokens(2048)
  assert_eq(large_tokens.length(), small_tokens.length() * 4)
  let small_code = build_code_span_delimiter_index(small_tokens)
  let large_code = build_code_span_delimiter_index(large_tokens)
  let small_links = index_inline_links(small_tokens, small_code)
  let large_links = index_inline_links(large_tokens, large_code)
  let small_plan = build_inline_delimiter_plan(
    small_tokens, small_code, small_links,
  )
  let large_plan = build_inline_delimiter_plan(
    large_tokens, large_code, large_links,
  )
  assert_eq(large_plan.stats.run_count, small_plan.stats.run_count * 4)
  assert_eq(large_plan.stats.opener_checks, small_plan.stats.opener_checks * 4)
}

///|
test "issue 893: angle-free and greater-than-only facts skip autolink indexing" {
  let angle_free = perf_inline_analysis_tokens(4)
  let angle_free_code = build_code_span_delimiter_index(angle_free)
  assert_true(!angle_free_code.has_angle_open)
  assert_true(index_inline_links(angle_free, angle_free_code).autolinks is None)

  let greater_than_only : Array[InlineAnalysisToken] = []
  let mut offset = 0
  for i = 0; i < 64; i = i + 1 {
    offset = perf_inline_push_token(
      greater_than_only,
      AnalysisAngleClose,
      ">",
      offset,
    )
  }
  let greater_than_code = build_code_span_delimiter_index(greater_than_only)
  assert_true(!greater_than_code.has_angle_open)
  assert_true(
    index_inline_links(greater_than_only, greater_than_code).autolinks is None,
  )
}

///|
test "perf residual: inline code index 512 motifs" (b : @bench.T) {
  bench_perf_inline_code_index(b, 512)
}

///|
test "perf residual: inline code index 2048 motifs" (b : @bench.T) {
  bench_perf_inline_code_index(b, 2048)
}

///|
test "perf residual: inline link index 512 motifs" (b : @bench.T) {
  bench_perf_inline_link_index(b, 512)
}

///|
test "perf residual: inline link index 2048 motifs" (b : @bench.T) {
  bench_perf_inline_link_index(b, 2048)
}

///|
test "perf residual: inline delimiter plan 512 motifs" (b : @bench.T) {
  bench_perf_inline_delimiter_plan(b, 512)
}

///|
test "perf residual: inline delimiter plan 2048 motifs" (b : @bench.T) {
  bench_perf_inline_delimiter_plan(b, 2048)
}

///|
test "perf residual: complete inline analysis 512 motifs" (b : @bench.T) {
  bench_perf_inline_analysis_pipeline(b, 512)
}

///|
test "perf residual: complete inline analysis 2048 motifs" (b : @bench.T) {
  bench_perf_inline_analysis_pipeline(b, 2048)
}
