///|
test "RawKind equality" {
  let a = RawKind(5)
  let b = RawKind(5)
  let c = RawKind(6)
  inspect(a == b, content="true")
  inspect(a == c, content="false")
}

///|
test "CstToken constructor computes hash" {
  let t = CstToken::new(RawKind(9), "hello")
  inspect(t.text, content="hello")
  inspect(t.kind == RawKind(9), content="true")
  // Hash is nonzero
  inspect(t.hash != 0, content="true")
}

///|
test "CstToken Eq is hash-based fast path" {
  let a = CstToken::new(RawKind(9), "x")
  let b = CstToken::new(RawKind(9), "x")
  let c = CstToken::new(RawKind(9), "y")
  inspect(a == b, content="true")
  inspect(a == c, content="false")
}

///|
test "CstToken text_len" {
  let t = CstToken::new(RawKind(9), "hello")
  inspect(t.text_len(), content="5")
}

///|
test "CstNode constructor computes text_len and hash" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let node = CstNode::new(RawKind(20), [elem])
  inspect(node.text_len, content="1")
  inspect(node.hash != 0, content="true")
}

///|
test "CstNode Eq: identical nodes are equal" {
  let a = CstNode::new(RawKind(0), [])
  let b = CstNode::new(RawKind(0), [])
  inspect(a == b, content="true")
}

///|
test "CstNode Eq: different kind not equal" {
  let a = CstNode::new(RawKind(0), [])
  let b = CstNode::new(RawKind(1), [])
  inspect(a == b, content="false")
}

///|
test "CstElement text_len and kind" {
  let tok = CstToken::new(RawKind(9), "hello")
  let elem = CstElement::Token(tok)
  inspect(elem.text_len(), content="5")
  inspect(elem.kind() == RawKind(9), content="true")
}

///|
test "CstNode token_count: no trivia_kind counts all leaf tokens" {
  let ws_tok = CstToken::new(RawKind(11), " ")
  let id_tok = CstToken::new(RawKind(9), "x")
  let node = CstNode::new(RawKind(20), [
    CstElement::Token(id_tok),
    CstElement::Token(ws_tok),
  ])
  inspect(node.token_count, content="2")
}

///|
test "CstNode token_count: trivia_kind excludes whitespace" {
  let ws_kind = RawKind(11)
  let ws_tok = CstToken::new(ws_kind, " ")
  let id_tok = CstToken::new(RawKind(9), "x")
  let node = CstNode::new(
    RawKind(20),
    [CstElement::Token(id_tok), CstElement::Token(ws_tok)],
    trivia_kind=Some(ws_kind),
  )
  inspect(node.token_count, content="1")
}

///|
test "CstNode token_count: propagates through sub-nodes" {
  let ws_kind = RawKind(11)
  let ws_tok = CstToken::new(ws_kind, " ")
  let id_tok = CstToken::new(RawKind(9), "x")
  let int_tok = CstToken::new(RawKind(10), "1")
  let inner = CstNode::new(
    RawKind(19),
    [CstElement::Token(int_tok)],
    trivia_kind=Some(ws_kind),
  )
  let root = CstNode::new(
    RawKind(16),
    [
      CstElement::Token(id_tok),
      CstElement::Token(ws_tok),
      CstElement::Node(inner),
    ],
    trivia_kind=Some(ws_kind),
  )
  // id_tok (1) + ws_tok (excluded) + inner.token_count (1) = 2
  inspect(root.token_count, content="2")
}

///|
test "has_errors detects error node kind" {
  let error_node_kind = RawKind(21)
  let error_token_kind = RawKind(12)
  let err = CstNode::new(error_node_kind, [])
  inspect(err.has_errors(error_node_kind, error_token_kind), content="true")
}

///|
test "has_errors returns false for clean node" {
  let error_node_kind = RawKind(21)
  let error_token_kind = RawKind(12)
  let clean = CstNode::new(RawKind(22), [])
  inspect(clean.has_errors(error_node_kind, error_token_kind), content="false")
}

///|
test "CstNode::first_token: returns first non-trivia token" {
  // ws token (kind 11 = WhitespaceToken), then ident token (kind 9 = IdentToken)
  let ws = CstToken::new(RawKind(11), " ")
  let id = CstToken::new(RawKind(9), "x")
  let cst = CstNode::new(RawKind(22), [
    CstElement::Token(ws),
    CstElement::Token(id),
  ])
  let is_trivia = fn(k : RawKind) { k == RawKind(11) }
  match cst.first_token(is_trivia) {
    Some(t) => inspect(t.text, content="x")
    None => inspect("none", content="x")
  }
}

///|
test "CstNode::first_token: descends into child nodes" {
  let id = CstToken::new(RawKind(9), "y")
  let inner = CstNode::new(RawKind(20), [CstElement::Token(id)])
  let outer = CstNode::new(RawKind(22), [CstElement::Node(inner)])
  let is_trivia = fn(_k : RawKind) { false }
  match outer.first_token(is_trivia) {
    Some(t) => inspect(t.text, content="y")
    None => inspect("none", content="y")
  }
}

///|
test "CstNode::first_token: returns None for empty node" {
  let cst = CstNode::new(RawKind(22), [])
  let is_trivia = fn(_k : RawKind) { false }
  inspect(cst.first_token(is_trivia) is None, content="true")
}

///|
test "CstNode::first_token: returns None when all tokens are trivia" {
  let ws = CstToken::new(RawKind(11), " ")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(ws)])
  let is_trivia = fn(k : RawKind) { k == RawKind(11) }
  inspect(cst.first_token(is_trivia) is None, content="true")
}
