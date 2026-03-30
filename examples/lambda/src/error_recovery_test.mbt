// Tests for error recovery — migrated to parse_cst API.

///|
fn parse_cst_or_fail_recovery(
  source : String,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise {
  parse_cst(source) catch {
    _ => fail("lex error on " + source)
  }
}

///|
test "parse_cst returns diagnostics" {
  let (cst, diagnostics) = parse_cst_or_fail_recovery("λ.x")
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected parameter after λ")
  // Cst should be a valid SourceFile
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
}

///|
test "parse_cst no errors on valid input" {
  let (cst, diagnostics) = parse_cst_or_fail_recovery("λx.x")
  inspect(diagnostics.length(), content="0")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
}

///|
test "parse_cst EOF diagnostics point to end of source" {
  // "if x then y" is missing "else" — the diagnostic for the missing
  // "else" keyword fires at EOF which should be at the end of the source.
  let source = "if x then y"
  let (_, diagnostics) = parse_cst_or_fail_recovery(source)
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
test "parse_cst: valid inputs produce no diagnostics" {
  let inputs = [
    "42", "x", "λx.x", "f x", "1 + 2", "if x then 1 else 2", "(x)", "λf.λx.f (f x)",
  ]
  for input in inputs {
    let (_, diagnostics) = parse_cst_or_fail_recovery(input)
    inspect(diagnostics.length(), content="0")
  }
}

// ============================================================================
// lambda_expect error paths — verify Bool return + diagnostic + CST completeness
// ============================================================================

///|
/// Helper: verify CST text_len == source length (every code unit accounted for).
fn assert_cst_complete(source : String, cst : @seam.CstNode) -> Unit raise {
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == source.length(), content="true")
}

///|
/// Helper: verify the first child node of the CST root has the expected kind.
fn assert_first_child_kind(
  cst : @seam.CstNode,
  expected : @syntax.SyntaxKind,
) -> Unit raise {
  let tree = @seam.SyntaxNode::from_cst(cst)
  let kind = @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind())
  inspect(kind == expected, content="true")
}

///|
test "lambda_expect: missing dot in lambda" {
  let source = "λx x"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected .")
  assert_first_child_kind(cst, @syntax.LambdaExpr)
}

///|
test "lambda_expect: missing '=' in let" {
  let source = "let x 1\nx"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
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
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected )")
  assert_first_child_kind(cst, @syntax.ParenExpr)
}

///|
test "lambda_expect: missing ')' in if condition keeps then/else" {
  let source = "if (x then y else z"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(
    @ast.print_term(syntax_node_to_term(tree)),
    content="if x then y else z",
  )
  let mut found_paren = false
  for diag in diagnostics {
    if diag.message.contains(")") {
      found_paren = true
    }
  }
  inspect(found_paren, content="true")
}

// ============================================================================
// skip_until recovery — multi-token garbage is consumed into error nodes
// ============================================================================

///|
test "skip_until: garbage before lambda recovers" {
  // Two unexpected tokens should be skipped, then λx.x parsed normally
  let source = "+ + λx. x"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  // Tree should cover the full input including the recovered lambda
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end(), content="9")
}

///|
test "skip_until: garbage at end of input" {
  let source = "λx. x + +"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  // Should report at least one error for the trailing "+"
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "skip_until: multiple garbage tokens before sync point" {
  let source = "+ - + λx.x"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
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
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  assert_first_child_kind(cst, @syntax.ParenExpr)
}

///|
test "balanced: nested parens with one missing close" {
  // Inner paren is closed, outer is missing )
  let source = "((λx. x)"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "balanced: missing close paren at EOF" {
  let source = "(x + y"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected )")
}

// ============================================================================
// node_with_recovery — constructs recover from internal failures
// ============================================================================

///|
test "node_with_recovery: malformed let missing identifier" {
  // "let = 1\nx" — missing variable name after 'let'
  let source = "let = 1\nx"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  assert_first_child_kind(cst, @syntax.LetDef)
}

///|
test "node_with_recovery: malformed if missing then" {
  // "if x else z" — missing 'then' keyword
  let source = "if x else z"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
  assert_first_child_kind(cst, @syntax.IfExpr)
}

///|
test "node_with_recovery: malformed lambda missing dot and body" {
  // "λx" — missing dot and body
  let source = "λx"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
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
  inspect(@ast.print_term(new_tree), content="(λx. x)")
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
  inspect(@ast.print_term(new_tree), content="(λx. x)")
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
  // Should produce a term with error recovery (λ with missing param → error + body)
  inspect(
    @ast.print_term(new_tree),
    content=(
      #|(λ. y)
    ),
  )
}

// ============================================================================
// ParamList error recovery
// ============================================================================

///|
test "error recovery: empty param list" {
  let (cst, diagnostics) = parse_cst_or_fail_recovery("let f() = x")
  assert_cst_complete("let f() = x", cst)
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: trailing comma in param list" {
  let (cst, diagnostics) = parse_cst_or_fail_recovery("let f(x,) = x")
  assert_cst_complete("let f(x,) = x", cst)
  // Trailing comma should emit a diagnostic
  inspect(diagnostics.length() > 0, content="true")
}

// ============================================================================
// BlockExpr error recovery
// ============================================================================

///|
test "error recovery: empty block" {
  let (cst, diagnostics) = parse_cst_or_fail_recovery("{ }")
  assert_cst_complete("{ }", cst)
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing closing brace" {
  let source = "let x = { let a = 1\na"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing semicolon between defs in block" {
  let source = "{ let a = 1 let b = 2; a }"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: leading comma in param list" {
  let source = "let f(,) = x"
  let (cst, diagnostics) = parse_cst_or_fail_recovery(source)
  assert_cst_complete(source, cst)
  inspect(diagnostics.length() > 0, content="true")
}
