///|
/// Container-local token facts for one indexed inline parse.
priv struct ContainerFactPlan[T] {
  delimiters : CodeSpanDelimiterIndex
  actions : Map[Int, T]
  end_offset : Int
}

///|
fn[T] build_container_fact_plan(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  handler : ContinuationHandler[T]?,
) -> ContainerFactPlan[T] {
  let delimiters : CodeSpanDelimiterIndex = {
    eligible_openers: {},
    successors: {},
  }
  let previous_by_length : Map[Int, Int] = {}
  let actions : Map[Int, T] = {}
  let mut offset = ctx.current_token_range().start
  let mut preceding_text_ends_escaped = false
  while true {
    let (token, end) = ctx.token_at(offset, 0)
    if token == EOF || token_is_inline_block_boundary(token, policy) {
      break
    }
    match token {
      Newline =>
        match handler {
          Some(handler) =>
            match (handler.observe)(offset) {
            Continue(action) => {
              let next_offset = (handler.advance)(offset, action)
              guard next_offset > offset else {
                abort("continuation fact advance did not progress")
              }
              actions[offset] = action
              offset = next_offset
              preceding_text_ends_escaped = false
              }
              Stop => break
            }
          None => break
        }
      Text(text) => {
        preceding_text_ends_escaped = text_ends_with_odd_backslashes(text.view())
        offset = end
      }
      Backtick => {
        index_code_span_delimiter_run(
          delimiters,
          previous_by_length,
          offset,
          end - offset,
          !preceding_text_ends_escaped,
        )
        preceding_text_ends_escaped = false
        offset = end
      }
      _ => {
        preceding_text_ends_escaped = false
        offset = end
      }
    }
  }
  { delimiters, actions, end_offset: offset }
}
