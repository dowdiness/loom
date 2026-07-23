///|
test "lexer: heading" {
  let tokens = tokenize("# Hello\n")
  inspect(@debug.to_string(tokens[0].token), content="HeadingMarker(1)")
  inspect(@debug.to_string(tokens[1].token), content="Text(\"Hello\")")
  inspect(@debug.to_string(tokens[2].token), content="Newline")
  inspect(@debug.to_string(tokens[3].token), content="EOF")
}

///|
test "lexer: h2 heading" {
  let tokens = tokenize("## World\n")
  inspect(@debug.to_string(tokens[0].token), content="HeadingMarker(2)")
  inspect(@debug.to_string(tokens[1].token), content="Text(\"World\")")
}

///|
test "lexer: paragraph text preserves spaces" {
  let tokens = tokenize("hello world\n")
  inspect(@debug.to_string(tokens[0].token), content="Text(\"hello world\")")
  inspect(@debug.to_string(tokens[1].token), content="Newline")
}

///|
test "lexer: paragraph text keeps non-BMP character in one token" {
  let tokens = tokenize("hello 😈 world\n")
  inspect(
    @debug.to_string(tokens[0].token),
    content="Text(\"hello 😈 world\")",
  )
  inspect(tokens[0].len, content="14")
}

///|
test "lexer: CRLF paragraph newline" {
  let tokens = tokenize("hello\r\n")
  inspect(@debug.to_string(tokens[0].token), content="Text(\"hello\")")
  inspect(@debug.to_string(tokens[1].token), content="Newline")
  inspect(tokens[1].len, content="2")
}

///|
test "lexer: whitespace-only CRLF line is blank" {
  let tokens = tokenize(" \t\r\nnext")
  inspect(@debug.to_string(tokens[0].token), content="BlankLine")
  inspect(tokens[0].len, content="4")
  inspect(@debug.to_string(tokens[1].token), content="Text(\"next\")")
}

///|
test "lexer: code fence with info" {
  let tokens = tokenize("```python\ncode here\n```\n")
  inspect(
    @debug.to_string(tokens[0].token),
    content="CodeFenceOpen(3, \"python\")",
  )
  inspect(@debug.to_string(tokens[1].token), content="Newline")
  inspect(@debug.to_string(tokens[2].token), content="CodeText(\"code here\")")
  inspect(@debug.to_string(tokens[3].token), content="Newline")
  inspect(@debug.to_string(tokens[4].token), content="CodeFenceClose")
  // CodeFenceClose now consumes trailing newline, so EOF is next
  inspect(@debug.to_string(tokens[5].token), content="EOF")
}

///|
test "lexer: code fence info and text keep non-BMP characters" {
  let tokens = tokenize("```😈\ncode 😈\n```\n")
  inspect(
    @debug.to_string(tokens[0].token),
    content="CodeFenceOpen(3, \"😈\")",
  )
  inspect(tokens[0].len, content="5")
  inspect(@debug.to_string(tokens[2].token), content="CodeText(\"code 😈\")")
  inspect(tokens[2].len, content="7")
}

///|
test "lexer: inline markers" {
  let tokens = tokenize("**bold** and *italic*\n")
  inspect(@debug.to_string(tokens[0].token), content="StarStar")
  inspect(@debug.to_string(tokens[1].token), content="Text(\"bold\")")
  inspect(@debug.to_string(tokens[2].token), content="StarStar")
  inspect(@debug.to_string(tokens[3].token), content="Text(\" and \")")
  inspect(@debug.to_string(tokens[4].token), content="Star")
  inspect(@debug.to_string(tokens[5].token), content="Text(\"italic\")")
  inspect(@debug.to_string(tokens[6].token), content="Star")
}

///|
test "lexer: list marker consumes trailing space" {
  let tokens = tokenize("- item\n")
  inspect(@debug.to_string(tokens[0].token), content="ListMarker(Dash)")
  inspect(@debug.to_string(tokens[1].token), content="Text(\"item\")")
}

///|
test "lexer: transports thematic and unordered-list marker facts" {
  let thematic = tokenize("  * * *  \n")
  inspect(@debug.to_string(thematic[0].token), content="Indentation(\"  \")")
  inspect(
    @debug.to_string(thematic[1].token),
    content="ThematicBreak(\"* * *  \")",
  )
  inspect(thematic[1].len, content="7")

  let dash = tokenize("- \n")
  inspect(@debug.to_string(dash[0].token), content="ListMarker(Dash)")
  inspect(dash[0].len, content="2")

  let star = tokenize("* item\n")
  inspect(@debug.to_string(star[0].token), content="ListMarker(Star)")
  inspect(star[0].len, content="2")

  let plus = tokenize("+\n")
  inspect(@debug.to_string(plus[0].token), content="ListMarker(Plus)")
  inspect(plus[0].len, content="1")
}

///|
test "lexer: ordered list marker consumes full marker text" {
  let tokens = tokenize("01. item\n")
  inspect(
    @debug.to_string(tokens[0].token),
    content="OrderedListMarker({ start: 1, delimiter: Period })",
  )
  inspect(@debug.to_string(tokens[1].token), content="Text(\"item\")")
}

///|
test "lexer: blank line" {
  let tokens = tokenize("\n\n")
  // First \n from empty line -> BlankLine, second \n -> BlankLine
  inspect(@debug.to_string(tokens[0].token), content="BlankLine")
}

///|
test "lexer: code fence backtick count matching" {
  let tokens = tokenize("````\n```\n````\n")
  inspect(@debug.to_string(tokens[0].token), content="CodeFenceOpen(4, \"\")")
  inspect(@debug.to_string(tokens[2].token), content="CodeText(\"```\")")
  inspect(@debug.to_string(tokens[4].token), content="CodeFenceClose")
}

///|
test "lexer: link brackets" {
  let tokens = tokenize("[text](url)\n")
  inspect(@debug.to_string(tokens[0].token), content="LeftBracket")
  inspect(@debug.to_string(tokens[1].token), content="Text(\"text\")")
  inspect(@debug.to_string(tokens[2].token), content="RightBracket")
  inspect(@debug.to_string(tokens[3].token), content="LeftParen")
  inspect(@debug.to_string(tokens[4].token), content="Text(\"url\")")
  inspect(@debug.to_string(tokens[5].token), content="RightParen")
}

///|
test "lexer: baseline indentation exposes normal line-start tokens" {
  let tokens = tokenize("    `code`\n  # heading\n")
  inspect(@debug.to_string(tokens[0].token), content="Indentation(\"    \")")
  inspect(@debug.to_string(tokens[1].token), content="Backtick")
  inspect(@debug.to_string(tokens[2].token), content="Text(\"code\")")
  inspect(@debug.to_string(tokens[3].token), content="Backtick")
  inspect(@debug.to_string(tokens[4].token), content="Newline")
  inspect(@debug.to_string(tokens[5].token), content="Indentation(\"  \")")
  inspect(@debug.to_string(tokens[6].token), content="HeadingMarker(1)")
  inspect(@debug.to_string(tokens[7].token), content="Text(\"heading\")")
}

///|
test "lexer: baseline indentation preserves marker candidates" {
  let heading = tokenize("  # heading\n")
  inspect(@debug.to_string(heading[0].token), content="Indentation(\"  \")")
  inspect(@debug.to_string(heading[1].token), content="HeadingMarker(1)")

  let quote = tokenize("    > quote\n")
  inspect(@debug.to_string(quote[0].token), content="Indentation(\"    \")")
  inspect(@debug.to_string(quote[1].token), content="BlockQuoteMarker")

  let list = tokenize("    - item\n")
  inspect(@debug.to_string(list[0].token), content="Indentation(\"    \")")
  inspect(@debug.to_string(list[1].token), content="ListMarker(Dash)")

  let fence = tokenize("    ```\n")
  inspect(@debug.to_string(fence[0].token), content="Indentation(\"    \")")
  inspect(@debug.to_string(fence[1].token), content="CodeFenceOpen(3, \"\")")
}

///|
test "lexer: list-relative indentation exposes inline candidates" {
  let tokens = tokenize("- item\n    `code`\n")
  inspect(@debug.to_string(tokens[3].token), content="Indentation(\"    \")")
  inspect(@debug.to_string(tokens[4].token), content="Backtick")
  inspect(@debug.to_string(tokens[5].token), content="Text(\"code\")")
  inspect(@debug.to_string(tokens[6].token), content="Backtick")
}

///|
test "lexer: list-relative indentation preserves marker candidates" {
  let heading = tokenize("- item\n    # heading\n")
  inspect(@debug.to_string(heading[3].token), content="Indentation(\"    \")")
  inspect(@debug.to_string(heading[4].token), content="HeadingMarker(1)")

  let quote = tokenize("- item\n    > quote\n")
  inspect(@debug.to_string(quote[3].token), content="Indentation(\"    \")")
  inspect(@debug.to_string(quote[4].token), content="BlockQuoteMarker")

  let list = tokenize("- item\n    - nested\n")
  inspect(@debug.to_string(list[3].token), content="Indentation(\"    \")")
  inspect(@debug.to_string(list[4].token), content="ListMarker(Dash)")

  let fence = tokenize("- item\n    ```\n")
  inspect(@debug.to_string(fence[3].token), content="Indentation(\"    \")")
  inspect(@debug.to_string(fence[4].token), content="CodeFenceOpen(3, \"\")")
}

///|
test "lexer: list-content indentation preserves quote candidate" {
  let tokens = tokenize("- item\n  > quote\n")
  inspect(@debug.to_string(tokens[3].token), content="Indentation(\"  \")")
  inspect(@debug.to_string(tokens[4].token), content="BlockQuoteMarker")
}

///|
test "lexer: indented thematic break preserves indentation token" {
  let tokens = tokenize("  ---\n")
  inspect(@debug.to_string(tokens[0].token), content="Indentation(\"  \")")
  inspect(@debug.to_string(tokens[1].token), content="ThematicBreak(\"---\")")
}

///|
test "lexer: three-space-prefixed closing fence closes code block" {
  let tokens = tokenize("   ```\ncode\n   ```\n")
  inspect(@debug.to_string(tokens[5].token), content="CodeFenceClose")
}

///|
test "lexer: inline backtick runs are maximal and escaped runs remain visible" {
  let runs = tokenize("``code```\n")
  inspect(@debug.to_string(runs[0].token), content="Backtick")
  inspect(runs[0].len, content="2")
  inspect(@debug.to_string(runs[1].token), content="Text(\"code\")")
  inspect(@debug.to_string(runs[2].token), content="Backtick")
  inspect(runs[2].len, content="3")

  let escaped = tokenize("\\`literal\n")
  inspect(escaped[0].len, content="1")
  inspect(@debug.to_string(escaped[1].token), content="Backtick")
}
