///|
test "from_graph: chained edge targets are linked sequentially" {
  let graph : @parser.Graph = {
    strict: false,
    directed: true,
    id: None,
    statements: [
      @parser.NodeStmt({ id: "a", port: None }, None),
      @parser.NodeStmt({ id: "b", port: None }, None),
      @parser.NodeStmt({ id: "c", port: None }, None),
      @parser.EdgeStmt(
        { id: "a", port: None },
        [
          (@parser.Directed, { id: "b", port: None }),
          (@parser.Directed, { id: "c", port: None }),
        ],
        None,
      ),
    ],
  }

  match DotTreeNode::from_graph(graph) {
    Some(root) => {
      inspect(root.id, content="a")
      inspect(root.children.length(), content="1")
      inspect(root.children[0].id, content="b")
      inspect(root.children[0].children.length(), content="1")
      inspect(root.children[0].children[0].id, content="c")
    }
    None => inspect(false, content="true")
  }
}

///|
test "from_graph: returns None when graph contains a reachable cycle" {
  let graph : @parser.Graph = {
    strict: false,
    directed: true,
    id: None,
    statements: [
      @parser.NodeStmt({ id: "a", port: None }, None),
      @parser.NodeStmt({ id: "b", port: None }, None),
      @parser.NodeStmt({ id: "c", port: None }, None),
      @parser.EdgeStmt(
        { id: "a", port: None },
        [(@parser.Directed, { id: "b", port: None })],
        None,
      ),
      @parser.EdgeStmt(
        { id: "b", port: None },
        [(@parser.Directed, { id: "c", port: None })],
        None,
      ),
      @parser.EdgeStmt(
        { id: "c", port: None },
        [(@parser.Directed, { id: "b", port: None })],
        None,
      ),
    ],
  }

  match DotTreeNode::from_graph(graph) {
    Some(_) => inspect(false, content="true")
    None => inspect(true, content="true")
  }
}

///|
test "from_graph: accepts trees where nodes come from edge statements only" {
  let graph : @parser.Graph = {
    strict: false,
    directed: true,
    id: None,
    statements: [
      @parser.EdgeStmt(
        { id: "a", port: None },
        [
          (@parser.Directed, { id: "b", port: None }),
          (@parser.Directed, { id: "c", port: None }),
        ],
        None,
      ),
    ],
  }

  match DotTreeNode::from_graph(graph) {
    Some(root) => {
      inspect(root.id, content="a")
      inspect(root.children.length(), content="1")
      inspect(root.children[0].id, content="b")
      inspect(root.children[0].children.length(), content="1")
      inspect(root.children[0].children[0].id, content="c")
    }
    None => inspect(false, content="true")
  }
}

///|
test "from_graph: returns None when a node has multiple parents" {
  let graph : @parser.Graph = {
    strict: false,
    directed: true,
    id: None,
    statements: [
      @parser.EdgeStmt(
        { id: "a", port: None },
        [(@parser.Directed, { id: "c", port: None })],
        None,
      ),
      @parser.EdgeStmt(
        { id: "b", port: None },
        [(@parser.Directed, { id: "c", port: None })],
        None,
      ),
    ],
  }

  match DotTreeNode::from_graph(graph) {
    Some(_) => inspect(false, content="true")
    None => inspect(true, content="true")
  }
}

///|
test "from_graph: rejects undirected graph" {
  let graph : @parser.Graph = {
    strict: false,
    directed: false,
    id: None,
    statements: [
      @parser.EdgeStmt(
        { id: "a", port: None },
        [(@parser.Undirected, { id: "b", port: None })],
        None,
      ),
    ],
  }

  match DotTreeNode::from_graph(graph) {
    Some(_) => inspect(false, content="true")
    None => inspect(true, content="true")
  }
}

///|
test "from_graph: rejects undirected edge operator in directed graph" {
  let graph : @parser.Graph = {
    strict: false,
    directed: true,
    id: None,
    statements: [
      @parser.EdgeStmt(
        { id: "a", port: None },
        [(@parser.Undirected, { id: "b", port: None })],
        None,
      ),
    ],
  }

  match DotTreeNode::from_graph(graph) {
    Some(_) => inspect(false, content="true")
    None => inspect(true, content="true")
  }
}
