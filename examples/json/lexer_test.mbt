// ===== JSON Lexer Tests =====

///|
test "tokenize simple braces" {
  let source_id = @core.SourceId("json-lexer-simple-braces")
  let tokens = tokenize(source_id, "{}")
  inspect(print_token_infos(tokens), content="{(1), }(1), EOF(0)")
}

///|
test "tokenize simple brackets" {
  let source_id = @core.SourceId("json-lexer-simple-brackets")
  let tokens = tokenize(source_id, "[]")
  inspect(print_token_infos(tokens), content="[(1), ](1), EOF(0)")
}

///|
test "tokenize colon" {
  let source_id = @core.SourceId("json-lexer-colon")
  let tokens = tokenize(source_id, ":")
  inspect(print_token_infos(tokens), content=":(1), EOF(0)")
}

///|
test "tokenize comma" {
  let source_id = @core.SourceId("json-lexer-comma")
  let tokens = tokenize(source_id, ",")
  inspect(print_token_infos(tokens), content=",(1), EOF(0)")
}

///|
test "tokenize simple string" {
  let source_id = @core.SourceId("json-lexer-simple-string")
  let tokens = tokenize(source_id, "\"hello\"")
  inspect(print_token_infos(tokens), content="<string>(7), EOF(0)")
}

///|
test "tokenize string with escape" {
  let source_id = @core.SourceId("json-lexer-string-escape")
  let tokens = tokenize(source_id, "\"hello\\nworld\"")
  inspect(print_token_infos(tokens), content="<string>(14), EOF(0)")
}

///|
test "tokenize empty string" {
  let source_id = @core.SourceId("json-lexer-empty-string")
  let tokens = tokenize(source_id, "\"\"")
  inspect(print_token_infos(tokens), content="<string>(2), EOF(0)")
}

///|
test "tokenize integer" {
  let source_id = @core.SourceId("json-lexer-integer")
  let tokens = tokenize(source_id, "42")
  inspect(print_token_infos(tokens), content="<number>(2), EOF(0)")
}

///|
test "tokenize decimal number" {
  let source_id = @core.SourceId("json-lexer-decimal")
  let tokens = tokenize(source_id, "3.14")
  inspect(print_token_infos(tokens), content="<number>(4), EOF(0)")
}

///|
test "tokenize scientific notation" {
  let source_id = @core.SourceId("json-lexer-scientific")
  let tokens = tokenize(source_id, "1e10")
  inspect(print_token_infos(tokens), content="<number>(4), EOF(0)")
}

///|
test "tokenize negative zero" {
  let source_id = @core.SourceId("json-lexer-negative-zero")
  let tokens = tokenize(source_id, "-0")
  inspect(print_token_infos(tokens), content="<number>(2), EOF(0)")
}

///|
test "tokenize negative decimal with exponent" {
  let source_id = @core.SourceId("json-lexer-negative-decimal-exponent")
  let tokens = tokenize(source_id, "-2.5E-3")
  inspect(print_token_infos(tokens), content="<number>(7), EOF(0)")
}

///|
test "tokenize true" {
  let source_id = @core.SourceId("json-lexer-true")
  let tokens = tokenize(source_id, "true")
  inspect(print_token_infos(tokens), content="true(4), EOF(0)")
}

///|
test "tokenize false" {
  let source_id = @core.SourceId("json-lexer-false")
  let tokens = tokenize(source_id, "false")
  inspect(print_token_infos(tokens), content="false(5), EOF(0)")
}

///|
test "tokenize null" {
  let source_id = @core.SourceId("json-lexer-null")
  let tokens = tokenize(source_id, "null")
  inspect(print_token_infos(tokens), content="null(4), EOF(0)")
}

///|
test "tokenize whitespace spaces" {
  let source_id = @core.SourceId("json-lexer-whitespace-spaces")
  let tokens = tokenize(source_id, "   ")
  inspect(print_token_infos(tokens), content=" (3), EOF(0)")
}

///|
test "tokenize whitespace tabs" {
  let source_id = @core.SourceId("json-lexer-whitespace-tabs")
  let tokens = tokenize(source_id, "\t\t")
  inspect(print_token_infos(tokens), content=" (2), EOF(0)")
}

///|
test "tokenize whitespace mixed" {
  let source_id = @core.SourceId("json-lexer-whitespace-mixed")
  let tokens = tokenize(source_id, " \t\n\r ")
  inspect(print_token_infos(tokens), content=" (5), EOF(0)")
}

///|
test "tokenize full JSON object" {
  let source_id = @core.SourceId("json-lexer-full-object")
  let tokens = tokenize(source_id, "{\"key\": 42, \"arr\": [1, true, null]}")
  let s = print_token_infos(tokens)
  inspect(s.contains("{"), content="true")
  inspect(s.contains("}"), content="true")
  inspect(s.contains("<string>"), content="true")
  inspect(s.contains("<number>"), content="true")
  inspect(s.contains("["), content="true")
  inspect(s.contains("]"), content="true")
  inspect(s.contains("true"), content="true")
  inspect(s.contains("null"), content="true")
  inspect(s.contains("EOF"), content="true")
}

///|
test "tokenize empty input" {
  let source_id = @core.SourceId("json-lexer-empty-input")
  let tokens = tokenize(source_id, "")
  inspect(print_token_infos(tokens), content="EOF(0)")
}

///|
test "tokenize number then comma" {
  let source_id = @core.SourceId("json-lexer-number-comma")
  let tokens = tokenize(source_id, "1,2")
  inspect(
    print_token_infos(tokens),
    content="<number>(1), ,(1), <number>(1), EOF(0)",
  )
}

///|
test "tokenize string with unicode escape" {
  let source_id = @core.SourceId("json-lexer-unicode-escape")
  let tokens = tokenize(source_id, "\"\\u0041\"")
  inspect(print_token_infos(tokens), content="<string>(8), EOF(0)")
}

///|
test "tokenize invalid string escape preserves following comma" {
  let source_id = @core.SourceId("json-lexer-invalid-escape")
  let tokens = tokenize(source_id, "\"a\\q,1")
  inspect(
    print_token_infos(tokens),
    content="<error: Invalid escape sequence>(4), ,(1), <number>(1), EOF(0)",
  )
}

///|
test "tokenize string with non-BMP character" {
  let source_id = @core.SourceId("json-lexer-string-non-bmp")
  let tokens = tokenize(source_id, "\"😈\"")
  inspect(print_token_infos(tokens), content="<string>(4), EOF(0)")
}

///|
test "tokenize unexpected non-BMP character as one error token" {
  let source_id = @core.SourceId("json-lexer-unexpected-non-bmp")
  let tokens = tokenize(source_id, "😈")
  inspect(
    print_token_infos(tokens),
    content="<error: Unexpected character: 😈>(2), EOF(0)",
  )
}

///|
test "tokenize nested structure" {
  let source_id = @core.SourceId("json-lexer-nested-structure")
  let tokens = tokenize(source_id, "{\"a\":{\"b\":1}}")
  let s = print_token_infos(tokens)
  // Should have two LBrace, two RBrace
  let lbrace_count = tokens.iter().filter(t => t.token == LBrace).count()
  let rbrace_count = tokens.iter().filter(t => t.token == RBrace).count()
  inspect(lbrace_count, content="2")
  inspect(rbrace_count, content="2")
  inspect(s.contains("EOF"), content="true")
}

///|
test "step_lex returns Done on empty input" {
  let result = json_step_lexer("", 0)
  let is_done = match result {
    Done => true
    _ => false
  }
  inspect(is_done, content="true")
}

///|
test "step_lex returns Done past end" {
  let result = json_step_lexer("x", 5)
  let is_done = match result {
    Done => true
    _ => false
  }
  inspect(is_done, content="true")
}

///|
test "tokenize whitespace between tokens preserved" {
  let source_id = @core.SourceId("json-lexer-whitespace-between-tokens")
  let tokens = tokenize(source_id, "[ 1 , 2 ]")
  let has_whitespace = tokens.iter().any(t => t.token == Whitespace)
  inspect(has_whitespace, content="true")
  // Count whitespace tokens: before 1, after 1, after comma, after 2 = 4
  let ws_count = tokens.iter().filter(t => t.token == Whitespace).count()
  inspect(ws_count, content="4")
}

///|
test "tokenize zero" {
  let source_id = @core.SourceId("json-lexer-zero")
  let tokens = tokenize(source_id, "0")
  inspect(print_token_infos(tokens), content="<number>(1), EOF(0)")
}

///|
test "token byte_length matches raw text" {
  let source_id = @core.SourceId("json-lexer-token-length")
  let tokens = tokenize(source_id, "\"hello\"")
  // StringLit("\"hello\"") should have len=7 (including quotes)
  let str_token = tokens[0]
  inspect(str_token.len, content="7")
}
