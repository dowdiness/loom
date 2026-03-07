// DotTreeNode — concrete round-trip type for tree structures.
// Implements DotNode (re-export to DOT) and can be constructed from a Graph AST.

///|
pub(all) struct DotTreeNode {
  int_id : Int
  id : String
  label : String
  attrs : Map[String, String]
  children : Array[DotTreeNode]
  edge_labels : Array[String]
}

///|
pub impl DotNode for DotTreeNode with node_id(self) {
  self.int_id
}

///|
pub impl DotNode for DotTreeNode with label(self) {
  self.label
}

///|
pub impl DotNode for DotTreeNode with node_attrs(self) {
  let buf = StringBuilder::new()
  let mut first = true
  self.attrs.each(fn(k, v) {
    if not(first) {
      buf.write_string(", ")
    }
    buf.write_string(k)
    buf.write_string("=")
    buf.write_string(@parser.format_id(v))
    first = false
  })
  buf.to_string()
}

///|
pub impl DotNode for DotTreeNode with children(self) {
  self.children
}

///|
pub impl DotNode for DotTreeNode with edge_label(self, i) {
  if i < self.edge_labels.length() {
    self.edge_labels[i]
  } else {
    ""
  }
}

///|
/// Build a DotTreeNode from a graphviz Graph AST.
/// Collects nodes and edges, finds root (no incoming edges), builds tree.
pub fn DotTreeNode::from_graph(graph : @parser.Graph) -> DotTreeNode? {
  let node_labels : Map[String, String] = Map::new()
  let node_attrs_map : Map[String, Map[String, String]] = Map::new()
  let child_list : Map[String, Array[(String, String)]] = Map::new()
  let has_incoming : Map[String, Bool] = Map::new()
  let all_node_ids : Array[String] = []
  for stmt in graph.statements {
    match stmt {
      @parser.NodeStmt(node_id, attr_list) => {
        let nid = node_id.id
        let mut lbl = nid
        let attrs : Map[String, String] = Map::new()
        match attr_list {
          Some(al) =>
            for attr in al.attributes {
              if attr.key == "label" {
                lbl = attr.value
              } else {
                attrs[attr.key] = attr.value
              }
            }
          None => ()
        }
        node_labels[nid] = lbl
        node_attrs_map[nid] = attrs
        all_node_ids.push(nid)
      }
      @parser.EdgeStmt(start, targets, attr_list) => {
        let mut edge_label = ""
        match attr_list {
          Some(al) =>
            for attr in al.attributes {
              if attr.key == "label" {
                edge_label = attr.value
              }
            }
          None => ()
        }
        for pair in targets {
          let target = pair.1
          match child_list.get(start.id) {
            Some(arr) => arr.push((target.id, edge_label))
            None => child_list[start.id] = [(target.id, edge_label)]
          }
          has_incoming[target.id] = true
        }
      }
      _ => ()
    }
  }
  // Find root: first node with no incoming edges
  let mut root_id : String? = None
  for nid in all_node_ids {
    match has_incoming.get(nid) {
      Some(true) => ()
      _ => {
        root_id = Some(nid)
        break
      }
    }
  }
  match root_id {
    None => None
    Some(rid) => {
      let counter = Ref::new(0)
      Some(build_tree(rid, node_labels, node_attrs_map, child_list, counter))
    }
  }
}

///|
fn build_tree(
  nid : String,
  node_labels : Map[String, String],
  node_attrs_map : Map[String, Map[String, String]],
  child_list : Map[String, Array[(String, String)]],
  counter : Ref[Int],
) -> DotTreeNode {
  let int_id = counter.val
  counter.val = counter.val + 1
  let label = node_labels.get(nid).unwrap_or(nid)
  let attrs = node_attrs_map.get(nid).unwrap_or(Map::new())
  let kids : Array[DotTreeNode] = []
  let edge_labels : Array[String] = []
  match child_list.get(nid) {
    Some(children) =>
      for pair in children {
        let (child_id, el) = pair
        kids.push(
          build_tree(child_id, node_labels, node_attrs_map, child_list, counter),
        )
        edge_labels.push(el)
      }
    None => ()
  }
  { int_id, id: nid, label, attrs, children: kids, edge_labels }
}
