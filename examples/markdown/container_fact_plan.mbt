///|
priv struct ContainerFactPlan[T] {
  mut end_offset : Int
  actions : Map[Int, T]
  delimiters : CodeSpanDelimiterIndex
}

///|
fn new_code_span_delimiter_index() -> CodeSpanDelimiterIndex {
  { eligible_openers: Map([]), successors: Map([]) }
}

///|
fn[T] build_container_fact_plan(
  ctx : @core.ParserContext[Token, SyntaxKind],
  start_offset : Int,
  policy : InlineParsePolicy,
  handler : ContinuationHandler[T],
) -> ContainerFactPlan[T] {
  let plan : ContainerFactPlan[T] = {
    end_offset: start_offset,
    actions: Map([]),
    delimiters: new_code_span_delimiter_index(),
  }
  let previous_by_length : Map[Int, Int] = Map([])
  let mut offset = start_offset
  let mut preceding_text_ends_escaped = false
  while true {
    let (token, next_offset) = ctx.token_at(offset, 0)
    if token is EOF {
      plan.end_offset = offset
      break
    }
    match token {
      Newline =>
        match (handler.observe)(offset) {
          Stop => {
            plan.end_offset = offset
            break
          }
          Continue(action) => {
            plan.actions[offset] = action
            let advanced_offset = (handler.advance)(offset, action)
            guard advanced_offset > offset else {
              abort("container fact plan continuation did not advance")
            }
            offset = advanced_offset
            preceding_text_ends_escaped = false
            continue
          }
        }
      _ if token_is_inline_block_boundary(token, policy) => {
        plan.end_offset = offset
        break
      }
      Text(text) =>
        preceding_text_ends_escaped = text_ends_with_odd_backslashes(
          text.view(),
        )
      Backtick => {
        index_code_span_delimiter_run(
          plan.delimiters,
          previous_by_length,
          offset,
          next_offset - offset,
          !preceding_text_ends_escaped,
        )
        preceding_text_ends_escaped = false
      }
      _ => preceding_text_ends_escaped = false
    }
    guard next_offset > offset else {
      abort("container fact plan token scan did not advance")
    }
    offset = next_offset
  }
  plan
}

///|
fn build_line_container_fact_plan(
  ctx : @core.ParserContext[Token, SyntaxKind],
  start_offset : Int,
  policy : InlineParsePolicy,
) -> ContainerFactPlan[Unit] {
  let terminal_newline_handler : ContinuationHandler[Unit] = {
    consume: _ => (),
    observe: _ => Stop,
    advance: (offset, _) => offset,
  }
  build_container_fact_plan(ctx, start_offset, policy, terminal_newline_handler)
}
