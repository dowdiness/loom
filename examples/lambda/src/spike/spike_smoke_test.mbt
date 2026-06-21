///|
test "spike package can call public lambda parse_cst" {
  let (_, diagnostics) = @lambda.parse_cst("let x = 1")
  inspect(diagnostics.is_empty(), content="true")
}
