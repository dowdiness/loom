///|
/// P2: (x : Int) => x — typed arrow parameter must match A's CST.
test "lambda chain: B handles typed arrow param" {
  let source = "(x : Int) => x"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// (x : Int, y : Bool) => x — Bool is not a known type. Both A and B must
/// report at least one diagnostic; exact count parity is not required since
/// recovery paths differ (A's lambda_expect vs ctx.expect).
test "lambda chain: B handles unknown typed param with diagnostic" {
  let source = "(x : Int, y : Bool) => x"
  let (_, a_diag) = @lambda.parse_cst(source)
  let b = build_b_syntax_grammar()
  let (_, b_diag) = b.parse_cst(source)
  inspect(a_diag.is_empty(), content="false")
  inspect(b_diag.is_empty(), content="false")
}

///|
/// (x : Unit) => x — Unit type annotation.
test "lambda chain: B handles Unit typed param" {
  let source = "(x : Unit) => x"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// (f : Int -> Unit) => f — function arrow type annotation.
test "lambda chain: B handles TypeArrow param" {
  let source = "(f : Int -> Unit) => f"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}
