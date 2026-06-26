///|
fn make_lambda_let_chain(count : Int) -> String {
  let init : Array[String] = [ for i in 0..<count => "let x\{i} = ((f, x) => f (f x)) ((g) => g)" ]
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
