///|
fn make_lambda_let_chain(count : Int) -> String {
  let init : Array[String] = [
    for i in 0..<count => "let x\{i} = ((f, x) => f (f x)) ((g) => g)"
  ]
  init.push("x\{count - 1}")
  init.join("\n")
}

///|
/// #476 permanent parse-health test: build_b() must parse the actual benchmark
/// workload into a clean initial CST with no diagnostics and structural parity
/// with A. Uses the replicated make_lambda_let_chain(20) matching the benchmark.
test "lambda chain: B parses N=20 workload cleanly with structural parity to A" {
  let source = make_lambda_let_chain(20)
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// #476 minimal reproduction: a single let with the arrow-lambda init.
test "lambda chain: B parses single let with arrow lambda cleanly" {
  let source = "let x0 = ((f, x) => f (f x)) ((g) => g)\nx0"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// Simple arrow lambda (g) => g — minimal lambda expression.
test "lambda chain: B parses simple arrow lambda cleanly" {
  let source = "let x0 = ((g) => g)\nx0"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// P2: (x)\n=> x — soft newline between params and FatArrow must be consumed.
test "lambda chain: B handles soft newline before FatArrow" {
  let source = "(x)\n=> x"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b = build_b_syntax_grammar()
  let (b_cst, _) = b.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// P2: (x) =>\nx — soft newline between FatArrow and body must be consumed.
test "lambda chain: B handles soft newline before lambda body" {
  let source = "(x) =>\nx"
  let (a_cst, _) = @lambda.parse_cst(source)
  let b = build_b_syntax_grammar()
  let (b_cst, _) = b.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// P2: () => 1 — empty param list must emit the same diagnostic as A.
test "lambda chain: B rejects empty param list with same diagnostic" {
  let source = "() => 1"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
  // Both must report the empty-param-list diagnostic
  inspect(a_diag.is_empty(), content="false")
  inspect(b_diag.is_empty(), content="false")
}

///|
/// (x y) => z — malformed params. Both must report diagnostics; exact CST
/// recovery shape may differ between A's node_with_recovery and B's probe.
test "lambda chain: B recovers from malformed arrow params like A" {
  let source = "(x y) => z"
  let (_, a_diag) = @lambda.parse_cst(source)
  let b = build_b_syntax_grammar()
  let (_, b_diag) = b.parse_cst(source)
  inspect(a_diag.is_empty(), content="false")
  inspect(b_diag.is_empty(), content="false")
}

///|
/// P2: (x) => { x } — block body lambda. A's parse_arrow_lambda routes { }
/// through parse_block_expr, not the expression/application path.
test "lambda chain: B parses block-bodied lambda cleanly" {
  let source = "(x) => { x }"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}

///|
/// P2: (x\n) => x — soft newline before closing paren.
test "lambda chain: B handles newline before closing paren" {
  let source = "(x\n) => x"
  let (a_cst, a_diag) = @lambda.parse_cst(source)
  inspect(a_diag.is_empty(), content="true")
  let b = build_b_syntax_grammar()
  let (b_cst, b_diag) = b.parse_cst(source)
  inspect(b_diag.is_empty(), content="true")
  let diff = @core.tree_diff(a_cst, b_cst)
  inspect(diff.length() == 0, content="true")
}
