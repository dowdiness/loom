///|
fn make_test_tree() -> CstElement {
  let foo = CstToken::new(RawKind(9), "foo")
  let ws = CstToken::new(RawKind(11), " ")
  let one = CstToken::new(RawKind(10), "1")
  let plus = CstToken::new(RawKind(12), "+")
  let two = CstToken::new(RawKind(10), "2")
  let eof = CstToken::new(RawKind(13), "")
  let bin_expr = CstNode::new(RawKind(21), [
    CstElement::Token(one),
    CstElement::Token(plus),
    CstElement::Token(two),
  ])
  let root = CstNode::new(RawKind(20), [
    CstElement::Token(foo),
    CstElement::Token(ws),
    CstElement::Node(bin_expr),
    CstElement::Token(eof),
  ])
  CstElement::Node(root)
}

///|
test "transform: reconstruct source text" {
  let tree = make_test_tree()
  let result = tree.transform(fn(token) { token.text }, fn(_kind, children) {
    let mut s = ""
    for child in children {
      s = s + child
    }
    s
  })
  inspect(result, content="foo 1+2")
}

///|
test "transform: count nodes" {
  let tree = make_test_tree()
  let result = tree.transform(fn(_token) { 1 }, fn(_kind, children) {
    let mut sum = 1
    for child in children {
      sum = sum + child
    }
    sum
  })
  // 2 branch nodes + 6 leaf tokens = 8
  inspect(result, content="8")
}

///|
test "transform: single token" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let result = elem.transform(fn(t) { t.text }, fn(_k, _c) { "" })
  inspect(result, content="x")
}

///|
test "fold: sum text lengths" {
  let tree = make_test_tree()
  let result = tree.fold(
    fn(token) { token.text.length() },
    fn(a, b) { a + b },
    0,
  )
  // "foo" + " " + "1" + "+" + "2" + "" = 7
  inspect(result, content="7")
}

///|
test "fold: count tokens only" {
  let tree = make_test_tree()
  let result = tree.fold(fn(_token) { 1 }, fn(a, b) { a + b }, 0)
  // 6 leaf tokens
  inspect(result, content="6")
}

///|
test "fold: single token" {
  let tok = CstToken::new(RawKind(10), "42")
  let elem = CstElement::Token(tok)
  let result = elem.fold(fn(t) { t.text.length() }, fn(a, b) { a + b }, 0)
  inspect(result, content="2")
}
