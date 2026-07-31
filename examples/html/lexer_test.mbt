///|
test "lex simple open tag" {
  let source_id = @core.SourceId("html-lexer-simple-open-tag")
  let tokens = lex(source_id, "<div>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex close tag" {
  let source_id = @core.SourceId("html-lexer-close-tag")
  let tokens = lex(source_id, "</div>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.CloseTag(name) => inspect(name, content="div")
    _ => fail("Expected CloseTag")
  }
}

///|
test "lex element with text content" {
  let source_id = @core.SourceId("html-lexer-text-content")
  let tokens = lex(source_id, "<p>hello</p>").tokens()
  inspect(tokens.length(), content="4")
}

///|
test "lex void element" {
  let source_id = @core.SourceId("html-lexer-void-element")
  let tokens = lex(source_id, "<br>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.OpenTag(name) => inspect(name, content="br")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex self-closing element" {
  let source_id = @core.SourceId("html-lexer-self-closing-element")
  let tokens = lex(source_id, "<br/>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.OpenTag(name) => inspect(name, content="br")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex empty input" {
  let source_id = @core.SourceId("html-lexer-empty-input")
  let tokens = lex(source_id, "").tokens()
  inspect(tokens.length(), content="1")
}

///|
test "lex attribute with double quotes" {
  let source_id = @core.SourceId("html-lexer-double-quoted-attribute")
  let tokens = lex(source_id, "<div class=\"foo\">").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag")
  }
}

///|
test "lex comment" {
  let source_id = @core.SourceId("html-lexer-comment")
  let tokens = lex(source_id, "<!-- comment -->").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.Comment => ()
    _ => fail("Expected Comment")
  }
}

///|
test "lex doctype" {
  let source_id = @core.SourceId("html-lexer-doctype")
  let tokens = lex(source_id, "<!DOCTYPE html>").tokens()
  inspect(tokens.length(), content="2")
  match tokens[0].token {
    @token.Doctype => ()
    _ => fail("Expected Doctype")
  }
}

///|
test "lex multiple elements" {
  let source_id = @core.SourceId("html-lexer-multiple-elements")
  let tokens = lex(source_id, "<ul><li>a</li><li>b</li></ul>").tokens()
  inspect(tokens.length(), content="9")
}

///|
test "lex with whitespace" {
  let source_id = @core.SourceId("html-lexer-whitespace")
  let tokens = lex(source_id, "<p>\n  text\n</p>").tokens()
  inspect(tokens.length(), content="5")
}

///|
test "lex input with whitespace before tag" {
  let source_id = @core.SourceId("html-lexer-leading-whitespace")
  let tokens = lex(source_id, "  <div>").tokens()
  inspect(tokens.length(), content="3")
  match tokens[1].token {
    @token.OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag as second token")
  }
}

///|
test "lex script content as raw text, not text" {
  // Regression for loom #626.
  let source_id = @core.SourceId("html-lexer-script-raw-text")
  let result = lex(source_id, "<script>var x = 1;</script>")
  let tokens = result.tokens()
  let starts = result.starts()
  inspect(tokens.length(), content="4")
  match tokens[1].token {
    @token.RawText => {
      inspect(starts[1], content="8")
      inspect(tokens[1].len, content="10")
    }
    _ => fail("Expected RawText as second token")
  }
  match tokens[2].token {
    @token.CloseTag(name) => inspect(name, content="script")
    _ => fail("Expected CloseTag as third token")
  }
}

///|
test "lex script raw text is case-insensitive and empty-safe" {
  // Regression for loom #626 — mixed-case tag names and an immediately
  // closed raw-text element (no zero-width RawText token, no hang).
  let source_id = @core.SourceId("html-lexer-script-case-and-empty")
  let mixed_case = lex(source_id, "<SCRIPT>a</SCRIPT>").tokens()
  inspect(mixed_case.length(), content="4")
  match mixed_case[1].token {
    @token.RawText => ()
    _ => fail("Expected RawText for mixed-case script tag")
  }
  let empty = lex(source_id, "<script></script>").tokens()
  inspect(empty.length(), content="3")
  match empty[1].token {
    @token.CloseTag(name) => inspect(name, content="script")
    _ => fail("Expected immediate CloseTag, no zero-width RawText token")
  }
}

///|
test "generated element classifier is case insensitive and custom safe" {
  debug_inspect(@syntax.classify_element("BR"), content="Some(Br)")
  debug_inspect(@syntax.classify_element("ScRiPt"), content="Some(Script)")
  debug_inspect(@syntax.classify_element("my-widget"), content="None")
}

///|
test "open tag preserves complete source span while payload stays name only" {
  let source = "<div class=\"foo\">"
  let source_id = @core.SourceId("html-lexer-open-tag-span")
  let result = lex(source_id, source)
  let tokens = result.tokens()
  inspect(tokens[0].len, content="17")
  inspect(result.starts()[0], content="0")
  match tokens[0].token {
    @token.OpenTag(name) => inspect(name, content="div")
    _ => fail("Expected OpenTag")
  }
}

///|
test "syntax kinds preserve legacy raw IDs and append new tag kinds" {
  inspect(@syntax.DoctypeNode.to_raw(), content="RawKind(13)")
  inspect(@syntax.CommentNode.to_raw(), content="RawKind(14)")
  inspect(@syntax.TextLeaf.to_raw(), content="RawKind(15)")
  inspect(@syntax.RawTextLeaf.to_raw(), content="RawKind(16)")
  inspect(@syntax.ErrorNode.to_raw(), content="RawKind(17)")
  inspect(@syntax.RootNode.to_raw(), content="RawKind(18)")
  inspect(@syntax.Div.to_raw(), content="RawKind(19)")
  inspect(@syntax.Style.to_raw(), content="RawKind(35)")
  inspect(
    @syntax.SyntaxKind::from_raw(@seam.RawKind(13)),
    content="DoctypeNode",
  )
  inspect(@syntax.SyntaxKind::from_raw(@seam.RawKind(19)), content="Div")
}
