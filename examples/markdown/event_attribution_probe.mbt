// Temporary package-private deterministic counters for #872. These counters
// are never enabled by production entrypoints and must be removed after the
// checked-in attribution transcript is captured.

///|
priv enum MarkdownEventAttributionLookaheadKind {
  BlockDispatchLookahead
  ParagraphContinuationLookahead
  ContainerContinuationLookahead
  InlineAnalysisLookahead
}

///|
#warnings("-unused_field")
priv struct MarkdownEventAttributionProbe {
  mut block_dispatches : Int
  mut root_paragraph_continuations : Int
  mut block_quote_paragraph_continuations : Int
  mut list_item_paragraph_continuations : Int
  mut setext_continuations : Int
  mut block_dispatch_lookaheads : Int
  mut paragraph_continuation_lookaheads : Int
  mut container_continuation_lookaheads : Int
  mut inline_analysis_lookaheads : Int
  mut inline_containers : Int
  mut inline_analysis_tokens : Int
  mut code_eligible_openers : Int
  mut code_successors : Int
  mut link_candidates : Int
  mut delimiter_runs : Int
  mut delimiter_opener_checks : Int
  mut delimiter_plan_events : Int
}

///|
#warnings("-unused_value")
fn new_markdown_event_attribution_probe() -> MarkdownEventAttributionProbe {
  {
    block_dispatches: 0,
    root_paragraph_continuations: 0,
    block_quote_paragraph_continuations: 0,
    list_item_paragraph_continuations: 0,
    setext_continuations: 0,
    block_dispatch_lookaheads: 0,
    paragraph_continuation_lookaheads: 0,
    container_continuation_lookaheads: 0,
    inline_analysis_lookaheads: 0,
    inline_containers: 0,
    inline_analysis_tokens: 0,
    code_eligible_openers: 0,
    code_successors: 0,
    link_candidates: 0,
    delimiter_runs: 0,
    delimiter_opener_checks: 0,
    delimiter_plan_events: 0,
  }
}

///|
let markdown_event_attribution_probe_ref : Ref[MarkdownEventAttributionProbe?] = Ref(
  None,
)

///|
#warnings("-unused_value")
fn[R] with_markdown_event_attribution_probe(
  probe : MarkdownEventAttributionProbe,
  body : () -> R,
) -> R {
  markdown_event_attribution_probe_ref.protect(Some(probe), body)
}

///|
fn record_markdown_block_decision(
  state : BlockContainerState,
  facts : BlockLineFacts,
) -> Unit {
  match markdown_event_attribution_probe_ref.val {
    None => ()
    Some(probe) =>
      match facts {
        BlockStart(_) => probe.block_dispatches += 1
        RootContinuation(_) =>
          if state.mode is ParagraphMode {
            probe.root_paragraph_continuations += 1
          } else {
            probe.setext_continuations += 1
          }
        BlockQuoteContinuation(_) =>
          if state.mode is ParagraphMode {
            probe.block_quote_paragraph_continuations += 1
          } else {
            probe.setext_continuations += 1
          }
        ListItemContinuation(_) =>
          if state.mode is ParagraphMode {
            probe.list_item_paragraph_continuations += 1
          } else {
            probe.setext_continuations += 1
          }
      }
  }
}

///|
fn record_markdown_inline_analysis(
  tokens : Array[InlineAnalysisToken],
  code : CodeSpanDelimiterIndex,
  links : InlineLinkDelimiterIndex,
  delimiters : DelimiterResolutionPlan,
) -> Unit {
  match markdown_event_attribution_probe_ref.val {
    None => ()
    Some(probe) => {
      probe.inline_containers += 1
      probe.inline_analysis_tokens += tokens.length()
      probe.code_eligible_openers += code.eligible_openers.length()
      probe.code_successors += code.successors.length()
      probe.link_candidates += links.candidates.length()
      probe.delimiter_runs += delimiters.stats.run_count
      probe.delimiter_opener_checks += delimiters.stats.opener_checks
      probe.delimiter_plan_events += delimiters.events.length()
    }
  }
}

///|
fn[R] markdown_event_attribution_lookahead(
  ctx : @core.ParserContext[Token, SyntaxKind],
  kind : MarkdownEventAttributionLookaheadKind,
  body : () -> R,
) -> R {
  match markdown_event_attribution_probe_ref.val {
    None => ()
    Some(probe) =>
      match kind {
        BlockDispatchLookahead => probe.block_dispatch_lookaheads += 1
        ParagraphContinuationLookahead =>
          probe.paragraph_continuation_lookaheads += 1
        ContainerContinuationLookahead =>
          probe.container_continuation_lookaheads += 1
        InlineAnalysisLookahead => probe.inline_analysis_lookaheads += 1
      }
  }
  ctx.lookahead(body)
}
