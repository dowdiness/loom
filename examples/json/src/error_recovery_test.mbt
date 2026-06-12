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
// Guards the *existing* missing-separator recovery in `parse_comma_separated`
// (cst_parser.mbt). The comma between `1` and `2` is missing; the parser must
// recover `2` as a distinct second array element with a diagnostic, NOT truncate
// the list and drop `2` as an unexpected trailing token. See loom #291 — this is
// the behavior `separated_list` currently lacks, so it must stay pinned before
// any combinator migration.
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
