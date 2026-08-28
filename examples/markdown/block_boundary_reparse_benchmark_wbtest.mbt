///|
#cfg(target="js")
extern "js" fn block_boundary_bench_now_ms() -> Double =
  #| () => performance.now()

///|
#cfg(target="js")
priv struct BoundaryBenchFixture {
  source : String
  starts : Array[Int]
}

///|
#cfg(target="js")
fn boundary_bench_fixture(block_count : Int) -> BoundaryBenchFixture {
  let units = block_count / 2
  let builder = StringBuilder::new()
  let starts : Array[Int] = []
  let mut offset = 0
  for i in 0..<units {
    let heading = "## Section " + i.to_string() + "\n\n"
    builder.write_string(heading)
    offset = offset + heading.length()
    starts.push(offset)
    let paragraph = "Alpha paragraph " +
      i.to_string() +
      " has enough stable interior text for distributed edits.\n\n"
    builder.write_string(paragraph)
    offset = offset + paragraph.length()
  }
  { source: builder.to_string(), starts }
}

///|
#cfg(target="js")
fn boundary_bench_replace(
  source : String,
  position : Int,
  text : String,
) -> String {
  source[:position].to_owned() + text + source[position + 1:].to_owned()
}

///|
#cfg(target="js")
fn boundary_bench_p95(sorted : Array[Double]) -> Double {
  let rank = (sorted.length() * 95 + 99) / 100
  sorted[if rank > 0 { rank - 1 } else { 0 }]
}

///|
#cfg(target="js")
fn boundary_bench_report(
  block_count : Int,
  path : String,
  samples : Array[Double],
) -> Unit {
  let sorted = samples.copy()
  sorted.sort_by((left, right) => Compare::compare(left, right))
  println(
    "block-boundary-js-release blocks=" +
    block_count.to_string() +
    " path=" +
    path +
    " n=" +
    samples.length().to_string() +
    " median_ms=" +
    sorted[sorted.length() / 2].to_string() +
    " p95_ms=" +
    boundary_bench_p95(sorted).to_string() +
    " max_ms=" +
    sorted.last().unwrap().to_string(),
  )
}

///|
#cfg(target="js")
fn assert_boundary_benchmark_paths(
  fixture : BoundaryBenchFixture,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-block-boundary-benchmark-paths")
  let (old_cst, old_diagnostics) = try! parse_cst(source_id, fixture.source)
  let old_syntax = @seam.SyntaxNode::from_cst(old_cst)
  let position = fixture.starts[fixture.starts.length() / 2]
  for case in [(0, "O", true), (14, "X", true), (0, "#", false)] {
    let (offset, replacement, expected) = case
    let edit_position = position + offset
    let updated = boundary_bench_replace(
      fixture.source,
      edit_position,
      replacement,
    )
    let result = @core.reparse_block(
      source_id,
      old_syntax,
      updated,
      @core.Edit::replace(edit_position, edit_position + 1, edit_position + 1),
      lex_for_grammar,
      markdown_spec,
      markdown_block_reparse_spec,
      old_diagnostics,
    )
    assert_eq(result is Some(_), expected)
  }
}

///|
#cfg(target="js")
fn run_boundary_parser_benchmark(
  block_count : Int,
  path : String,
  offset : Int,
  replacement : String,
) -> Unit raise {
  let fixture = boundary_bench_fixture(block_count)
  let parser = @loom.new_syntax_parser(
    @core.SourceId("markdown-block-boundary-benchmark"),
    fixture.source,
    markdown_grammar.to_syntax_grammar(),
  )
  let samples : Array[Double] = []
  let locations = 16
  let warmups = 20
  let measured = 44
  for iteration in 0..<(warmups + measured) {
    let slot = (iteration * 7 + 3) % locations
    let fixture_index = slot * fixture.starts.length() / locations
    let position = fixture.starts[fixture_index] + offset
    let updated = boundary_bench_replace(fixture.source, position, replacement)
    let forward = @core.Edit::replace(position, position + 1, position + 1)
    let start = block_boundary_bench_now_ms()
    parser.apply_edit(forward, updated)
    let elapsed = block_boundary_bench_now_ms() - start
    parser.apply_edit(forward, fixture.source)
    if iteration >= warmups {
      samples.push(elapsed)
    }
  }
  boundary_bench_report(block_count, path, samples)
}

///|
#cfg(target="js")
fn benchmark_markdown_ancestor_of_kind(
  syntax : @seam.SyntaxNode,
  position : Int,
  kind : @seam.RawKind,
) -> @seam.SyntaxNode {
  let mut current : @seam.SyntaxNode? = Some(syntax.find_at(position))
  while current is Some(node) {
    if node.kind() == kind {
      return node
    }
    current = node.parent()
  }
  abort("benchmark candidate kind not found")
}

///|
#cfg(target="js")
fn run_boundary_phase_benchmark(block_count : Int) -> Unit raise {
  let fixture = boundary_bench_fixture(block_count)
  let source_id = @core.SourceId("markdown-block-boundary-phase-benchmark")
  let (old_cst, old_diagnostics) = try! parse_cst(source_id, fixture.source)
  let old_syntax = @seam.SyntaxNode::from_cst(old_cst)
  let locations = 16
  let updates : Array[(Int, String, @core.Edit, @core.LexResult[Token])] = []
  let splice_inputs : Array[(Array[Int], @seam.CstNode)] = []
  for slot in 0..<locations {
    let fixture_index = slot * fixture.starts.length() / locations
    let position = fixture.starts[fixture_index]
    let updated = boundary_bench_replace(fixture.source, position, "O")
    let edit = @core.Edit::replace(position, position + 1, position + 1)
    let full_lex = lex_for_grammar(source_id, updated)
    updates.push((position, updated, edit, full_lex))
    let (_, path) = @core.find_reparseable_ancestor(
      old_syntax,
      @core.Edit::replace(position + 14, position + 15, position + 15),
      kind => kind == @seam.ToRawKind::to_raw(ParagraphNode),
    ).unwrap()
    let (fresh_cst, _) = try! parse_cst(source_id, updated)
    let fresh_syntax = @seam.SyntaxNode::from_cst(fresh_cst)
    let replacement = benchmark_markdown_ancestor_of_kind(
      fresh_syntax,
      position,
      @seam.ToRawKind::to_raw(ParagraphNode),
    )
    splice_inputs.push((path, replacement.cst_node()))
  }

  let ancestor_samples : Array[Double] = []
  let detached_lex_samples : Array[Double] = []
  let block_reparse_samples : Array[Double] = []
  let isolated_parse_derived_samples : Array[Double] = []
  let splice_samples : Array[Double] = []
  let fallback_parse_samples : Array[Double] = []
  let warmups = 20
  let measured = 44
  for iteration in 0..<(warmups + measured) {
    let slot = (iteration * 7 + 3) % locations
    let (position, updated, edit, full_lex) = updates[slot]

    let start_ancestor = block_boundary_bench_now_ms()
    let candidate = @core.find_reparseable_ancestor(
      old_syntax,
      @core.Edit::replace(position + 14, position + 15, position + 15),
      kind => kind == @seam.ToRawKind::to_raw(ParagraphNode),
    )
    let ancestor_elapsed = block_boundary_bench_now_ms() - start_ancestor
    assert_true(candidate is Some(_))

    let (candidate_node, _) = candidate.unwrap()
    let block_text = updated[position:candidate_node.end()].to_owned()
    let start_lex = block_boundary_bench_now_ms()
    let detached = lex_for_grammar(source_id, block_text)
    let lex_elapsed = block_boundary_bench_now_ms() - start_lex
    assert_true(detached.tokens().length() > 0)

    let start_reparse = block_boundary_bench_now_ms()
    let reparsed = @core.reparse_block(
      source_id, old_syntax, updated, edit, lex_for_grammar, markdown_spec, markdown_block_reparse_spec,
      old_diagnostics,
    )
    let reparse_elapsed = block_boundary_bench_now_ms() - start_reparse
    assert_true(reparsed is Some(_))

    let (path, replacement) = splice_inputs[slot]
    let start_splice = block_boundary_bench_now_ms()
    let spliced = @core.splice_tree(old_cst, path, replacement)
    let splice_elapsed = block_boundary_bench_now_ms() - start_splice
    assert_eq(spliced.text_len(), updated.length())

    let tokens = full_lex.tokens()
    let starts = full_lex.starts()
    let cursor = @core.ReuseCursor::new_with_edit(
      old_cst,
      edit,
      tokens.length(),
      i => tokens[i].token,
      i => starts[i],
      i => updated[starts[i]:starts[i] + tokens[i].len],
      markdown_spec,
      reuse_size_threshold=markdown_spec.reuse_size_threshold,
      allow_left_adjacent_reuse=false,
    )
    let start_fallback = block_boundary_bench_now_ms()
    let parsed = @core.parse_tokens_indexed(
      source_id,
      updated,
      tokens.length(),
      i => tokens[i].token,
      i => starts[i],
      i => starts[i] + tokens[i].len,
      markdown_spec,
      cursor=Some(cursor),
    )
    let fallback_elapsed = block_boundary_bench_now_ms() - start_fallback
    assert_eq(parsed.0.text_len(), updated.length())

    if iteration >= warmups {
      ancestor_samples.push(ancestor_elapsed)
      detached_lex_samples.push(lex_elapsed)
      block_reparse_samples.push(reparse_elapsed)
      let isolated_residual = reparse_elapsed -
        ancestor_elapsed -
        lex_elapsed -
        splice_elapsed
      isolated_parse_derived_samples.push(
        if isolated_residual > 0.0 {
          isolated_residual
        } else {
          0.0
        },
      )
      splice_samples.push(splice_elapsed)
      fallback_parse_samples.push(fallback_elapsed)
    }
  }
  boundary_bench_report(block_count, "phase-ancestor-search", ancestor_samples)
  boundary_bench_report(block_count, "phase-detached-lex", detached_lex_samples)
  boundary_bench_report(
    block_count, "phase-block-reparse-composite", block_reparse_samples,
  )
  boundary_bench_report(
    block_count, "phase-isolated-parse-diagnostics-derived", isolated_parse_derived_samples,
  )
  boundary_bench_report(block_count, "phase-splice", splice_samples)
  boundary_bench_report(
    block_count, "phase-fallback-parse-tokens-indexed", fallback_parse_samples,
  )
}

///|
#cfg(target="js")
test "benchmark: varying-operand block boundary paths" {
  for block_count in [500, 2500] {
    assert_boundary_benchmark_paths(boundary_bench_fixture(block_count))
    run_boundary_parser_benchmark(block_count, "exact-start-admitted", 0, "O")
    run_boundary_parser_benchmark(block_count, "strict-interior", 14, "X")
    run_boundary_parser_benchmark(block_count, "ownership-fallback", 0, "#")
    run_boundary_phase_benchmark(block_count)
  }
}
