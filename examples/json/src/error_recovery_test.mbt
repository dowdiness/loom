///|
test "error recovery: trailing comma in object" {
  let (cst, diagnostics) = try! parse_cst("{\"a\": 1,}")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "{\"a\": 1,}".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: trailing comma in array" {
  let (cst, diagnostics) = try! parse_cst("[1,]")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "[1,]".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing colon" {
  let (cst, diagnostics) = try! parse_cst("{\"key\" 42}")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "{\"key\" 42}".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing closing brace" {
  let (cst, diagnostics) = try! parse_cst("{\"a\": 1")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "{\"a\": 1".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: empty input" {
  let (cst, diagnostics) = try! parse_cst("")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end(), content="0")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing closing bracket" {
  let (cst, diagnostics) = try! parse_cst("[1, 2")
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "[1, 2".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
// Guards missing-separator recovery for the JSON separated-list parser. The
// comma between `1` and `2` is missing; the parser must recover `2` as a
// distinct second array element with a diagnostic, NOT truncate the list and
// drop `2` as an unexpected trailing token. See loom #291.
test "error recovery: missing comma between array elements" {
  let (value, diagnostics) = try! parse_json("[1 2]")
  // The missing separator must surface as a diagnostic.
  inspect(diagnostics.length() > 0, content="true")
  match value {
    Array(items) => {
      inspect(items.length(), content="2")
      inspect(items[1], content="Number(2)")
    }
    _ => fail("expected array recovery, got " + value.to_string())
  }
}

///|
test "error recovery: missing comma array CST shape stays wrapper-free" {
  let (cst, diagnostics) = try! parse_cst("[1 2]")
  inspect(diagnostics.length() > 0, content="true")
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [array_node] => {
      inspect(SyntaxKind::from_raw(array_node.kind()), content="ArrayNode")
      match array_node.children() {
        [first, second] => {
          inspect(SyntaxKind::from_raw(first.kind()), content="NumberValue")
          inspect(SyntaxKind::from_raw(second.kind()), content="NumberValue")
        }
        _ => fail("expected two array values")
      }
      inspect(
        array_node.direct_token_of_kind(SyntaxKind::ErrorToken.to_raw())
        is Some(_),
        content="true",
      )
    }
    _ => fail("expected single array root child")
  }
}

///|
test "error recovery: trailing comma array CST shape stays wrapper-free" {
  let (cst, diagnostics) = try! parse_cst("[1,]")
  inspect(diagnostics.length() > 0, content="true")
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [array_node] => {
      inspect(SyntaxKind::from_raw(array_node.kind()), content="ArrayNode")
      match array_node.children() {
        [_] => ()
        _ => fail("expected one array value")
      }
      inspect(
        array_node.direct_token_of_kind(SyntaxKind::ErrorToken.to_raw())
        is Some(_),
        content="true",
      )
    }
    _ => fail("expected single array root child")
  }
}

///|
test "error recovery: non-sync array element stays an error child" {
  let (cst, diagnostics) = try! parse_cst("[1, @, 2]")
  inspect(diagnostics.length() > 0, content="true")
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [array_node] =>
      match array_node.children() {
        [_, middle, _] =>
          inspect(SyntaxKind::from_raw(middle.kind()), content="ErrorToken")
        _ => fail("expected three array values")
      }
    _ => fail("expected single array root child")
  }
}

///|
// Object counterpart of the array missing-comma guard above: `{"a":1 "b":2}`
// omits the separator between members; the second member must be recovered.
test "error recovery: missing comma between object members" {
  let (value, diagnostics) = try! parse_json("{\"a\":1 \"b\":2}")
  inspect(diagnostics.length() > 0, content="true")
  match value {
    Object(members) => {
      // Both members recovered, in source order — `b` was not dropped.
      inspect(members.length(), content="2")
      inspect(members[0].0, content="a")
      inspect(members[1].0, content="b")
    }
    _ => fail("expected object recovery, got " + value.to_string())
  }
}

///|
test "error recovery: missing comma object CST shape stays wrapper-free" {
  let (cst, diagnostics) = try! parse_cst("{\"a\":1 \"b\":2}")
  inspect(diagnostics.length() > 0, content="true")
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [object_node] => {
      inspect(SyntaxKind::from_raw(object_node.kind()), content="ObjectNode")
      match
        object_node.direct_children_of_kind(SyntaxKind::MemberNode.to_raw()) {
        [_, _] => ()
        _ => fail("expected two object members")
      }
      inspect(
        object_node.direct_token_of_kind(SyntaxKind::ErrorToken.to_raw())
        is Some(_),
        content="true",
      )
    }
    _ => fail("expected single object root child")
  }
}

///|
test "error recovery: trailing comma object CST shape stays wrapper-free" {
  let (cst, diagnostics) = try! parse_cst("{\"a\":1,}")
  inspect(diagnostics.length() > 0, content="true")
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [object_node] => {
      inspect(SyntaxKind::from_raw(object_node.kind()), content="ObjectNode")
      match
        object_node.direct_children_of_kind(SyntaxKind::MemberNode.to_raw()) {
        [_] => ()
        _ => fail("expected one object member")
      }
      inspect(
        object_node.direct_token_of_kind(SyntaxKind::ErrorToken.to_raw())
        is Some(_),
        content="true",
      )
    }
    _ => fail("expected single object root child")
  }
}
