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
