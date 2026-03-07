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
  self.attrs.each((k, v) => {
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
  let indegree : Map[String, Int] = Map::new()
  let known_node_ids : Map[String, Bool] = Map::new()
  let all_node_ids : Array[String] = []

  fn register_node_id(
    nid : String,
    known_node_ids : Map[String, Bool],
    all_node_ids : Array[String],
    indegree : Map[String, Int],
  ) -> Unit {
    match known_node_ids.get(nid) {
      Some(true) => ()
      _ => {
        known_node_ids[nid] = true
        all_node_ids.push(nid)
        indegree[nid] = 0
      }
    }
  }

  for stmt in graph.statements {
    match stmt {
      @parser.NodeStmt(node_id, attr_list) => {
        let nid = node_id.id
        register_node_id(nid, known_node_ids, all_node_ids, indegree)
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
      }
      @parser.EdgeStmt(start, targets, attr_list) => {
        register_node_id(start.id, known_node_ids, all_node_ids, indegree)
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
        let mut current_source = start.id
        // EdgeStmt attributes apply to every segment in a chain: a->b->c means
        // both (a,b) and (b,c) inherit the statement-level edge label.
        for pair in targets {
          let target = pair.1
          register_node_id(target.id, known_node_ids, all_node_ids, indegree)
          match child_list.get(current_source) {
            Some(arr) => arr.push((target.id, edge_label))
            None => child_list[current_source] = [(target.id, edge_label)]
          }
          indegree[target.id] = indegree.get(target.id).unwrap_or(0) + 1
          current_source = target.id
        }
      }
      _ => ()
    }
  }

  if all_node_ids.length() == 0 {
    return None
  }

  // Validate tree indegrees: exactly one root (0 incoming), every other node has exactly 1 incoming.
  let root_candidates : Array[String] = []
  for nid in all_node_ids {
    match indegree.get(nid).unwrap_or(0) {
      0 => root_candidates.push(nid)
      1 => ()
      _ => return None
    }
  }
  if root_candidates.length() != 1 {
    return None
  }

  let rid = root_candidates[0]

  // Validate connectivity and acyclicity before building the concrete tree.
  let visit_state : Map[String, Int] = Map::new() // 1=in stack, 2=done
  if not(validate_reachability(rid, child_list, visit_state)) {
    return None
  }
  for nid in all_node_ids {
    match visit_state.get(nid) {
      Some(2) => ()
      _ => return None
    }
  }

  let counter = Ref::new(0)
  let visiting : Map[String, Bool] = Map::new()
  build_tree(rid, node_labels, node_attrs_map, child_list, counter, visiting)
}

///|
fn validate_reachability(
  nid : String,
  child_list : Map[String, Array[(String, String)]],
  visit_state : Map[String, Int],
) -> Bool {
  match visit_state.get(nid) {
    Some(1) | Some(2) => return false
    _ => ()
  }
  visit_state[nid] = 1
  match child_list.get(nid) {
    Some(children) =>
      for pair in children {
        if not(validate_reachability(pair.0, child_list, visit_state)) {
          return false
        }
      }
    None => ()
  }
  visit_state[nid] = 2
  true
}

///|
fn build_tree(
  nid : String,
  node_labels : Map[String, String],
  node_attrs_map : Map[String, Map[String, String]],
  child_list : Map[String, Array[(String, String)]],
  counter : Ref[Int],
  visiting : Map[String, Bool],
) -> DotTreeNode? {
  match visiting.get(nid) {
    Some(true) => return None
    _ => ()
  }
  visiting[nid] = true
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
        let child = build_tree(
          child_id, node_labels, node_attrs_map, child_list, counter, visiting,
        )
        match child {
          Some(node) => kids.push(node)
          None => {
            visiting[nid] = false
            return None
          }
        }
        edge_labels.push(el)
      }
    None => ()
  }
  visiting[nid] = false
  Some({ int_id, id: nid, label, attrs, children: kids, edge_labels })
}
