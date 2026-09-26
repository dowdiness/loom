///|
test "children of containers" {
  let el = @jsx.JsxNode::Element(tag="div", attrs=[], children=[
    @jsx.JsxNode::Text("a"),
    @jsx.JsxNode::Text("b"),
  ])
  inspect(@core.TreeNode::children(el).length(), content="2")
  let root = @jsx.JsxNode::Root(children=[@jsx.JsxNode::Text("a")])
  inspect(@core.TreeNode::children(root).length(), content="1")
  inspect(@core.TreeNode::children(@jsx.JsxNode::Text("x")).length(), content="0")
  inspect(
    @core.TreeNode::children(@jsx.JsxNode::ExprSpan(raw="x")).length(),
    content="0",
  )
}

///|
test "same_kind requires equal element tag" {
  let div1 = @jsx.JsxNode::Element(tag="div", attrs=[], children=[])
  let div2 = @jsx.JsxNode::Element(tag="div", attrs=[], children=[@jsx.JsxNode::Text("x")])
  let span = @jsx.JsxNode::Element(tag="span", attrs=[], children=[])
  inspect(@core.TreeNode::same_kind(div1, div2), content="true")
  inspect(@core.TreeNode::same_kind(div1, span), content="false")
}

///|
test "same_kind ignores content for text and expressions" {
  inspect(
    @core.TreeNode::same_kind(
      @jsx.JsxNode::Text("a"),
      @jsx.JsxNode::Text("completely different"),
    ),
    content="true",
  )
  // Load-bearing for the plan's growing-span ProjNode identity via
  // @core.reconcile — see Design B notes.
  inspect(
    @core.TreeNode::same_kind(
      @jsx.JsxNode::ExprSpan(raw="fo"),
      @jsx.JsxNode::ExprSpan(raw="foo.bar("),
    ),
    content="true",
  )
  inspect(
    @core.TreeNode::same_kind(
      @jsx.JsxNode::Fragment(children=[]),
      @jsx.JsxNode::Fragment(children=[@jsx.JsxNode::Text("x")]),
    ),
    content="true",
  )
}

///|
test "same_kind is false across variants" {
  inspect(
    @core.TreeNode::same_kind(
      @jsx.JsxNode::Element(tag="div", attrs=[], children=[]),
      @jsx.JsxNode::Text("div"),
    ),
    content="false",
  )
  inspect(
    @core.TreeNode::same_kind(
      @jsx.JsxNode::Root(children=[]),
      @jsx.JsxNode::Fragment(children=[]),
    ),
    content="false",
  )
  inspect(
    @core.TreeNode::same_kind(@jsx.JsxNode::Error("x"), @jsx.JsxNode::Text("x")),
    content="false",
  )
}

///|
test "kind_tag is the plain variant name" {
  inspect(
    @core.Renderable::kind_tag(@jsx.JsxNode::Root(children=[])),
    content="Root",
  )
  inspect(
    @core.Renderable::kind_tag(
      @jsx.JsxNode::Element(tag="div", attrs=[], children=[]),
    ),
    content="Element",
  )
  inspect(
    @core.Renderable::kind_tag(@jsx.JsxNode::Fragment(children=[])),
    content="Fragment",
  )
  inspect(@core.Renderable::kind_tag(@jsx.JsxNode::Text("x")), content="Text")
  inspect(
    @core.Renderable::kind_tag(@jsx.JsxNode::ExprSpan(raw="x")),
    content="ExprSpan",
  )
  inspect(@core.Renderable::kind_tag(@jsx.JsxNode::Error("x")), content="Error")
}

///|
test "label shapes" {
  inspect(
    @core.Renderable::label(@jsx.JsxNode::Element(tag="div", attrs=[], children=[])),
    content="<div>",
  )
  inspect(@core.Renderable::label(@jsx.JsxNode::Fragment(children=[])), content="<>")
  inspect(
    @core.Renderable::label(
      @jsx.JsxNode::Root(children=[@jsx.JsxNode::Text("a"), @jsx.JsxNode::Text("b")]),
    ),
    content="[2 children]",
  )
  inspect(@core.Renderable::label(@jsx.JsxNode::ExprSpan(raw="x")), content="{x}")
}

///|
test "label truncates long text" {
  let long = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  inspect(
    @core.Renderable::label(@jsx.JsxNode::Text(long)),
    content="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...",
  )
  inspect(@core.Renderable::label(@jsx.JsxNode::Text("short")), content="short")
}

///|
test "placeholder is constant" {
  inspect(
    @core.Renderable::placeholder(
      @jsx.JsxNode::Element(tag="div", attrs=[], children=[]),
    ),
    content="...",
  )
  inspect(@core.Renderable::placeholder(@jsx.JsxNode::Text("x")), content="...")
}

///|
test "unparse closed element with attrs and children" {
  let node = @jsx.JsxNode::Element(
    tag="div",
    attrs=[@jsx.JsxAttr::JsxAttr(name="class", value=@jsx.JsxAttrValue::StringLit("foo"))],
    children=[
      @jsx.JsxNode::Element(tag="p", attrs=[], children=[
        @jsx.JsxNode::Text("hi"),
        @jsx.JsxNode::ExprSpan(raw="x"),
      ]),
    ],
  )
  inspect(
    @core.Renderable::unparse(node),
    content="<div class=\"foo\"><p>hi{x}</p></div>",
  )
}

///|
test "unparse attr value forms" {
  let node = @jsx.JsxNode::Element(
    tag="a",
    attrs=[
      @jsx.JsxAttr::JsxAttr(name="id", value=@jsx.JsxAttrValue::ExprSpan(raw="f()")),
      @jsx.JsxAttr::JsxAttr(name="hidden", value=@jsx.JsxAttrValue::Bare),
    ],
    children=[],
  )
  inspect(@core.Renderable::unparse(node), content="<a id={f()} hidden/>")
}

///|
test "unparse fragment and root concatenation" {
  let node = @jsx.JsxNode::Root(children=[
    @jsx.JsxNode::Element(tag="br", attrs=[], children=[]),
    @jsx.JsxNode::Fragment(children=[@jsx.JsxNode::Text("hi")]),
  ])
  inspect(@core.Renderable::unparse(node), content="<br/><>hi</>")
}

///|
test "unparse picks a safe quote for attribute strings" {
  // Codex post-implementation-review case: re-quoting with `"` unescaped
  // breaks a parsed single-quoted value containing a double quote.
  let source = "<div a='x\"y'/>"
  let source_id = @core.SourceId("jsx-projection-safe-attribute-quote")
  let result = @jsx.parse_ast(source_id, source) catch {
    _ => return fail("lex error")
  }
  let (ast, _diagnostics) = result
  inspect(@core.Renderable::unparse(ast), content="<div a='x\"y'/>")
  // Both quote kinds present: double-quote and backslash-escape the
  // doubles (re-parseable; the lexer's escape rule consumes the next
  // char unconditionally).
  let both = @jsx.JsxNode::Element(
    tag="a",
    attrs=[@jsx.JsxAttr::JsxAttr(name="b", value=@jsx.JsxAttrValue::StringLit("x\"y'z"))],
    children=[],
  )
  inspect(@core.Renderable::unparse(both), content="<a b=\"x\\\"y'z\"/>")
}

///|
test "label truncation preserves surrogate pairs" {
  // Codex post-implementation-review case: code-unit slicing at 30 must
  // not split an astral character sitting on the boundary.
  let text = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaa" + "\u{1D11E}" + "zzzzz"
  inspect(
    @core.Renderable::label(@jsx.JsxNode::Text(text)),
    content="aaaaaaaaaaaaaaaaaaaaaaaaaaaaa\u{1D11E}...",
  )
}

///|
test "unparse round-trips a parsed fixture" {
  let source = "<div class=\"foo\"><p>hi{x}</p></div>"
  let source_id = @core.SourceId("jsx-projection-round-trip")
  let result = @jsx.parse_ast(source_id, source) catch {
    _ => return fail("lex error")
  }
  let (ast, _diagnostics) = result
  inspect(@core.Renderable::unparse(ast), content=source)
  inspect(
    @core.Renderable::unparse(@jsx.JsxNode::Error("</span>")),
    content="</span>",
  )
}
