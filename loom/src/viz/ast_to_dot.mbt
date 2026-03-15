// Generic graphviz visualizer — language-agnostic DOT renderer.
// Language-specific DotNode implementations live in their own packages.
// Uses the graphviz Graph AST as the interchange format.

///|
/// Trait for types that can be visualized as a Graphviz DOT graph node.
/// Implement in your language package; the generic `to_dot` renderer does the rest.
pub(open) trait DotNode {
  /// Unique integer id — used as the DOT node name (`node<id>`).
  node_id(Self) -> Int
  /// Raw label text; the renderer escapes it for DOT before writing.
  label(Self) -> String
  /// Extra DOT style attributes, e.g. `color="#c586c0", fillcolor="#c586c022"`.
  /// Return "" to use the default graph-wide node style.
  node_attrs(Self) -> String
  /// Child nodes in traversal order.
  children(Self) -> Array[Self]
  /// Label for the i-th outgoing edge, or "" for no label.
  edge_label(Self, Int) -> String
}

///|
/// Convert any DotNode tree to a graphviz Graph AST.
pub fn[T : DotNode] to_graph(root : T) -> @parser.Graph {
  let stmts : Array[@parser.Statement] = []
  stmts.push(@parser.Assignment("bgcolor", "transparent"))
  stmts.push(
    @parser.AttrStmt(@parser.NodeAttr, {
      attributes: [
        { key: "shape", value: "box" },
        { key: "style", value: "rounded,filled" },
        { key: "fillcolor", value: "#252526" },
        { key: "fontname", value: "Arial" },
        { key: "fontcolor", value: "#d4d4d4" },
        { key: "color", value: "#3c3c3c" },
      ],
    }),
  )
  stmts.push(
    @parser.AttrStmt(@parser.EdgeAttr, {
      attributes: [
        { key: "fontname", value: "Arial" },
        { key: "fontcolor", value: "#858585" },
        { key: "color", value: "#3c3c3c" },
      ],
    }),
  )
  collect_statements(stmts, root)
  { strict: false, directed: true, id: None, statements: stmts }
}

///|
fn[T : DotNode] collect_statements(
  stmts : Array[@parser.Statement],
  node : T,
) -> Unit {
  let node_name = "node" + DotNode::node_id(node).to_string()
  let attrs : Array[@parser.Attribute] = [
    { key: "label", value: DotNode::label(node) },
  ]
  let extra = DotNode::node_attrs(node)
  if extra != "" {
    attrs.append(@parser.parse_attributes(extra))
  }
  stmts.push(
    @parser.NodeStmt({ id: node_name, port: None }, Some({ attributes: attrs })),
  )
  let cs = DotNode::children(node)
  for i = 0; i < cs.length(); i = i + 1 {
    let child = cs[i]
    let child_name = "node" + DotNode::node_id(child).to_string()
    let el = DotNode::edge_label(node, i)
    let edge_attrs : @parser.AttributeList? = if el != "" {
      Some({ attributes: [{ key: "label", value: el }] })
    } else {
      None
    }
    stmts.push(
      @parser.EdgeStmt(
        { id: node_name, port: None },
        [(@parser.Directed, { id: child_name, port: None })],
        edge_attrs,
      ),
    )
    collect_statements(stmts, child)
  }
}

///|
/// Convert any DotNode tree to a Graphviz DOT string.
pub fn[T : DotNode] to_dot(node : T) -> String {
  @parser.format_graph(to_graph(node))
}
