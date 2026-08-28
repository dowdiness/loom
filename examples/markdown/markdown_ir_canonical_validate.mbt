///|
priv struct MarkdownIRCanonicalFormatStats {
  container_candidates : Int
  container_expansions : Int
  candidates : Int
  search_expansions : Int
  reparses : Int
}

///|
priv struct MarkdownIRCanonicalFormatAttempt {
  result : Result[String, MarkdownIRCanonicalFormatFailure]
  stats : MarkdownIRCanonicalFormatStats
}

///|
fn markdown_ir_canonical_empty_stats() -> MarkdownIRCanonicalFormatStats {
  {
    container_candidates: 0,
    container_expansions: 0,
    candidates: 0,
    search_expansions: 0,
    reparses: 0,
  }
}

///|
fn markdown_ir_canonical_max_string_set_length(
  sets : Array[Array[String]],
) -> Int {
  let mut maximum = 0
  for set in sets {
    maximum = maximum.max(set.length())
  }
  maximum
}

///|
fn markdown_ir_canonical_max_assignment_set_length(
  sets : Array[Array[Array[Int]]],
) -> Int {
  let mut maximum = 0
  for set in sets {
    maximum = maximum.max(set.length())
  }
  maximum
}

///|
fn markdown_ir_canonical_search_stats(
  search : MarkdownIRCanonicalSearchState,
  reparses : Int,
) -> MarkdownIRCanonicalFormatStats {
  {
    container_candidates: markdown_ir_canonical_max_string_set_length(
      search.container_seen_markdown,
    ),
    container_expansions: markdown_ir_canonical_max_assignment_set_length(
      search.container_expanded_assignments,
    ),
    candidates: search.seen_markdown.length(),
    search_expansions: search.expansions,
    reparses,
  }
}

///|
fn MarkdownIRCanonicalFormatAttempt::into_result(
  self : MarkdownIRCanonicalFormatAttempt,
) -> Result[String, MarkdownIRCanonicalFormatFailure] {
  guard self.stats.container_candidates >= 0 &&
    self.stats.container_expansions >= 0 &&
    self.stats.candidates >= 0 &&
    self.stats.search_expansions >= 0 &&
    self.stats.reparses >= 0 else {
    abort("canonical formatting statistics must be non-negative")
  }
  self.result
}

///|
fn markdown_ir_contains_task_list_item(ir : MarkdownIR) -> Bool {
  match ir.node {
    ListItem(_, _, _, _, Some(_)) | OrderedListItem(_, _, _, _, Some(_)) => true
    _ => ir.children().iter().any(markdown_ir_contains_task_list_item)
  }
}

///|
fn markdown_ir_canonical_candidate_matches(
  source_id : @core.SourceId,
  expected : MarkdownIRCanonicalSemantic,
  markdown : String,
  extensions? : MarkdownExtensions = MarkdownExtensions::none(),
) -> Bool {
  let (cst, diagnostics) = parse_cst(source_id, markdown) catch {
    _ => return false
  }
  let reparsed = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
    extensions~,
  )
  match markdown_ir_canonical_semantic(reparsed) {
    Some(actual) => actual == expected
    None => false
  }
}

///|
fn markdown_ir_canonical_format_attempt(
  source_id : @core.SourceId,
  ir : MarkdownIR,
  limits : MarkdownIRCanonicalFormatLimits,
) -> MarkdownIRCanonicalFormatAttempt {
  match ir.node {
    Document(_) => ()
    _ =>
      return {
        result: Err(ExpectedDocument),
        stats: markdown_ir_canonical_empty_stats(),
      }
  }
  match markdown_ir_first_canonical_opaque(ir) {
    Some((kind, origin)) =>
      return {
        result: Err(OpaqueNode(kind, origin)),
        stats: markdown_ir_canonical_empty_stats(),
      }
    None => ()
  }
  let expected = match markdown_ir_canonical_semantic(ir) {
    Some(expected) => expected
    None =>
      return {
        result: Err(Unrepresentable),
        stats: markdown_ir_canonical_empty_stats(),
      }
  }
  let extensions = if markdown_ir_contains_task_list_item(ir) {
    MarkdownExtensions::task_list()
  } else {
    MarkdownExtensions::none()
  }
  let plan = markdown_ir_canonical_choice_plan(ir)
  let (candidate_limit, _) = markdown_ir_canonical_document_search_limits(
    plan, limits,
  )
  let mut search = markdown_ir_canonical_search_start(ir, limits)
  let mut reparses = 0
  while true {
    match markdown_ir_canonical_search_next_layer(search, ir) {
      CandidateLayer(next, candidates) => {
        search = next
        for candidate in candidates {
          if reparses >= candidate_limit {
            return {
              result: Err(
                SearchLimitExceeded(
                  observed=candidate_limit + 1,
                  limit=candidate_limit,
                ),
              ),
              stats: markdown_ir_canonical_search_stats(search, reparses),
            }
          }
          reparses = reparses + 1
          if markdown_ir_canonical_candidate_matches(
              source_id,
              expected,
              candidate.markdown,
              extensions~,
            ) {
            return {
              result: Ok(candidate.markdown),
              stats: markdown_ir_canonical_search_stats(search, reparses),
            }
          }
        }
      }
      Exhausted(done) =>
        return {
          result: Err(Unrepresentable),
          stats: markdown_ir_canonical_search_stats(done, reparses),
        }
      ExpansionLimited(done, failure) =>
        return {
          result: Err(failure),
          stats: markdown_ir_canonical_search_stats(done, reparses),
        }
    }
  }
  abort("unreachable canonical validation search")
}

///|
/// Canonically format one semantic MarkdownIR document and prove the result by
/// reparsing it through the normal Markdown parser and diagnostic-aware
/// MarkdownIR lowering path.
///
/// A successful result preserves position- and surface-independent document
/// semantics. Non-document roots, opaque nodes, unrepresentable trees, and
/// bounded-search exhaustion return structured failures.
pub fn experimental_markdown_ir_canonical_format_checked(
  source_id : @core.SourceId,
  ir : MarkdownIR,
) -> Result[String, MarkdownIRCanonicalFormatFailure] {
  markdown_ir_canonical_format_attempt(
    source_id,
    ir,
    markdown_ir_canonical_default_limits(),
  ).into_result()
}
