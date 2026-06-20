///|
fn char_at(input : String, pos : Int) -> Char? {
  input.get_char(pos)
}

///|
fn produced_until(
  token : Token,
  pos : Int,
  rest : StringView,
  mode : MarkdownLexMode,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  let end = rest.start_offset()
  (Produced(@core.TokenInfo::new(token, end - pos), next_offset=end), mode)
}

///|
/// Count consecutive backticks starting at pos.
fn count_backticks(input : String, pos : Int) -> Int {
  let mut n = 0
  while pos + n < input.length() {
    match char_at(input, pos + n) {
      Some('`') => n = n + 1
      _ => break
    }
  }
  n
}

///|
/// Count consecutive '#' starting at pos.
fn count_hashes(input : String, pos : Int) -> Int {
  let mut n = 0
  while pos + n < input.length() && n < 6 {
    match char_at(input, pos + n) {
      Some('#') => n = n + 1
      _ => break
    }
  }
  n
}

///|
fn ordered_list_marker_at(input : String, pos : Int) -> OrderedListMarker? {
  let digits = count_ordered_marker_digits(input, pos)
  guard digits > 0 else { return None }
  guard char_at(input, pos + digits + 1) == Some(' ') else { return None }
  match char_at(input, pos + digits) {
    Some('.') | Some(')') =>
      ordered_list_marker_from_text(input[pos:pos + digits + 1].to_owned())
    _ => None
  }
}

///|
fn produce_token_from(
  token : Token,
  start : Int,
  len : Int,
  mode : MarkdownLexMode,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  (Produced(@core.TokenInfo::new(token, len), next_offset=start + len), mode)
}

///|
fn lex_indented_block_marker(
  input : String,
  pos : Int,
  marker_start : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  let indent_len = marker_start - pos
  match char_at(input, marker_start) {
    Some('>') => {
      let marker_len = if char_at(input, marker_start + 1) == Some(' ') {
        2
      } else {
        1
      }
      produce_token_from(
        BlockQuoteMarker,
        pos,
        indent_len + marker_len,
        BlockQuoteLineStart,
      )
    }
    Some('-') | Some('*') | Some('+') =>
      if char_at(input, marker_start + 1) == Some(' ') {
        produce_token_from(ListMarker, pos, indent_len + 2, Inline)
      } else {
        lex_inline(input, pos)
      }
    Some(ch) if is_decimal_digit(ch) =>
      match ordered_list_marker_at(input, marker_start) {
        Some(marker) => {
          let marker_len = count_ordered_marker_digits(input, marker_start) + 2
          produce_token_from(
            OrderedListMarker(marker),
            pos,
            indent_len + marker_len,
            Inline,
          )
        }
        None => lex_inline(input, pos)
      }
    _ => lex_inline(input, pos)
  }
}

///|
/// Lex from LineStart mode. Recognizes block markers at line beginning.
fn lex_line_start(
  input : String,
  pos : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() {
    return (Done, LineStart)
  }
  match input.view(start_offset=pos) {
    ['\r', '\n', .. rest] | ['\r', .. rest] | ['\n', .. rest] =>
      // Empty line = BlankLine
      produced_until(BlankLine, pos, rest, LineStart)
    [' ', ..] | ['\t', ..] => {
      // Check if this is a whitespace-only line (blank line with spaces/tabs)
      let mut end = pos
      let mut is_blank = false
      let mut spaces_only = true
      while end < input.length() {
        match char_at(input, end) {
          Some(' ') => end = end + 1
          Some('\t') => {
            spaces_only = false
            end = end + 1
          }
          Some('\r') => {
            is_blank = true
            let next = @core.next_char_offset(input, end)
            end = if next < input.length() {
              match char_at(input, next) {
                Some('\n') => @core.next_char_offset(input, next)
                _ => next
              }
            } else {
              next
            }
            break
          }
          Some('\n') => {
            is_blank = true
            end = @core.next_char_offset(input, end)
            break
          }
          None => {
            is_blank = true
            break
          }
          _ => break
        }
      }
      if is_blank {
        (
          Produced(@core.TokenInfo::new(BlankLine, end - pos), next_offset=end),
          LineStart,
        )
      } else if spaces_only && end - pos <= 3 {
        lex_indented_block_marker(input, pos, end)
      } else {
        // Leading whitespace followed by content — treat as paragraph
        lex_inline(input, pos)
      }
    }
    ['#', ..] => {
      let n = count_hashes(input, pos)
      // Must be followed by space (or EOL) to be a heading
      if n > 0 && n <= 6 {
        match char_at(input, pos + n) {
          Some(' ') =>
            // HeadingMarker includes the trailing space
            (
              Produced(
                @core.TokenInfo::new(HeadingMarker(n), n + 1),
                next_offset=pos + n + 1,
              ),
              Inline,
            )
          Some('\r') | Some('\n') | None =>
            // Heading with no content (just "##\n")
            (
              Produced(
                @core.TokenInfo::new(HeadingMarker(n), n),
                next_offset=pos + n,
              ),
              Inline,
            )
          _ =>
            // Not a valid heading marker, treat as paragraph text
            lex_inline(input, pos)
        }
      } else {
        lex_inline(input, pos)
      }
    }
    ['>', ' ', .. rest] =>
      produced_until(BlockQuoteMarker, pos, rest, BlockQuoteLineStart)
    ['>', ..] =>
      produce_token_from(BlockQuoteMarker, pos, 1, BlockQuoteLineStart)
    ['-', ' ', .. rest] =>
      // List marker: must be followed by space
      produced_until(ListMarker, pos, rest, Inline)
    ['*', ' ', .. rest] =>
      // List marker: must be followed by space
      produced_until(ListMarker, pos, rest, Inline)
    ['+', ' ', .. rest] =>
      // List marker: must be followed by space
      produced_until(ListMarker, pos, rest, Inline)
    ['-' | '*' | '+', ..] =>
      // Not a list marker in LineStart; fall through to inline
      // (e.g., "**bold**" at line start — * not followed by space)
      lex_inline(input, pos)
    [ch, ..] if is_decimal_digit(ch) =>
      match ordered_list_marker_at(input, pos) {
        Some(marker) => {
          let marker_len = count_ordered_marker_digits(input, pos) + 2
          (
            Produced(
              @core.TokenInfo::new(OrderedListMarker(marker), marker_len),
              next_offset=pos + marker_len,
            ),
            Inline,
          )
        }
        None => lex_inline(input, pos)
      }
    ['`', ..] => {
      let n = count_backticks(input, pos)
      if n >= 3 {
        // Code fence — consume info string until newline
        let mut info_end = pos + n
        while info_end < input.length() {
          match char_at(input, info_end) {
            Some('\r') | Some('\n') | None => break
            _ => info_end = @core.next_char_offset(input, info_end)
          }
        }
        let info : StringView = input[pos + n:info_end]
        (
          Produced(
            @core.TokenInfo::new(
              CodeFenceOpen(n, info.to_owned()),
              info_end - pos,
            ),
            next_offset=info_end,
          ),
          CodeBlock(n),
        )
      } else {
        // Less than 3 backticks — not a fence, treat as inline
        lex_inline(input, pos)
      }
    }
    _ =>
      // No block marker recognized — switch to inline for paragraph content
      lex_inline(input, pos)
  }
}

///|
fn lex_block_quote_line_start(
  input : String,
  pos : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  match input.view(start_offset=pos) {
    ['`', ..] => lex_inline(input, pos)
    _ => lex_line_start(input, pos)
  }
}

///|
/// Special characters that terminate a Text run in Inline mode.
fn is_inline_special(ch : Char) -> Bool {
  match ch {
    '*' | '`' | '[' | ']' | '(' | ')' | '\r' | '\n' => true
    _ => false
  }
}

///|
/// Lex from Inline mode. Recognizes emphasis, code, links, text runs.
fn lex_inline(
  input : String,
  pos : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() {
    return (Done, Inline)
  }
  match input.view(start_offset=pos) {
    ['\r', '\n', .. rest] | ['\r', .. rest] | ['\n', .. rest] =>
      produced_until(Newline, pos, rest, LineStart)
    [.. "**", .. rest] => produced_until(StarStar, pos, rest, Inline)
    ['*', .. rest] => produced_until(Star, pos, rest, Inline)
    ['`', .. rest] => produced_until(Backtick, pos, rest, Inline)
    ['[', .. rest] => produced_until(LeftBracket, pos, rest, Inline)
    [']', .. rest] => produced_until(RightBracket, pos, rest, Inline)
    ['(', .. rest] => produced_until(LeftParen, pos, rest, Inline)
    [')', .. rest] => produced_until(RightParen, pos, rest, Inline)
    _ => {
      // Text run: consume until next special char or newline
      let mut end = @core.next_char_offset(input, pos)
      while end < input.length() {
        match char_at(input, end) {
          Some(ch) if is_inline_special(ch) => break
          None => break
          _ => end = @core.next_char_offset(input, end)
        }
      }
      let text : StringView = input[pos:end]
      (
        Produced(
          @core.TokenInfo::new(Text(text.to_owned()), end - pos),
          next_offset=end,
        ),
        Inline,
      )
    }
  }
}

///|
/// Consume characters until newline and emit as CodeText. Used by lex_code_block
/// for the three cases where content is not a closing fence.
fn emit_code_text_line(
  input : String,
  pos : Int,
  fence_len : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  let mut line_end = pos
  while line_end < input.length() {
    match char_at(input, line_end) {
      Some('\r') | Some('\n') | None => break
      _ => line_end = @core.next_char_offset(input, line_end)
    }
  }
  let text : StringView = input[pos:line_end]
  (
    Produced(
      @core.TokenInfo::new(CodeText(text.to_owned()), line_end - pos),
      next_offset=line_end,
    ),
    CodeBlock(fence_len),
  )
}

///|
/// Lex from CodeBlock mode. Emits CodeText lines until closing fence.
fn lex_code_block(
  input : String,
  pos : Int,
  fence_len : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() {
    return (Done, CodeBlock(fence_len))
  }
  match input.view(start_offset=pos) {
    ['\r', '\n', .. rest] =>
      produced_until(Newline, pos, rest, CodeBlock(fence_len))
    ['\r', .. rest] | ['\n', .. rest] =>
      produced_until(Newline, pos, rest, CodeBlock(fence_len))
    ['`', ..] => {
      let n = count_backticks(input, pos)
      if n >= fence_len {
        // Check that rest of line is empty (only whitespace/newline)
        let mut after = pos + n
        let mut is_close = true
        while after < input.length() {
          match char_at(input, after) {
            Some('\r') | Some('\n') | None => break
            Some(' ') | Some('\t') => after = after + 1
            _ => {
              is_close = false
              break
            }
          }
        }
        if is_close {
          // Closing fence: consume backticks + trailing whitespace + newline.
          // Including the newline prevents lex_line_start from seeing it as BlankLine.
          let fence_end = if after < input.length() {
            match input.view(start_offset=after) {
              ['\r', '\n', .. rest] => rest.start_offset()
              ['\r', .. rest] | ['\n', .. rest] => rest.start_offset()
              _ => after
            }
          } else {
            after
          }
          (
            Produced(
              @core.TokenInfo::new(CodeFenceClose, fence_end - pos),
              next_offset=fence_end,
            ),
            LineStart,
          )
        } else {
          emit_code_text_line(input, pos, fence_len)
        }
      } else {
        emit_code_text_line(input, pos, fence_len)
      }
    }
    _ => emit_code_text_line(input, pos, fence_len)
  }
}

///|
/// Mode-aware lex step. Dispatches to mode-specific lexer.
pub fn markdown_lex_step(
  input : String,
  pos : Int,
  mode : MarkdownLexMode,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() {
    return (Done, mode)
  }
  match mode {
    LineStart => lex_line_start(input, pos)
    BlockQuoteLineStart => lex_block_quote_line_start(input, pos)
    Inline => lex_inline(input, pos)
    CodeBlock(n) => lex_code_block(input, pos, n)
  }
}

///|
/// The ModeLexer instance for Markdown.
pub let markdown_mode_lexer : @core.ModeLexer[Token, MarkdownLexMode] = {
  lex_step: markdown_lex_step,
  initial_mode: LineStart,
}

///|
/// Tokenize a full Markdown source string.
pub fn tokenize(
  input : String,
) -> Array[@core.TokenInfo[Token]] raise @core.LexError {
  let (tokens, _modes) = @core.tokenize_with_modes(
    markdown_mode_lexer,
    input,
    EOF,
  )
  tokens
}
