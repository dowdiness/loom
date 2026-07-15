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
    allow_trailing_newline=true,
  )
}

///|
/// Accept a root-aligned unordered-list container, including nested marker
/// lines whose indentation is resolved by `parse_list_at_min_indent`.
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
          Indentation(_) if expect_marker => ()
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
/// Reject HTML block streams when:
/// - Tokens are left unconsumed (blank-line split, structural change).
/// - A type-1/2 block (Until-delimiter) loses its closing delimiter
///   or the delimiter is no longer the block terminator (e.g. an edit
///   removed it, leaving the block unterminated at EOF).  Like fenced
///   code requiring a closing fence, delimiter-backed HTML blocks must
///   prove the matching terminator is still present.
fn is_html_block_token_stream(tokens : Array[@core.TokenInfo[Token]]) -> Bool {
  match tokens {
    [] => false
    [first, ..] => {
      guard first.token is HtmlBlockOpen(open_line) else { return false }
      let block_class = classify_html_block_opening_for_reparse(open_line)
      let mut i = 1
      // Optional Newline after HtmlBlockOpen
      if i < tokens.length() && tokens[i].token is Newline {
        i = i + 1
      }
      // HtmlText / Newline loop matching parse_html_block.
      while i < tokens.length() {
        match tokens[i].token {
          HtmlText(_) => i = i + 1
          Newline =>
            if html_newline_run_continues_in_stream(tokens, i) {
              i = i + 1
              if i < tokens.length() &&
                tokens[i].token is Newline &&
                !(i + 1 < tokens.length() && tokens[i + 1].token is Newline) {
                i = i + 1
              }
            } else {
              break
            }
          EOF => {
            i = i + 1
            break
          }
          _ => break
        }
      }
      // Trailing newline run before EOF — match parse_html_block fix.
      while i < tokens.length() && tokens[i].token is Newline {
        i = i + 1
      }
      // Trailing EOF is always accepted (token stream terminator).
      if i < tokens.length() && tokens[i].token is EOF {
        i = i + 1
      }
      guard i >= tokens.length() else { return false }
      // For type-1/2 blocks, the closing delimiter must be present AND
      // appear in the last line of consumed content (the block terminator),
      // not just anywhere.  If the delimiter was removed or is only a
      // leftover substring earlier in the block, the old span doesn't
      // cover the complete extent.
      match block_class {
        HtmlBlockUntil(delimiter) =>
          html_block_contains_delimiter_at_end(tokens, open_line, delimiter)
        _ => true
      }
    }
  }
}

///|
/// Verify that an Until-delimiter HTML block's delimiter is the actual
/// block terminator.  The delimiter must appear on the last HtmlText line
/// (or the opening line if it's a single-line block), not as a stray
/// substring earlier in the block.
fn html_block_contains_delimiter_at_end(
  tokens : Array[@core.TokenInfo[Token]],
  open_line : String,
  delimiter : String,
) -> Bool {
  // Single-line block: opening line contains the delimiter.
  if open_line.to_lower().contains(delimiter) {
    return true
  }
  // Find the last HtmlText token and check it for the delimiter.
  let mut last_html = None
  for t in tokens {
    match t.token {
      HtmlText(text) => last_html = Some(text)
      _ => ()
    }
  }
  match last_html {
    Some(text) => text.to_lower().contains(delimiter)
    None => false
  }
}

///|
/// Lightweight classification copied from lexer.mbt:classify_html_block_opening
/// so the balance check doesn't need to import private lexer internals.
priv enum HtmlBlockClass {
  HtmlBlockUntil(String)
  HtmlBlockRaw
}

///|
fn classify_html_block_opening_for_reparse(line : String) -> HtmlBlockClass {
  let trimmed = line.trim_start()
  guard trimmed.length() > 1 && trimmed[0] == '<' else { return HtmlBlockRaw }
  // Type 2: comments, processing instructions, CDATA, declarations
  if trimmed.has_prefix("<!--") {
    return HtmlBlockUntil("-->")
  }
  if trimmed.has_prefix("<?") {
    return HtmlBlockUntil("?>")
  }
  if trimmed.has_prefix("<![CDATA[") {
    return HtmlBlockUntil("]]>")
  }
  if trimmed.has_prefix("<!") {
    return HtmlBlockUntil(">")
  }
  // Type 1: pre / script / style / textarea
  let name_start = if trimmed.has_prefix("</") { 2 } else { 1 }
  let mut name_end = name_start
  while name_end < trimmed.length() &&
        trimmed.get_char(name_end).map_or(false, ch => ch.is_ascii_alphabetic()) {
    name_end = name_end + 1
  }
  let tag = trimmed[name_start:name_end].to_owned().to_lower()
  match tag {
    "pre" | "script" | "style" | "textarea" => HtmlBlockUntil("</" + tag)
    _ => HtmlBlockRaw
  }
}

///|
fn html_newline_run_continues_in_stream(
  tokens : Array[@core.TokenInfo[Token]],
  start : Int,
) -> Bool {
  for j = start {
    if j >= tokens.length() {
      break false
    }
    match tokens[j].token {
      HtmlText(_) => break true
      Newline => continue j + 1
      _ => break false
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
        HtmlBlockOpen(_) => is_html_block_token_stream(tokens)
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
  ctx.lookahead(() => {
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
        Indentation(_) if expect_marker && ctx.peek_nth(1) is ListMarker =>
          ctx.emit_current_token()
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
    result && saw_marker
  })
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
  guard marker_indent_columns_after_optional_indent(marker_text, 0)
    is Some(min_indent) else {
    return None
  }
  Some(ctx => parse_unordered_list_if_unchanged(ctx, marker, min_indent))
}

///|
/// Returns whether each unordered marker line has a non-zero visual indent.
fn unordered_list_marker_indent_prefixes(
  tokens : Array[@core.TokenInfo[Token]],
) -> Array[Bool] {
  let prefixes : Array[Bool] = []
  let mut indent_columns = 0
  for info in tokens {
    match info.token {
      Indentation(text) =>
        indent_columns = count_indent_columns(text, 0, text.length())
      ListMarker => {
        prefixes.push(indent_columns > 0)
        indent_columns = 0
      }
      Newline => indent_columns = 0
      _ => ()
    }
  }
  prefixes
}

///|
/// Declines a list candidate when a marker line gains or loses an indentation
/// prefix, because that changes sibling/nested ownership beyond a local splice.
fn unordered_list_ownership_changes(
  node : @seam.SyntaxNode,
  new_tokens : Array[@core.TokenInfo[Token]],
) -> Bool {
  let old_tokens = tokenize(node.text()) catch { _ => return false }
  let old_prefixes = unordered_list_marker_indent_prefixes(old_tokens)
  let new_prefixes = unordered_list_marker_indent_prefixes(new_tokens)
  if old_prefixes.length() != new_prefixes.length() {
    return false
  }
  for i in 0..<old_prefixes.length() {
    if old_prefixes[i] != new_prefixes[i] {
      return true
    }
  }
  false
}

///|
let markdown_block_reparse_spec : @core.BlockReparseSpec[Token, SyntaxKind] = {
  is_reparseable: is_markdown_reparseable_block,
  get_reparser: fn(node, _, tokens) {
    let kind = node.kind()
    if kind == ListItemNode.to_raw() &&
      unordered_list_ownership_changes(node, tokens) {
      None
    } else if kind == CodeBlockNode.to_raw() {
      Some(parse_code_block_if_still_code_block)
    } else if kind == HtmlBlockNode.to_raw() {
      Some(ctx => {
        if ctx.peek() is HtmlBlockOpen(_) {
          parse_html_block(ctx, None)
        }
      })
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
