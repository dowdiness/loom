// Tests for error recovery — migrated to parse_cst_recover API.
// Tests for the old parse_with_error_recovery/has_errors/collect_errors API
// have been removed; use parse_cst_recover + diagnostics() instead.

///|
test "parse_cst_recover returns diagnostics" {
  let (cst, diagnostics) = parse_cst_recover("λ.x")
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected parameter after λ")
  // Cst should be a valid SourceFile
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
}

///|
test "parse_cst_recover no errors on valid input" {
  let (cst, diagnostics) = parse_cst_recover("λx.x")
  inspect(diagnostics.length(), content="0")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
}

///|
test "parse_cst_recover EOF diagnostics point to end of source" {
  // "if x then y" is missing "else" — the diagnostic for the missing
  // "else" keyword fires at EOF which should be at the end of the source.
  let source = "if x then y"
  let (_, diagnostics) = parse_cst_recover(source)
  inspect(diagnostics.length() > 0, content="true")
  // Find the diagnostic about the missing "else"
  let mut found = false
  for diag in diagnostics {
    if diag.message.contains("else") {
      // Position must be at or near the end of the source, not 0
      inspect(diag.start > 0, content="true")
      found = true
    }
  }
  inspect(found, content="true")
}

///|
test "parse_cst still raises on first error" {
  // parse_cst should maintain backward compat and raise
  let result = parse_cst("λ.x") catch {
    _ =>
      // Expected to raise ParseError
      return
  }
  ignore(result)
  // Should not reach here — parse_cst should have raised
  inspect(false, content="true")
}

///|
test "parse_cst_recover: valid inputs produce no diagnostics" {
  let inputs = [
    "42", "x", "λx.x", "f x", "1 + 2", "if x then 1 else 2", "(x)", "λf.λx.f (f x)",
  ]
  for input in inputs {
    let (_, diagnostics) = parse_cst_recover(input)
    inspect(diagnostics.length(), content="0")
  }
}

// ============================================================================
// lambda_expect error paths — verify Bool return + diagnostic + CST completeness
// ============================================================================

///|
/// Helper: verify CST text_len == source length (every code unit accounted for).
fn assert_cst_complete(source : String, cst : @seam.CstNode) -> Unit {
  let tree = @seam.SyntaxNode::from_cst(cst)
  if tree.end() != source.length() {
    abort(
      "CST incomplete: text_len=\{tree.end()}, source.length()=\{source.length()} for \"\{source}\"",
    )
  }
}

///|
/// Helper: verify the first child node of the CST root has the expected kind.
fn assert_first_child_kind(
  cst : @seam.CstNode,
  expected : @syntax.SyntaxKind,
) -> Unit {
  let tree = @seam.SyntaxNode::from_cst(cst)
  let kind = @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind())
  if kind != expected {
    abort("Expected first child \{expected}, got \{kind}")
  }
}

///|
test "lambda_expect: missing dot in lambda" {
  let source = "λx x"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected .")
  assert_first_child_kind(cst, @syntax.LambdaExpr)
}

///|
test "lambda_expect: missing 'in' in let" {
  let source = "let x = 1 x"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  // node_with_recovery: missing 'in' → body returns false → skip_until
  // consumes trailing 'x' inside LetExpr, so only 1 diagnostic
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected in")
}

///|
test "lambda_expect: missing '=' in let" {
  let source = "let x 1 in x"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  // Should report missing '='
  let mut found_eq = false
  for diag in diagnostics {
    if diag.message.contains("=") {
      found_eq = true
    }
  }
  inspect(found_eq, content="true")
}

///|
test "lambda_expect: missing closing paren" {
  let source = "(λx. x"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected )")
  assert_first_child_kind(cst, @syntax.ParenExpr)
}

// ============================================================================
// skip_until recovery — multi-token garbage is consumed into error nodes
// ============================================================================

///|
test "skip_until: garbage before lambda recovers" {
  // Two unexpected tokens should be skipped, then λx.x parsed normally
  let source = "+ + λx. x"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  // Tree should cover the full input including the recovered lambda
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end(), content="9")
}

///|
test "skip_until: garbage at end of input" {
  let source = "λx. x + +"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  // Should report at least one error for the trailing "+"
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "skip_until: multiple garbage tokens before sync point" {
  let source = "+ - + λx.x"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  // Tree should cover the full input including the recovered lambda
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end(), content="10")
}

// ============================================================================
// skip_until_balanced — paren recovery respecting nesting
// ============================================================================

///|
test "balanced: extra tokens before close paren" {
  // Garbage between expression and ) — should skip to )
  let source = "(λx. x + + )"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  assert_first_child_kind(cst, @syntax.ParenExpr)
}

///|
test "balanced: nested parens with one missing close" {
  // Inner paren is closed, outer is missing )
  let source = "((λx. x)"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "balanced: missing close paren at EOF" {
  let source = "(x + y"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected )")
}

// ============================================================================
// node_with_recovery — constructs recover from internal failures
// ============================================================================

///|
test "node_with_recovery: malformed let missing identifier" {
  // "let = 1 in x" — missing variable name after 'let'
  let source = "let = 1 in x"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  assert_first_child_kind(cst, @syntax.LetExpr)
}

///|
test "node_with_recovery: malformed if missing then" {
  // "if x else z" — missing 'then' keyword
  let source = "if x else z"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  assert_first_child_kind(cst, @syntax.IfExpr)
}

///|
test "node_with_recovery: malformed lambda missing dot and body" {
  // "λx" — missing dot and body
  let source = "λx"
  let (cst, diagnostics) = parse_cst_recover(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  assert_first_child_kind(cst, @syntax.LambdaExpr)
}

// ============================================================================
// Incremental reuse with error recovery transitions
// ============================================================================

///|
test "incremental: fix missing dot by editing" {
  // 1. Parse broken input: "λx x" (missing dot)
  let parser = @loom.new_imperative_parser("λx x", lambda_grammar)
  let _ = parser.parse()
  inspect(parser.diagnostics().length() > 0, content="true")

  // 2. Insert "." after "λx" → "λx. x"
  // "λx x" positions: λ=0, x=1, ' '=2, x=3
  // Insert "." at position 2, shifting ' ' right → "λx. x"
  let edit = @core.Edit::insert(2, 1)
  let new_tree = parser.edit(edit, "λx. x")
  inspect(parser.diagnostics().length(), content="0")
  // The fixed tree should parse correctly
  inspect(@ast.print_term(syntax_node_to_term(new_tree)), content="(λx. x)")
}

///|
test "incremental: introduce error by deleting dot" {
  // 1. Parse valid input: "λx. x"
  let parser = @loom.new_imperative_parser("λx. x", lambda_grammar)
  let _ = parser.parse()
  inspect(parser.diagnostics().length(), content="0")

  // 2. Delete "." at position 2 → "λx x"
  let edit = @core.Edit::delete(2, 3)
  let _ = parser.edit(edit, "λx x")
  inspect(parser.diagnostics().length() > 0, content="true")
}

///|
test "incremental: fix missing paren by appending" {
  // 1. Parse broken input: "(λx. x" (missing closing paren)
  let parser = @loom.new_imperative_parser("(λx. x", lambda_grammar)
  let _ = parser.parse()
  inspect(parser.diagnostics().length() > 0, content="true")

  // 2. Append ")" at end → "(λx. x)"
  let edit = @core.Edit::insert(6, 1)
  let new_tree = parser.edit(edit, "(λx. x)")
  inspect(parser.diagnostics().length(), content="0")
  inspect(@ast.print_term(syntax_node_to_term(new_tree)), content="(λx. x)")
}

///|
test "incremental: error to error edit" {
  // 1. Parse broken input: "λ.x" (missing param)
  let parser = @loom.new_imperative_parser("λ.x", lambda_grammar)
  let _ = parser.parse()
  inspect(parser.diagnostics().length() > 0, content="true")

  // 2. Change "x" to "y" — still broken but different
  let edit = @core.Edit::replace(2, 3, 3)
  let new_tree = parser.edit(edit, "λ.y")
  // Should still have diagnostics (missing param) but produce a valid tree
  inspect(parser.diagnostics().length() > 0, content="true")
  // CST should cover the full source
  inspect(new_tree.end(), content="3")
}
