///|
fn markdown_ir_canonical_benchmark_ir_from_source(
  source_id : @core.SourceId,
  source : String,
) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("canonical benchmark source failed to parse")
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn markdown_ir_canonical_benchmark_origin() -> MarkdownIROrigin {
  MarkdownIROrigin::MarkdownIROrigin(start=0, end=1)
}

///|
fn markdown_ir_canonical_bounded_failure_ir() -> MarkdownIR {
  let origin = markdown_ir_canonical_benchmark_origin()
  MarkdownIR::document(
    [
      MarkdownIR::paragraph(
        [MarkdownIR::text("*a*", origin)],
        origin,
        Some(origin),
      ),
    ],
    origin,
  )
}

///|
fn markdown_ir_canonical_bounded_failure_limits() -> MarkdownIRCanonicalFormatLimits {
  markdown_ir_canonical_limits(
    max_container_candidates=100,
    max_container_expansions=100,
    max_document_candidates_per_container=1,
    max_document_expansions_per_container=100,
  )
}

///|
priv struct MarkdownIRCanonicalBenchmarkCase {
  label : String
  source_id : @core.SourceId
  ir : MarkdownIR
  limits : MarkdownIRCanonicalFormatLimits
}

///|
fn markdown_ir_canonical_benchmark_cases() -> Array[
  MarkdownIRCanonicalBenchmarkCase,
] {
  [
    {
      label: "first-candidate success",
      source_id: @core.SourceId("markdown-canonical-benchmark:first-candidate"),
      ir: markdown_ir_canonical_benchmark_ir_from_source(
        @core.SourceId("markdown-canonical-benchmark:first-candidate"),
        "plain text\n",
      ),
      limits: markdown_ir_canonical_default_limits(),
    },
    {
      label: "late success",
      source_id: @core.SourceId("markdown-canonical-benchmark:late-success"),
      ir: markdown_ir_canonical_benchmark_ir_from_source(
        @core.SourceId("markdown-canonical-benchmark:late-success"),
        "\\*a\\*\n",
      ),
      limits: markdown_ir_canonical_default_limits(),
    },
    {
      label: "bounded failure",
      source_id: @core.SourceId("markdown-canonical-benchmark:bounded-failure"),
      ir: markdown_ir_canonical_bounded_failure_ir(),
      limits: markdown_ir_canonical_bounded_failure_limits(),
    },
    {
      label: "flat adjacency",
      source_id: @core.SourceId("markdown-canonical-benchmark:flat-adjacency"),
      ir: markdown_ir_canonical_benchmark_ir_from_source(
        @core.SourceId("markdown-canonical-benchmark:flat-adjacency"),
        "_a_*b*\n",
      ),
      limits: markdown_ir_canonical_default_limits(),
    },
    {
      label: "recursive nesting",
      source_id: @core.SourceId(
        "markdown-canonical-benchmark:recursive-nesting",
      ),
      ir: markdown_ir_canonical_benchmark_ir_from_source(
        @core.SourceId("markdown-canonical-benchmark:recursive-nesting"),
        "**x *y **z** y* x**\n",
      ),
      limits: markdown_ir_canonical_default_limits(),
    },
    {
      label: "marker-backslash-heavy text",
      source_id: @core.SourceId("markdown-canonical-benchmark:marker-heavy"),
      ir: markdown_ir_canonical_benchmark_ir_from_source(
        @core.SourceId("markdown-canonical-benchmark:marker-heavy"),
        "\\*\\_\\[\\]\\(\\)\\&\\<\\>\\`\\\\\n",
      ),
      limits: markdown_ir_canonical_default_limits(),
    },
    {
      label: "link-code opacity",
      source_id: @core.SourceId("markdown-canonical-benchmark:link-code"),
      ir: markdown_ir_canonical_benchmark_ir_from_source(
        @core.SourceId("markdown-canonical-benchmark:link-code"),
        "[\\*literal\\* and `code * _`](u)\n",
      ),
      limits: markdown_ir_canonical_default_limits(),
    },
    {
      label: "Unicode punctuation",
      source_id: @core.SourceId("markdown-canonical-benchmark:unicode"),
      ir: markdown_ir_canonical_benchmark_ir_from_source(
        @core.SourceId("markdown-canonical-benchmark:unicode"),
        "。_a_→*b*😈\n",
      ),
      limits: markdown_ir_canonical_default_limits(),
    },
  ]
}

///|
fn markdown_ir_canonical_benchmark_result_tag(
  result : Result[String, MarkdownIRCanonicalFormatFailure],
) -> String {
  match result {
    Ok(_) => "ok"
    Err(ExpectedDocument) => "expected-document"
    Err(OpaqueNode(_, _)) => "opaque"
    Err(Unrepresentable) => "unrepresentable"
    Err(SearchLimitExceeded(observed~, limit~)) =>
      "limit-" + observed.to_string() + "-" + limit.to_string()
  }
}

///|
fn markdown_ir_canonical_benchmark_signature(
  case : MarkdownIRCanonicalBenchmarkCase,
) -> String {
  let attempt = markdown_ir_canonical_format_attempt(
    case.source_id,
    case.ir,
    case.limits,
  )
  let buf = StringBuilder::StringBuilder()
  buf.write_string(case.label)
  buf.write_char(':')
  buf.write_string(attempt.stats.container_candidates.to_string())
  buf.write_char('/')
  buf.write_string(attempt.stats.container_expansions.to_string())
  buf.write_char('/')
  buf.write_string(attempt.stats.candidates.to_string())
  buf.write_char('/')
  buf.write_string(attempt.stats.search_expansions.to_string())
  buf.write_char('/')
  buf.write_string(attempt.stats.reparses.to_string())
  buf.write_char('/')
  buf.write_string(markdown_ir_canonical_benchmark_result_tag(attempt.result))
  buf.to_string()
}

///|
test "checked canonical benchmark operation counts stay deterministic" {
  let signatures = markdown_ir_canonical_benchmark_cases().map(
    markdown_ir_canonical_benchmark_signature,
  )
  inspect(
    signatures.join("\n"),
    content=(
      #|first-candidate success:0/0/1/1/1/ok
      #|late success:3/2/2/3/2/ok
      #|bounded failure:3/2/2/3/1/limit-2-1
      #|flat adjacency:4/3/3/4/2/ok
      #|recursive nesting:4/1/1/4/1/ok
      #|marker-backslash-heavy text:3/2/2/3/2/ok
      #|link-code opacity:3/2/2/3/2/ok
      #|Unicode punctuation:3/1/1/3/1/ok
    ),
  )
}

///|
fn benchmark_markdown_ir_canonical_checked(
  b : @bench.T,
  case : MarkdownIRCanonicalBenchmarkCase,
) -> Unit {
  b.bench(() => {
    b.keep(
      markdown_ir_canonical_format_attempt(case.source_id, case.ir, case.limits).result,
    )
  })
}

///|
test "markdown canonical checked first-candidate success" (b : @bench.T) {
  benchmark_markdown_ir_canonical_checked(
    b,
    markdown_ir_canonical_benchmark_cases()[0],
  )
}

///|
test "markdown canonical checked late success" (b : @bench.T) {
  benchmark_markdown_ir_canonical_checked(
    b,
    markdown_ir_canonical_benchmark_cases()[1],
  )
}

///|
test "markdown canonical checked bounded failure" (b : @bench.T) {
  benchmark_markdown_ir_canonical_checked(
    b,
    markdown_ir_canonical_benchmark_cases()[2],
  )
}

///|
test "markdown canonical checked flat adjacency" (b : @bench.T) {
  benchmark_markdown_ir_canonical_checked(
    b,
    markdown_ir_canonical_benchmark_cases()[3],
  )
}

///|
test "markdown canonical checked recursive nesting" (b : @bench.T) {
  benchmark_markdown_ir_canonical_checked(
    b,
    markdown_ir_canonical_benchmark_cases()[4],
  )
}

///|
test "markdown canonical checked marker-backslash-heavy text" (b : @bench.T) {
  benchmark_markdown_ir_canonical_checked(
    b,
    markdown_ir_canonical_benchmark_cases()[5],
  )
}

///|
test "markdown canonical checked link-code opacity" (b : @bench.T) {
  benchmark_markdown_ir_canonical_checked(
    b,
    markdown_ir_canonical_benchmark_cases()[6],
  )
}

///|
test "markdown canonical checked Unicode punctuation" (b : @bench.T) {
  benchmark_markdown_ir_canonical_checked(
    b,
    markdown_ir_canonical_benchmark_cases()[7],
  )
}
