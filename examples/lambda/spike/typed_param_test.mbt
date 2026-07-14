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
/// (x : Int, y : Bool) => x — malformed annotation recovery must retain
/// structural CST and diagnostic-count parity with the hand-written parser.
test "lambda chain: unknown typed param preserves A/B recovery parity" {
  let source = "(x : Int, y : Bool) => x"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(a_diag.is_empty(), content="false")
  inspect(b_diag.is_empty(), content="false")
  inspect(a_diag.length() == b_diag.length(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
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

///|
/// (f : Int -> Unit -> Int) => f — right-associative nested TypeArrow.
test "lambda chain: B handles nested TypeArrow param" {
  let source = "(f : Int -> Unit -> Int) => f"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// (f : (Int -> Unit)) => f — parenthesized function type.
test "lambda chain: B handles parenthesized TypeArrow param" {
  let source = "(f : (Int -> Unit)) => f"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}
