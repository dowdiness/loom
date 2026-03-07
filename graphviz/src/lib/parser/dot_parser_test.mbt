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

///|
test "parse_dot rejects missing port id after colon" {
  let parsed = parse_dot("digraph { a: -> b; }")
  inspect(parsed == None, content="true")
}

///|
test "parse_dot rejects trailing colon without compass point" {
  let parsed = parse_dot("digraph { a:port: -> b; }")
  inspect(parsed == None, content="true")
}

///|
test "parse_dot accepts valid port with compass point" {
  let parsed = parse_dot("digraph { a:port:n -> b; }")
  match parsed {
    Some(graph) => inspect(graph.statements.length(), content="1")
    None => abort("expected parser to accept valid port syntax")
  }
}

///|
test "parse_dot accepts compass-like port id with explicit compass suffix" {
  let parsed = parse_dot("digraph { a:n:sw -> b; }")
  match parsed {
    Some(graph) =>
      match graph.statements[0] {
        EdgeStmt(start, _edges, _) =>
          match start.port {
            Some(port) => {
              match port.id {
                Some(id) => inspect(id, content="n")
                None => abort("expected explicit port id")
              }
              match port.compass {
                Some(SW) => inspect(true, content="true")
                _ => abort("expected sw compass point")
              }
            }
            None => abort("expected parsed port")
          }
        _ => abort("expected edge statement")
      }
    None => abort("expected parser to accept a:n:sw")
  }
}

///|
test "parse_dot rejects malformed edge rhs after consumed operator" {
  let parsed = parse_dot("digraph { a -> ; }")
  inspect(parsed == None, content="true")
}
