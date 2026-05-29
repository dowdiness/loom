///|
struct RecordingSyntaxVisitor {
  log : Array[String]
  skip_kind : RawKind?
}

///|
fn syntax_visitor_kind_text(kind : RawKind) -> String {
  kind.0.to_string()
}

///|
fn syntax_visitor_span_text(start : Int, end : Int) -> String {
  "@" + start.to_string() + "-" + end.to_string()
}

///|
impl SyntaxMutVisitor for RecordingSyntaxVisitor with fn enter_node(self, node) {
  self.log.push(
    "enter:" +
    syntax_visitor_kind_text(node.kind()) +
    syntax_visitor_span_text(node.start(), node.end()),
  )
  match self.skip_kind {
    Some(kind) => node.kind() != kind
    None => true
  }
}

///|
impl SyntaxMutVisitor for RecordingSyntaxVisitor with fn exit_node(self, node) {
  self.log.push(
    "exit:" +
    syntax_visitor_kind_text(node.kind()) +
    syntax_visitor_span_text(node.start(), node.end()),
  )
}

///|
impl SyntaxMutVisitor for RecordingSyntaxVisitor with fn visit_token(
  self,
  token,
) {
  self.log.push(
    "token:" +
    syntax_visitor_kind_text(token.kind()) +
    syntax_visitor_span_text(token.start(), token.end()) +
    ":" +
    token.text(),
  )
}

///|
fn syntax_visitor_token(kind : Int, text : String) -> CstElement {
  Token(CstToken(RawKind(kind), text))
}

///|
fn syntax_visitor_node(kind : Int, children : Array[CstElement]) -> CstElement {
  Node(CstNode::new(RawKind(kind), children))
}

///|
test "SyntaxNode::accept_visitor walks source order and flattens repeat groups" {
  let repeated = CstNode::new(repeat_group_kind, [
    syntax_visitor_token(4, "c"),
    syntax_visitor_node(5, [syntax_visitor_token(6, "d")]),
  ])
  let root = CstNode::new(RawKind(0), [
    syntax_visitor_token(1, "a"),
    syntax_visitor_node(2, [syntax_visitor_token(3, "b")]),
    Node(repeated),
    syntax_visitor_token(7, "e"),
  ])
  let visitor = RecordingSyntaxVisitor::{ log: [], skip_kind: None }

  SyntaxNode::from_cst(root).accept_visitor(visitor)

  inspect(
    visitor.log.join("|"),
    content="enter:0@0-5|token:1@0-1:a|enter:2@1-2|token:3@1-2:b|exit:2@1-2|token:4@2-3:c|enter:5@3-4|token:6@3-4:d|exit:5@3-4|token:7@4-5:e|exit:0@0-5",
  )
}

///|
test "SyntaxNode::accept_visitor skips subtree when enter_node returns false" {
  let root = CstNode::new(RawKind(0), [
    syntax_visitor_node(9, [syntax_visitor_token(1, "x")]),
    syntax_visitor_token(2, "y"),
  ])
  let visitor = RecordingSyntaxVisitor::{ log: [], skip_kind: Some(RawKind(9)) }

  SyntaxNode::from_cst(root).accept_visitor(visitor)

  inspect(
    visitor.log.join("|"),
    content="enter:0@0-2|enter:9@0-1|token:2@1-2:y|exit:0@0-2",
  )
}
