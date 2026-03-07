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
    None => inspect(false, content="true")
  }
}
