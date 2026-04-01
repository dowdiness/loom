///|
fn char_at(input : String, pos : Int) -> Char? {
  if pos >= input.length() {
    return None
  }
  input.code_unit_at(pos).to_char()
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
/// Lex from LineStart mode. Recognizes block markers at line beginning.
fn lex_line_start(
  input : String,
  pos : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() {
    return (Done, LineStart)
  }
  match char_at(input, pos) {
    Some('\n') =>
      // Empty line = BlankLine
      (
        Produced(@core.TokenInfo::new(BlankLine, 1), next_offset=pos + 1),
        LineStart,
      )
    Some('#') => {
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
          Some('\n') | None =>
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
    Some('-') | Some('*') | Some('+') =>
      // List marker: must be followed by space
      match char_at(input, pos + 1) {
        Some(' ') =>
          (
            Produced(@core.TokenInfo::new(ListMarker, 2), next_offset=pos + 2),
            Inline,
          )
        _ =>
          // Not a list marker in LineStart; fall through to inline
          // (e.g., "**bold**" at line start — * not followed by space)
          lex_inline(input, pos)
      }
    Some('`') => {
      let n = count_backticks(input, pos)
      if n >= 3 {
        // Code fence — consume info string until newline
        let mut info_end = pos + n
        while info_end < input.length() {
          match char_at(input, info_end) {
            Some('\n') | None => break
            _ => info_end = info_end + 1
          }
        }
        let info : StringView = input[pos + n:info_end]
        (
          Produced(
            @core.TokenInfo::new(
              CodeFenceOpen(n, info.to_string()),
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
/// Special characters that terminate a Text run in Inline mode.
fn is_inline_special(ch : Char) -> Bool {
  match ch {
    '*' | '`' | '[' | ']' | '(' | ')' | '\n' => true
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
  match char_at(input, pos) {
    Some('\n') =>
      (
        Produced(@core.TokenInfo::new(Newline, 1), next_offset=pos + 1),
        LineStart,
      )
    Some('*') =>
      match char_at(input, pos + 1) {
        Some('*') =>
          (
            Produced(@core.TokenInfo::new(StarStar, 2), next_offset=pos + 2),
            Inline,
          )
        _ =>
          (Produced(@core.TokenInfo::new(Star, 1), next_offset=pos + 1), Inline)
      }
    Some('`') =>
      (Produced(@core.TokenInfo::new(Backtick, 1), next_offset=pos + 1), Inline)
    Some('[') =>
      (
        Produced(@core.TokenInfo::new(LeftBracket, 1), next_offset=pos + 1),
        Inline,
      )
    Some(']') =>
      (
        Produced(@core.TokenInfo::new(RightBracket, 1), next_offset=pos + 1),
        Inline,
      )
    Some('(') =>
      (
        Produced(@core.TokenInfo::new(LeftParen, 1), next_offset=pos + 1),
        Inline,
      )
    Some(')') =>
      (
        Produced(@core.TokenInfo::new(RightParen, 1), next_offset=pos + 1),
        Inline,
      )
    _ => {
      // Text run: consume until next special char or newline
      let mut end = pos + 1
      while end < input.length() {
        match char_at(input, end) {
          Some(ch) if is_inline_special(ch) => break
          None => break
          _ => end = end + 1
        }
      }
      let text : StringView = input[pos:end]
      (
        Produced(
          @core.TokenInfo::new(Text(text.to_string()), end - pos),
          next_offset=end,
        ),
        Inline,
      )
    }
  }
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
  match char_at(input, pos) {
    Some('\n') =>
      (
        Produced(@core.TokenInfo::new(Newline, 1), next_offset=pos + 1),
        CodeBlock(fence_len),
      )
    Some('`') => {
      let n = count_backticks(input, pos)
      if n >= fence_len {
        // Check that rest of line is empty (only whitespace/newline)
        let mut after = pos + n
        let mut is_close = true
        while after < input.length() {
          match char_at(input, after) {
            Some('\n') | None => break
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
            match char_at(input, after) {
              Some('\n') => after + 1
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
          // Backticks followed by non-whitespace — treat as code text
          let mut line_end = pos
          while line_end < input.length() {
            match char_at(input, line_end) {
              Some('\n') | None => break
              _ => line_end = line_end + 1
            }
          }
          let text : StringView = input[pos:line_end]
          (
            Produced(
              @core.TokenInfo::new(CodeText(text.to_string()), line_end - pos),
              next_offset=line_end,
            ),
            CodeBlock(fence_len),
          )
        }
      } else {
        // Fewer backticks than fence — treat as code text
        let mut line_end = pos
        while line_end < input.length() {
          match char_at(input, line_end) {
            Some('\n') | None => break
            _ => line_end = line_end + 1
          }
        }
        let text : StringView = input[pos:line_end]
        (
          Produced(
            @core.TokenInfo::new(CodeText(text.to_string()), line_end - pos),
            next_offset=line_end,
          ),
          CodeBlock(fence_len),
        )
      }
    }
    _ => {
      // Code text: consume until newline
      let mut line_end = pos
      while line_end < input.length() {
        match char_at(input, line_end) {
          Some('\n') | None => break
          _ => line_end = line_end + 1
        }
      }
      let text : StringView = input[pos:line_end]
      (
        Produced(
          @core.TokenInfo::new(CodeText(text.to_string()), line_end - pos),
          next_offset=line_end,
        ),
        CodeBlock(fence_len),
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
