///|
fn text_at(
  input : String,
  result : @core.LexResult[@token.Token],
  i : Int,
) -> String {
  let start = result.starts()[i]
  let len = result.tokens()[i].len
  input[start:start + len].to_owned()
}

///|
test "lex empty input" {
  let tokens = lex("").tokens()
  inspect(tokens.length(), content="1")
  match tokens[0].token {
    @token.EOF => ()
    _ => fail("Expected EOF")
  }
}

///|
test "lex plain text" {
  let result = lex("hello")
  let tokens = result.tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.Text => inspect(text_at("hello", result, 0), content="hello")
    _ => fail("Expected Text")
  }
}

///|
test "lex simple open tag" {
  let result = lex("<div>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="4")
  match tokens[0].token {
    @token.OpenTagStart => ()
    _ => fail("Expected OpenTagStart")
  }
  match tokens[1].token {
    @token.TagName => inspect(text_at("<div>", result, 1), content="div")
    _ => fail("Expected TagName")
  }
  match tokens[2].token {
    @token.TagEnd => ()
    _ => fail("Expected TagEnd")
  }
}

///|
test "lex self-closing tag" {
  let result = lex("<br/>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="4")
  match tokens[1].token {
    @token.TagName => inspect(text_at("<br/>", result, 1), content="br")
    _ => fail("Expected TagName")
  }
  match tokens[2].token {
    @token.SelfCloseEnd => ()
    _ => fail("Expected SelfCloseEnd")
  }
}

///|
test "lex close tag" {
  let result = lex("</div>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="5")
  match tokens[0].token {
    @token.OpenTagStart => ()
    _ => fail("Expected OpenTagStart")
  }
  match tokens[1].token {
    @token.Slash => ()
    _ => fail("Expected Slash")
  }
  match tokens[2].token {
    @token.TagName => inspect(text_at("</div>", result, 2), content="div")
    _ => fail("Expected TagName")
  }
  match tokens[3].token {
    @token.TagEnd => ()
    _ => fail("Expected TagEnd")
  }
}

///|
test "lex fragment open and close" {
  let tokens = lex("<></>").tokens()
  inspect(tokens.length(), content="3")
  match tokens[0].token {
    @token.FragmentOpen => ()
    _ => fail("Expected FragmentOpen")
  }
  match tokens[1].token {
    @token.FragmentClose => ()
    _ => fail("Expected FragmentClose")
  }
}

///|
test "lex attribute with double-quoted string value" {
  let result = lex("<div class=\"foo\">")
  let tokens = result.tokens()
  inspect(tokens.length(), content="8")
  match tokens[3].token {
    @token.AttrName =>
      inspect(text_at("<div class=\"foo\">", result, 3), content="class")
    _ => fail("Expected AttrName")
  }
  match tokens[4].token {
    @token.Eq => ()
    _ => fail("Expected Eq")
  }
  match tokens[5].token {
    @token.AttrStringLit =>
      inspect(text_at("<div class=\"foo\">", result, 5), content="\"foo\"")
    _ => fail("Expected AttrStringLit")
  }
  match tokens[2].token {
    @token.Whitespace => ()
    _ => fail("Expected Whitespace")
  }
}

///|
test "lex attribute with single-quoted string value" {
  let tokens = lex("<div class='foo'>").tokens()
  inspect(tokens.length(), content="8")
  match tokens[5].token {
    @token.AttrStringLit => ()
    _ => fail("Expected AttrStringLit")
  }
}

///|
test "lex unterminated attribute string value" {
  let result = lex("<div class=\"foo")
  let tokens = result.tokens()
  inspect(tokens.length(), content="7")
  match tokens[5].token {
    @token.AttrStringLitUnterminated =>
      inspect(text_at("<div class=\"foo", result, 5), content="\"foo")
    _ => fail("Expected AttrStringLitUnterminated")
  }
}

///|
test "lex attribute with embedded expression value" {
  let result = lex("<div id={x}>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="10")
  match tokens[5].token {
    @token.BraceOpen => ()
    _ => fail("Expected BraceOpen")
  }
  match tokens[6].token {
    @token.ExprRawText =>
      inspect(text_at("<div id={x}>", result, 6), content="x")
    _ => fail("Expected ExprRawText")
  }
  match tokens[7].token {
    @token.BraceClose => ()
    _ => fail("Expected BraceClose")
  }
  match tokens[8].token {
    @token.TagEnd => ()
    _ => fail("Expected TagEnd after resuming tag body")
  }
}

///|
test "lex text child" {
  let result = lex("<p>hello</p>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="9")
  match tokens[3].token {
    @token.Text => inspect(text_at("<p>hello</p>", result, 3), content="hello")
    _ => fail("Expected Text")
  }
}

///|
test "lex expression child" {
  let result = lex("<p>{x}</p>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="11")
  match tokens[3].token {
    @token.BraceOpen => ()
    _ => fail("Expected BraceOpen")
  }
  match tokens[4].token {
    @token.ExprRawText => inspect(text_at("<p>{x}</p>", result, 4), content="x")
    _ => fail("Expected ExprRawText")
  }
  match tokens[5].token {
    @token.BraceClose => ()
    _ => fail("Expected BraceClose")
  }
}

///|
test "lex nested braces inside expression are not separately tokenized" {
  // Codex round-1-verified case: {foo({bar: 1})} — the inner object-literal
  // braces are ordinary characters within the ExprRawText run, not their
  // own BraceOpen/BraceClose tokens; only the outermost pair is.
  let result = lex("<p>{foo({bar: 1})}</p>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="11")
  match tokens[4].token {
    @token.ExprRawText =>
      inspect(
        text_at("<p>{foo({bar: 1})}</p>", result, 4),
        content="foo({bar: 1})",
      )
    _ => fail("Expected one ExprRawText token spanning the nested braces")
  }
  match tokens[5].token {
    @token.BraceClose => ()
    _ => fail("Expected BraceClose to be the outermost closing brace only")
  }
}

///|
test "lex brace inside a string literal does not close the expression" {
  // Design A / Codex round-1-verified case: {"a}b"} — the `}` inside the
  // string must not be mistaken for the expression's closing brace.
  let result = lex("<p>{\"a}b\"}</p>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="11")
  match tokens[4].token {
    @token.ExprRawText =>
      inspect(text_at("<p>{\"a}b\"}</p>", result, 4), content="\"a}b\"")
    _ => fail("Expected ExprRawText to include the string's internal brace")
  }
  match tokens[5].token {
    @token.BraceClose => ()
    _ => fail("Expected BraceClose to be the real outer closing brace")
  }
}

///|
test "lex non-nested template literal inside expression" {
  // Design A's accepted case: a single (non-nested) backtick pair with a
  // ${...} interpolation works even though ${} is not specially tracked,
  // because there is exactly one open/close backtick pair to find.
  let result = lex("<p>{`btn ${x}`}</p>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="11")
  match tokens[4].token {
    @token.ExprRawText =>
      inspect(text_at("<p>{`btn ${x}`}</p>", result, 4), content="`btn ${x}`")
    _ => fail("Expected ExprRawText spanning the whole template literal")
  }
  match tokens[5].token {
    @token.BraceClose => ()
    _ => fail("Expected BraceClose after the template literal closes")
  }
}

///|
test "lex expression truncated before closing brace" {
  // Design B case 4: EOF while depth > 0 — no BraceClose token, no
  // synthetic error token; the parser is responsible for the diagnostic.
  let result = lex("<p>{foo.bar(")
  let tokens = result.tokens()
  inspect(tokens.length(), content="6")
  match tokens[4].token {
    @token.ExprRawText =>
      inspect(text_at("<p>{foo.bar(", result, 4), content="foo.bar(")
    _ => fail("Expected ExprRawText for the truncated content")
  }
  match tokens[5].token {
    @token.EOF => ()
    _ => fail("Expected EOF immediately after, no BraceClose")
  }
}

///|
test "lex expression truncated inside a string literal" {
  // Design B case 4 / Codex round-2 gap fix: EOF inside a string gets the
  // distinct ExprStringUnterminated token, not a plain ExprRawText, so the
  // parser can push an additive "missing quote" diagnostic.
  let result = lex("<p>{\"x")
  let tokens = result.tokens()
  inspect(tokens.length(), content="6")
  match tokens[4].token {
    @token.ExprStringUnterminated =>
      inspect(text_at("<p>{\"x", result, 4), content="\"x")
    _ => fail("Expected ExprStringUnterminated")
  }
}

///|
test "lex whitespace between attributes is trivia" {
  let result = lex("<div  a=\"1\"  b=\"2\">")
  let tokens = result.tokens()
  match tokens[2].token {
    @token.Whitespace => ()
    _ => fail("Expected Whitespace")
  }
}

///|
test "lex two levels of nested braces inside expression" {
  // Codex round-2 post-implementation-review case: confirms local_depth
  // increments/decrements correctly through two nesting levels and stops
  // only at the true outermost closing brace.
  let result = lex("<p>{a({b: {c: 1}})}</p>")
  let tokens = result.tokens()
  inspect(tokens.length(), content="11")
  match tokens[4].token {
    @token.ExprRawText =>
      inspect(
        text_at("<p>{a({b: {c: 1}})}</p>", result, 4),
        content="a({b: {c: 1}})",
      )
    _ => fail("Expected one ExprRawText token spanning both nesting levels")
  }
  match tokens[5].token {
    @token.BraceClose => ()
    _ => fail("Expected BraceClose to be the true outermost closing brace")
  }
}

///|
test "lex close tag does not misclassify a following attribute-like token" {
  // Codex round-2 post-implementation-review case: a malformed close tag
  // with attribute-like content still lexes `div` as TagName (first
  // identifier after OpenTagStart+Slash) and `attr` as AttrName (not a
  // second TagName) — expects_tag_name only applies to the first
  // identifier, never resets for a later one.
  let result = lex("</div attr>")
  let tokens = result.tokens()
  match tokens[2].token {
    @token.TagName => inspect(text_at("</div attr>", result, 2), content="div")
    _ => fail("Expected TagName for the close tag's own name")
  }
  match tokens[4].token {
    @token.AttrName =>
      inspect(text_at("</div attr>", result, 4), content="attr")
    _ => fail("Expected AttrName, not a second TagName")
  }
}
