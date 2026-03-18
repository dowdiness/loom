///|
test "SyntaxNode Show" {
  let tok = CstToken::new(RawKind(9), "hello")
  let cst = CstNode::new(RawKind(20), [CstElement::Token(tok)])
  let sn = SyntaxNode::from_cst(cst)
  inspect(sn, content="SyntaxNode@[0,5)")
}

///|
test "SyntaxElement wraps node and token" {
  let tok = CstToken::new(RawKind(9), "x")
  let st = SyntaxToken::new(tok, 5)
  let elem_tok = SyntaxElement::Token(st)
  inspect(elem_tok.start(), content="5")
  inspect(elem_tok.end(), content="6")

  let cst = CstNode::new(RawKind(20), [])
  let sn = SyntaxNode::from_cst(cst)
  let elem_node = SyntaxElement::Node(sn)
  inspect(elem_node.start(), content="0")
}

///|
test "SyntaxNode::from_cst creates root at offset 0" {
  let cst = CstNode::new(RawKind(22), [])
  let syntax = SyntaxNode::from_cst(cst)
  inspect(syntax.start(), content="0")
  inspect(syntax.end(), content="0")
  inspect(syntax.kind() == RawKind(22), content="true")
}

///|
test "SyntaxToken::start and end" {
  let tok = CstToken::new(RawKind(9), "hello")
  let st = SyntaxToken::new(tok, 3)
  inspect(st.start(), content="3")
  inspect(st.end(), content="8")
}

///|
test "SyntaxToken::kind and text" {
  let tok = CstToken::new(RawKind(9), "foo")
  let st = SyntaxToken::new(tok, 0)
  inspect(st.kind() == RawKind(9), content="true")
  inspect(st.text(), content="foo")
}

///|
test "SyntaxToken Show" {
  let tok = CstToken::new(RawKind(9), "foo")
  let st = SyntaxToken::new(tok, 3)
  inspect(st, content="SyntaxToken@[3,6)")
}

///|
test "SyntaxNode::all_children includes tokens and nodes" {
  let tok = CstToken::new(RawKind(9), "hi")
  let inner = CstNode::new(RawKind(20), [])
  let root = CstNode::new(RawKind(22), [
    CstElement::Token(tok),
    CstElement::Node(inner),
  ])
  let sn = SyntaxNode::from_cst(root)
  let children = sn.all_children()
  inspect(children.length(), content="2")
  inspect(children[0].start(), content="0")
  inspect(children[0].end(), content="2")
  inspect(children[1].start(), content="2")
}

///|
test "SyntaxNode::tokens returns only leaf tokens with offsets" {
  let t1 = CstToken::new(RawKind(9), "ab")
  let t2 = CstToken::new(RawKind(10), "cd")
  let inner = CstNode::new(RawKind(20), [CstElement::Token(t2)])
  let root = CstNode::new(RawKind(22), [
    CstElement::Token(t1),
    CstElement::Node(inner),
  ])
  let sn = SyntaxNode::from_cst(root)
  let toks = sn.tokens()
  inspect(toks.length(), content="1")
  inspect(toks[0].text(), content="ab")
  inspect(toks[0].start(), content="0")
}

///|
test "SyntaxNode::tokens accumulates offset past skipped node" {
  // Structure: root[ node("cd"), token("ab") ]
  // tokens() skips the node (text_len=2) then yields "ab" at offset 2
  let inner_tok = CstToken::new(RawKind(10), "cd")
  let inner = CstNode::new(RawKind(20), [CstElement::Token(inner_tok)])
  let trailing = CstToken::new(RawKind(9), "ab")
  let root = CstNode::new(RawKind(22), [
    CstElement::Node(inner),
    CstElement::Token(trailing),
  ])
  let sn = SyntaxNode::from_cst(root)
  let toks = sn.tokens()
  inspect(toks.length(), content="1")
  inspect(toks[0].text(), content="ab")
  inspect(toks[0].start(), content="2")
}

///|
test "SyntaxNode::find_token returns first matching token" {
  let ident = CstToken::new(RawKind(9), "x")
  let dot = CstToken::new(RawKind(2), ".")
  let root = CstNode::new(RawKind(22), [
    CstElement::Token(ident),
    CstElement::Token(dot),
  ])
  let sn = SyntaxNode::from_cst(root)
  match sn.find_token(RawKind(2)) {
    Some(t) => inspect(t.text(), content=".")
    None => inspect("none", content=".")
  }
  match sn.find_token(RawKind(99)) {
    Some(_) => inspect("found", content="none")
    None => inspect("none", content="none")
  }
}

///|
test "SyntaxNode::tokens_of_kind collects all matching tokens" {
  let plus1 = CstToken::new(RawKind(5), "+")
  let ident = CstToken::new(RawKind(9), "x")
  let plus2 = CstToken::new(RawKind(5), "+")
  let root = CstNode::new(RawKind(22), [
    CstElement::Token(plus1),
    CstElement::Token(ident),
    CstElement::Token(plus2),
  ])
  let sn = SyntaxNode::from_cst(root)
  let ops = sn.tokens_of_kind(RawKind(5))
  inspect(ops.length(), content="2")
  inspect(ops[0].start(), content="0")
  inspect(ops[1].start(), content="2")
}

///|
test "SyntaxNode::tight_span no trivia" {
  let t1 = CstToken::new(RawKind(9), "ab")
  let t2 = CstToken::new(RawKind(9), "cd")
  let root = CstNode::new(RawKind(22), [
    CstElement::Token(t1),
    CstElement::Token(t2),
  ])
  let sn = SyntaxNode::from_cst(root)
  let (s, e) = sn.tight_span()
  inspect(s, content="0")
  inspect(e, content="4")
}

///|
test "SyntaxNode::tight_span skips leading and trailing trivia" {
  let ws1 = CstToken::new(RawKind(0), " ") // trivia kind = RawKind(0)
  let ident = CstToken::new(RawKind(9), "x")
  let ws2 = CstToken::new(RawKind(0), "  ")
  let root = CstNode::new(RawKind(22), [
    CstElement::Token(ws1),
    CstElement::Token(ident),
    CstElement::Token(ws2),
  ])
  let sn = SyntaxNode::from_cst(root)
  let (s, e) = sn.tight_span(trivia_kind=Some(RawKind(0)))
  inspect(s, content="1")
  inspect(e, content="2") // "x" is 1 char at offset 1, so end = 2
}

///|
test "SyntaxNode::tight_span all-trivia collapses to start" {
  let ws1 = CstToken::new(RawKind(0), " ")
  let ws2 = CstToken::new(RawKind(0), "  ")
  let inner = CstNode::new(RawKind(20), [
    CstElement::Token(ws1),
    CstElement::Token(ws2),
  ])
  let lead = CstToken::new(RawKind(9), "x")
  let root = CstNode::new(RawKind(22), [
    CstElement::Token(lead),
    CstElement::Node(inner),
  ])
  let sn = SyntaxNode::from_cst(root)
  let child = sn.children()[0]
  let (s, e) = child.tight_span(trivia_kind=Some(RawKind(0)))
  inspect(s, content="1")
  inspect(e, content="1")
}

///|
test "SyntaxNode::children computes offsets" {
  // Build: SourceFile containing a CstToken "hello"
  let tok = CstToken::new(RawKind(9), "hello")
  let child_elem = CstElement::Token(tok)
  let inner = CstNode::new(RawKind(20), [child_elem])
  let root = CstNode::new(RawKind(22), [CstElement::Node(inner)])
  let syntax = SyntaxNode::from_cst(root)
  let children = syntax.children()
  inspect(children.length(), content="1")
  inspect(children[0].start(), content="0")
  inspect(children[0].end(), content="5")
}

///|
// Out-of-range and empty-node inputs return self without panicking.
// Callers querying a well-formed tree should stay within root's span;
// these tests document the fallback contract, not intended usage.
test "SyntaxNode::find_at returns self for out-of-range offset" {
  let tok = CstToken::new(RawKind(9), "ab")
  let root = CstNode::new(RawKind(22), [CstElement::Token(tok)])
  let sn = SyntaxNode::from_cst(root) // span [0, 2)
  // offset before span
  inspect(sn.find_at(-1).kind() == RawKind(22), content="true")
  // offset at end (exclusive boundary)
  inspect(sn.find_at(2).kind() == RawKind(22), content="true")
  // offset well past end
  inspect(sn.find_at(99).kind() == RawKind(22), content="true")
}

///|
test "SyntaxNode::find_at returns self for empty node" {
  let empty = CstNode::new(RawKind(22), [])
  let sn = SyntaxNode::from_cst(empty) // span [0, 0)
  inspect(sn.find_at(0).kind() == RawKind(22), content="true")
}

///|
test "SyntaxNode::find_at returns self when no child node covers offset" {
  let tok = CstToken::new(RawKind(9), "x")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(tok)])
  let sn = SyntaxNode::from_cst(cst)
  let found = sn.find_at(0)
  inspect(found.kind() == RawKind(22), content="true")
}

///|
test "SyntaxNode::cst_node returns underlying CstNode" {
  let cst = CstNode::new(RawKind(22), [])
  let sn = SyntaxNode::from_cst(cst)
  inspect(sn.cst_node() == cst, content="true")
}

///|
test "SyntaxNode Eq: same CstNode pointer = equal" {
  let cst = CstNode::new(RawKind(0), [])
  let s1 = SyntaxNode::from_cst(cst)
  let s2 = SyntaxNode::from_cst(cst)
  inspect(s1 == s2, content="true")
}

///|
test "SyntaxNode Eq: different offset = still equal (offset ignored)" {
  let cst = CstNode::new(RawKind(0), [])
  let s1 = SyntaxNode::new(cst, None, 0)
  let s2 = SyntaxNode::new(cst, None, 99)
  inspect(s1 == s2, content="true")
}

///|
test "SyntaxNode Eq: different CstNode kind = not equal" {
  let s1 = SyntaxNode::from_cst(CstNode::new(RawKind(1), []))
  let s2 = SyntaxNode::from_cst(CstNode::new(RawKind(2), []))
  inspect(s1 == s2, content="false")
}

///|
test "SyntaxNode ToJson: produces kind, start, end, children keys" {
  let cst = CstNode::new(RawKind(5), [])
  let syn = SyntaxNode::new(cst, None, 10)
  let j = syn.to_json()
  let s = j.to_string()
  inspect(s.contains("\"kind\""), content="true")
  inspect(s.contains("\"start\""), content="true")
  inspect(s.contains("\"end\""), content="true")
}

///|
test "nth_child: returns None on empty node" {
  let cst = CstNode::new(RawKind(0), [])
  let syn = SyntaxNode::from_cst(cst)
  inspect(syn.nth_child(0) is None, content="true")
}

///|
test "nth_child: returns first interior child" {
  let leaf = CstElement::Node(CstNode::new(RawKind(1), []))
  let root = CstNode::new(RawKind(0), [leaf])
  let syn = SyntaxNode::from_cst(root)
  inspect(syn.nth_child(0) is Some(_), content="true")
}

///|
test "nth_child: skips token children" {
  let tok = CstElement::Token(CstToken::new(RawKind(99), "x"))
  let inner = CstElement::Node(CstNode::new(RawKind(1), []))
  let root = CstNode::new(RawKind(0), [tok, inner])
  let syn = SyntaxNode::from_cst(root)
  // nth_child(0) skips the token, returns the node
  inspect(syn.nth_child(0) is Some(_), content="true")
  // nth_child(1) is None — only one inner node
  inspect(syn.nth_child(1) is None, content="true")
}

///|
test "child_of_kind: finds matching child" {
  let inner = CstElement::Node(CstNode::new(RawKind(7), []))
  let root = CstNode::new(RawKind(0), [inner])
  let syn = SyntaxNode::from_cst(root)
  inspect(syn.child_of_kind(RawKind(7)) is Some(_), content="true")
  inspect(syn.child_of_kind(RawKind(99)) is None, content="true")
}

///|
test "SyntaxNode::first_token: empty node returns None" {
  let cst = CstNode::new(RawKind(1), [])
  let node = SyntaxNode::from_cst(cst)
  inspect(node.first_token() is None, content="true")
}

///|
test "SyntaxNode::first_token: returns first token with correct offset" {
  let tok_a = CstToken::new(RawKind(9), "ab")
  let tok_b = CstToken::new(RawKind(9), "cd")
  let cst = CstNode::new(RawKind(1), [
    CstElement::Token(tok_a),
    CstElement::Token(tok_b),
  ])
  let node = SyntaxNode::from_cst(cst)
  let ft = node.first_token()
  inspect(ft is Some(_), content="true")
  inspect(ft.unwrap().start(), content="0")
  inspect(ft.unwrap().text(), content="ab")
}

///|
test "SyntaxNode::first_token: skips leading node child to find token" {
  let tok = CstToken::new(RawKind(9), "x")
  let child_node = CstNode::new(RawKind(2), [])
  let cst = CstNode::new(RawKind(1), [
    CstElement::Node(child_node),
    CstElement::Token(tok),
  ])
  let node = SyntaxNode::from_cst(cst)
  let ft = node.first_token()
  inspect(ft is Some(_), content="true")
  inspect(ft.unwrap().text(), content="x")
}

///|
test "SyntaxNode::first_child: leaf node returns None" {
  let cst = CstNode::new(RawKind(1), [])
  let leaf = SyntaxNode::from_cst(cst)
  inspect(leaf.first_child() is None, content="true")
}

///|
test "SyntaxNode::first_child: node with children returns first" {
  let a = CstNode::new(RawKind(2), [])
  let b = CstNode::new(RawKind(3), [])
  let root_cst = CstNode::new(RawKind(1), [
    CstElement::Node(a),
    CstElement::Node(b),
  ])
  let root = SyntaxNode::from_cst(root_cst)
  let first = root.first_child()
  inspect(first is Some(_), content="true")
  inspect(first.unwrap().kind() == RawKind(2), content="true")
}

///|
test "SyntaxNode::parent: root returns None" {
  let cst = CstNode::new(RawKind(1), [])
  let root = SyntaxNode::from_cst(cst)
  inspect(root.parent() is None, content="true")
}

///|
test "SyntaxNode::parent: child returns Some(parent)" {
  let child_cst = CstNode::new(RawKind(2), [])
  let root_cst = CstNode::new(RawKind(1), [CstElement::Node(child_cst)])
  let root = SyntaxNode::from_cst(root_cst)
  let child = root.children()[0]
  match child.parent() {
    Some(p) => inspect(p == root, content="true")
    None => inspect("no parent", content="Some(parent)")
  }
}

///|
test "SyntaxNode::is_error: error-kind node returns true" {
  let error_kind = RawKind(99)
  let cst = CstNode::new(error_kind, [])
  let node = SyntaxNode::from_cst(cst)
  inspect(node.is_error(error_kind), content="true")
}

///|
test "SyntaxNode::is_error: non-error node returns false" {
  let error_kind = RawKind(99)
  let cst = CstNode::new(RawKind(1), [])
  let node = SyntaxNode::from_cst(cst)
  inspect(node.is_error(error_kind), content="false")
}

///|
test "SyntaxNode::contains_errors: clean subtree returns false" {
  let tok = CstToken::new(RawKind(5), "x")
  let cst = CstNode::new(RawKind(1), [CstElement::Token(tok)])
  let node = SyntaxNode::from_cst(cst)
  inspect(node.contains_errors(RawKind(99), RawKind(98)), content="false")
}

///|
test "SyntaxNode::contains_errors: subtree with error node returns true" {
  let error_node = CstNode::new(RawKind(99), [])
  let root_cst = CstNode::new(RawKind(1), [CstElement::Node(error_node)])
  let root = SyntaxNode::from_cst(root_cst)
  inspect(root.contains_errors(RawKind(99), RawKind(98)), content="true")
}

///|
test "SyntaxNode::contains_errors: subtree with error token returns true" {
  let err_tok = CstToken::new(RawKind(98), "?")
  let cst = CstNode::new(RawKind(1), [CstElement::Token(err_tok)])
  let node = SyntaxNode::from_cst(cst)
  inspect(node.contains_errors(RawKind(99), RawKind(98)), content="true")
}

///|
test "SyntaxNode::find_at_checked: in-span offset returns Some" {
  let tok = CstToken::new(RawKind(9), "hello")
  let cst = CstNode::new(RawKind(1), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  inspect(root.find_at_checked(2) is Some(_), content="true")
}

///|
test "SyntaxNode::find_at_checked: out-of-span offset returns None" {
  let tok = CstToken::new(RawKind(9), "hello")
  let cst = CstNode::new(RawKind(1), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  inspect(root.find_at_checked(99) is None, content="true")
}

///|
test "SyntaxNode::find_at_checked: boundary conditions" {
  // span [0,5) — "hello" is 5 bytes
  let tok = CstToken::new(RawKind(9), "hello")
  let cst = CstNode::new(RawKind(1), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  inspect(root.find_at_checked(0) is Some(_), content="true") // start (inclusive)
  inspect(root.find_at_checked(4) is Some(_), content="true") // end-1 (inclusive)
  inspect(root.find_at_checked(5) is None, content="true") // end (exclusive)
  inspect(root.find_at_checked(-1) is None, content="true") // before start
}

///|
test "SyntaxNode::find_at_checked: contrasts with find_at fallback" {
  // find_at returns self on bad offset; find_at_checked returns None
  let tok = CstToken::new(RawKind(9), "hi")
  let cst = CstNode::new(RawKind(1), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  // find_at silently returns root
  let fallback = root.find_at(99)
  inspect(fallback.kind() == RawKind(1), content="true")
  // find_at_checked is explicit
  inspect(root.find_at_checked(99) is None, content="true")
}

///|
test "SyntaxNode::find_at drills into deepest child" {
  // Build: root[0,5) → child[0,3) → grandchild[0,2)
  let leaf_tok = CstToken::new(RawKind(9), "ab")
  let grandchild = CstNode::new(RawKind(21), [CstElement::Token(leaf_tok)])
  let child_tok = CstToken::new(RawKind(10), "c")
  let child = CstNode::new(RawKind(20), [
    CstElement::Node(grandchild),
    CstElement::Token(child_tok),
  ])
  let root_tok = CstToken::new(RawKind(11), "de")
  let root = CstNode::new(RawKind(22), [
    CstElement::Node(child),
    CstElement::Token(root_tok),
  ])
  let sn = SyntaxNode::from_cst(root)
  // offset 1 is inside grandchild [0,2)
  inspect(sn.find_at(1).kind() == RawKind(21), content="true")
  // offset 2 is inside child [0,3), past grandchild [0,2)
  inspect(sn.find_at(2).kind() == RawKind(20), content="true")
  // offset 4 is inside root only (past child [0,3))
  inspect(sn.find_at(4).kind() == RawKind(22), content="true")
}

///|
test "SyntaxNode::token_at_offset: Single (offset inside token)" {
  // token "hello" spans [0,5), query offset=2 → Single
  let tok = CstToken::new(RawKind(9), "hello")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  match root.token_at_offset(2) {
    Single(t) => inspect(t.text(), content="hello")
    _ => inspect("wrong", content="hello")
  }
}

///|
test "SyntaxNode::token_at_offset: Single (offset at start)" {
  let tok = CstToken::new(RawKind(9), "hi")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  // offset=0 is inside "hi"[0,2) → Single
  match root.token_at_offset(0) {
    Single(t) => inspect(t.text(), content="hi")
    _ => inspect("wrong", content="hi")
  }
}

///|
test "SyntaxNode::token_at_offset: Between (offset at boundary)" {
  // "ab"[0,2) then "cd"[2,4), query offset=2 → Between
  let t1 = CstToken::new(RawKind(9), "ab")
  let t2 = CstToken::new(RawKind(9), "cd")
  let cst = CstNode::new(RawKind(22), [
    CstElement::Token(t1),
    CstElement::Token(t2),
  ])
  let root = SyntaxNode::from_cst(cst)
  match root.token_at_offset(2) {
    Between(l, r) => {
      inspect(l.text(), content="ab")
      inspect(r.text(), content="cd")
    }
    _ => inspect("wrong", content="ab")
  }
}

///|
test "SyntaxNode::token_at_offset: None (empty tree)" {
  let cst = CstNode::new(RawKind(22), [])
  let root = SyntaxNode::from_cst(cst)
  match root.token_at_offset(0) {
    TokenAtOffset::None => inspect("none", content="none")
    _ => inspect("wrong", content="none")
  }
}

///|
test "SyntaxNode::token_at_offset: None (offset past end)" {
  let tok = CstToken::new(RawKind(9), "x")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  // "x"[0,1), offset=5 → None
  match root.token_at_offset(5) {
    TokenAtOffset::None => inspect("none", content="none")
    _ => inspect("wrong", content="none")
  }
}

///|
test "SyntaxNode::token_text returns text of matching token" {
  let ident = CstToken::new(RawKind(9), "foo")
  let dot = CstToken::new(RawKind(2), ".")
  let root = CstNode::new(RawKind(22), [
    CstElement::Token(dot),
    CstElement::Token(ident),
  ])
  let sn = SyntaxNode::from_cst(root)
  inspect(sn.token_text(RawKind(9)), content="foo")
}

///|
test "SyntaxNode::token_text returns empty string when no match" {
  let tok = CstToken::new(RawKind(9), "x")
  let root = CstNode::new(RawKind(22), [CstElement::Token(tok)])
  let sn = SyntaxNode::from_cst(root)
  inspect(sn.token_text(RawKind(99)), content="")
}

///|
test "SyntaxNode::token_text returns first match when multiple exist" {
  let a = CstToken::new(RawKind(9), "first")
  let b = CstToken::new(RawKind(9), "second")
  let root = CstNode::new(RawKind(22), [
    CstElement::Token(a),
    CstElement::Token(b),
  ])
  let sn = SyntaxNode::from_cst(root)
  inspect(sn.token_text(RawKind(9)), content="first")
}

///|
test "SyntaxNode::token_text on empty node returns empty string" {
  let root = CstNode::new(RawKind(22), [])
  let sn = SyntaxNode::from_cst(root)
  inspect(sn.token_text(RawKind(9)), content="")
}

///|
test "SyntaxNode::children_from skips first N node children" {
  let a = CstNode::new(RawKind(1), [])
  let b = CstNode::new(RawKind(2), [])
  let c = CstNode::new(RawKind(3), [])
  let root = CstNode::new(RawKind(0), [
    CstElement::Node(a),
    CstElement::Node(b),
    CstElement::Node(c),
  ])
  let sn = SyntaxNode::from_cst(root)
  let tail = sn.children_from(1)
  inspect(tail.length(), content="2")
  inspect(tail[0].kind() == RawKind(2), content="true")
  inspect(tail[1].kind() == RawKind(3), content="true")
}

///|
test "SyntaxNode::children_from skips tokens in indexing" {
  let tok = CstToken::new(RawKind(99), "+")
  let a = CstNode::new(RawKind(1), [])
  let b = CstNode::new(RawKind(2), [])
  let root = CstNode::new(RawKind(0), [
    CstElement::Node(a),
    CstElement::Token(tok),
    CstElement::Node(b),
  ])
  let sn = SyntaxNode::from_cst(root)
  let tail = sn.children_from(1)
  inspect(tail.length(), content="1")
  inspect(tail[0].kind() == RawKind(2), content="true")
}

///|
test "SyntaxNode::children_from with start=0 returns all children" {
  let a = CstNode::new(RawKind(1), [])
  let b = CstNode::new(RawKind(2), [])
  let root = CstNode::new(RawKind(0), [CstElement::Node(a), CstElement::Node(b)])
  let sn = SyntaxNode::from_cst(root)
  inspect(sn.children_from(0).length(), content="2")
}

///|
test "SyntaxNode::children_from with negative start returns all children" {
  let a = CstNode::new(RawKind(1), [])
  let b = CstNode::new(RawKind(2), [])
  let root = CstNode::new(RawKind(0), [CstElement::Node(a), CstElement::Node(b)])
  let sn = SyntaxNode::from_cst(root)
  inspect(sn.children_from(-1).length(), content="2")
}

///|
test "SyntaxNode::children_from past end returns empty" {
  let a = CstNode::new(RawKind(1), [])
  let root = CstNode::new(RawKind(0), [CstElement::Node(a)])
  let sn = SyntaxNode::from_cst(root)
  inspect(sn.children_from(5).length(), content="0")
}

///|
test "SyntaxNode::children_from computes correct offsets" {
  let lead = CstToken::new(RawKind(99), "ab")
  let a = CstNode::new(RawKind(1), [
    CstElement::Token(CstToken::new(RawKind(9), "cd")),
  ])
  let b = CstNode::new(RawKind(2), [
    CstElement::Token(CstToken::new(RawKind(9), "ef")),
  ])
  let root = CstNode::new(RawKind(0), [
    CstElement::Token(lead),
    CstElement::Node(a),
    CstElement::Node(b),
  ])
  let sn = SyntaxNode::from_cst(root)
  let tail = sn.children_from(1)
  inspect(tail.length(), content="1")
  inspect(tail[0].start(), content="4")
  inspect(tail[0].end(), content="6")
}

///|
test "SyntaxNode::nodes_and_tokens partitions children" {
  let a = CstNode::new(RawKind(1), [
    CstElement::Token(CstToken::new(RawKind(9), "1")),
  ])
  let plus = CstToken::new(RawKind(5), "+")
  let b = CstNode::new(RawKind(1), [
    CstElement::Token(CstToken::new(RawKind(9), "2")),
  ])
  let root = CstNode::new(RawKind(0), [
    CstElement::Node(a),
    CstElement::Token(plus),
    CstElement::Node(b),
  ])
  let sn = SyntaxNode::from_cst(root)
  let (nodes, tokens) = sn.nodes_and_tokens()
  inspect(nodes.length(), content="2")
  inspect(tokens.length(), content="1")
  inspect(tokens[0].text(), content="+")
}

///|
test "SyntaxNode::nodes_and_tokens filters trivia" {
  let a = CstNode::new(RawKind(1), [
    CstElement::Token(CstToken::new(RawKind(9), "1")),
  ])
  let ws = CstToken::new(RawKind(0), " ")
  let plus = CstToken::new(RawKind(5), "+")
  let ws2 = CstToken::new(RawKind(0), " ")
  let b = CstNode::new(RawKind(1), [
    CstElement::Token(CstToken::new(RawKind(9), "2")),
  ])
  let root = CstNode::new(RawKind(0), [
    CstElement::Node(a),
    CstElement::Token(ws),
    CstElement::Token(plus),
    CstElement::Token(ws2),
    CstElement::Node(b),
  ])
  let sn = SyntaxNode::from_cst(root)
  let (nodes, tokens) = sn.nodes_and_tokens(trivia_kind=Some(RawKind(0)))
  inspect(nodes.length(), content="2")
  inspect(tokens.length(), content="1")
  inspect(tokens[0].text(), content="+")
}

///|
test "SyntaxNode::nodes_and_tokens on empty node" {
  let root = CstNode::new(RawKind(0), [])
  let sn = SyntaxNode::from_cst(root)
  let (nodes, tokens) = sn.nodes_and_tokens()
  inspect(nodes.length(), content="0")
  inspect(tokens.length(), content="0")
}

///|
test "SyntaxNode::nodes_and_tokens tokens only" {
  let a = CstToken::new(RawKind(5), "+")
  let b = CstToken::new(RawKind(6), "-")
  let root = CstNode::new(RawKind(0), [
    CstElement::Token(a),
    CstElement::Token(b),
  ])
  let sn = SyntaxNode::from_cst(root)
  let (nodes, tokens) = sn.nodes_and_tokens()
  inspect(nodes.length(), content="0")
  inspect(tokens.length(), content="2")
}

///|
test "SyntaxNode::nodes_and_tokens nodes only" {
  let a = CstNode::new(RawKind(1), [])
  let b = CstNode::new(RawKind(2), [])
  let root = CstNode::new(RawKind(0), [CstElement::Node(a), CstElement::Node(b)])
  let sn = SyntaxNode::from_cst(root)
  let (nodes, tokens) = sn.nodes_and_tokens()
  inspect(nodes.length(), content="2")
  inspect(tokens.length(), content="0")
}

///|
test "SyntaxNode::nodes_and_tokens preserves offsets" {
  let a = CstNode::new(RawKind(1), [
    CstElement::Token(CstToken::new(RawKind(9), "ab")),
  ])
  let plus = CstToken::new(RawKind(5), "+")
  let b = CstNode::new(RawKind(1), [
    CstElement::Token(CstToken::new(RawKind(9), "cd")),
  ])
  let root = CstNode::new(RawKind(0), [
    CstElement::Node(a),
    CstElement::Token(plus),
    CstElement::Node(b),
  ])
  let sn = SyntaxNode::from_cst(root)
  let (nodes, tokens) = sn.nodes_and_tokens()
  inspect(nodes[0].start(), content="0")
  inspect(nodes[0].end(), content="2")
  inspect(tokens[0].start(), content="2")
  inspect(tokens[0].end(), content="3")
  inspect(nodes[1].start(), content="3")
  inspect(nodes[1].end(), content="5")
}

///|
test "SyntaxNode::nodes_and_tokens without trivia_kind includes all tokens" {
  let ws = CstToken::new(RawKind(0), " ")
  let plus = CstToken::new(RawKind(5), "+")
  let root = CstNode::new(RawKind(0), [
    CstElement::Token(ws),
    CstElement::Token(plus),
  ])
  let sn = SyntaxNode::from_cst(root)
  let (_nodes, tokens) = sn.nodes_and_tokens()
  inspect(tokens.length(), content="2")
}
