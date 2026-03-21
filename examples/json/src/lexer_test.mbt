// ===== JSON Lexer Tests =====

///|
test "tokenize simple braces" {
  let tokens = tokenize("{}")
  inspect(print_token_infos(tokens), content="{(1), }(1), EOF(0)")
}

///|
test "tokenize simple brackets" {
  let tokens = tokenize("[]")
  inspect(print_token_infos(tokens), content="[(1), ](1), EOF(0)")
}

///|
test "tokenize colon" {
  let tokens = tokenize(":")
  inspect(print_token_infos(tokens), content=":(1), EOF(0)")
}

///|
test "tokenize comma" {
  let tokens = tokenize(",")
  inspect(print_token_infos(tokens), content=",(1), EOF(0)")
}

///|
test "tokenize simple string" {
  let tokens = tokenize("\"hello\"")
  inspect(print_token_infos(tokens), content="\"hello\"(7), EOF(0)")
}

///|
test "tokenize string with escape" {
  let tokens = tokenize("\"hello\\nworld\"")
  inspect(print_token_infos(tokens), content="\"hello\\nworld\"(14), EOF(0)")
}

///|
test "tokenize empty string" {
  let tokens = tokenize("\"\"")
  inspect(print_token_infos(tokens), content="\"\"(2), EOF(0)")
}

///|
test "tokenize integer" {
  let tokens = tokenize("42")
  inspect(print_token_infos(tokens), content="42(2), EOF(0)")
}

///|
test "tokenize decimal number" {
  let tokens = tokenize("3.14")
  inspect(print_token_infos(tokens), content="3.14(4), EOF(0)")
}

///|
test "tokenize scientific notation" {
  let tokens = tokenize("1e10")
  inspect(print_token_infos(tokens), content="1e10(4), EOF(0)")
}

///|
test "tokenize negative zero" {
  let tokens = tokenize("-0")
  inspect(print_token_infos(tokens), content="-0(2), EOF(0)")
}

///|
test "tokenize negative decimal with exponent" {
  let tokens = tokenize("-2.5E-3")
  inspect(print_token_infos(tokens), content="-2.5E-3(7), EOF(0)")
}

///|
test "tokenize true" {
  let tokens = tokenize("true")
  inspect(print_token_infos(tokens), content="true(4), EOF(0)")
}

///|
test "tokenize false" {
  let tokens = tokenize("false")
  inspect(print_token_infos(tokens), content="false(5), EOF(0)")
}

///|
test "tokenize null" {
  let tokens = tokenize("null")
  inspect(print_token_infos(tokens), content="null(4), EOF(0)")
}

///|
test "tokenize whitespace spaces" {
  let tokens = tokenize("   ")
  inspect(print_token_infos(tokens), content=" (3), EOF(0)")
}

///|
test "tokenize whitespace tabs" {
  let tokens = tokenize("\t\t")
  inspect(print_token_infos(tokens), content=" (2), EOF(0)")
}

///|
test "tokenize whitespace mixed" {
  let tokens = tokenize(" \t\n\r ")
  inspect(print_token_infos(tokens), content=" (5), EOF(0)")
}

///|
test "tokenize full JSON object" {
  let tokens = tokenize("{\"key\": 42, \"arr\": [1, true, null]}")
  let s = print_token_infos(tokens)
  inspect(s.contains("{"), content="true")
  inspect(s.contains("}"), content="true")
  inspect(s.contains("key"), content="true")
  inspect(s.contains("42"), content="true")
  inspect(s.contains("["), content="true")
  inspect(s.contains("]"), content="true")
  inspect(s.contains("true"), content="true")
  inspect(s.contains("null"), content="true")
  inspect(s.contains("EOF"), content="true")
}

///|
test "tokenize empty input" {
  let tokens = tokenize("")
  inspect(print_token_infos(tokens), content="EOF(0)")
}

///|
test "tokenize number then comma" {
  let tokens = tokenize("1,2")
  inspect(print_token_infos(tokens), content="1(1), ,(1), 2(1), EOF(0)")
}

///|
test "tokenize string with unicode escape" {
  let tokens = tokenize("\"\\u0041\"")
  inspect(print_token_infos(tokens), content="\"\\u0041\"(8), EOF(0)")
}

///|
test "tokenize nested structure" {
  let tokens = tokenize("{\"a\":{\"b\":1}}")
  let s = print_token_infos(tokens)
  // Should have two LBrace, two RBrace
  let lbrace_count = tokens.iter().filter(fn(t) { t.token == LBrace }).count()
  let rbrace_count = tokens.iter().filter(fn(t) { t.token == RBrace }).count()
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
  let tokens = tokenize("[ 1 , 2 ]")
  let has_whitespace = tokens.iter().any(fn(t) { t.token == Whitespace })
  inspect(has_whitespace, content="true")
  // Count whitespace tokens: before 1, after 1, after comma, after 2 = 4
  let ws_count = tokens.iter().filter(fn(t) { t.token == Whitespace }).count()
  inspect(ws_count, content="4")
}

///|
test "tokenize zero" {
  let tokens = tokenize("0")
  inspect(print_token_infos(tokens), content="0(1), EOF(0)")
}

///|
test "token byte_length matches raw text" {
  let tokens = tokenize("\"hello\"")
  // StringLit("\"hello\"") should have len=7 (including quotes)
  let str_token = tokens[0]
  inspect(str_token.len, content="7")
}
