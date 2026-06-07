///|
const MAX_SKELETON_ERRORS : Int = 200

///|
const MAX_ITEM_PREFIX_LOOKAHEAD : Int = 8

///|
/// Parse a coarse token-stream CST.
///
/// This is intentionally not the real MoonBit grammar yet. It establishes the
/// Loom integration points: official lexer tokens in, reusable CST nodes out.
fn parse_moonbit_root(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  consume_layout_tokens(ctx)
  while !ctx.at_eof() && ctx.error_count < MAX_SKELETON_ERRORS {
    parse_source_item(ctx)
    consume_layout_tokens(ctx)
  }
  ctx.flush_trivia()
}

///|
fn consume_layout_tokens(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  while !ctx.at_eof() && ctx.peek().is_layout_token() {
    let token = ctx.peek()
    ctx.emit_token(token.syntax_kind())
  }
}

///|
fn parse_source_item(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  let kind = source_item_node_kind(ctx)
  ctx.node(kind, fn() {
    let (consumed, group_depth) = consume_source_item_tokens(ctx)
    if group_depth > 0 {
      ctx.error(
        "moonbit skeleton parser reached item boundary with an unclosed delimiter",
      )
      ctx.emit_incomplete_placeholder()
    }
    if consumed == 0 && !ctx.at_eof() {
      ctx.error("moonbit skeleton parser made no progress")
      ctx.bump_error()
    }
  })
}

///|
fn source_item_node_kind(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> MoonbitSyntaxKind {
  for index = 0; index < MAX_ITEM_PREFIX_LOOKAHEAD; {
    let token = ctx.peek_nth(index)
    match token.source_item_node_kind() {
      Some(kind) => break kind
      None =>
        if token.is_layout_token() {
          continue index + 1
        } else if token.is_source_item_prefix() {
          continue skip_source_item_prefix(ctx, index, token)
        } else {
          break SourceItemNode
        }
    }
  } nobreak {
    SourceItemNode
  }
}

///|
fn skip_source_item_prefix(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  index : Int,
  token : MoonToken,
) -> Int {
  let next_index = index + 1
  let next = ctx.peek_nth(next_index)
  if token.accepts_source_item_prefix_group_payload() &&
    next.opens_balanced_group() {
    skip_balanced_prefix_group(ctx, next_index)
  } else if token.accepts_source_item_prefix_literal_payload() &&
    next.is_source_item_prefix_literal_payload() {
    next_index + 1
  } else {
    next_index
  }
}

///|
fn skip_balanced_prefix_group(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  group_start : Int,
) -> Int {
  for index = group_start, depth = 0; index < MAX_ITEM_PREFIX_LOOKAHEAD; {
    let token = ctx.peek_nth(index)
    let next_depth = if token.opens_balanced_group() {
      depth + 1
    } else if token.closes_balanced_group() && depth > 0 {
      depth - 1
    } else {
      depth
    }
    let next_index = index + 1
    if next_depth == 0 {
      break next_index
    }
    continue next_index, next_depth
  } nobreak {
    group_start + 1
  }
}

///|
fn consume_source_item_tokens(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  for consumed = 0, group_depth = 0; !ctx.at_eof() &&
     ctx.error_count < MAX_SKELETON_ERRORS; {
    let token = ctx.peek()
    if group_depth == 0 && token.is_item_delimiter() {
      ctx.emit_token(token.syntax_kind())
      break (consumed + 1, group_depth)
    }
    ctx.emit_token(token.syntax_kind())
    let next_depth = if token.opens_balanced_group() {
      group_depth + 1
    } else if token.closes_balanced_group() && group_depth > 0 {
      group_depth - 1
    } else {
      group_depth
    }
    continue consumed + 1, next_depth
  } nobreak {
    (consumed, group_depth)
  }
}
