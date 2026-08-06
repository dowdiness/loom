// Temporary stage-isolation benchmark for Issue #883.
//
// The immutable token, code-span, and link-index inputs are built outside each
// timed closure. Each row measures one delimiter-plan stage rather than adding
// stage times together.

///|
priv struct DelimiterPlanAttributionFixture {
  tokens : Array[InlineAnalysisToken]
  code : CodeSpanDelimiterIndex
  links : InlineLinkDelimiterIndex
  resolver_events : Array[DelimiterResolverEvent]
  resolved_state : DelimiterResolverState
  plan_events : Array[DelimiterPlanEvent]
}

///|
fn delimiter_plan_attribution_fixture(
  repeat_count : Int,
) -> DelimiterPlanAttributionFixture {
  let tokens = perf_inline_analysis_tokens(repeat_count)
  let code = build_code_span_delimiter_index(tokens)
  let links = index_inline_links(tokens, code)
  let resolver_events = build_inline_delimiter_events(tokens, code, links)
  let resolved_state = resolve_delimiter_event_state(resolver_events)
  let plan_events = build_delimiter_plan_events(resolved_state.runs)
  { tokens, code, links, resolver_events, resolved_state, plan_events }
}

///|
test "delimiter attribution: construct resolver events 2048 motifs" (
  b : @bench.T,
) {
  let fixture = delimiter_plan_attribution_fixture(2048)
  b.bench(() => {
    b.keep(
      build_inline_delimiter_events(fixture.tokens, fixture.code, fixture.links),
    )
  })
}

///|
test "delimiter attribution: resolve event state 2048 motifs" (b : @bench.T) {
  let fixture = delimiter_plan_attribution_fixture(2048)
  b.bench(() => b.keep(resolve_delimiter_event_state(fixture.resolver_events)))
}

///|
test "delimiter attribution: flatten plan events 2048 motifs" (b : @bench.T) {
  let fixture = delimiter_plan_attribution_fixture(2048)
  b.bench(() => b.keep(build_delimiter_plan_events(fixture.resolved_state.runs)))
}

///|
test "delimiter attribution: freeze plan events 2048 motifs" (b : @bench.T) {
  let fixture = delimiter_plan_attribution_fixture(2048)
  b.bench(() => b.keep(ReadOnlyArray::from_array(fixture.plan_events)))
}

///|
test "delimiter attribution: complete plan after stage split 2048 motifs" (
  b : @bench.T,
) {
  let fixture = delimiter_plan_attribution_fixture(2048)
  b.bench(() => {
    b.keep(
      build_inline_delimiter_plan(fixture.tokens, fixture.code, fixture.links),
    )
  })
}
