///|
fn is_markdown_reparseable_block(kind : @seam.RawKind) -> Bool {
  kind == CodeBlockNode.to_raw() || kind == ParagraphNode.to_raw()
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
fn is_paragraph_token_stream(tokens : Array[@core.TokenInfo[Token]]) -> Bool {
  for info in tokens {
    match info.token {
      HeadingMarker(_)
      | ListMarker
      | CodeFenceOpen(_, _)
      | CodeFenceClose
      | BlankLine => return false
      _ => ()
    }
  }
  true
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
        _ => is_paragraph_token_stream(tokens)
      }
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
let markdown_block_reparse_spec : @core.BlockReparseSpec[Token, SyntaxKind] = {
  is_reparseable: is_markdown_reparseable_block,
  get_reparser: fn(node) {
    let kind = node.kind()
    if kind == CodeBlockNode.to_raw() {
      Some(parse_code_block_if_still_code_block)
    } else if kind == ParagraphNode.to_raw() &&
      paragraph_start_allows_reparse(node.text()) {
      Some(parse_paragraph_if_still_paragraph)
    } else {
      None
    }
  },
  is_balanced: markdown_tokens_safe_for_block_reparse,
}
