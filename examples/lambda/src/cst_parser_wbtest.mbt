///|
test "finish_node without matching start_node is ignored" {
  let ctx = @core.ParserContext::new([], "", lambda_spec)
  ctx.finish_node()
  inspect(ctx.open_nodes, content="0")
}

///|
// test "parse_cst: raises with offending token, not EOF" removed:
// Old parse_cst test removed; use parse_cst (formerly parse_source_file) for error recovery.

///|
test "reuse fires: VarRef unchanged after identifier edit" {
  // Old: "x + y"  →  New: "z + y"  (damage [0,1): only "x" changed)
  // VarRef("y") at [3,5) is outside damage and text is unchanged → reused.
  // reuse_count > 0 confirms the cursor path is live, not a stub.
  let old_source = "x + y"
  let (old_tree, _) = parse_cst(old_source)
  let new_source = "z + y"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 0, 1, new_tokens)
  let (new_tree, errors, reuse_count) = parse_cst_recover_with_tokens(
    new_source,
    new_tokens,
    Some(cursor),
  )
  let (full_tree, _) = parse_cst(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
  inspect(reuse_count > 0, content="true")
}

///|
test "reuse fires: lambda body VarRef unchanged after parameter edit" {
  // Old: "λx.y"  →  New: "λz.y"  (damage [2,3): only the parameter code unit changed)
  // LambdaExpr overlaps damage → body runs normally.
  // VarRef("y") at [4,5) inside the body is outside damage → reused.
  let old_source = "λx.y"
  let (old_tree, _) = parse_cst(old_source)
  let new_source = "λz.y"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 2, 3, new_tokens)
  let (new_tree, errors, reuse_count) = parse_cst_recover_with_tokens(
    new_source,
    new_tokens,
    Some(cursor),
  )
  let (full_tree, _) = parse_cst(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
  inspect(reuse_count > 0, content="true")
}

///|
test "incremental reuse: identifier boundary merge matches full reparse" {
  // Old: "x y" -> New: "xy" (space deleted at [1,2) in old source).
  // Reuse must not produce a stale split; result must match full reparse.
  let old_source = "x y"
  let (old_tree, _) = parse_cst(old_source)
  let new_source = "xy"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 1, 2, new_tokens)
  let (new_tree, errors, _reuse_count) = parse_cst_recover_with_tokens(
    new_source,
    new_tokens,
    Some(cursor),
  )
  let (full_tree, _) = parse_cst(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
}

///|
test "incremental reuse: integer boundary merge matches full reparse" {
  // Old: "1 2" -> New: "12" (space deleted at [1,2) in old source).
  // Reuse must not keep two stale IntLiteral nodes.
  let old_source = "1 2"
  let (old_tree, _) = parse_cst(old_source)
  let new_source = "12"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 1, 2, new_tokens)
  let (new_tree, errors, _reuse_count) = parse_cst_recover_with_tokens(
    new_source,
    new_tokens,
    Some(cursor),
  )
  let (full_tree, _) = parse_cst(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
}

///|
test "incremental reuse: preserves prior diagnostic messages on reused invalid subtree" {
  let source = "λ.x"
  let tokens = @lexer.tokenize(source)
  let (old_tree, old_errors) = parse_cst(source)
  inspect(old_errors.length(), content="1")
  inspect(old_errors[0].message, content="Expected parameter after λ")

  let cursor = make_reuse_cursor(old_tree, 99, 99, tokens)
  let (_, errors, reuse_count) = parse_cst_recover_with_tokens(
    source,
    tokens,
    Some(cursor),
    prev_diagnostics=Some(old_errors),
  )
  inspect(reuse_count > 0, content="true")
  inspect(errors.length(), content="1")
  inspect(errors[0].message, content="Expected parameter after λ")
}

///|
test "parse_cst_recover_with_tokens: preserves prior diagnostic messages on reused invalid subtree" {
  let source = "λ.x"
  let tokens = @lexer.tokenize(source)
  let (old_tree, old_errors) = parse_cst(source)
  inspect(old_errors.length(), content="1")
  inspect(old_errors[0].message, content="Expected parameter after λ")

  let cursor = make_reuse_cursor(old_tree, 99, 99, tokens)
  let (_, errors, reuse_count) = parse_cst_recover_with_tokens(
    source,
    tokens,
    Some(cursor),
    prev_diagnostics=Some(old_errors),
  )
  inspect(reuse_count > 0, content="true")
  inspect(errors.length(), content="1")
  inspect(errors[0].message, content="Expected parameter after λ")
}

///|
test "reuse fires: let init IntLiteral reused after def value edit" {
  // Old: "let x = 1\ny"  →  New: "let x = 1\nz"  (damage [10,11))
  // IntLiteral(1) at [8,9) is outside damage and text is unchanged.
  // Its TRAILING context token is NewlineToken. Reuse should fire.
  let old_source = "let x = 1\ny"
  let (old_tree, _) = parse_cst(old_source)
  let new_source = "let x = 1\nz"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 10, 11, new_tokens)
  let (new_tree, errors, reuse_count) = parse_cst_recover_with_tokens(
    new_source,
    new_tokens,
    Some(cursor),
  )
  let (full_tree, _) = parse_cst(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
  inspect(reuse_count > 0, content="true")
}
