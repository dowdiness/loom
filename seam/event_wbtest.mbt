///|
test "build_tree: single token produces root node" {
  let events = [ParseEvent::Token(RawKind(10), "42")]
  let root = build_tree(events, RawKind(22))
  inspect(root.kind == RawKind(22), content="true")
  inspect(root.children.length(), content="1")
  inspect(root.text_len, content="2")
}

///|
test "build_tree: nested StartNode/FinishNode" {
  let events = [
    ParseEvent::StartNode(RawKind(19)), // IntLiteral
    ParseEvent::Token(RawKind(10), "5"),
    ParseEvent::FinishNode,
  ]
  let root = build_tree(events, RawKind(22))
  inspect(root.kind == RawKind(22), content="true")
  inspect(root.children.length(), content="1")
  let child = match root.children[0] {
    CstElement::Node(n) => n
    CstElement::Token(_) => abort("expected node")
  }
  inspect(child.kind == RawKind(19), content="true")
  inspect(child.text_len, content="1")
}

///|
test "EventBuffer mark and start_at" {
  let buf = EventBuffer::new()
  let m = buf.mark()
  buf.push(ParseEvent::Token(RawKind(9), "x"))
  buf.start_at(m, RawKind(20)) // retroactively set mark to VarRef
  inspect(buf.events[m] == ParseEvent::StartNode(RawKind(20)), content="true")
}

///|
test "Tombstone events are ignored by build_tree" {
  let events = [ParseEvent::Tombstone, ParseEvent::Token(RawKind(10), "1")]
  let root = build_tree(events, RawKind(22))
  inspect(root.children.length(), content="1")
}

///|
test "panic EventBuffer::start_at rejects out-of-bounds mark" {
  let buf = EventBuffer::new()
  buf.start_at(0, RawKind(20))
}

///|
test "panic EventBuffer::start_at rejects non-Tombstone mark" {
  let buf = EventBuffer::new()
  buf.push(ParseEvent::Token(RawKind(9), "x"))
  buf.start_at(0, RawKind(20))
}

///|
test "build_tree: missing FinishNode raises" {
  let result : Result[CstNode, _] = try? build_tree(
    [ParseEvent::StartNode(RawKind(19)), ParseEvent::Token(RawKind(10), "5")],
    RawKind(22),
  )
  guard result is Err(_)
}

///|
test "build_tree: leading FinishNode raises" {
  let result : Result[CstNode, _] = try? build_tree(
    [ParseEvent::FinishNode],
    RawKind(22),
  )
  guard result is Err(_)
}

///|
test "build_tree: extra FinishNode raises" {
  let result : Result[CstNode, _] = try? build_tree(
    [
      ParseEvent::StartNode(RawKind(19)),
      ParseEvent::Token(RawKind(10), "5"),
      ParseEvent::FinishNode,
      ParseEvent::FinishNode,
    ],
    RawKind(22),
  )
  guard result is Err(_)
}

///|
test "build_tree_interned: structurally equal to build_tree" {
  let root_kind = RawKind(0)
  let node_kind = RawKind(1)
  let tok_kind = RawKind(2)
  let events1 = [
    ParseEvent::StartNode(node_kind),
    ParseEvent::Token(tok_kind, "x"),
    ParseEvent::Token(tok_kind, "x"),
    ParseEvent::FinishNode,
  ]
  let events2 = [
    ParseEvent::StartNode(node_kind),
    ParseEvent::Token(tok_kind, "x"),
    ParseEvent::Token(tok_kind, "x"),
    ParseEvent::FinishNode,
  ]
  let plain = build_tree(events1, root_kind)
  let interner = Interner::new()
  let interned = build_tree_interned(events2, root_kind, interner)
  inspect(plain == interned, content="true")
}

///|
test "build_tree_fully_interned: identical subtrees share canonical reference" {
  let interner = Interner::new()
  let ni = NodeInterner::new()
  let events : Array[ParseEvent] = [Token(RawKind(1), "x")]
  let ws = RawKind(99)
  let root_kind = RawKind(0)
  let t1 = build_tree_fully_interned(
    events,
    root_kind,
    interner,
    ni,
    trivia_kind=Some(ws),
  )
  let t2 = build_tree_fully_interned(
    events,
    root_kind,
    interner,
    ni,
    trivia_kind=Some(ws),
  )
  inspect(t1 == t2, content="true")
  inspect(ni.size() <= 2, content="true") // root + child, no duplication
}

///|
test "build_tree_interned: interner size bounded by vocabulary" {
  let root_kind = RawKind(0)
  let tok_kind = RawKind(1)
  let interner = Interner::new()
  let events : Array[ParseEvent] = []
  for _ in 0..<100 {
    events.push(ParseEvent::Token(tok_kind, "x"))
  }
  let _ = build_tree_interned(events, root_kind, interner)
  inspect(interner.size(), content="1")
}

///|
test "build_tree balances >8 same-kind siblings into RepeatGroup" {
  let events : Array[ParseEvent] = []
  // Wrap 16 children inside an explicit parent node (StartNode/FinishNode)
  // so that balance_children is invoked on the parent's children.
  events.push(StartNode(RawKind(1)))
  for _i = 0; _i < 16; _i = _i + 1 {
    events.push(StartNode(RawKind(2)))
    events.push(Token(RawKind(100), "x"))
    events.push(FinishNode)
  }
  events.push(FinishNode)
  let tree = build_tree(events, RawKind(0))
  // The root has one child: the RawKind(1) node
  let parent = match tree.children[0] {
    CstElement::Node(n) => n
    CstElement::Token(_) => abort("expected node")
  }
  // Parent should have fewer than 16 direct children (some grouped into RepeatGroup)
  inspect(parent.children.length() < 16, content="true")
  // But SyntaxNode::children() should still see all 16
  let syn = SyntaxNode::from_cst(tree)
  let parent_syn = syn.children()[0]
  inspect(parent_syn.children().length(), content="16")
}

///|
test "RepeatGroup flattening preserves offsets" {
  let events : Array[ParseEvent] = []
  // Wrap 12 children inside an explicit parent node so balance_children runs
  events.push(StartNode(RawKind(1)))
  for _i = 0; _i < 12; _i = _i + 1 {
    events.push(StartNode(RawKind(2)))
    events.push(Token(RawKind(100), "ab"))
    events.push(FinishNode)
  }
  events.push(FinishNode)
  let tree = build_tree(events, RawKind(0))
  let syn = SyntaxNode::from_cst(tree)
  let parent_syn = syn.children()[0]
  let children = parent_syn.children()
  inspect(children.length(), content="12")
  // Each child should have offset = 2 * index
  for i = 0; i < children.length(); i = i + 1 {
    inspect(children[i].start() == i * 2, content="true")
  }
}

///|
test "build_tree does not balance 8 or fewer same-kind siblings" {
  let events : Array[ParseEvent] = []
  events.push(StartNode(RawKind(1)))
  for _i = 0; _i < 8; _i = _i + 1 {
    events.push(StartNode(RawKind(2)))
    events.push(Token(RawKind(100), "x"))
    events.push(FinishNode)
  }
  events.push(FinishNode)
  let tree = build_tree(events, RawKind(0))
  let parent = match tree.children[0] {
    CstElement::Node(n) => n
    CstElement::Token(_) => abort("expected node")
  }
  // Exactly 8: should NOT be grouped
  inspect(parent.children.length(), content="8")
}

///|
test "build_tree balances 9 same-kind siblings" {
  let events : Array[ParseEvent] = []
  events.push(StartNode(RawKind(1)))
  for _i = 0; _i < 9; _i = _i + 1 {
    events.push(StartNode(RawKind(2)))
    events.push(Token(RawKind(100), "x"))
    events.push(FinishNode)
  }
  events.push(FinishNode)
  let tree = build_tree(events, RawKind(0))
  let parent = match tree.children[0] {
    CstElement::Node(n) => n
    CstElement::Token(_) => abort("expected node")
  }
  // 9 siblings: should be grouped (fewer than 9 direct children)
  inspect(parent.children.length() < 9, content="true")
  // SyntaxNode flattening should still show all 9
  let syn = SyntaxNode::from_cst(tree)
  inspect(syn.children()[0].children().length(), content="9")
}

///|
test "build_tree handles single child without grouping" {
  let events : Array[ParseEvent] = []
  events.push(StartNode(RawKind(1)))
  events.push(StartNode(RawKind(2)))
  events.push(Token(RawKind(100), "x"))
  events.push(FinishNode)
  events.push(FinishNode)
  let tree = build_tree(events, RawKind(0))
  let parent = match tree.children[0] {
    CstElement::Node(n) => n
    CstElement::Token(_) => abort("expected node")
  }
  inspect(parent.children.length(), content="1")
}

///|
test "build_tree handles empty children" {
  let events : Array[ParseEvent] = []
  events.push(StartNode(RawKind(1)))
  events.push(FinishNode)
  let tree = build_tree(events, RawKind(0))
  let parent = match tree.children[0] {
    CstElement::Node(n) => n
    CstElement::Token(_) => abort("expected node")
  }
  inspect(parent.children.length(), content="0")
}

///|
test "build_tree balances interleaved node-separator runs correctly" {
  // Simulates: Node, Sep, Node, Sep, ... (12 nodes with 11 separators = 23 elements)
  // The balanced split should always land on a Node boundary, not a separator.
  let events : Array[ParseEvent] = []
  events.push(StartNode(RawKind(1))) // parent
  for i = 0; i < 12; i = i + 1 {
    events.push(StartNode(RawKind(2))) // child node
    events.push(Token(RawKind(100), "x"))
    events.push(FinishNode)
    if i < 11 {
      events.push(Token(RawKind(200), "\n")) // separator between nodes
    }
  }
  events.push(FinishNode)
  let tree = build_tree(events, RawKind(0))
  let parent = match tree.children[0] {
    CstElement::Node(n) => n
    CstElement::Token(_) => abort("expected node")
  }
  // Should be grouped (fewer than 23 direct children)
  inspect(parent.children.length() < 23, content="true")
  // SyntaxNode flattening should show all 12 node children
  let syn = SyntaxNode::from_cst(tree)
  let parent_syn = syn.children()[0]
  inspect(parent_syn.children().length(), content="12")
  // Every RepeatGroup in the raw tree should start with a Node, not a Token
  fn check_groups(children : Array[CstElement]) -> Unit {
    for elem in children {
      match elem {
        CstElement::Node(n) =>
          if n.kind == repeat_group_kind {
            // First child of a RepeatGroup must be a Node
            match n.children[0] {
              CstElement::Node(_) => check_groups(n.children)
              CstElement::Token(_) =>
                abort("RepeatGroup starts with separator token")
            }
          }
        CstElement::Token(_) => ()
      }
    }
  }
  check_groups(parent.children)
}
