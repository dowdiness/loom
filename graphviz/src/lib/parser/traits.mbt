// ToDot / FromDot — traits for converting between domain types and Graph AST.

///|
pub(open) trait ToDot {
  to_graph(Self) -> Graph
}

///|
pub(open) trait FromDot {
  from_graph(Graph) -> Self?
}

///|
pub fn[T : ToDot] to_dot_string(value : T) -> String {
  format_graph(ToDot::to_graph(value))
}

///|
pub fn[T : FromDot] from_dot_string(dot : String) -> T? {
  match parse_dot(dot) {
    Some(graph) => FromDot::from_graph(graph)
    None => None
  }
}
