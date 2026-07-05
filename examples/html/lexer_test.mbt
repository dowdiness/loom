///|
test "lex simple open tag" {
  let tokens = lex("<div>").tokens()
  inspect(tokens.length(), content="2") // OpenTag("div"), EOF
  match tokens[0].token {
    OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex close tag" {
  let tokens = lex("</div>").tokens()
  inspect(tokens.length(), content="2") // CloseTag("div"), EOF
  match tokens[0].token {
    CloseTag(name) => inspect(name, content="div")
    _ => fail("Expected CloseTag")
  }
}

///|
test "lex element with text content" {
  let tokens = lex("<p>hello</p>").tokens()
  inspect(tokens.length(), content="4") // OpenTag, Text, CloseTag, EOF
}

///|
test "lex void element" {
  let tokens = lex("<br>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    OpenTag(name) => inspect(name, content="br")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex self-closing element" {
  let tokens = lex("<br/>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    OpenTag(name) => inspect(name, content="br")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex empty input" {
  let tokens = lex("").tokens()
  inspect(tokens.length(), content="1") // EOF only
}

///|
test "lex attribute with double quotes" {
  let tokens = lex("<div class=\"foo\">").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex comment" {
  let tokens = lex("<!-- comment -->").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    Comment => ()
    _ => fail("Expected Comment")
  }
}

///|
test "lex doctype" {
  let tokens = lex("<!DOCTYPE html>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    Doctype => ()
    _ => fail("Expected Doctype")
  }
}

///|
test "lex multiple elements" {
  let tokens = lex("<ul><li>a</li><li>b</li></ul>").tokens()
  // ul, li, text, /li, li, text, /li, /ul, EOF = 9
  inspect(tokens.length(), content="9")
}

///|
test "lex with whitespace" {
  let tokens = lex("<p>\n  text\n</p>").tokens()
  // OpenTag, Whitespace, Text, CloseTag, EOF = 5 (trailing \n consumed as Text)
  inspect(tokens.length(), content="5")
}

///|
test "lex input with whitespace before tag" {
  let tokens = lex("  <div>").tokens()
  inspect(tokens.length(), content="3") // Whitespace, OpenTag, EOF
  match tokens[1].token {
    OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag as second token")
  }
}
