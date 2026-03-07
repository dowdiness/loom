///|
test "parse_dot rejects trailing tokens after closing brace" {
  let parsed = parse_dot("digraph { a -> b; } garbage")
  inspect(parsed == None, content="true")
}

///|
test "parse_dot handles non-comment slash without hanging" {
  let parsed = parse_dot("/")
  inspect(parsed == None, content="true")
}

///|
test "parse_dot still accepts valid comments in graph body" {
  let parsed = parse_dot("digraph { a -> b; // trailing comment\n }")
  match parsed {
    Some(graph) => {
      inspect(graph.directed, content="true")
      inspect(graph.statements.length(), content="1")
    }
    None => abort("expected parser to accept valid comment")
  }
}

///|
test "parse_attributes accepts decimal numerals" {
  let attrs = parse_attributes("penwidth=1.5")
  inspect(attrs.length(), content="1")
  inspect(attrs[0].key, content="penwidth")
  inspect(attrs[0].value, content="1.5")
}

///|
test "parse_dot accepts edge statement with subgraph start operand" {
  let parsed = parse_dot("digraph { subgraph { a } -> b; }")
  match parsed {
    Some(graph) => {
      inspect(graph.statements.length(), content="1")
      match graph.statements[0] {
        EdgeStmt(start, edges, _) => {
          inspect(start.id, content="a")
          inspect(edges.length(), content="1")
          inspect(edges[0].1.id, content="b")
        }
        _ => abort("expected edge statement")
      }
    }
    None => abort("expected parser to accept subgraph edge start operand")
  }
}

///|
test "parse_dot accepts edge statement with subgraph target operand" {
  let parsed = parse_dot("digraph { a -> subgraph { b }; }")
  match parsed {
    Some(graph) => {
      inspect(graph.statements.length(), content="1")
      match graph.statements[0] {
        EdgeStmt(start, edges, _) => {
          inspect(start.id, content="a")
          inspect(edges.length(), content="1")
          inspect(edges[0].1.id, content="b")
        }
        _ => abort("expected edge statement")
      }
    }
    None => abort("expected parser to accept subgraph edge target operand")
  }
}
