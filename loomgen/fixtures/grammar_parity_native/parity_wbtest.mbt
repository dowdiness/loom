///|
/// Interpreted-path native (`call_rule("inner")`) and emitted-path native
/// (direct `parse_inner(ctx)`, in `native_parser.g.mbt`) must agree — this is
/// the parity contract `Native` is not exempt from (issue #541 correction 5).
test "generated parser matches grammar interpreter for a Native re-entry" {
  let interpreted = @grammar.interpret(native_ir(), natives=native_registry())
  let tokens = [tok(NativeParityToken::Int), tok(NativeParityToken::EOF)]
  let (expected_tree, expected_diags) = @core.parse_with(
    "x",
    native_parity_spec(interpreted),
    _source => tokens,
    interpreted,
  )
  let (actual_tree, actual_diags) = @core.parse_with(
    "x",
    native_parity_spec(parse_root),
    _source => tokens,
    parse_root,
  )
  inspect(@core.tree_diff(expected_tree, actual_tree).length(), content="0")
  inspect(actual_diags == expected_diags, content="true")
}
