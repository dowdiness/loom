///|
test "NodeInterner: intern_node returns structurally equal node" {
  let ni = NodeInterner::new()
  let node = CstNode::new(RawKind(1), [])
  let result = ni.intern_node(node)
  inspect(result == node, content="true")
}

///|
test "NodeInterner: second call for equal structure does not grow size" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  let _ = ni.intern_node(CstNode::new(RawKind(1), [])) // structurally equal
  inspect(ni.size(), content="1")
}

///|
test "NodeInterner: distinct structures get distinct entries" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  let _ = ni.intern_node(CstNode::new(RawKind(2), []))
  inspect(ni.size(), content="2")
}

///|
test "NodeInterner: clear resets size to zero" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  inspect(ni.size(), content="1")
  ni.clear()
  inspect(ni.size(), content="0")
}

///|
test "NodeInterner: intern works correctly after clear" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  ni.clear()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  inspect(ni.size(), content="1")
}

///|
test "NodeInterner: parent with interned children deduplicates" {
  let ni = NodeInterner::new()
  let child = ni.intern_node(CstNode::new(RawKind(1), []))
  let p1 = CstNode::new(RawKind(2), [Node(child)])
  let p2 = CstNode::new(RawKind(2), [Node(child)])
  let _ = ni.intern_node(p1)
  let _ = ni.intern_node(p2)
  inspect(ni.size(), content="2") // child + parent, no duplicate parent
}

///|
test "NodeInterner: nodes differing only in has_any_error are distinct" {
  let ni = NodeInterner::new()
  // Same structure, different has_any_error (built with vs without error_kind)
  let healthy = CstNode::new(RawKind(1), [])
  let error_bearing = CstNode::new(RawKind(1), [], error_kind=Some(RawKind(1)))
  inspect(healthy.has_any_error, content="false")
  inspect(error_bearing.has_any_error, content="true")
  let interned_healthy = ni.intern_node(healthy)
  let interned_error = ni.intern_node(error_bearing)
  // They must be interned as distinct entries
  inspect(ni.size(), content="2")
  inspect(physical_equal(interned_healthy, interned_error), content="false")
}
