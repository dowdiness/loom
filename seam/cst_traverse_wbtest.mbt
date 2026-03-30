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

///|
test "transform_fold: node count" {
  let tree = make_test_tree()
  let result = tree.transform_fold(fn(_token) { 1 }, fn(_kind) { 1 }, fn(
    _kind,
    acc,
    child,
  ) {
    acc + child
  })
  // 2 branch nodes + 6 tokens = 8
  inspect(result, content="8")
}

///|
test "transform_fold: single token" {
  let tok = CstToken::new(RawKind(10), "7")
  let elem = CstElement::Token(tok)
  let result = elem.transform_fold(fn(t) { t.text.length() }, fn(_kind) { 0 }, fn(
    _kind,
    acc,
    child,
  ) {
    acc + child
  })
  inspect(result, content="1")
}

///|
test "each: visits all nodes and can terminate early" {
  let tree = make_test_tree()
  let mut count = 0
  let completed = tree.each(fn(_elem) {
    count = count + 1
    true
  })
  inspect(completed, content="true")
  // 2 branch nodes + 6 tokens = 8
  inspect(count, content="8")
}

///|
test "each: early termination" {
  let tree = make_test_tree()
  let mut count = 0
  let completed = tree.each(fn(elem) {
    count = count + 1
    // Stop at first Token with kind 10 (Number)
    match elem {
      CstElement::Token(t) => t.kind != RawKind(10)
      _ => true
    }
  })
  inspect(completed, content="false")
  // Root(20) -> Token(9,"foo") -> Token(11," ") -> BinaryExpr(21) -> Token(10,"1") stops
  inspect(count, content="5")
}

///|
test "each: single token" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let mut visited = false
  let _ = elem.each(fn(_e) {
    visited = true
    true
  })
  inspect(visited, content="true")
}

///|
test "iter: collects all elements" {
  let tree = make_test_tree()
  let count = tree.iter().fold(init=0, fn(acc, _elem) { acc + 1 })
  // 2 branch nodes + 6 tokens = 8
  inspect(count, content="8")
}

///|
test "iter: find_first" {
  let tree = make_test_tree()
  let found = tree
    .iter()
    .find_first(fn(elem) {
      match elem {
        CstElement::Token(t) => t.kind == RawKind(12) // Plus
        _ => false
      }
    })
  inspect(found is None, content="false")
  match found {
    Some(CstElement::Token(t)) => inspect(t.text, content="+")
    _ => inspect("unreachable", content="")
  }
}

///|
test "iter: empty node" {
  let node = CstNode::new(RawKind(20), [])
  let elem = CstElement::Node(node)
  let count = elem.iter().fold(init=0, fn(acc, _e) { acc + 1 })
  inspect(count, content="1")
}

///|
test "map: identity preserves structure" {
  let tree = make_test_tree()
  let mapped = tree.map(fn(elem) { elem })
  // Reconstruct source text to verify structure
  let text = mapped.transform(fn(token) { token.text }, fn(_kind, children) {
    let mut s = ""
    for child in children {
      s = s + child
    }
    s
  })
  inspect(text, content="foo 1+2")
}

///|
test "map: transform tokens" {
  let tree = make_test_tree()
  let mapped = tree.map(fn(elem) {
    match elem {
      CstElement::Token(t) =>
        if t.kind == RawKind(9) { // Ident
          CstElement::Token(CstToken::new(t.kind, "bar"))
        } else {
          elem
        }
      _ => elem
    }
  })
  let text = mapped.transform(fn(token) { token.text }, fn(_kind, children) {
    let mut s = ""
    for child in children {
      s = s + child
    }
    s
  })
  inspect(text, content="bar 1+2")
}

///|
test "map: single token" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let mapped = elem.map(fn(e) {
    match e {
      CstElement::Token(t) => CstElement::Token(CstToken::new(t.kind, "y"))
      _ => e
    }
  })
  match mapped {
    CstElement::Token(t) => inspect(t.text, content="y")
    _ => inspect("unreachable", content="")
  }
}

///|
struct NumberFinder {
  kind : RawKind
}

///|
impl Finder for NumberFinder with check(self, elem) {
  match elem {
    CstElement::Token(t) => t.kind == self.kind
    _ => false
  }
}

///|
test "find: locates first number token" {
  let tree = make_test_tree()
  let found = tree.find(NumberFinder::{ kind: RawKind(10) })
  match found {
    Some(CstElement::Token(t)) => inspect(t.text, content="1")
    _ => inspect("not found", content="")
  }
}

///|
test "find: returns None when no match" {
  let tree = make_test_tree()
  let found = tree.find(NumberFinder::{ kind: RawKind(99) })
  inspect(found is None, content="true")
}

///|
struct NodeKindFinder {
  kind : RawKind
}

///|
impl Finder for NodeKindFinder with check(self, elem) {
  match elem {
    CstElement::Node(n) => n.kind == self.kind
    _ => false
  }
}

///|
test "find: matches node element" {
  let tree = make_test_tree()
  let found = tree.find(NodeKindFinder::{ kind: RawKind(21) })
  match found {
    Some(CstElement::Node(n)) => inspect(n.kind == RawKind(21), content="true")
    _ => inspect("not found", content="")
  }
}

///|
test "find: single token match" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let found = elem.find(NumberFinder::{ kind: RawKind(9) })
  match found {
    Some(CstElement::Token(t)) => inspect(t.text, content="x")
    _ => inspect("not found", content="")
  }
}

///|
test "find: single token no match" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let found = elem.find(NumberFinder::{ kind: RawKind(10) })
  inspect(found is None, content="true")
}
