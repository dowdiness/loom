// Phase 3: Integrated Error Recovery Tests
//
// These tests verify the Phase 3 exit criteria from ROADMAP.md:
// 1. Parser produces partial trees for all error test cases
// 2. Multiple errors reported for inputs with multiple problems
// 3. Parser never panics or enters infinite loop on any input
// 4. All valid inputs still parse identically to current behavior
// 5. Fuzzing with random inputs: parser always terminates, always produces a tree
//
// Migrated from parse_with_error_recovery/AstNode to parse_cst_recover/SyntaxNode.

// ============================================================================
// Section 1: Partial Tree Construction
// ============================================================================

///|
test "phase3: missing lambda parameter produces partial lambda" {
  let (cst, errors) = parse_source_file("λ.x") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  // Should have error but still produce LambdaExpr
  inspect(errors.length() > 0, content="true")
  inspect(
    @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) ==
    @syntax.LambdaExpr,
    content="true",
  )
}

///|
test "phase3: missing lambda body produces partial lambda" {
  let (cst, errors) = parse_source_file("λx.") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  // Should have error for missing body, but still produce lambda structure
  inspect(errors.length() > 0, content="true")
  inspect(
    @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) ==
    @syntax.LambdaExpr,
    content="true",
  )
}

///|
test "phase3: unexpected operator in lambda body - recovery continues" {
  let (cst, errors) = parse_source_file("λx. + y") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(errors.length(), content="1")
  inspect(
    @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) ==
    @syntax.LambdaExpr,
    content="true",
  )
}

///|
test "phase3: unclosed paren produces partial ParenExpr" {
  let (cst, errors) = parse_source_file("(x + y") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  // Should report missing ), but parse the inner expression
  inspect(errors.length() > 0, content="true")
  inspect(tree.end() > 0, content="true")
}

///|
test "phase3: missing if condition" {
  let (cst, errors) = parse_source_file("if then y else z") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  // Should report error but still produce IfExpr structure
  inspect(errors.length() > 0, content="true")
  inspect(
    @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) ==
    @syntax.IfExpr,
    content="true",
  )
}

///|
test "phase3: missing then branch" {
  let (cst, errors) = parse_source_file("if x else z") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  // Should report missing then
  inspect(errors.length() > 0, content="true")
  inspect(
    @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) ==
    @syntax.IfExpr,
    content="true",
  )
}

///|
test "phase3: missing else branch" {
  let (cst, errors) = parse_source_file("if x then y") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  // Should report missing else
  inspect(errors.length() > 0, content="true")
  inspect(
    @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) ==
    @syntax.IfExpr,
    content="true",
  )
}

// ============================================================================
// Section 2: Multiple Error Reporting
// ============================================================================

///|
test "phase3: two errors - missing param and extra token" {
  let (_, errors) = parse_source_file("λ.x )") catch {
    _ => abort("lex error")
  }
  // Should report: missing param, extra token after expression
  inspect(errors.length() >= 2, content="true")
}

///|
test "phase3: three errors - complex malformed input" {
  let (_, errors) = parse_source_file("λ. + ) x") catch {
    _ => abort("lex error")
  }
  // Should report: missing param, unexpected +, extra tokens
  inspect(errors.length() >= 2, content="true")
}

///|
test "phase3: error in each clause of if" {
  let (cst, errors) = parse_source_file("if + then + else +") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  // Each + is unexpected, should get multiple errors
  inspect(errors.length() >= 3, content="true")
  inspect(
    @syntax.SyntaxKind::from_raw(tree.nth_child(0).unwrap().kind()) ==
    @syntax.IfExpr,
    content="true",
  )
}

///|
test "phase3: nested errors" {
  let (_, errors) = parse_source_file("(λ.x (+ y))") catch {
    _ => abort("lex error")
  }
  // Missing param in lambda, unexpected + in inner paren
  inspect(errors.length() >= 2, content="true")
}

// ============================================================================
// Section 3: Termination Guarantees (Random Input Fuzzing)
// ============================================================================

// Note: The lexer does NOT do error recovery - invalid characters like '@' cause
// tokenization failure which short-circuits parsing entirely. This is by design.
// These tests use only lexer-valid tokens to test parser-level error recovery.

///|
fn phase3_lcg_next(seed : Int) -> Int {
  let a = 1664525
  let c = 1013904223
  // Use a mask to keep within positive 31-bit range
  (seed * a + c) & 0x7FFFFFFF
}

///|
fn phase3_random_token(seed : Int) -> (String, Int) {
  let next = phase3_lcg_next(seed)
  // Pool of valid tokens (no invalid chars that would fail lexer)
  let tokens = [
    "x", "y", "z", "a", "b", "f", "g", "0", "1", "2", "42", "99", "if", "then", "else",
    "\\", "λ", ".", "(", ")", "+", "-", " ", "  ",
  ]
  let idx = (next & 0x7FFFFFFF) % tokens.length()
  (tokens[idx], next)
}

///|
fn phase3_random_string(seed : Int, token_count : Int) -> String {
  let mut s = seed
  let mut result = ""
  for _i = 0; _i < token_count; _i = _i + 1 {
    let (token, next) = phase3_random_token(s)
    result = result + token
    s = next
  }
  result
}

///|
test "phase3-fuzz: random token inputs terminate" {
  // Generate 100 random strings and verify parser terminates
  let mut seed = 42
  for _i = 0; _i < 100; _i = _i + 1 {
    let input = phase3_random_string(seed, 30)
    seed = phase3_lcg_next(seed)

    // Parser must terminate without panic (lex error is ok, just skip)
    try {
      let (cst, _errors) = parse_source_file(input)
      let tree = @seam.SyntaxNode::from_cst(cst)
      assert_true(tree.start() >= 0)
    } catch {
      _ => () // Lex error is fine — just verifying termination
    }
  }
}

///|
test "phase3-fuzz: very long random inputs terminate" {
  // Test with longer inputs to stress error budget
  let mut seed = 12345
  for _i = 0; _i < 20; _i = _i + 1 {
    let input = phase3_random_string(seed, 100)
    seed = phase3_lcg_next(seed)
    try {
      let (cst, _errors) = parse_source_file(input)
      let tree = @seam.SyntaxNode::from_cst(cst)
      assert_true(tree.start() >= 0)
    } catch {
      _ => ()
    }
  }
}

///|
test "phase3-fuzz: pathological repeated operators" {
  // Input designed to hit error budget: repeated unexpected operators
  let input = "+ + + + + + + + + + + + + + + + + + + + + + + + + + + + + +"
  let (cst, _errors) = parse_source_file(input) catch { _ => return }
  let tree = @seam.SyntaxNode::from_cst(cst)
  // Should terminate (error budget prevents infinite loop)
  assert_true(tree.start() >= 0)
}

///|
test "phase3-fuzz: alternating valid/invalid constructs" {
  // Stress recovery by alternating operators and identifiers in wrong places
  let input = "+ x + y + z + if + then + else +"
  let (cst, errors) = parse_source_file(input) catch { _ => return }
  let tree = @seam.SyntaxNode::from_cst(cst)
  // Should produce tree with multiple errors
  assert_true(tree.start() >= 0)
  assert_true(errors.length() > 0)
}

///|
test "phase3-fuzz: deeply nested parens with errors" {
  let input = "(((((( + x )))))))"
  let (cst, errors) = parse_source_file(input) catch { _ => return }
  let tree = @seam.SyntaxNode::from_cst(cst)
  assert_true(tree.start() >= 0)
  assert_true(errors.length() > 0)
}

///|
test "phase3-fuzz: lambda chain with errors" {
  let input = "λa.λb.λc.λd.λe. + x"
  let (cst, errors) = parse_source_file(input) catch { _ => return }
  let tree = @seam.SyntaxNode::from_cst(cst)
  assert_true(tree.start() >= 0)
  assert_true(errors.length() > 0)
}

// ============================================================================
// Section 4: Valid Input Identity (Regression)
// ============================================================================

///|
test "phase3: valid inputs unchanged - comprehensive" {
  let inputs = [
    "0", "42", "123456789", "x", "abc", "variable123", "λx.x", "\\x.x", "λa.λb.a",
    "f x", "f x y z", "1 + 2", "1 - 2", "1 + 2 - 3 + 4", "if x then 1 else 2", "if 1 then if 2 then 3 else 4 else 5",
    "(x)", "((x))", "(λx.x) 42", "λf.λx.f (f x)", "λm.λn.λf.λx.m f (n f x)",
    "(1 + 2) - 3",
  ]
  for input in inputs {
    let direct_term = parse(input) catch {
      e => abort("parse failed on \{input}: \{e}")
    }
    let (cst, errors) = parse_source_file(input) catch {
      _ => abort("lex error on \{input}")
    }
    let recovered_tree = @seam.SyntaxNode::from_cst(cst)

    // No errors on valid input
    if errors.length() != 0 {
      abort("Unexpected error on valid input: \{input}, errors: \{errors}")
    }

    // Terms must match
    let direct_str = @ast.print_term(direct_term)
    let recovered_str = @ast.print_term(syntax_node_to_term(recovered_tree))
    if direct_str != recovered_str {
      abort("Mismatch on valid input: \{input}")
    }
  }
}

// ============================================================================
// Section 5: Error Recovery Continues After Sync Points
// ============================================================================

// Note: Using valid tokens that are unexpected in context, not invalid chars.
// The lexer doesn't do error recovery - it fails on invalid characters.

///|
test "phase3: recovery at right paren" {
  // Error (unexpected +) before ), then valid expression follows
  let (cst, errors) = parse_source_file("(+) x") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  assert_true(errors.length() > 0)
  // Should parse the x after the paren - tree should cover significant content
  assert_true(tree.end() >= 4)
}

///|
test "phase3: recovery at lambda" {
  // Error (leading +) then lambda should be parsed
  let (cst, errors) = parse_source_file("+ λx.x") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  assert_true(errors.length() > 0)
  assert_true(tree.end() >= 6)
}

///|
test "phase3: recovery at if" {
  // Error (leading +) then if should work
  let (cst, errors) = parse_source_file("+ if x then y else z") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  assert_true(errors.length() > 0)
  // Tree should contain the if expression
  assert_true(tree.end() >= 10)
}

///|
test "phase3: multiple sync point recoveries" {
  // Multiple parse errors, parser should recover and continue
  let (cst, errors) = parse_source_file("+ ) λx.x + + if 1 then 2 else 3") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  assert_true(errors.length() > 0)
  // Parser should have recovered and parsed significant content
  assert_true(tree.end() > 10)
}
