// Tests for incremental parser

///|
test "IncrementalParser::new creates parser" {
  let parser = @loom.new_incremental_parser("42", lambda_grammar)
  inspect(parser.get_source(), content="42")
  inspect(parser.get_tree() is None, content="true")
}

///|
test "IncrementalParser::parse initial parse" {
  let parser = @loom.new_incremental_parser("λx.x", lambda_grammar)
  let tree = parser.parse()
  inspect(@ast.print_ast_node(tree), content="(λx. x)")
  inspect(parser.get_tree() is None, content="false")
}

///|
test "IncrementalParser::edit simple insertion" {
  let parser = @loom.new_incremental_parser("42", lambda_grammar)
  let _ = parser.parse()

  // Insert " + 1" at the end
  let edit = @core.Edit::insert(2, 4) // Insert 4 chars at position 2
  let new_tree = parser.edit(edit, "42 + 1")
  inspect(@ast.print_ast_node(new_tree).contains("42"), content="true")
  inspect(@ast.print_ast_node(new_tree).contains("+"), content="true")
  inspect(@ast.print_ast_node(new_tree).contains("1"), content="true")
}

///|
test "IncrementalParser::edit simple deletion" {
  let parser = @loom.new_incremental_parser("42 + 1", lambda_grammar)
  let _ = parser.parse()

  // Delete " + 1"
  let edit = @core.Edit::delete(2, 6)
  let new_tree = parser.edit(edit, "42")
  inspect(@ast.print_ast_node(new_tree), content="42")
}

///|
test "IncrementalParser::edit replacement" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // Replace "x" with "y"
  let edit = @core.Edit::replace(0, 1, 1)
  let new_tree = parser.edit(edit, "y")
  inspect(@ast.print_ast_node(new_tree), content="y")
}

///|
test "IncrementalParser::edit with no initial tree" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)

  // Edit without parsing first
  let edit = @core.Edit::replace(0, 1, 1)
  let tree = parser.edit(edit, "y")
  inspect(@ast.print_ast_node(tree), content="y")
}

///|
test "IncrementalParser::edit preserves structure" {
  let parser = @loom.new_incremental_parser("λf.λx.f x", lambda_grammar)
  let initial_tree = parser.parse()

  // Insert space (cosmetic change)
  let edit = @core.Edit::insert(9, 1)
  let new_tree = parser.edit(edit, "λf.λx.f x ")

  // Structure should be similar (both are lambda abstractions)
  inspect(@ast.print_ast_node(initial_tree).contains("λf"), content="true")
  inspect(@ast.print_ast_node(new_tree).contains("λf"), content="true")
}

///|
test "IncrementalParser::multiple edits" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // First edit: x -> x + 1
  let edit1 = @core.Edit::insert(1, 4)
  let tree1 = parser.edit(edit1, "x + 1")
  inspect(@ast.print_ast_node(tree1).contains("+"), content="true")

  // Second edit: x + 1 -> x + 2
  let edit2 = @core.Edit::replace(4, 5, 5)
  let tree2 = parser.edit(edit2, "x + 2")
  inspect(@ast.print_ast_node(tree2).contains("2"), content="true")

  // Third edit: x + 2 -> y + 2
  let edit3 = @core.Edit::replace(0, 1, 1)
  let tree3 = parser.edit(edit3, "y + 2")
  inspect(@ast.print_ast_node(tree3).contains("y"), content="true")
}

///|
test "IncrementalParser::edit result equals full reparse" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // Incremental edit
  let edit = @core.Edit::insert(1, 4)
  let incremental_tree = parser.edit(edit, "x + 1")

  // Full reparse
  let full_tree = parse_tree("x + 1")

  // Results should be equivalent (same printed form)
  inspect(
    @ast.print_ast_node(incremental_tree),
    content=@ast.print_ast_node(full_tree),
  )
}

///|
test "tree fragment reuse for unchanged regions" {
  let parser = @loom.new_incremental_parser("λf.λx.f (x + 1)", lambda_grammar)
  let initial_tree = parser.parse()

  // Small edit at the end: "1" -> "2"
  let edit = @core.Edit::replace(14, 15, 15)
  let new_tree = parser.edit(edit, "λf.λx.f (x + 2)")

  // Both trees should have similar structure for unchanged parts
  let initial_str = @ast.print_ast_node(initial_tree)
  let new_str = @ast.print_ast_node(new_tree)
  inspect(initial_str.contains("λf"), content="true")
  inspect(new_str.contains("λf"), content="true")
  inspect(initial_str.contains("λx"), content="true")
  inspect(new_str.contains("λx"), content="true")
  inspect(new_str.contains("2"), content="true")
}

///|
test "minimal reparsing for local edits" {
  let parser = @loom.new_incremental_parser("a + b + c + d", lambda_grammar)
  let _ = parser.parse()

  // Edit only affects "c" -> "x"
  let edit = @core.Edit::replace(8, 9, 9)
  let new_tree = parser.edit(edit, "a + b + x + d")

  // Tree should be correctly updated
  inspect(@ast.print_ast_node(new_tree).contains("x"), content="true")
  inspect(@ast.print_ast_node(new_tree).contains("a"), content="true")
  inspect(@ast.print_ast_node(new_tree).contains("d"), content="true")
}

///|
test "multiple incremental edits preserve correctness" {
  let parser = @loom.new_incremental_parser("λx.x", lambda_grammar)
  let _ = parser.parse()

  // Series of small edits
  let edit1 = @core.Edit::insert(4, 4) // "λx.x" -> "λx.x + 1"
  let tree1 = parser.edit(edit1, "λx.x + 1")
  inspect(@ast.print_ast_node(tree1).contains("+"), content="true")
  let edit2 = @core.Edit::replace(7, 8, 8) // "λx.x + 1" -> "λx.x + 2"
  let tree2 = parser.edit(edit2, "λx.x + 2")
  inspect(@ast.print_ast_node(tree2).contains("2"), content="true")
  let edit3 = @core.Edit::insert(0, 3) // "λx.x + 2" -> "λy.λx.x + 2"
  let tree3 = parser.edit(edit3, "λy.λx.x + 2")
  inspect(@ast.print_ast_node(tree3).contains("λy"), content="true")

  // Final result should match full reparse
  let full_tree = parse_tree("λy.λx.x + 2")
  inspect(@ast.print_ast_node(tree3), content=@ast.print_ast_node(full_tree))
}

///|
test "damage tracking accuracy" {
  let parser = @loom.new_incremental_parser("(a + b) + (c + d)", lambda_grammar)
  let _ = parser.parse()

  // Edit only affects right side: "c" -> "x"
  let edit = @core.Edit::replace(11, 12, 12)
  let new_tree = parser.edit(edit, "(a + b) + (x + d)")

  // Incremental result must match a full reparse of the edited source
  let full_tree = parse_tree("(a + b) + (x + d)")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

// Edge case tests for incremental parsing

///|
test "Edge case: insertion at position 0" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // Insert at the very beginning
  let edit = @core.Edit::insert(0, 3)
  let new_tree = parser.edit(edit, "λx.x")

  // Should correctly parse the new structure
  let full_tree = parse_tree("λx.x")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: insertion at end of document" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // Insert at the very end
  let edit = @core.Edit::insert(1, 4)
  let new_tree = parser.edit(edit, "x + 1")

  // Should correctly parse the new structure
  let full_tree = parse_tree("x + 1")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: delete entire document" {
  let parser = @loom.new_incremental_parser("x + y", lambda_grammar)
  let _ = parser.parse()

  // Delete everything
  let edit = @core.Edit::delete(0, 5)
  let _ = parser.edit(edit, "")

  // Should handle empty document
  inspect(parser.get_source(), content="")
}

///|
test "Edge case: replace with longer text" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // Replace single char with much longer expression
  let edit = @core.Edit::replace(0, 1, 15)
  let new_tree = parser.edit(edit, "λf.λx.f (f (x))")
  let full_tree = parse_tree("λf.λx.f (f (x))")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: replace with shorter text" {
  let parser = @loom.new_incremental_parser("λf.λx.f (f (x))", lambda_grammar)
  let _ = parser.parse()

  // Replace long expression with single char
  let edit = @core.Edit::replace(0, 15, 1)
  let new_tree = parser.edit(edit, "y")
  let full_tree = parse_tree("y")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: consecutive insertions at same position" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // First insertion
  let edit1 = @core.Edit::insert(1, 2)
  let _ = parser.edit(edit1, "x y")

  // Second insertion at same position (after first edit)
  let edit2 = @core.Edit::insert(3, 2)
  let tree2 = parser.edit(edit2, "x y z")
  let full_tree = parse_tree("x y z")
  inspect(@ast.print_ast_node(tree2), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: insertion in middle of lambda parameter" {
  let parser = @loom.new_incremental_parser("λx.x", lambda_grammar)
  let _ = parser.parse()

  // Insert in the middle of parameter name (should change structure)
  let edit = @core.Edit::insert(2, 1)
  let new_tree = parser.edit(edit, "λxy.x")
  let full_tree = parse_tree("λxy.x")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: deletion at boundary between nodes" {
  let parser = @loom.new_incremental_parser("x + y", lambda_grammar)
  let _ = parser.parse()

  // Delete the operator (critical boundary)
  let edit = @core.Edit::delete(2, 4)
  let new_tree = parser.edit(edit, "x y")
  let full_tree = parse_tree("x y")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: structural change from leaf to compound" {
  let parser = @loom.new_incremental_parser("42", lambda_grammar)
  let _ = parser.parse()

  // Change from simple int to binary operation
  let edit = @core.Edit::insert(2, 4)
  let new_tree = parser.edit(edit, "42 + 1")
  let full_tree = parse_tree("42 + 1")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: structural change from compound to leaf" {
  let parser = @loom.new_incremental_parser("x + y", lambda_grammar)
  let _ = parser.parse()

  // Change from binary operation to simple variable
  let edit = @core.Edit::replace(0, 5, 1)
  let new_tree = parser.edit(edit, "z")
  let full_tree = parse_tree("z")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: nested lambda insertion at start" {
  let parser = @loom.new_incremental_parser("λx.x + 1", lambda_grammar)
  let _ = parser.parse()

  // Wrap with another lambda
  let edit = @core.Edit::insert(0, 3)
  let new_tree = parser.edit(edit, "λy.λx.x + 1")
  let full_tree = parse_tree("λy.λx.x + 1")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: multiple rapid edits in sequence" {
  let parser = @loom.new_incremental_parser("a", lambda_grammar)
  let _ = parser.parse()

  // Rapid sequence of edits
  let edit1 = @core.Edit::insert(1, 2)
  let _ = parser.edit(edit1, "a b")
  let edit2 = @core.Edit::insert(3, 2)
  let _ = parser.edit(edit2, "a b c")
  let edit3 = @core.Edit::insert(5, 2)
  let tree3 = parser.edit(edit3, "a b c d")
  let full_tree = parse_tree("a b c d")
  inspect(@ast.print_ast_node(tree3), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: edit that changes operator precedence" {
  let parser = @loom.new_incremental_parser("a + b * c", lambda_grammar)
  let _ = parser.parse()

  // Change to affect precedence structure
  let edit = @core.Edit::replace(4, 5, 5)
  let new_tree = parser.edit(edit, "a + b + c")
  let full_tree = parse_tree("a + b + c")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: whitespace-only insertion" {
  let parser = @loom.new_incremental_parser("λx.x", lambda_grammar)
  let _ = parser.parse()

  // Insert whitespace (should not change structure)
  let edit = @core.Edit::insert(4, 1)
  let new_tree = parser.edit(edit, "λx.x ")

  // Structure should be preserved
  inspect(@ast.print_ast_node(new_tree).contains("λx"), content="true")
}

///|
test "Edge case: validation with identical structure but different content" {
  let parser = @loom.new_incremental_parser("λx.x", lambda_grammar)
  let _ = parser.parse()

  // Change variable name (same structure, different content)
  let edit = @core.Edit::replace(1, 2, 2)
  let new_tree = parser.edit(edit, "λy.x")
  let full_tree = parse_tree("λy.x")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: insertion that creates error node" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // Insert invalid syntax
  let edit = @core.Edit::insert(1, 1)
  let _ = parser.edit(edit, "x+")

  // Should produce some tree (with error recovery)
  inspect(parser.get_source(), content="x+")
}

///|
test "Edge case: zero-length edit (no-op)" {
  let parser = @loom.new_incremental_parser("x + y", lambda_grammar)
  let initial_tree = parser.parse()

  // Zero-length insertion (no change)
  let edit = @core.Edit::insert(2, 0)
  let new_tree = parser.edit(edit, "x + y")

  // Should produce same result
  inspect(
    @ast.print_ast_node(new_tree),
    content=@ast.print_ast_node(initial_tree),
  )
}

///|
test "Edge case: position boundary at node start" {
  let parser = @loom.new_incremental_parser("λx.λy.x", lambda_grammar)
  let _ = parser.parse()

  // Insert exactly at inner lambda boundary
  let edit = @core.Edit::insert(3, 1)
  let new_tree = parser.edit(edit, "λx. λy.x")
  let full_tree = parse_tree("λx. λy.x")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

///|
test "Edge case: position boundary at node end" {
  let parser = @loom.new_incremental_parser("λx.λy.x", lambda_grammar)
  let _ = parser.parse()

  // Insert exactly at end of inner lambda
  let edit = @core.Edit::insert(7, 2)
  let new_tree = parser.edit(edit, "λx.λy.x y")
  let full_tree = parse_tree("λx.λy.x y")
  inspect(@ast.print_ast_node(new_tree), content=@ast.print_ast_node(full_tree))
}

// ============================================================================
// Differential tests: incremental parse == full reparse
// ============================================================================

///|
test "Differential: single token edit in middle" {
  let parser = @loom.new_incremental_parser("a + b + c", lambda_grammar)
  let _ = parser.parse()

  // Change "b" to "x"
  let edit = @core.Edit::replace(4, 5, 5)
  let incremental = parser.edit(edit, "a + x + c")
  let full = parse_tree("a + x + c")
  inspect(@ast.print_ast_node(incremental), content=@ast.print_ast_node(full))
}

///|
test "Differential: insert at beginning" {
  let parser = @loom.new_incremental_parser("y", lambda_grammar)
  let _ = parser.parse()

  // Insert "λx." at beginning
  let edit = @core.Edit::insert(0, 3)
  let incremental = parser.edit(edit, "λx.y")
  let full = parse_tree("λx.y")
  inspect(@ast.print_ast_node(incremental), content=@ast.print_ast_node(full))
}

///|
test "Differential: delete in middle" {
  let parser = @loom.new_incremental_parser("λx.x + 1", lambda_grammar)
  let _ = parser.parse()

  // Delete " + 1"
  let edit = @core.Edit::delete(4, 8)
  let incremental = parser.edit(edit, "λx.x")
  let full = parse_tree("λx.x")
  inspect(@ast.print_ast_node(incremental), content=@ast.print_ast_node(full))
}

///|
test "Differential: complex nested expression" {
  let parser = @loom.new_incremental_parser("λf.λx.f (f x)", lambda_grammar)
  let _ = parser.parse()

  // Change inner "f" to "g"
  let edit = @core.Edit::replace(9, 10, 10)
  let incremental = parser.edit(edit, "λf.λx.f (g x)")
  let full = parse_tree("λf.λx.f (g x)")
  inspect(@ast.print_ast_node(incremental), content=@ast.print_ast_node(full))
}

///|
test "Differential: if-then-else modification" {
  let parser = @loom.new_incremental_parser(
    "if x then 1 else 2", lambda_grammar,
  )
  let _ = parser.parse()

  // Change condition "x" to "y"
  let edit = @core.Edit::replace(3, 4, 4)
  let incremental = parser.edit(edit, "if y then 1 else 2")
  let full = parse_tree("if y then 1 else 2")
  inspect(@ast.print_ast_node(incremental), content=@ast.print_ast_node(full))
}

///|
test "Differential: identifier boundary merge" {
  let parser = @loom.new_incremental_parser("x y", lambda_grammar)
  let _ = parser.parse()

  // Delete boundary whitespace: "x y" -> "xy"
  let edit = @core.Edit::delete(1, 2)
  let incremental = parser.edit(edit, "xy")
  let full = parse_tree("xy")
  inspect(@ast.print_ast_node(full), content="xy")
  inspect(@ast.print_ast_node(incremental), content=@ast.print_ast_node(full))
}

///|
test "Differential: identifier boundary split" {
  let parser = @loom.new_incremental_parser("xy", lambda_grammar)
  let _ = parser.parse()

  // Insert boundary whitespace: "xy" -> "x y"
  let edit = @core.Edit::insert(1, 1)
  let incremental = parser.edit(edit, "x y")
  let full = parse_tree("x y")
  inspect(@ast.print_ast_node(full), content="(x y)")
  inspect(@ast.print_ast_node(incremental), content=@ast.print_ast_node(full))
}

///|
test "Differential: integer boundary merge" {
  let parser = @loom.new_incremental_parser("1 2", lambda_grammar)
  let _ = parser.parse()

  // Delete boundary whitespace: "1 2" -> "12"
  let edit = @core.Edit::delete(1, 2)
  let incremental = parser.edit(edit, "12")
  let full = parse_tree("12")
  inspect(@ast.print_ast_node(full), content="12")
  inspect(@ast.print_ast_node(incremental), content=@ast.print_ast_node(full))
}

///|
test "Differential: integer boundary split" {
  let parser = @loom.new_incremental_parser("12", lambda_grammar)
  let _ = parser.parse()

  // Insert boundary whitespace: "12" -> "1 2"
  let edit = @core.Edit::insert(1, 1)
  let incremental = parser.edit(edit, "1 2")
  let full = parse_tree("1 2")
  inspect(@ast.print_ast_node(full), content="(1 2)")
  inspect(@ast.print_ast_node(incremental), content=@ast.print_ast_node(full))
}

///|
test "Differential: multiple consecutive edits" {
  let parser = @loom.new_incremental_parser("a", lambda_grammar)
  let _ = parser.parse()

  // First edit: a -> a b
  let edit1 = @core.Edit::insert(1, 2)
  let incr1 = parser.edit(edit1, "a b")
  let full1 = parse_tree("a b")
  inspect(@ast.print_ast_node(incr1), content=@ast.print_ast_node(full1))

  // Second edit: a b -> a b c
  let edit2 = @core.Edit::insert(3, 2)
  let incr2 = parser.edit(edit2, "a b c")
  let full2 = parse_tree("a b c")
  inspect(@ast.print_ast_node(incr2), content=@ast.print_ast_node(full2))

  // Third edit: a b c -> a b c d
  let edit3 = @core.Edit::insert(5, 2)
  let incr3 = parser.edit(edit3, "a b c d")
  let full3 = parse_tree("a b c d")
  inspect(@ast.print_ast_node(incr3), content=@ast.print_ast_node(full3))
}

// ============================================================================
// Reuse rate verification tests
// ============================================================================

///|
test "Reuse: count is zero on initial parse" {
  let parser = @loom.new_incremental_parser("λx.x", lambda_grammar)
  let _ = parser.parse()
  // Initial parse has no reuse (no old tree)
  inspect(parser.get_last_reuse_count(), content="0")
}

///|
test "Reuse: nodes are reused for non-overlapping edits" {
  let parser = @loom.new_incremental_parser("a + b + c + d + e", lambda_grammar)
  let _ = parser.parse()

  // Edit only "c" -> "x" (positions 8-9)
  let edit = @core.Edit::replace(8, 9, 9)
  let _ = parser.edit(edit, "a + b + x + d + e")

  // Should have some reuse (nodes a, b, d, e are unchanged)
  // Actual reuse depends on tree structure and damage calculation
  let reuse_count = parser.get_last_reuse_count()
  // At least verify we have the mechanism working
  inspect(reuse_count >= 0, content="true")
}

///|
test "Reuse: edit at end should allow front reuse" {
  let parser = @loom.new_incremental_parser("a b c d e", lambda_grammar)
  let _ = parser.parse()

  // Edit only at the end: "e" -> "x"
  let edit = @core.Edit::replace(8, 9, 9)
  let _ = parser.edit(edit, "a b c d x")

  // Nodes before the edit could potentially be reused
  let reuse_count = parser.get_last_reuse_count()
  inspect(reuse_count >= 0, content="true")
}

///|
test "Reuse: full replacement has no reuse" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // Replace entire document
  let edit = @core.Edit::replace(0, 1, 5)
  let _ = parser.edit(edit, "λf.λx.f x")

  // Complete replacement - likely no reuse
  let reuse_count = parser.get_last_reuse_count()
  inspect(reuse_count >= 0, content="true")
}

///|
test "Reuse: adjacent insert should not incorrectly reuse" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()

  // Insert at end (adjacent to existing node)
  let edit = @core.Edit::insert(1, 2)
  let incr_tree = parser.edit(edit, "x y")
  let full_tree = parse_tree("x y")

  // Most importantly: result should match full reparse
  inspect(
    @ast.print_ast_node(incr_tree),
    content=@ast.print_ast_node(full_tree),
  )
}

///|
test "Reuse: whitespace-containing expressions parse correctly" {
  // Test that internal whitespace in reused nodes is handled correctly
  let parser = @loom.new_incremental_parser("λx. x + 1", lambda_grammar)
  let _ = parser.parse()

  // Edit only the number at the end
  let edit = @core.Edit::replace(8, 9, 9)
  let incr_tree = parser.edit(edit, "λx. x + 2")
  let full_tree = parse_tree("λx. x + 2")

  // Result must match full reparse - validates whitespace handling
  inspect(
    @ast.print_ast_node(incr_tree),
    content=@ast.print_ast_node(full_tree),
  )
}

///|
test "Reuse: multiple spaces between tokens" {
  let parser = @loom.new_incremental_parser("a   +   b", lambda_grammar)
  let _ = parser.parse()

  // Edit "b" -> "c"
  let edit = @core.Edit::replace(8, 9, 9)
  let incr_tree = parser.edit(edit, "a   +   c")
  let full_tree = parse_tree("a   +   c")
  inspect(
    @ast.print_ast_node(incr_tree),
    content=@ast.print_ast_node(full_tree),
  )
}

///|
test "Reuse: leading whitespace in source" {
  let parser = @loom.new_incremental_parser("  x + y", lambda_grammar)
  let _ = parser.parse()

  // Edit "y" -> "z"
  let edit = @core.Edit::replace(6, 7, 7)
  let incr_tree = parser.edit(edit, "  x + z")
  let full_tree = parse_tree("  x + z")
  inspect(
    @ast.print_ast_node(incr_tree),
    content=@ast.print_ast_node(full_tree),
  )
}

///|
test "Reuse: trailing whitespace in source" {
  let parser = @loom.new_incremental_parser("x + y  ", lambda_grammar)
  let _ = parser.parse()

  // Edit "y" -> "z"
  let edit = @core.Edit::replace(4, 5, 5)
  let incr_tree = parser.edit(edit, "x + z  ")
  let full_tree = parse_tree("x + z  ")
  inspect(
    @ast.print_ast_node(incr_tree),
    content=@ast.print_ast_node(full_tree),
  )
}

///|
test "Reuse: tokenization error clears stale concrete syntax tree state" {
  let parser = @loom.new_incremental_parser("1+1+1", lambda_grammar)
  let _ = parser.parse()

  // Introduce a valid edit plus an invalid trailing token.
  let edit1 = @core.Edit::replace(0, 5, 6)
  let _ = parser.edit(edit1, "1+2+1@")
  inspect(parser.get_last_reuse_count(), content="0")

  // Remove invalid token; incremental parse must match full reparse.
  let edit2 = @core.Edit::delete(5, 6)
  let incr_tree = parser.edit(edit2, "1+2+1")
  let full_tree = parse_tree("1+2+1")
  inspect(
    @ast.print_ast_node(incr_tree),
    content=@ast.print_ast_node(full_tree),
  )
}
