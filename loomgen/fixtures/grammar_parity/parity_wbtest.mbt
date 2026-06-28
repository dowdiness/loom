///|
test "generated parser matches grammar interpreter for simple node" {
  let interpreted = @grammar.interpret(simple_ir())
  let tokens = [tok(ParityToken::Int), tok(ParityToken::EOF)]
  let (expected_tree, expected_diags) = @core.parse_with(
    "x",
    parity_spec(interpreted),
    _source => tokens,
    interpreted,
  )
  let (actual_tree, actual_diags) = @core.parse_with(
    "x",
    parity_spec(parse_root),
    _source => tokens,
    parse_root,
  )
  inspect(@core.tree_diff(expected_tree, actual_tree).length(), content="0")
  inspect(actual_diags == expected_diags, content="true")
}
