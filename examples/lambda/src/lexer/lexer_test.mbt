// ===== Tokenizer Tests =====

///|
test "tokenize_layout simple integer" {
  let tokens = tokenize_layout("42")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("42"), content="true")
  inspect(token_str.contains("EOF"), content="true")
}

///|
test "tokenize_layout simple variable" {
  let tokens = tokenize_layout("x")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("x"), content="true")
  inspect(token_str.contains("EOF"), content="true")
}

///|
test "tokenize_layout lambda expression" {
  let tokens = tokenize_layout("λx.x")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("λ"), content="true")
  inspect(token_str.contains("x"), content="true")
  inspect(token_str.contains("."), content="true")
}

///|
test "tokenize_layout with backslash lambda" {
  let tokens = tokenize_layout("\\x.x")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("λ"), content="true")
}

///|
test "tokenize_layout plus binary operator" {
  let tokens = tokenize_layout("1 + 2")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("1"), content="true")
  inspect(token_str.contains("+"), content="true")
  inspect(token_str.contains("2"), content="true")
}

///|
test "tokenize_layout minus binary operator" {
  let tokens = tokenize_layout("5 - 2")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("5"), content="true")
  inspect(token_str.contains("-"), content="true")
}

///|
test "tokenize_layout if-then-else" {
  let tokens = tokenize_layout("if x then y else z")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("if"), content="true")
  inspect(token_str.contains("then"), content="true")
  inspect(token_str.contains("else"), content="true")
}

///|
test "tokenize_layout parentheses" {
  let tokens = tokenize_layout("(x)")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("("), content="true")
  inspect(token_str.contains("x"), content="true")
}

///|
test "tokenize_layout multi-digit integer" {
  let tokens = tokenize_layout("12345")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("12345"), content="true")
}

///|
test "tokenize_layout identifier with numbers" {
  let tokens = tokenize_layout("x1y2")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("x1y2"), content="true")
}

///|
test "tokenize_layout whitespace handling" {
  let tokens = tokenize_layout("  x   y  ")
  let token_str = @token.print_token_infos(tokens)
  inspect(token_str.contains("x"), content="true")
  inspect(token_str.contains("y"), content="true")
}

///|
test "tokenize_layout complex expression" {
  let tokens = tokenize_layout("λf.λx.(f (f x))")
  inspect(tokens.length() > 0, content="true")
}

///|
test "tokenize_layout error - invalid character" {
  let should_error = try {
    let _tokens = tokenize_layout("@")
    false
  } catch {
    @core.LexError(_) => true
  }
  inspect(should_error, content="true")
}

///|
test "token_buffer update insertion matches full tokenize_layout" {
  let source = "x"
  let new_source = "x + 1"
  let edit = @core.Edit::insert(1, 4)
  let buffer = @core.TokenBuffer::new(
    source,
    tokenize_fn=tokenize_layout,
    eof_token=@token.EOF,
  )
  buffer.update(edit, new_source)
  let updated = buffer.get_tokens()
  let full = tokenize_layout(new_source)
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
    tokenize_fn=tokenize_layout,
    eof_token=@token.EOF,
  )
  buffer.update(edit, new_source)
  let updated = buffer.get_tokens()
  let full = tokenize_layout(new_source)
  inspect(
    @token.print_token_infos(updated),
    content=@token.print_token_infos(full),
  )
}

///|
test "token_buffer update replacement matches full tokenize_layout" {
  let source = "x + 1"
  let new_source = "x + 42"
  let edit = @core.Edit::replace(4, 5, 6)
  let buffer = @core.TokenBuffer::new(
    source,
    tokenize_fn=tokenize_layout,
    eof_token=@token.EOF,
  )
  buffer.update(edit, new_source)
  let updated = buffer.get_tokens()
  let full = tokenize_layout(new_source)
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
    tokenize_fn=tokenize_layout,
    eof_token=@token.EOF,
  )
  buffer.update(edit, new_source)
  let updated = buffer.get_tokens()
  let full = tokenize_layout(new_source)
  inspect(
    @token.print_token_infos(updated),
    content=@token.print_token_infos(full),
  )
}

///|
test "tokenize_layout includes whitespace tokens" {
  // "x + 1" has whitespace runs between syntactic tokens
  let tokens = tokenize_layout("x + 1")
  let has_whitespace = tokens.iter().any(fn(t) { t.token == @token.Whitespace })
  inspect(has_whitespace, content="true")
}

///|
test "tokenize_layout leading whitespace produces whitespace token" {
  // "  x" has leading whitespace that must become a Whitespace token
  let tokens = tokenize_layout("  x")
  let first = tokens[0]
  inspect(first.token == @token.Whitespace, content="true")
  inspect(first.len, content="2")
}

///|
test "tokenize_layout whitespace lengths are correct" {
  // "x + 1": x(1), ws(1), +(1), ws(1), 1(1), EOF(0)
  let tokens = tokenize_layout("x + 1")
  let ws_tokens = tokens.filter(fn(t) { t.token == @token.Whitespace })
  inspect(ws_tokens.length(), content="2")
  let ws0 = ws_tokens[0]
  inspect(ws0.len, content="1")
  let ws1 = ws_tokens[1]
  inspect(ws1.len, content="1")
}

///|
test "tokenize_layout whitespace-only input" {
  // "   " should produce a single Whitespace token covering the whole input, then EOF
  let tokens = tokenize_layout("   ")
  let ws_tokens = tokens.filter(fn(t) { t.token == @token.Whitespace })
  inspect(ws_tokens.length(), content="1")
  let ws0 = ws_tokens[0]
  inspect(ws0.len, content="3")
  let has_eof = tokens.iter().any(fn(t) { t.token == @token.EOF })
  inspect(has_eof, content="true")
}

///|
test "tokenize_layout mixed whitespace characters fold into one token" {
  // " \t\n" should produce a single Whitespace token, not three separate ones
  let tokens = tokenize_layout(" \t\n")
  let ws_tokens = tokens.filter(fn(t) { t.token == @token.Whitespace })
  inspect(ws_tokens.length(), content="1")
}

///|
test "tokenize_layout trailing whitespace produces whitespace token before EOF" {
  // "x  " should include a Whitespace token after the identifier and before EOF
  let tokens = tokenize_layout("x  ")
  let ws_tokens = tokens.filter(fn(t) { t.token == @token.Whitespace })
  inspect(ws_tokens.length() > 0, content="true")
  let last_ws = ws_tokens[ws_tokens.length() - 1]
  inspect(last_ws.len, content="2")
}

///|
test "tokenize_layout let keyword" {
  let tokens = tokenize_layout("let") catch {
    _ => abort("tokenize_layout failed")
  }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("let"), content="true")
  inspect(s.contains("EOF"), content="true")
}

///|
test "tokenize_layout in keyword" {
  let tokens = tokenize_layout("in") catch {
    _ => abort("tokenize_layout failed")
  }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("in"), content="true")
}

///|
test "tokenize_layout eq" {
  let tokens = tokenize_layout("=") catch {
    _ => abort("tokenize_layout failed")
  }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("="), content="true")
}

///|
test "tokenize_layout let expression" {
  let tokens = tokenize_layout("let x = 1 in x") catch {
    _ => abort("tokenize_layout failed")
  }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("let"), content="true")
  inspect(s.contains("in"), content="true")
  inspect(s.contains("="), content="true")
}
