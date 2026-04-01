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
  // After CodeFenceClose, mode is LineStart, so \n is BlankLine
  inspect(@debug.to_string(tokens[5].token), content="BlankLine")
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
  inspect(@debug.to_string(tokens[0].token), content="ListMarker")
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
