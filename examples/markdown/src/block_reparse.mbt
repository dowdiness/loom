///|
/// UnorderedListNode is intentionally omitted: its child Newline/ListMarker
/// tokens are list-boundary structure. Safe list edits reparse ListItemNode.
fn is_markdown_reparseable_block(kind : @seam.RawKind) -> Bool {
  kind == CodeBlockNode.to_raw() ||
  kind == ParagraphNode.to_raw() ||
  kind == HeadingNode.to_raw() ||
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
        ListMarker => is_list_item_token_stream(tokens)
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
    } else if kind == ListItemNode.to_raw() {
      marker_block_reparser(node, token => token is ListMarker, parse_list_item)
    } else {
      None
    }
  },
  is_balanced: markdown_tokens_safe_for_block_reparse,
}
