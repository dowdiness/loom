// Throwaway white-box evidence for #890.
//
// This file proves that production angle classification can feed one wrapper
// around the existing code/link/emphasis delimiter plan. It is intentionally
// test-only and does not change production parser behavior or public APIs.

///|
priv struct PrototypeAngleFact {
  kind : InlineAngleKind
  start : Int
  end : Int
}

///|
priv enum PrototypeAnglePath {
  NoAnglePath
  ClassifiedAnglePath(Array[PrototypeAngleFact])
}

///|
priv struct PrototypeCombinedInlinePlan {
  delimiters : DelimiterResolutionPlan
  angles : PrototypeAnglePath
}

///|
fn prototype_production_angle_path(
  source : String,
  angle_trigger : Bool,
) -> PrototypeAnglePath {
  // The trigger is a fact already observed by the production lexer. Keeping
  // this guard before index construction is the angle-free allocation gate.
  guard angle_trigger else { return NoAnglePath }
  let delimiter_index = build_inline_angle_delimiter_index(source)
  let facts : Array[PrototypeAngleFact] = []
  let mut cursor = 0
  while cursor < source.length() {
    if source.code_unit_at(cursor).to_int() == 0x3C {
      match
        classify_inline_angle_at_with_index(
          source,
          cursor,
          Some(delimiter_index),
        ) {
        Some(candidate) => {
          facts.push({ kind: candidate.kind, start: cursor, end: candidate.end })
          cursor = candidate.end
        }
        None => cursor = cursor + 1
      }
    } else {
      cursor = cursor + 1
    }
  }
  ClassifiedAnglePath(facts)
}

///|
fn prototype_combined_inline_plan(
  tokens : Array[InlineAnalysisToken],
  code_delimiters : CodeSpanDelimiterIndex,
  links : InlineLinkDelimiterIndex,
  angles : PrototypeAnglePath,
) -> PrototypeCombinedInlinePlan {
  // Classification belongs to the lexer shell. The plan consumes those facts
  // rather than scanning or classifying the source a second time.
  {
    delimiters: build_inline_delimiter_plan(tokens, code_delimiters, links),
    angles,
  }
}

///|
fn prototype_angle_kind_label(kind : InlineAngleKind) -> String {
  match kind {
    UriAutolink => "uri"
    EmailAutolink => "email"
    InlineHtmlAngle => "html"
  }
}

///|
fn prototype_angle_path_signature(
  source : String,
  path : PrototypeAnglePath,
) -> String {
  match path {
    NoAnglePath => "no-angle-path"
    ClassifiedAnglePath(facts) => {
      let parts : Array[String] = []
      for fact in facts {
        parts.push(
          prototype_angle_kind_label(fact.kind) +
          "=" +
          source[fact.start:fact.end].to_owned(),
        )
      }
      parts.join("|")
    }
  }
}

///|
fn prototype_phase2_tokens() -> Array[InlineAnalysisToken] {
  let tokens = perf_inline_analysis_tokens(1)
  let mut offset = match tokens.last() {
    Some(token) => token.end
    None => 0
  }
  // Add one image so the combined artifact covers both link ownership forms.
  offset = perf_inline_push_token(tokens, AnalysisOther, "!", offset)
  offset = perf_inline_push_token(tokens, AnalysisLeftBracket, "[", offset)
  offset = perf_inline_push_token(tokens, AnalysisOther, "image", offset)
  offset = perf_inline_push_token(tokens, AnalysisRightBracket, "]", offset)
  offset = perf_inline_push_token(tokens, AnalysisLeftParen, "(", offset)
  offset = perf_inline_push_token(tokens, AnalysisOther, "/image", offset)
  ignore(perf_inline_push_token(tokens, AnalysisRightParen, ")", offset))
  tokens
}

///|
test "prototype seam uses the production classifier fixture matrix" {
  let cases : Array[(String, String)] = [
    ("<http://foo.bar.baz>", "uri=<http://foo.bar.baz>"),
    ("<foo@bar.example.com>", "email=<foo@bar.example.com>"),
    ("<i>", "html=<i>"),
    ("</i>", "html=</i>"),
    ("<!-- comment -->", "html=<!-- comment -->"),
    (
      "<a title=\"line one\nline two\">", "html=<a title=\"line one\nline two\">",
    ),
    (
      "<http://foo.bar.baz><i></i>", "uri=<http://foo.bar.baz>|html=<i>|html=</i>",
    ),
    ("<a h*#ref=\"hi\">", ""),
    ("< a>", ""),
    ("<bar/ >", ""),
    ("</a href=\"foo\">", ""),
    ("plain text", "no-angle-path"),
  ]
  for angle_case in cases {
    let (source, expected) = angle_case
    let path = prototype_production_angle_path(source, source.has_prefix("<"))
    inspect(prototype_angle_path_signature(source, path), content=expected)
  }
}

///|
test "prototype seam composes production code link image emphasis and angle facts" {
  let tokens = prototype_phase2_tokens()
  let code_delimiters = build_code_span_delimiter_index(tokens)
  let links = index_inline_links(tokens, code_delimiters)
  let source = "<http://foo.bar.baz><i></i>"
  let combined = prototype_combined_inline_plan(
    tokens,
    code_delimiters,
    links,
    prototype_production_angle_path(source, true),
  )
  assert_true(combined.delimiters.stats.run_count > 0)
  assert_true(links.candidates.any(candidate => !candidate.is_image))
  assert_true(links.candidates.any(candidate => candidate.is_image))
  match combined.angles {
    ClassifiedAnglePath(facts) => {
      assert_eq(facts.length(), 3)
      match (facts[0].kind, facts[1].kind, facts[2].kind) {
        (UriAutolink, InlineHtmlAngle, InlineHtmlAngle) => ()
        _ => fail("unexpected production-classified angle kinds")
      }
    }
    NoAnglePath => fail("expected production-classified angle facts")
  }
}

///|
test "prototype seam keeps the angle-free path before index allocation" {
  let source = angle_free_inline_workload(64)
  match prototype_production_angle_path(source, false) {
    NoAnglePath => ()
    ClassifiedAnglePath(_) => fail("angle-free input entered the angle path")
  }
}

///|
test "prototype seam indexes one shared closer endpoint per opener" {
  let opener_count = 4096
  let source = prototype_shared_closer_source(opener_count)
  let delimiter_index = build_inline_angle_delimiter_index(source)
  for opener = 0; opener < opener_count; opener = opener + 1 {
    match delimiter_index.angle_delimiters.get(opener) {
      Some(snapshot) =>
        assert_eq(snapshot.greater_than_end, Some(source.length()))
      None => fail("missing shared-closer index entry")
    }
  }
}

///|
fn prototype_angle_heavy_source(repeat_count : Int) -> String {
  let builder = StringBuilder::new()
  for index = 0; index < repeat_count; index = index + 1 {
    builder.write_string("<https://example.com/")
    builder.write_string(index.to_string())
    builder.write_string("><i></i>")
  }
  builder.to_string()
}

///|
fn prototype_shared_closer_source(repeat_count : Int) -> String {
  let builder = StringBuilder::new()
  for index = 0; index < repeat_count; index = index + 1 {
    builder.write_char('<')
  }
  builder.write_string("a>")
  builder.to_string()
}

///|
fn benchmark_production_delimiter_control(
  b : @bench.T,
  tokens : Array[InlineAnalysisToken],
  code_delimiters : CodeSpanDelimiterIndex,
  links : InlineLinkDelimiterIndex,
) -> Unit {
  b.bench(() => {
    b.keep(build_inline_delimiter_plan(tokens, code_delimiters, links))
  })
}

///|
fn benchmark_prototype_angle_path(b : @bench.T, source : String) -> Unit {
  b.bench(() => b.keep(prototype_production_angle_path(source, true)))
}

///|
fn benchmark_prototype_combined_plan(
  b : @bench.T,
  tokens : Array[InlineAnalysisToken],
  code_delimiters : CodeSpanDelimiterIndex,
  links : InlineLinkDelimiterIndex,
  angles : PrototypeAnglePath,
) -> Unit {
  b.bench(() => {
    b.keep(
      prototype_combined_inline_plan(tokens, code_delimiters, links, angles),
    )
  })
}

///|
test "prototype seam control A: production delimiter plan 512 motifs" (
  b : @bench.T,
) {
  let tokens = perf_inline_analysis_tokens(512)
  let code_delimiters = build_code_span_delimiter_index(tokens)
  let links = index_inline_links(tokens, code_delimiters)
  benchmark_production_delimiter_control(b, tokens, code_delimiters, links)
}

///|
test "prototype seam control A repeat: production delimiter plan 512 motifs" (
  b : @bench.T,
) {
  let tokens = perf_inline_analysis_tokens(512)
  let code_delimiters = build_code_span_delimiter_index(tokens)
  let links = index_inline_links(tokens, code_delimiters)
  benchmark_production_delimiter_control(b, tokens, code_delimiters, links)
}

///|
test "prototype seam: angle-free combined plan 512 motifs" (b : @bench.T) {
  let tokens = perf_inline_analysis_tokens(512)
  let code_delimiters = build_code_span_delimiter_index(tokens)
  let links = index_inline_links(tokens, code_delimiters)
  benchmark_prototype_combined_plan(
    b,
    tokens,
    code_delimiters,
    links,
    NoAnglePath,
  )
}

///|
test "prototype seam: angle-heavy combined plan 512 motifs" (b : @bench.T) {
  let tokens = perf_inline_analysis_tokens(512)
  let code_delimiters = build_code_span_delimiter_index(tokens)
  let links = index_inline_links(tokens, code_delimiters)
  let angles = prototype_production_angle_path(
    prototype_angle_heavy_source(512),
    true,
  )
  benchmark_prototype_combined_plan(b, tokens, code_delimiters, links, angles)
}

///|
test "prototype seam: shared angle closer path 1024 openers" (b : @bench.T) {
  benchmark_prototype_angle_path(b, prototype_shared_closer_source(1024))
}

///|
test "prototype seam: shared angle closer path 4096 openers" (b : @bench.T) {
  benchmark_prototype_angle_path(b, prototype_shared_closer_source(4096))
}

///|
test "prototype seam: shared angle closer path 16384 openers" (b : @bench.T) {
  benchmark_prototype_angle_path(b, prototype_shared_closer_source(16384))
}

///|
test "prototype seam: shared angle closer combined plan 4096 openers" (
  b : @bench.T,
) {
  let tokens = perf_inline_analysis_tokens(512)
  let code_delimiters = build_code_span_delimiter_index(tokens)
  let links = index_inline_links(tokens, code_delimiters)
  let angles = prototype_production_angle_path(
    prototype_shared_closer_source(4096),
    true,
  )
  benchmark_prototype_combined_plan(b, tokens, code_delimiters, links, angles)
}
