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
/// Count visual indentation columns with CommonMark 4-column tab stops.
fn count_indent_columns(input : String, start : Int, end : Int) -> Int {
  input[start:end].fold(init=0, (col, ch) => {
    match ch {
      ' ' => col + 1
      '\t' => (col / 4 + 1) * 4
      _ => col + 1
    }
  })
}

///|
/// True when the character at `pos` is preceded by an odd-length contiguous
/// backslash run (CommonMark §6.5: only odd runs escape the following char).
fn preceded_by_odd_backslashes(input : String, pos : Int) -> Bool {
  for i = pos - 1, count = 0; i >= 0; {
    match char_at(input, i) {
      Some('\\') => continue i - 1, count + 1
      _ => break count % 2 == 1
    }
  } nobreak { false }
}

///|
fn ordered_list_marker_at(input : String, pos : Int) -> OrderedListMarker? {
  let digits = count_ordered_marker_digits(input, pos)
  guard digits > 0 else { return None }
  guard char_at(input, pos + digits + 1) is Some(' ' | '\t') else {
    return None
  }
  match char_at(input, pos + digits) {
    Some('.') | Some(')') =>
      ordered_list_marker_from_text(input[pos:pos + digits + 1].to_owned())
    _ => None
  }
}

///|
priv enum HtmlBlockType {
  Until(String)
  Raw
}

///|
fn find_line_end(input : String, pos : Int) -> Int {
  let mut line_end = pos
  while line_end < input.length() {
    match char_at(input, line_end) {
      Some('\r') | Some('\n') | None => break
      _ => line_end = @core.next_char_offset(input, line_end)
    }
  }
  line_end
}

///|
fn line_is_blank(input : String, pos : Int, line_end : Int) -> Bool {
  input[pos:line_end].is_blank()
}

///|
fn is_ascii_letter(ch : Char) -> Bool {
  match ch {
    'A'..='Z' | 'a'..='z' => true
    _ => false
  }
}

///|
fn is_html_name_char(ch : Char) -> Bool {
  match ch {
    'A'..='Z' | 'a'..='z' | '0'..='9' | '-' => true
    _ => false
  }
}

///|
fn is_type1_tag_name(tag : String) -> Bool {
  match tag.to_lower() {
    "pre" | "script" | "style" | "textarea" => true
    _ => false
  }
}

///|
fn is_type6_tag_name(tag : String) -> Bool {
  match tag.to_lower() {
    "address"
    | "article"
    | "aside"
    | "base"
    | "basefont"
    | "blockquote"
    | "body"
    | "caption"
    | "center"
    | "col"
    | "colgroup"
    | "dd"
    | "details"
    | "dialog"
    | "dir"
    | "div"
    | "dl"
    | "dt"
    | "fieldset"
    | "figcaption"
    | "figure"
    | "footer"
    | "form"
    | "frame"
    | "frameset"
    | "h1"
    | "h2"
    | "h3"
    | "h4"
    | "h5"
    | "h6"
    | "head"
    | "header"
    | "hr"
    | "html"
    | "iframe"
    | "legend"
    | "li"
    | "link"
    | "main"
    | "menu"
    | "menuitem"
    | "nav"
    | "noframes"
    | "ol"
    | "optgroup"
    | "option"
    | "p"
    | "param"
    | "search"
    | "section"
    | "summary"
    | "table"
    | "tbody"
    | "td"
    | "tfoot"
    | "th"
    | "thead"
    | "title"
    | "tr"
    | "track"
    | "ul" => true
    _ => false
  }
}

///|
fn extract_html_tag_name(line : StringView, pos : Int) -> (String, Int)? {
  guard line.get_char(pos).map_or(false, is_ascii_letter) else { return None }
  let mut end = pos
  while end < line.length() {
    match line.get_char(end) {
      Some(ch) if is_html_name_char(ch) => end = end + 1
      _ => break
    }
  }
  Some((line[pos:end].to_owned(), end))
}

///|
fn valid_html_tag_quote_follow(line : StringView, pos : Int) -> Bool {
  if pos >= line.length() {
    true
  } else {
    match line.get_char(pos) {
      Some(' ') | Some('\t') | Some('/') | Some('>') => true
      _ => false
    }
  }
}

///|
fn first_html_tag_end(line : StringView) -> Int? {
  let mut quote : Char? = None
  for i, ch in line {
    match quote {
      Some(q) if ch == q => {
        guard valid_html_tag_quote_follow(line, i + 1) else { return None }
        quote = None
      }
      Some(_) => ()
      None =>
        match ch {
          '\"' | '\'' => quote = Some(ch)
          '>' => return Some(i)
          _ => ()
        }
    }
  }
  None
}

///|
fn line_has_only_tag(line : StringView) -> Bool {
  match first_html_tag_end(line) {
    Some(end) => line[end + 1:].trim().is_empty()
    None => false
  }
}

///|
fn html_tag_name_follow_is_valid(line : StringView, tag_end : Int) -> Bool {
  if tag_end >= line.length() {
    true
  } else {
    match line.get_char(tag_end) {
      Some(' ') | Some('\t') | Some('/') | Some('>') => true
      _ => false
    }
  }
}

///|
fn closing_line_has_only_tag(line : StringView, tag_end : Int) -> Bool {
  let mut pos = tag_end
  while pos < line.length() {
    match line.get_char(pos) {
      Some(' ') | Some('\t') => pos = pos + 1
      Some('>') => return line[pos + 1:].trim().is_empty()
      _ => return false
    }
  }
  false
}

///|
fn classify_html_block_opening(line : StringView) -> HtmlBlockType? {
  let trimmed = line.trim_start()
  guard trimmed.has_prefix("<") else { return None }
  if trimmed.has_prefix("<!--") {
    return Some(Until("-->"))
  }
  if trimmed.has_prefix("<?") {
    return Some(Until("?>"))
  }
  if trimmed.has_prefix("<![CDATA[") {
    return Some(Until("]]>"))
  }
  if trimmed.has_prefix("<!") {
    match trimmed.get_char(2) {
      Some(ch) if is_ascii_letter(ch) => return Some(Until(">"))
      _ => return None
    }
  }
  let name_start = if trimmed.has_prefix("</") { 2 } else { 1 }
  match extract_html_tag_name(trimmed, name_start) {
    Some((tag, tag_end)) if html_tag_name_follow_is_valid(trimmed, tag_end) &&
      is_type1_tag_name(tag) => Some(Until("</" + tag.to_lower() + ">"))
    Some((tag, tag_end)) if html_tag_name_follow_is_valid(trimmed, tag_end) &&
      is_type6_tag_name(tag) => Some(Raw)
    Some((_tag, tag_end)) if html_tag_name_follow_is_valid(trimmed, tag_end) &&
      name_start == 2 &&
      closing_line_has_only_tag(trimmed, tag_end) => Some(Raw)
    Some((_tag, tag_end)) if html_tag_name_follow_is_valid(trimmed, tag_end) &&
      name_start == 1 &&
      line_has_only_tag(trimmed) => Some(Raw)
    _ => None
  }
}

///|
fn html_block_mode_after_open(
  line : StringView,
  block_type : HtmlBlockType,
) -> MarkdownLexMode {
  match block_type {
    Raw => HtmlBlockRaw
    Until(delimiter) =>
      if line.to_lower().contains(delimiter) {
        HtmlBlockEndLine
      } else {
        HtmlBlockUntil(delimiter)
      }
  }
}

///|
fn produce_html_block_open(
  input : String,
  pos : Int,
  line_end : Int,
  block_type : HtmlBlockType,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  let line : StringView = input[pos:line_end]
  (
    Produced(
      @core.TokenInfo::new(HtmlBlockOpen(line.to_owned()), line_end - pos),
      next_offset=line_end,
    ),
    html_block_mode_after_open(line, block_type),
  )
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
      let marker_len = match char_at(input, marker_start + 1) {
        Some(' ') | Some('\t') => 2
        _ => 1
      }
      produce_token_from(
        BlockQuoteMarker,
        pos,
        indent_len + marker_len,
        BlockQuoteLineStart,
      )
    }
    Some('-') | Some('*') | Some('+') =>
      match char_at(input, marker_start + 1) {
Some(' ') | Some('\t') =>
          produce_token_from(ListMarker, pos, indent_len + 2, Inline)
        Some('\n') | Some('\r') | None =>
          produce_token_from(ListMarker, pos, indent_len + 1, Inline)
        _ => lex_inline(input, pos)
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
        None => {
          let digits = count_ordered_marker_digits(input, marker_start)
          match
            (
              char_at(input, marker_start + digits),
              char_at(input, marker_start + digits + 1),
            ) {
            (Some('.') | Some(')'), Some('\n') | Some('\r') | None) =>
              match
                ordered_list_marker_from_text(
                  input[marker_start:marker_start + digits + 1].to_owned(),
                ) {
                Some(marker) =>
                  produce_token_from(
                    OrderedListMarker(marker),
                    pos,
                    indent_len + digits + 1,
                    Inline,
                  )
                None => lex_inline(input, pos)
              }
            _ => lex_inline(input, pos)
          }
        }
      }
    Some('<') => {
      let line_end = find_line_end(input, pos)
      let line : StringView = input[pos:line_end]
      match classify_html_block_opening(line) {
        Some(block_type) =>
          produce_html_block_open(input, pos, line_end, block_type)
        None => lex_inline(input, pos)
      }
    }
    _ => lex_inline(input, pos)
  }
}

///|
fn lex_heading_marker(
  input : String,
  token_pos : Int,
  marker_pos : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  let n = count_hashes(input, marker_pos)
  // Must be followed by space, tab, or EOL to be a heading.
  if n > 0 && n <= 6 {
    match char_at(input, marker_pos + n) {
      Some(' ') | Some('\t') =>
        // HeadingMarker includes the trailing separator.
        (
          Produced(
            @core.TokenInfo::new(
              HeadingMarker(n),
              marker_pos - token_pos + n + 1,
            ),
            next_offset=marker_pos + n + 1,
          ),
          Inline,
        )
      Some('\r') | Some('\n') | None =>
        // Heading with no content (just "##\n")
        (
          Produced(
            @core.TokenInfo::new(HeadingMarker(n), marker_pos - token_pos + n),
            next_offset=marker_pos + n,
          ),
          Inline,
        )
      _ => lex_inline(input, token_pos)
    }
  } else {
    lex_inline(input, token_pos)
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
  let line_end = find_line_end(input, pos)
  if is_valid_thematic_break_markers(input[pos:line_end]) {
    return produced_until(
      ThematicBreak,
      pos,
      input.view(start_offset=line_end),
      LineStart,
    )
  }
  match input.view(start_offset=pos) {
    ['\r', '\n', .. rest] | ['\r', .. rest] | ['\n', .. rest] =>
      // Empty line = BlankLine
      produced_until(BlankLine, pos, rest, LineStart)
    [' ', ..] | ['\t', ..] => {
      // Check if this is a whitespace-only line (blank line with spaces/tabs)
      let mut end = pos
      let mut is_blank = false
      while end < input.length() {
        match char_at(input, end) {
          Some(' ') | Some('\t') => end = end + 1
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
      } else if count_indent_columns(input, pos, end) <= 3 {
        match char_at(input, end) {
          Some('#') => lex_heading_marker(input, pos, end)
          _ => lex_indented_block_marker(input, pos, end)
        }
      } else {
        // Leading whitespace followed by content — treat as paragraph
        lex_inline(input, pos)
      }
    }
    ['#', ..] => lex_heading_marker(input, pos, pos)
    ['>', ' ' | '\t', .. rest] =>
      produced_until(BlockQuoteMarker, pos, rest, BlockQuoteLineStart)
    ['>', ..] =>
      produce_token_from(BlockQuoteMarker, pos, 1, BlockQuoteLineStart)
    ['-' | '*' | '+', ' ' | '\t', .. rest] =>
      // List marker: must be followed by space or tab.
      produced_until(ListMarker, pos, rest, Inline)
    ['-' | '*' | '+', ..] =>
      // A lone bullet marker is an empty list item; other marker-looking text
      // falls through to inline (for example, "**bold**" at line start).
      match char_at(input, pos + 1) {
        Some('\n') | Some('\r') | None =>
          produce_token_from(ListMarker, pos, 1, Inline)
        _ => lex_inline(input, pos)
      }
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
        None => {
          let digits = count_ordered_marker_digits(input, pos)
          match
            (char_at(input, pos + digits), char_at(input, pos + digits + 1)) {
            (Some('.') | Some(')'), Some('\n') | Some('\r') | None) =>
              match
                ordered_list_marker_from_text(
                  input[pos:pos + digits + 1].to_owned(),
                ) {
                Some(marker) =>
                  produce_token_from(
                    OrderedListMarker(marker),
                    pos,
                    digits + 1,
                    Inline,
                  )
                None => lex_inline(input, pos)
              }
            _ => lex_inline(input, pos)
          }
        }
      }
    ['<', ..] => {
      let line : StringView = input[pos:line_end]
      match classify_html_block_opening(line) {
        Some(block_type) =>
          produce_html_block_open(input, pos, line_end, block_type)
        None => lex_inline(input, pos)
      }
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
          Some(ch) if is_inline_special(ch) =>
            if ch != '\r' &&
              ch != '\n' &&
              end > pos &&
              preceded_by_odd_backslashes(input, end) {
              end = @core.next_char_offset(input, end)
            } else {
              break
            }
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
fn lex_html_block_end_line(
  input : String,
  pos : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  match input.view(start_offset=pos) {
    ['\r', '\n', .. rest] | ['\r', .. rest] | ['\n', .. rest] =>
      produced_until(Newline, pos, rest, LineStart)
    _ => (Done, LineStart)
  }
}

///|
fn emit_html_text_line(
  input : String,
  pos : Int,
  mode : MarkdownLexMode,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  let line_end = find_line_end(input, pos)
  let text : StringView = input[pos:line_end]
  (
    Produced(
      @core.TokenInfo::new(HtmlText(text.to_owned()), line_end - pos),
      next_offset=line_end,
    ),
    mode,
  )
}

///|
fn lex_html_block_raw_newline_mode(
  input : String,
  next_pos : Int,
) -> MarkdownLexMode {
  if next_pos >= input.length() {
    HtmlBlockRaw
  } else {
    match char_at(input, next_pos) {
      Some('\r') | Some('\n') => LineStart
      _ => HtmlBlockRaw
    }
  }
}

///|
fn lex_html_block_raw(
  input : String,
  pos : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() {
    return (Done, HtmlBlockRaw)
  }
  let line_end = find_line_end(input, pos)
  match input.view(start_offset=pos) {
    ['\r', '\n', .. rest] =>
      produced_until(
        Newline,
        pos,
        rest,
        lex_html_block_raw_newline_mode(input, rest.start_offset()),
      )
    ['\r', .. rest] | ['\n', .. rest] =>
      produced_until(
        Newline,
        pos,
        rest,
        lex_html_block_raw_newline_mode(input, rest.start_offset()),
      )
    _ if line_is_blank(input, pos, line_end) => lex_line_start(input, pos)
    _ => emit_html_text_line(input, pos, HtmlBlockRaw)
  }
}

///|
fn lex_html_block_until(
  input : String,
  pos : Int,
  delimiter : String,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() {
    return (Done, HtmlBlockUntil(delimiter))
  }
  match input.view(start_offset=pos) {
    ['\r', '\n', .. rest] | ['\r', .. rest] | ['\n', .. rest] =>
      produced_until(Newline, pos, rest, HtmlBlockUntil(delimiter))
    _ => {
      let line_end = find_line_end(input, pos)
      let text : StringView = input[pos:line_end]
      let next_mode = if text.to_lower().contains(delimiter) {
        HtmlBlockEndLine
      } else {
        HtmlBlockUntil(delimiter)
      }
      (
        Produced(
          @core.TokenInfo::new(HtmlText(text.to_owned()), line_end - pos),
          next_offset=line_end,
        ),
        next_mode,
      )
    }
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
    HtmlBlockRaw => lex_html_block_raw(input, pos)
    HtmlBlockUntil(delimiter) => lex_html_block_until(input, pos, delimiter)
    HtmlBlockEndLine => lex_html_block_end_line(input, pos)
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
