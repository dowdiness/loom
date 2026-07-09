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
  while !ctx.at_eof() && !ctx.too_many_errors(MAX_SKELETON_ERRORS) {
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
        result = parse_source_item_header_tokens(ctx, item_kind)
      })
      result
    }
    None => (0, 0)
  }
}

///|
fn parse_source_item_header_tokens(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  item_kind : MoonbitSyntaxKind,
) -> (Int, Int) {
  match item_kind {
    LetItemNode => parse_let_item_header(ctx)
    FunctionItemNode => parse_function_item_header(ctx)
    StructItemNode => parse_struct_item_header(ctx)
    EnumItemNode => parse_enum_item_header(ctx)
    TypeItemNode => parse_type_item_header(ctx)
    _ => (0, 0)
  }
}

///|
fn parse_item_header_with(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  is_keyword : (MoonToken) -> Bool,
  parse_tail : (@core.ParserContext[MoonToken, MoonbitSyntaxKind]) -> (Int, Int),
) -> (Int, Int) {
  let (prefix_consumed, prefix_depth) = parse_source_item_prefixes(ctx)
  if prefix_depth > 0 {
    (prefix_consumed, prefix_depth)
  } else {
    let keyword_consumed = consume_item_header_keyword(ctx, is_keyword)
    let (tail_consumed, tail_depth) = parse_tail(ctx)
    (prefix_consumed + keyword_consumed + tail_consumed, tail_depth)
  }
}

///|
fn parse_let_item_header(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  parse_item_header_with(
    ctx,
    fn(token) { token.is_let_item_keyword() },
    parse_let_item_header_tail,
  )
}

///|
fn parse_function_item_header(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  parse_item_header_with(
    ctx,
    fn(token) { token.is_function_item_keyword() },
    parse_function_item_header_tail,
  )
}

///|
fn parse_struct_item_header(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  parse_item_header_with(
    ctx,
    fn(token) { token.is_struct_item_keyword() },
    parse_struct_item_header_tail,
  )
}

///|
fn parse_enum_item_header(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  parse_item_header_with(
    ctx,
    fn(token) { token.is_enum_item_keyword() },
    parse_enum_item_header_tail,
  )
}

///|
fn parse_type_item_header(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  parse_item_header_with(
    ctx,
    fn(token) { token.is_type_item_keyword() },
    parse_type_item_header_tail,
  )
}

///|
fn parse_let_item_header_tail(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  consume_header_tokens_until(ctx, fn(token) { token.starts_let_item_body() })
}

///|
fn parse_function_item_header_tail(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  consume_header_tokens_until(ctx, fn(token) {
    token.starts_function_item_body()
  })
}

///|
fn parse_struct_item_header_tail(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  consume_header_tokens_until(ctx, fn(token) { token.starts_struct_item_body() })
}

///|
fn parse_enum_item_header_tail(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  consume_header_tokens_until(ctx, fn(token) { token.starts_enum_item_body() })
}

///|
fn consume_item_header_keyword(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  is_item_keyword : (MoonToken) -> Bool,
) -> Int {
  if !ctx.at_eof() && is_item_keyword(ctx.peek()) {
    let token = ctx.peek()
    ctx.emit_token(token.syntax_kind())
    1
  } else {
    0
  }
}

///|
fn parse_source_item_prefixes(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  for consumed = 0; !ctx.at_eof() && !ctx.too_many_errors(MAX_SKELETON_ERRORS); {
    let token = ctx.peek()
    if token.is_layout_token() {
      ctx.emit_token(token.syntax_kind())
      continue consumed + 1
    }
    if token.is_source_item_prefix() {
      ctx.emit_token(token.syntax_kind())
      let (payload_consumed, payload_depth) = parse_source_item_prefix_payload(
        ctx, token,
      )
      if payload_depth > 0 {
        break (consumed + 1 + payload_consumed, payload_depth)
      }
      continue consumed + 1 + payload_consumed
    }
    break (consumed, 0)
  } nobreak {
    (consumed, 0)
  }
}

///|
fn parse_source_item_prefix_payload(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  prefix : MoonToken,
) -> (Int, Int) {
  if prefix.accepts_source_item_prefix_group_payload() {
    parse_group_prefix_payload(ctx)
  } else if prefix.accepts_source_item_prefix_literal_payload() {
    parse_literal_prefix_payload(ctx)
  } else {
    (0, 0)
  }
}

///|
fn parse_group_prefix_payload(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  let layout_consumed = consume_header_layout_tokens(ctx)
  if !ctx.at_eof() && ctx.peek().opens_balanced_group() {
    let (payload_consumed, payload_depth) = consume_balanced_header_group(ctx)
    (layout_consumed + payload_consumed, payload_depth)
  } else {
    (layout_consumed, 0)
  }
}

///|
fn parse_literal_prefix_payload(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  let layout_consumed = consume_header_layout_tokens(ctx)
  if !ctx.at_eof() && ctx.peek().is_source_item_prefix_literal_payload() {
    let token = ctx.peek()
    ctx.emit_token(token.syntax_kind())
    (layout_consumed + 1, 0)
  } else {
    (layout_consumed, 0)
  }
}

///|
fn consume_header_layout_tokens(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Int {
  for consumed = 0; !ctx.at_eof() && ctx.peek().is_layout_token(); {
    let token = ctx.peek()
    ctx.emit_token(token.syntax_kind())
    continue consumed + 1
  } nobreak {
    consumed
  }
}

///|
fn consume_balanced_header_group(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  for consumed = 0, group_depth = 0; !ctx.at_eof() &&
     !ctx.too_many_errors(MAX_SKELETON_ERRORS); {
    let token = ctx.peek()
    ctx.emit_token(token.syntax_kind())
    let next_depth = token.next_group_depth(group_depth)
    if next_depth == 0 {
      break (consumed + 1, next_depth)
    }
    continue consumed + 1, next_depth
  } nobreak {
    (consumed, group_depth)
  }
}

///|
fn consume_header_tokens_until(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
  starts_item_body : (MoonToken) -> Bool,
) -> (Int, Int) {
  for consumed = 0, group_depth = 0; !ctx.at_eof() &&
     !ctx.too_many_errors(MAX_SKELETON_ERRORS); {
    let token = ctx.peek()
    if group_depth == 0 &&
      (token.is_item_delimiter() || starts_item_body(token)) {
      break (consumed, group_depth)
    }
    ctx.emit_token(token.syntax_kind())
    continue consumed + 1, token.next_group_depth(group_depth)
  } nobreak {
    (consumed, group_depth)
  }
}

///|
fn parse_type_item_header_tail(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  for consumed = 0, group_depth = 0, type_name_seen = false; !ctx.at_eof() &&
     !ctx.too_many_errors(MAX_SKELETON_ERRORS); {
    let token = ctx.peek()
    if group_depth == 0 &&
      (
        token.is_item_delimiter() ||
        token.starts_type_item_body() ||
        token.starts_legacy_type_body_after_name(type_name_seen)
      ) {
      break (consumed, group_depth)
    }
    ctx.emit_token(token.syntax_kind())
    continue consumed + 1,
      token.next_group_depth(group_depth),
      type_name_seen || (group_depth == 0 && token.is_type_header_name())
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
  for next_index = index; ctx.peek_nth(next_index).is_layout_token(); {
    continue next_index + 1
  } nobreak {
    next_index
  }
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

///| Consume body tokens of a source item. At group_depth 0, dispatches

///| context-sensitive constructs (block, if, match) and breaks on item

///|
/// delimiters. Inside balanced groups, emits tokens flat.
fn consume_source_item_tokens(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> (Int, Int) {
  for consumed = 0, group_depth = 0; !ctx.at_eof() &&
     !ctx.too_many_errors(MAX_SKELETON_ERRORS); {
    let token = ctx.peek()
    if group_depth == 0 {
      if token.is_item_delimiter() {
        ctx.emit_token(token.syntax_kind())
        break (consumed + 1, group_depth)
      }
      match token {
        Official(kind=TK_LBRACE) => {
          ignore(parse_block_expr(ctx))
          continue consumed + 1, 0
        }
        Official(kind=TK_IF) => {
          ignore(parse_if_expr(ctx))
          continue consumed + 1, 0
        }
        Official(kind=TK_MATCH) => {
          ignore(parse_match_expr(ctx))
          continue consumed + 1, 0
        }
        _ => ()
      }
    }
    ctx.emit_token(token.syntax_kind())
    continue consumed + 1, token.next_group_depth(group_depth)
  } nobreak {
    (consumed, group_depth)
  }
}

///|
/// Check if the current token is `{`.
fn is_lbrace(token : MoonToken) -> Bool {
  token is Official(kind=TK_LBRACE)
}

///|
/// Check if the current token is `}`.
fn is_rbrace(token : MoonToken) -> Bool {
  token is Official(kind=TK_RBRACE)
}

///|
/// Parse a `match expr { arm; arm; ... }` expression.
fn parse_match_expr(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  ctx.node(MatchExprNode, fn() {
    ctx.emit_token(MatchToken)
    consume_until_body(ctx)
    if !ctx.at_eof() && is_lbrace(ctx.peek()) {
      ignore(parse_block_expr(ctx))
    }
  })
}

///|
/// Parse a `while cond { body }` expression.
fn parse_while_expr(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  ctx.node(WhileExprNode, fn() {
    ctx.emit_token(WhileToken)
    consume_until_body(ctx)
    if !ctx.at_eof() && is_lbrace(ctx.peek()) {
      ignore(parse_block_expr(ctx))
    }
  })
}

///|
/// Parse an `if cond { then } else { else }` expression.
fn parse_if_expr(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  ctx.node(IfExprNode, fn() {
    ctx.emit_token(IfToken)
    consume_until_body(ctx)
    if !ctx.at_eof() && is_lbrace(ctx.peek()) {
      ignore(parse_block_expr(ctx))
    }
    if !ctx.at_eof() && ctx.peek() is Official(kind=TK_ELSE) {
      ctx.emit_token(ElseToken)
      if !ctx.at_eof() && is_lbrace(ctx.peek()) {
        ignore(parse_block_expr(ctx))
      }
    }
  })
}

///|
/// Consume tokens that form the condition, stopping at `{`, `}`, or item delimiter.
fn consume_until_body(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  while !ctx.at_eof() {
    let token = ctx.peek()
    if is_lbrace(token) || is_rbrace(token) || token.is_item_delimiter() {
      break
    }
    ctx.emit_token(token.syntax_kind())
  }
}

///| Parse a `{ ... }` block expression. Inner statements/expressions are

///| separated by `;` or NEWLINE (ASI); context-sensitive constructs

///|
/// (if, while, match) are parsed recursively.
fn parse_block_expr(
  ctx : @core.ParserContext[MoonToken, MoonbitSyntaxKind],
) -> Unit {
  ctx.node(BlockExprNode, fn() {
    ctx.emit_token(LbraceToken)
    while !ctx.at_eof() {
      let token = ctx.peek()
      if is_rbrace(token) {
        break
      }
      if token.is_layout_token() || token.is_item_delimiter() {
        ctx.emit_token(token.syntax_kind())
        continue
      }
      match token {
        Official(kind=TK_IF) => ignore(parse_if_expr(ctx))
        Official(kind=TK_WHILE) => ignore(parse_while_expr(ctx))
        Official(kind=TK_MATCH) => ignore(parse_match_expr(ctx))
        _ => ctx.emit_token(token.syntax_kind())
      }
    }
    if !ctx.at_eof() && is_rbrace(ctx.peek()) {
      ctx.emit_token(RbraceToken)
    }
  })
}
