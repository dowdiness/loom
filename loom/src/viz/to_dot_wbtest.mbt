// Whitebox tests for the generic to_dot[T : DotNode] renderer.
// Uses a minimal TestNode fixture — no language dependency.

// ── Fixture ───────────────────────────────────────────────────────────────────

///|
struct TestNode {
  id : Int
  lbl : String
  attrs : String
  kids : Array[TestNode]
  elabels : Array[String]
}

///|
impl DotNode for TestNode with node_id(self) {
  self.id
}

///|
impl DotNode for TestNode with label(self) {
  self.lbl
}

///|
impl DotNode for TestNode with node_attrs(self) {
  self.attrs
}

///|
impl DotNode for TestNode with children(self) {
  self.kids
}

///|
impl DotNode for TestNode with edge_label(self, i) {
  if i < self.elabels.length() {
    self.elabels[i]
  } else {
    ""
  }
}

///|
fn leaf(id : Int, lbl : String, attrs : String) -> TestNode {
  { id, lbl, attrs, kids: [], elabels: [] }
}

///|
fn node(
  id : Int,
  lbl : String,
  attrs : String,
  kids : Array[TestNode],
  elabels : Array[String],
) -> TestNode {
  { id, lbl, attrs, kids, elabels }
}

// ── Header / footer ───────────────────────────────────────────────────────────

///|
test "to_dot: output starts with digraph header" {
  let dot = to_dot(leaf(0, "x", ""))
  inspect(dot.has_prefix("digraph {\n"), content="true")
}

///|
test "to_dot: output ends with closing brace" {
  let dot = to_dot(leaf(0, "x", ""))
  inspect(dot.has_suffix("}\n"), content="true")
}

// ── Node definitions ──────────────────────────────────────────────────────────

///|
test "to_dot: leaf node — label block only when attrs empty" {
  let dot = to_dot(leaf(0, "foo", ""))
  // No second attribute block
  inspect(dot.contains("node0 [label=\"foo\"];"), content="true")
}

///|
test "to_dot: non-empty node_attrs merges into attribute list" {
  let dot = to_dot(leaf(0, "bar", "color=\"#ff0000\""))
  let mut has_label = false
  let mut has_color = false
  match @parser.parse_dot(dot) {
    Some(graph) => {
      for stmt in graph.statements {
        match stmt {
          @parser.NodeStmt(node_id, attr_list) =>
            if node_id.id == "node0" {
              match attr_list {
                Some(al) =>
                  for attr in al.attributes {
                    if attr.key == "label" && attr.value == "bar" {
                      has_label = true
                    }
                    if attr.key == "color" && attr.value == "#ff0000" {
                      has_color = true
                    }
                  }
                None => ()
              }
            }
          _ => ()
        }
      }
      inspect(has_label && has_color, content="true")
    }
    None => inspect(false, content="true")
  }
}

// ── Edges ─────────────────────────────────────────────────────────────────────

///|
test "to_dot: parent-child pair generates an edge" {
  let child = leaf(1, "c", "")
  let parent = node(0, "p", "", [child], [""])
  let dot = to_dot(parent)
  inspect(dot.contains("node0 -> node1"), content="true")
}

///|
test "to_dot: empty edge_label produces plain edge line (no attribute block)" {
  let child = leaf(1, "c", "")
  let parent = node(0, "p", "", [child], [""])
  let dot = to_dot(parent)
  // Edge line must end with ";" immediately — no "[label=...]" between arrow and semicolon
  inspect(dot.contains("node0 -> node1;"), content="true")
}

///|
test "to_dot: non-empty edge_label appears on the edge" {
  let child = leaf(1, "c", "")
  let parent = node(0, "p", "", [child], ["body"])
  let dot = to_dot(parent)
  inspect(dot.contains("node0 -> node1 [label=\"body\"]"), content="true")
}

// ── Label escaping ────────────────────────────────────────────────────────────

///|
test "to_dot: backslash + double-quote escape" {
  let double = leaf(0, "\"", "")
  inspect(to_dot(double).contains("\\\""), content="true")
}

///|
test "to_dot: double backslash escape" {
  let backslash = leaf(0, "\\", "")
  inspect(to_dot(backslash).contains("\\\\"), content="true")
}

///|
test "to_dot: newline escape" {
  let newline = leaf(0, "\n", "")
  inspect(to_dot(newline).contains("\\n"), content="true")
}
