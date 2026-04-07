// ===== Tokenizer Tests =====

///|
test "tokenize simple integer" {
  let tokens = tokenize("42")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("<int>"), content="true")
  inspect(token_str.contains("EOF"), content="true")
}

///|
test "tokenize simple variable" {
  let tokens = tokenize("x")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("<ident>"), content="true")
  inspect(token_str.contains("EOF"), content="true")
}

///|
test "tokenize lambda expression" {
  let tokens = tokenize("λx.x")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("λ"), content="true")
  inspect(token_str.contains("<ident>"), content="true")
  inspect(token_str.contains("."), content="true")
}

///|
test "tokenize with backslash lambda" {
  let tokens = tokenize("\\x.x")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("λ"), content="true")
}

///|
test "tokenize plus binary operator" {
  let tokens = tokenize("1 + 2")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("<int>"), content="true")
  inspect(token_str.contains("+"), content="true")
}

///|
test "tokenize minus binary operator" {
  let tokens = tokenize("5 - 2")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("<int>"), content="true")
  inspect(token_str.contains("-"), content="true")
}

///|
test "tokenize if-then-else" {
  let tokens = tokenize("if x then y else z")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("if"), content="true")
  inspect(token_str.contains("then"), content="true")
  inspect(token_str.contains("else"), content="true")
}

///|
test "tokenize parentheses" {
  let tokens = tokenize("(x)")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("("), content="true")
  inspect(token_str.contains("<ident>"), content="true")
}

///|
test "tokenize multi-digit integer" {
  let tokens = tokenize("12345")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("<int>"), content="true")
}

///|
test "tokenize identifier with numbers" {
  let tokens = tokenize("x1y2")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("<ident>"), content="true")
}

///|
test "tokenize whitespace handling" {
  let tokens = tokenize("  x   y  ")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("<ident>"), content="true")
  inspect(token_str.contains("whitespace"), content="true")
}

///|
test "tokenize complex expression" {
  let tokens = tokenize("λf.λx.(f (f x))")
  inspect(tokens.length() > 0, content="true")
}

///|
test "tokenize error - invalid character" {
  let should_error = try {
    let _tokens = tokenize("@")
    false
  } catch {
    @core.LexError(_) => true
  }
  inspect(should_error, content="true")
}

///|
test "token_buffer update insertion matches full tokenize" {
  let source = "x"
  let new_source = "x + 1"
  let edit = @core.Edit::insert(1, 4)
  let buffer = @core.TokenBuffer::new(
    source,
    tokenize_fn=tokenize,
    eof_token=@token.EOF,
  )
  buffer.update(edit, new_source)
  let updated = buffer.get_tokens()
  let full = tokenize(new_source)
  inspect(
    @token.print_token_infos(updated),
    content=@token.print_token_infos(full),
  )
}

///|
test "token_buffer update deletion merges identifiers" {
  let source = "x y"
  let new_source = "xy"
  let edit = @core.Edit::delete(1, 2)
  let buffer = @core.TokenBuffer::new(
    source,
    tokenize_fn=tokenize,
    eof_token=@token.EOF,
  )
  buffer.update(edit, new_source)
  let updated = buffer.get_tokens()
  let full = tokenize(new_source)
  inspect(
    @token.print_token_infos(updated),
    content=@token.print_token_infos(full),
  )
}

///|
test "token_buffer update replacement matches full tokenize" {
  let source = "x + 1"
  let new_source = "x + 42"
  let edit = @core.Edit::replace(4, 5, 6)
  let buffer = @core.TokenBuffer::new(
    source,
    tokenize_fn=tokenize,
    eof_token=@token.EOF,
  )
  buffer.update(edit, new_source)
  let updated = buffer.get_tokens()
  let full = tokenize(new_source)
  inspect(
    @token.print_token_infos(updated),
    content=@token.print_token_infos(full),
  )
}

///|
test "token_buffer update insertion creates keyword" {
  let source = "i"
  let new_source = "if"
  let edit = @core.Edit::insert(1, 1)
  let buffer = @core.TokenBuffer::new(
    source,
    tokenize_fn=tokenize,
    eof_token=@token.EOF,
  )
  buffer.update(edit, new_source)
  let updated = buffer.get_tokens()
  let full = tokenize(new_source)
  inspect(
    @token.print_token_infos(updated),
    content=@token.print_token_infos(full),
  )
}

///|
test "tokenize includes whitespace tokens" {
  // "x + 1" has whitespace runs between syntactic tokens
  let tokens = tokenize("x + 1")
  let has_whitespace = tokens.iter().any(fn(t) { t.token == @token.Whitespace })
  inspect(has_whitespace, content="true")
}

///|
test "tokenize leading whitespace produces whitespace token" {
  // "  x" has leading whitespace that must become a Whitespace token
  let tokens = tokenize("  x")
  let first = tokens[0]
  inspect(first.token == @token.Whitespace, content="true")
  inspect(first.len, content="2")
}

///|
test "tokenize whitespace lengths are correct" {
  // "x + 1": x(1), ws(1), +(1), ws(1), 1(1), EOF(0)
  let tokens = tokenize("x + 1")
  let ws_tokens = tokens.filter(fn(t) { t.token == @token.Whitespace })
  inspect(ws_tokens.length(), content="2")
  let ws0 = ws_tokens[0]
  inspect(ws0.len, content="1")
  let ws1 = ws_tokens[1]
  inspect(ws1.len, content="1")
}

///|
test "tokenize whitespace-only input" {
  // "   " should produce a single Whitespace token covering the whole input, then EOF
  let tokens = tokenize("   ")
  let ws_tokens = tokens.filter(fn(t) { t.token == @token.Whitespace })
  inspect(ws_tokens.length(), content="1")
  let ws0 = ws_tokens[0]
  inspect(ws0.len, content="3")
  let has_eof = tokens.iter().any(fn(t) { t.token == @token.EOF })
  inspect(has_eof, content="true")
}

///|
test "tokenize mixed whitespace characters fold into one token" {
  // " \t\n" should produce a single Whitespace token, not three separate ones
  let tokens = tokenize(" \t\n")
  let ws_tokens = tokens.filter(fn(t) { t.token == @token.Whitespace })
  inspect(ws_tokens.length(), content="1")
}

///|
test "tokenize trailing whitespace produces whitespace token before EOF" {
  // "x  " should include a Whitespace token after the identifier and before EOF
  let tokens = tokenize("x  ")
  let ws_tokens = tokens.filter(fn(t) { t.token == @token.Whitespace })
  inspect(ws_tokens.length() > 0, content="true")
  let last_ws = ws_tokens[ws_tokens.length() - 1]
  inspect(last_ws.len, content="2")
}

///|
test "tokenize let keyword" {
  let tokens = tokenize("let") catch { _ => abort("tokenize failed") }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("let"), content="true")
  inspect(s.contains("EOF"), content="true")
}

///|
test "tokenize in as identifier (not a keyword)" {
  let tokens = tokenize("in") catch { _ => abort("tokenize failed") }
  let s = @token.print_token_infos(tokens)
  // "in" is no longer a keyword — lexes as an identifier
  inspect(s.contains("<ident>"), content="true")
}

///|
test "tokenize eq" {
  let tokens = tokenize("=") catch { _ => abort("tokenize failed") }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("="), content="true")
}

///|
test "tokenize let definition" {
  let tokens = tokenize("let x = 1") catch { _ => abort("tokenize failed") }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("let"), content="true")
  inspect(s.contains("<ident>"), content="true")
  inspect(s.contains("="), content="true")
  inspect(s.contains("<int>"), content="true")
}

///|
test "tokenize braces" {
  let tokens = tokenize("{}")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("{"), content="true")
  inspect(token_str.contains("}"), content="true")
}

///|
test "tokenize comma" {
  let tokens = tokenize("x,y")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains(","), content="true")
  inspect(token_str.contains("<ident>"), content="true")
}

///|
test "tokenize semicolon" {
  let tokens = tokenize("a;b")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains(";"), content="true")
}

///|
test "tokenize block with semicolons" {
  let tokens = tokenize("{ let a = 1; a }")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("{"), content="true")
  inspect(token_str.contains(";"), content="true")
  inspect(token_str.contains("}"), content="true")
}
