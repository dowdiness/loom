///|
test "fold simple element" {
  let result = parse_ast("<div></div>") catch { _ => return fail("lex error") }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[JsxNode::Element(tag="div", attrs=[], children=[])]),
  )
}

///|
test "fold nested elements with text" {
  let result = parse_ast("<div><span>hi</span></div>") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(tag="div", attrs=[], children=[
        JsxNode::Element(tag="span", attrs=[], children=[JsxNode::Text("hi")]),
      ]),
    ]),
  )
}

///|
test "fold fragment" {
  let result = parse_ast("<><p>x</p></>") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Fragment(children=[
        JsxNode::Element(tag="p", attrs=[], children=[JsxNode::Text("x")]),
      ]),
    ]),
  )
}

///|
test "fold self-closing element" {
  let result = parse_ast("<br/>") catch { _ => return fail("lex error") }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[JsxNode::Element(tag="br", attrs=[], children=[])]),
  )
}

///|
test "fold string attribute strips quotes" {
  let result = parse_ast("<div class=\"foo\"/>") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(
        tag="div",
        attrs=[
          JsxAttr::JsxAttr(name="class", value=JsxAttrValue::StringLit("foo")),
        ],
        children=[],
      ),
    ]),
  )
}

///|
test "fold expression attribute" {
  let result = parse_ast("<div id={x}/>") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(
        tag="div",
        attrs=[
          JsxAttr::JsxAttr(name="id", value=JsxAttrValue::ExprSpan(raw="x")),
        ],
        children=[],
      ),
    ]),
  )
}

///|
test "fold bare attribute" {
  let result = parse_ast("<div hidden/>") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(
        tag="div",
        attrs=[JsxAttr::JsxAttr(name="hidden", value=JsxAttrValue::Bare)],
        children=[],
      ),
    ]),
  )
}

///|
test "fold expression child" {
  let result = parse_ast("<p>{a + b}</p>") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(tag="p", attrs=[], children=[
        JsxNode::ExprSpan(raw="a + b"),
      ]),
    ]),
  )
}

///|
test "fold expression containing a string with a brace" {
  let result = parse_ast("<p>{f(\"a}b\")}</p>") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(tag="p", attrs=[], children=[
        JsxNode::ExprSpan(raw="f(\"a}b\")"),
      ]),
    ]),
  )
}

///|
test "fold multiple roots from a streaming prefix" {
  let result = parse_ast("<div/>text") catch { _ => return fail("lex error") }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(tag="div", attrs=[], children=[]),
      JsxNode::Text("text"),
    ]),
  )
}

///|
test "fold unclosed element identically to closed shape" {
  let result = parse_ast("<div><span>text") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="2")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(tag="div", attrs=[], children=[
        JsxNode::Element(tag="span", attrs=[], children=[JsxNode::Text("text")]),
      ]),
    ]),
  )
}

///|
test "fold truncated attribute string keeps scanned content" {
  let result = parse_ast("<div class=\"fo") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="2")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(
        tag="div",
        attrs=[
          JsxAttr::JsxAttr(name="class", value=JsxAttrValue::StringLit("fo")),
        ],
        children=[],
      ),
    ]),
  )
}

///|
test "fold truncated expression keeps scanned content" {
  let result = parse_ast("<p>{foo.bar(") catch { _ => return fail("lex error") }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="2")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(tag="p", attrs=[], children=[
        JsxNode::ExprSpan(raw="foo.bar("),
      ]),
    ]),
  )
}

///|
test "fold mismatched close keeps open tag names" {
  // Codex post-implementation-review case: the unwind CST for
  // <div><span></div> leaves span's node holding only a zero-width error
  // placeholder while div claims the close tag — both elements must fold
  // with their OPEN tag's name (first direct TagNameToken).
  let result = parse_ast("<div><span></div>") catch {
    _ => return fail("lex error")
  }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="1")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(tag="div", attrs=[], children=[
        JsxNode::Element(tag="span", attrs=[], children=[]),
      ]),
    ]),
  )
}

///|
test "fold minimum-length attribute strings" {
  // Codex post-implementation-review case: attr_string_content's bounds at
  // the two lexer-minimal token texts — `""` (terminated, len 2) and `"`
  // (unterminated, len 1) — both fold to the empty string.
  let closed = parse_ast("<div a=\"\"/>") catch {
    _ => return fail("lex error")
  }
  let (closed_ast, closed_diags) = closed
  inspect(closed_diags.length(), content="0")
  @debug.assert_eq(
    closed_ast,
    JsxNode::Root(children=[
      JsxNode::Element(
        tag="div",
        attrs=[JsxAttr::JsxAttr(name="a", value=JsxAttrValue::StringLit(""))],
        children=[],
      ),
    ]),
  )
  let open_ = parse_ast("<div a=\"") catch { _ => return fail("lex error") }
  let (open_ast, open_diags) = open_
  inspect(open_diags.length(), content="2")
  @debug.assert_eq(
    open_ast,
    JsxNode::Root(children=[
      JsxNode::Element(
        tag="div",
        attrs=[JsxAttr::JsxAttr(name="a", value=JsxAttrValue::StringLit(""))],
        children=[],
      ),
    ]),
  )
}

///|
test "fold error recovery artifacts" {
  let result = parse_ast("</span>") catch { _ => return fail("lex error") }
  let (ast, diagnostics) = result
  inspect(diagnostics.length(), content="1")
  @debug.assert_eq(ast, JsxNode::Root(children=[JsxNode::Error("</span>")]))
}
