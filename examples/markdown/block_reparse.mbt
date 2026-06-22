///|
fn is_markdown_reparseable_block(kind : @seam.RawKind) -> Bool {
  kind == CodeBlockNode.to_raw() ||
  kind == HtmlBlockNode.to_raw() ||
  kind == ParagraphNode.to_raw() ||
  kind == HeadingNode.to_raw() ||
  kind == UnorderedListNode.to_raw() ||
  kind == ListItemNode.to_raw()
}

///|
/// Strict-interior edits keep the first character fixed, but marker-prefixed
/// paragraphs can still become headings, lists, or code fences by editing after
/// that first character. Decline them without adding BlockReparseContext.
fn paragraph_start_allows_reparse(text : String) -> Bool {
  match text {
    ['#' | '-' | '*' | '+' | '`' | '>', ..] => false
    _ => true
  }
}

///|
fn text_starts_with_space_or_tab(text : String) -> Bool {
  match text {
    [' ' | '\t', ..] => true
    _ => false
  }
}

///|
fn token_breaks_isolated_inline_block(token : Token) -> Bool {
  match token {
    EOF => false
    CodeFenceClose => true
    _ => is_block_boundary(token)
  }
}

///|
/// True when a token can remain inline content on an isolated list item line.
/// The parser and block reparse share marker-metadata boundaries; this helper
/// documents the reparse-only extra guard that prevents marker-line splits,
/// indented continuations, and nested/container-looking tokens from being
/// accepted as a single-node replacement.
fn token_stays_on_isolated_list_item_line(
  token : Token,
  saw_content : Bool,
) -> Bool {
  match token {
    EOF => true
    Newline => false
    token if token_breaks_isolated_inline_block(token) => false
    Text(text) => saw_content || !text_starts_with_space_or_tab(text)
    _ => true
  }
}

///|
fn is_paragraph_token_stream(tokens : Array[@core.TokenInfo[Token]]) -> Bool {
  tokens.iter().all(info => !token_breaks_isolated_inline_block(info.token))
}

///|
fn is_marker_line_token_stream(
  tokens : Array[@core.TokenInfo[Token]],
  is_start_marker : (Token) -> Bool,
  allow_trailing_newline~ : Bool,
) -> Bool {
  match tokens {
    [] => false
    [first, ..] => {
      guard is_start_marker(first.token) else { return false }
      let mut saw_newline = false
      let mut saw_content = false
      for i, info in tokens {
        match info.token {
          _ if i == 0 => ()
          EOF => ()
          Newline =>
            if !allow_trailing_newline || saw_newline {
              return false
            } else {
              saw_newline = true
            }
          token if token_breaks_isolated_inline_block(token) => return false
          Text(text) => {
            if saw_newline ||
              (!saw_content && text_starts_with_space_or_tab(text)) {
              return false
            }
            saw_content = true
          }
          _ => {
            if saw_newline {
              return false
            }
            saw_content = true
          }
        }
      }
      true
    }
  }
}

///|
fn is_heading_token_stream(tokens : Array[@core.TokenInfo[Token]]) -> Bool {
  is_marker_line_token_stream(
    tokens,
    token => token is HeadingMarker(_),
    allow_trailing_newline=true,
  )
}

///|
fn is_list_item_token_stream(tokens : Array[@core.TokenInfo[Token]]) -> Bool {
  is_marker_line_token_stream(
    tokens,
    token => token is ListMarker,
    allow_trailing_newline=false,
  )
}

///|
/// Accept only a contiguous unordered-list container: each non-empty line must
/// start with a list marker, and inline content must stay on that marker line.
fn is_unordered_list_token_stream(
  tokens : Array[@core.TokenInfo[Token]],
) -> Bool {
  match tokens {
    [] => false
    [first, ..] => {
      guard first.token is ListMarker else { return false }
      let mut expect_marker = true
      let mut saw_marker = false
      let mut saw_content = false
      let mut saw_non_blank_content = false
      for info in tokens {
        match info.token {
          EOF => ()
          ListMarker =>
            if expect_marker {
              expect_marker = false
              saw_marker = true
              saw_content = false
              saw_non_blank_content = false
            } else {
              return false
            }
          Newline => expect_marker = true
          token if token_continues_lazy_unordered_list_item(
              token, expect_marker, saw_marker, saw_non_blank_content,
            ) => {
            expect_marker = false
            saw_content = true
            saw_non_blank_content = true
          }
          token if expect_marker ||
            !token_stays_on_isolated_list_item_line(token, saw_content) =>
            return false
          _ => {
            saw_content = true
            saw_non_blank_content = saw_non_blank_content ||
              token_has_non_blank_inline_content(info.token)
          }
        }
      }
      saw_marker
    }
  }
}

///|
fn token_continues_lazy_unordered_list_item(
  token : Token,
  expect_marker : Bool,
  saw_marker : Bool,
  saw_non_blank_content : Bool,
) -> Bool {
  expect_marker &&
  saw_marker &&
  saw_non_blank_content &&
  token_can_start_lazy_list_item_continuation(token, allow_ordered_marker=true)
}

///|
fn is_code_block_token_stream(tokens : Array[@core.TokenInfo[Token]]) -> Bool {
  // Require an intact closing fence: removing a close can expand the block past
  // the old splice range, which a single-node replacement cannot represent.
  match tokens {
    [] => false
    [first, ..] => {
      guard first.token is CodeFenceOpen(_, _) else { return false }
      let mut saw_close = false
      let mut trailing_after_close = 0
      for i, info in tokens {
        match info.token {
          CodeFenceOpen(_, _) => if i != 0 { return false }
          CodeFenceClose =>
            if saw_close {
              return false
            } else {
              saw_close = true
            }
          CodeText(_) => if saw_close { return false }
          Newline | BlankLine =>
            if saw_close {
              trailing_after_close = trailing_after_close + 1
              if trailing_after_close > 1 {
                return false
              }
            }
          EOF => ()
          _ => return false
        }
      }
      saw_close
    }
  }
}

///|
fn markdown_tokens_safe_for_block_reparse(
  tokens : Array[@core.TokenInfo[Token]],
) -> Bool {
  match tokens {
    [] => false
    [first, ..] =>
      match first.token {
        CodeFenceOpen(_, _) => is_code_block_token_stream(tokens)
        HtmlBlockOpen(_) => true
        HeadingMarker(_) => is_heading_token_stream(tokens)
        ListMarker =>
          is_list_item_token_stream(tokens) ||
          is_unordered_list_token_stream(tokens)
        _ => is_paragraph_token_stream(tokens)
      }
  }
}

///|
fn first_token_text(text : String) -> String? {
  let lex = lex_for_grammar(text)
  match (lex.tokens, lex.starts) {
    ([first, ..], [start, ..]) => {
      let end = start + first.len
      if start < 0 || end < start || end > text.length() {
        None
      } else {
        Some(text[start:end].to_owned())
      }
    }
    _ => None
  }
}

///|
fn parse_code_block_if_still_code_block(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  // If the opening fence no longer lexes as a fence, emit no node so Loom
  // falls back to the normal incremental path.
  if ctx.peek() is CodeFenceOpen(_, _) {
    parse_code_block(ctx)
  }
}

///|
fn parse_paragraph_if_still_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  // Boundary tokens can change the block extent, so decline by emitting no node.
  if !is_block_boundary(ctx.peek()) {
    parse_paragraph(ctx)
  }
}

///|
fn parse_marker_block_if_unchanged(
  ctx : @core.ParserContext[Token, SyntaxKind],
  marker_text : String,
  is_marker : (Token) -> Bool,
  parse_block : (@core.ParserContext[Token, SyntaxKind]) -> Unit,
) -> Unit {
  if is_marker(ctx.peek()) && ctx.current_token_text().to_owned() == marker_text {
    parse_block(ctx)
  }
}

///|
fn marker_block_reparser(
  node : @seam.SyntaxNode,
  is_marker : (Token) -> Bool,
  parse_block : (@core.ParserContext[Token, SyntaxKind]) -> Unit,
) -> ((@core.ParserContext[Token, SyntaxKind]) -> Unit)? {
  first_token_text(node.text()).map(marker_text => {
    ctx => {
      parse_marker_block_if_unchanged(ctx, marker_text, is_marker, parse_block)
    }
  })
}

///|
/// `is_balanced` is token-only, so the broader ListMarker predicate needed for
/// UnorderedListNode must not make ListItemNode accept marker-line splits.
/// Re-check the isolated ListItemNode stream before emitting its replacement.
fn list_item_context_allows_reparse(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  let mut saw_content = false
  for i = 1 {
    match ctx.peek_nth(i) {
      EOF => break true
      token if !token_stays_on_isolated_list_item_line(token, saw_content) =>
        break false
      _ => saw_content = true
    }
    continue i + 1
  }
}

///|
fn parse_list_item_if_unchanged(
  ctx : @core.ParserContext[Token, SyntaxKind],
  marker : UnorderedListMarker,
) -> Unit {
  if list_marker_matches(ctx, marker) && list_item_context_allows_reparse(ctx) {
    parse_list_item(ctx)
  }
}

///|
fn list_item_reparser(
  node : @seam.SyntaxNode,
) -> ((@core.ParserContext[Token, SyntaxKind]) -> Unit)? {
  first_unordered_list_marker(node.text()).map(marker => {
    ctx => parse_list_item_if_unchanged(ctx, marker)
  })
}

///|
fn unordered_list_context_allows_reparse(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
  min_indent : Int,
) -> Bool {
  let checkpoint = ctx.checkpoint()
  let mut result = true
  let mut expect_marker = true
  let mut saw_marker = false
  let mut saw_content = false
  let mut saw_non_blank_content = false
  while result && ctx.peek() != EOF {
    match ctx.peek() {
      ListMarker =>
        if expect_marker &&
          list_marker_matches_at_min_indent(ctx, opening_marker, min_indent) {
          expect_marker = false
          saw_marker = true
          saw_content = false
          saw_non_blank_content = false
          ctx.emit_current_token()
        } else {
          result = false
        }
      Newline => {
        expect_marker = true
        ctx.emit_current_token()
      }
      token if token_continues_lazy_unordered_list_item(
          token, expect_marker, saw_marker, saw_non_blank_content,
        ) => {
        expect_marker = false
        saw_content = true
        saw_non_blank_content = true
        ctx.emit_current_token()
      }
      token if expect_marker ||
        !token_stays_on_isolated_list_item_line(token, saw_content) =>
        result = false
      _ => {
        let token = ctx.peek()
        saw_content = true
        saw_non_blank_content = saw_non_blank_content ||
          token_has_non_blank_inline_content(token)
        ctx.emit_current_token()
      }
    }
  }
  ctx.restore(checkpoint)
  result && saw_marker
}

///|
fn parse_unordered_list_if_unchanged(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
  min_indent : Int,
) -> Unit {
  if list_marker_matches_at_min_indent(ctx, opening_marker, min_indent) &&
    unordered_list_context_allows_reparse(ctx, opening_marker, min_indent) {
    parse_list_at_min_indent(ctx, min_indent)
  }
}

///|
fn unordered_list_reparser(
  node : @seam.SyntaxNode,
) -> ((@core.ParserContext[Token, SyntaxKind]) -> Unit)? {
  guard first_token_text(node.text()) is Some(marker_text) else { return None }
  guard unordered_list_marker_from_text(marker_text) is Some(marker) else {
    return None
  }
  guard marker_start_after_optional_indent(marker_text, 0) is Some(min_indent) else {
    return None
  }
  Some(ctx => parse_unordered_list_if_unchanged(ctx, marker, min_indent))
}

///|
let markdown_block_reparse_spec : @core.BlockReparseSpec[Token, SyntaxKind] = {
  is_reparseable: is_markdown_reparseable_block,
  get_reparser: fn(node) {
    let kind = node.kind()
    if kind == CodeBlockNode.to_raw() {
      Some(parse_code_block_if_still_code_block)
    } else if kind == HtmlBlockNode.to_raw() {
      Some(ctx => if ctx.peek() is HtmlBlockOpen(_) { parse_html_block(ctx) })
    } else if kind == ParagraphNode.to_raw() &&
      paragraph_start_allows_reparse(node.text()) {
      Some(parse_paragraph_if_still_paragraph)
    } else if kind == HeadingNode.to_raw() {
      marker_block_reparser(
        node,
        token => token is HeadingMarker(_),
        parse_heading,
      )
    } else if kind == UnorderedListNode.to_raw() {
      unordered_list_reparser(node)
    } else if kind == ListItemNode.to_raw() {
      list_item_reparser(node)
    } else {
      None
    }
  },
  is_balanced: markdown_tokens_safe_for_block_reparse,
}
