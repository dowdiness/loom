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
    let (header_consumed, header_depth) = parse_source_item_header(ctx, kind)
    let (body_consumed, group_depth) = if header_depth > 0 {
      (0, header_depth)
    } else {
      consume_source_item_tokens(ctx)
    }
    if group_depth > 0 {
      ctx.error(
        "moonbit skeleton parser reached item boundary with an unclosed delimiter",
      )
      ctx.emit_incomplete_placeholder()
    }
    if header_consumed + body_consumed == 0 && !ctx.at_eof() {
      ctx.error("moonbit skeleton parser made no progress")
      ctx.bump_error()
    }
  })
}

///|
fn parse_source_item_header(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  item_kind : MoonbitSyntaxKind,
) -> (Int, Int) {
  match item_kind.item_header_kind() {
    Some(header_kind) => {
      let mut result = (0, 0)
      ctx.node(header_kind, fn() {
        result = consume_source_item_header_tokens(ctx, item_kind)
      })
      result
    }
    None => (0, 0)
  }
}

///|
fn consume_source_item_header_tokens(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  item_kind : MoonbitSyntaxKind,
) -> (Int, Int) {
  for consumed = 0, group_depth = 0, type_keyword_seen = false, type_name_seen = false, prefix_group_payload_pending = false, prefix_literal_payload_pending = false; !ctx.at_eof() &&
     ctx.error_count < MAX_SKELETON_ERRORS; {
    let token = ctx.peek()
    let prefix_payload = group_depth == 0 &&
      (
        (prefix_group_payload_pending && token.opens_balanced_group()) ||
        (
          prefix_literal_payload_pending &&
          token.is_source_item_prefix_literal_payload()
        )
      )
    if group_depth == 0 &&
      !prefix_payload &&
      (
        token.is_item_delimiter() ||
        token.starts_item_body(item_kind) ||
        (
          item_kind == TypeItemNode &&
          token.starts_legacy_type_body(type_name_seen)
        )
      ) {
      break (consumed, group_depth)
    }
    ctx.emit_token(token.syntax_kind())
    let keep_prefix_payload_pending = group_depth == 0 &&
      token.is_layout_token()
    let next_prefix_group_payload_pending = if keep_prefix_payload_pending {
      prefix_group_payload_pending
    } else if prefix_payload || group_depth > 0 {
      false
    } else {
      token.accepts_source_item_prefix_group_payload()
    }
    let next_prefix_literal_payload_pending = if keep_prefix_payload_pending {
      prefix_literal_payload_pending
    } else if prefix_payload || group_depth > 0 {
      false
    } else {
      token.accepts_source_item_prefix_literal_payload()
    }
    continue consumed + 1,
      token.next_group_depth(group_depth),
      type_keyword_seen ||
      (item_kind == TypeItemNode && token.is_type_item_keyword()),
      type_name_seen ||
      (
        item_kind == TypeItemNode &&
        type_keyword_seen &&
        group_depth == 0 &&
        token.is_type_header_name()
      ),
      next_prefix_group_payload_pending,
      next_prefix_literal_payload_pending
  } nobreak {
    (consumed, group_depth)
  }
}

///|
fn source_item_node_kind(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> MoonbitSyntaxKind {
  for index = 0, meaningful = 0; meaningful < MAX_ITEM_PREFIX_LOOKAHEAD; {
    let token = ctx.peek_nth(index)
    match token.source_item_node_kind() {
      Some(kind) => break kind
      None =>
        if token.is_layout_token() {
          continue index + 1, meaningful
        } else if token.is_source_item_prefix() {
          continue skip_source_item_prefix(ctx, index, token), meaningful + 1
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
  let next_index = skip_layout_from(ctx, index + 1)
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
fn skip_layout_from(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  index : Int,
) -> Int {
  let mut next_index = index
  while ctx.peek_nth(next_index).is_layout_token() {
    next_index = next_index + 1
  }
  next_index
}

///|
fn skip_balanced_prefix_group(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  group_start : Int,
) -> Int {
  for index = group_start, depth = 0, meaningful = 0; meaningful <
     MAX_ITEM_PREFIX_LOOKAHEAD; {
    let token = ctx.peek_nth(index)
    let next_index = index + 1
    if token.is_layout_token() {
      continue next_index, depth, meaningful
    }
    let next_depth = token.next_group_depth(depth)
    if next_depth == 0 {
      break next_index
    }
    continue next_index, next_depth, meaningful + 1
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
    continue consumed + 1, token.next_group_depth(group_depth)
  } nobreak {
    (consumed, group_depth)
  }
}
