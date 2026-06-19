///|
fn is_markdown_reparseable_block(kind : @seam.RawKind) -> Bool {
  kind == CodeBlockNode.to_raw() ||
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
    ['#' | '-' | '*' | '+' | '`', ..] => false
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
      for info in tokens {
        match info.token {
          EOF => ()
          ListMarker =>
            if expect_marker {
              expect_marker = false
              saw_marker = true
              saw_content = false
            } else {
              return false
            }
          Newline => expect_marker = true
          token if expect_marker || token_breaks_isolated_inline_block(token) =>
            return false
          Text(text) => {
            if !saw_content && text_starts_with_space_or_tab(text) {
              return false
            }
            saw_content = true
          }
          _ => saw_content = true
        }
      }
      saw_marker
    }
  }
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
  match first_token_text(node.text()) {
    Some(marker_text) =>
      Some(fn(ctx) {
        parse_marker_block_if_unchanged(
          ctx, marker_text, is_marker, parse_block,
        )
      })
    None => None
  }
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
      Newline => break false
      token if token_breaks_isolated_inline_block(token) => break false
      Text(text) => {
        if !saw_content && text_starts_with_space_or_tab(text) {
          break false
        }
        saw_content = true
      }
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
fn first_unordered_list_marker(text : String) -> UnorderedListMarker? {
  match first_token_text(text) {
    Some(marker_text) => unordered_list_marker_from_text(marker_text)
    None => None
  }
}

///|
fn list_item_reparser(
  node : @seam.SyntaxNode,
) -> ((@core.ParserContext[Token, SyntaxKind]) -> Unit)? {
  match first_unordered_list_marker(node.text()) {
    Some(marker) => Some(fn(ctx) { parse_list_item_if_unchanged(ctx, marker) })
    None => None
  }
}

///|
fn unordered_list_context_allows_reparse(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
) -> Bool {
  let checkpoint = ctx.checkpoint()
  let mut result = true
  let mut expect_marker = true
  let mut saw_marker = false
  let mut saw_content = false
  while result && ctx.peek() != EOF {
    match ctx.peek() {
      ListMarker =>
        if expect_marker &&
          current_unordered_list_marker(ctx) == Some(opening_marker) {
          expect_marker = false
          saw_marker = true
          saw_content = false
          ctx.emit_current_token()
        } else {
          result = false
        }
      Newline => {
        expect_marker = true
        ctx.emit_current_token()
      }
      token if expect_marker || token_breaks_isolated_inline_block(token) =>
        result = false
      Text(text) =>
        if !saw_content && text_starts_with_space_or_tab(text) {
          result = false
        } else {
          saw_content = true
          ctx.emit_current_token()
        }
      _ => {
        saw_content = true
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
) -> Unit {
  if list_marker_matches(ctx, opening_marker) &&
    unordered_list_context_allows_reparse(ctx, opening_marker) {
    parse_list(ctx)
  }
}

///|
fn unordered_list_reparser(
  node : @seam.SyntaxNode,
) -> ((@core.ParserContext[Token, SyntaxKind]) -> Unit)? {
  match first_unordered_list_marker(node.text()) {
    Some(marker) =>
      Some(fn(ctx) { parse_unordered_list_if_unchanged(ctx, marker) })
    None => None
  }
}

///|
let markdown_block_reparse_spec : @core.BlockReparseSpec[Token, SyntaxKind] = {
  is_reparseable: is_markdown_reparseable_block,
  get_reparser: fn(node) {
    let kind = node.kind()
    if kind == CodeBlockNode.to_raw() {
      Some(parse_code_block_if_still_code_block)
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
