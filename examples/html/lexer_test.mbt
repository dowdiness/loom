///|
test "lex simple open tag" {
  let tokens = lex("<div>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex close tag" {
  let tokens = lex("</div>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.CloseTag(name) => inspect(name, content="div")
    _ => fail("Expected CloseTag")
  }
}

///|
test "lex element with text content" {
  let tokens = lex("<p>hello</p>").tokens()
  inspect(tokens.length(), content="4")
}

///|
test "lex void element" {
  let tokens = lex("<br>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.OpenTag(name) => inspect(name, content="br")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex self-closing element" {
  let tokens = lex("<br/>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.OpenTag(name) => inspect(name, content="br")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex empty input" {
  let tokens = lex("").tokens()
  inspect(tokens.length(), content="1")
}

///|
test "lex attribute with double quotes" {
  let tokens = lex("<div class=\"foo\">").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex comment" {
  let tokens = lex("<!-- comment -->").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.Comment => ()
    _ => fail("Expected Comment")
  }
}

///|
test "lex doctype" {
  let tokens = lex("<!DOCTYPE html>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.Doctype => ()
    _ => fail("Expected Doctype")
  }
}

///|
test "lex multiple elements" {
  let tokens = lex("<ul><li>a</li><li>b</li></ul>").tokens()
  inspect(tokens.length(), content="9")
}

///|
test "lex with whitespace" {
  let tokens = lex("<p>\n  text\n</p>").tokens()
  inspect(tokens.length(), content="5")
}

///|
test "lex input with whitespace before tag" {
  let tokens = lex("  <div>").tokens()
  inspect(tokens.length(), content="3")
  match tokens[1].token {
    @token.OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag as second token")
  }
}
