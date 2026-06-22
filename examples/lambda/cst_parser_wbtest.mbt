///|
// test "finish_node without matching start_node is ignored" relocated to
// loom core (parser_wbtest.mbt) in loom#251: it tests core's finish_node
// underflow guard via the now-private open_nodes field, so it belongs to core.

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
  let cursor = make_reuse_cursor(old_tree, 0, 1, new_tokens, new_source)
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
  // Old: "(x) => y"  →  New: "(z) => y"  (damage [2,3): only the parameter code unit changed)
  // LambdaExpr overlaps damage → body runs normally.
  // VarRef("y") at [4,5) inside the body is outside damage → reused.
  let old_source = "(x) => y"
  let (old_tree, _) = parse_cst(old_source)
  let new_source = "(z) => y"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 2, 3, new_tokens, new_source)
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
  let cursor = make_reuse_cursor(old_tree, 1, 2, new_tokens, new_source)
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
  let cursor = make_reuse_cursor(old_tree, 1, 2, new_tokens, new_source)
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
test "incremental reuse: deletion opt-in reuses left-adjacent expression" {
  // Old: "x + y" -> New: "x+ y" (space deleted at [1,2)).
  // Strict boundary handling reparses the left VarRef; deletion opt-in keeps it
  // reusable because the follow token remains "+".
  let old_source = "x + y"
  let (old_tree, _) = parse_cst(old_source)
  let new_source = "x+ y"
  let new_tokens = @lexer.tokenize(new_source)
  let edit = @core.Edit::delete(1, 2)
  let strict_cursor = make_reuse_cursor_with_edit(
    old_tree, edit, new_tokens, new_source,
  )
  let (_, strict_errors, strict_reuse_count) = parse_cst_recover_with_tokens(
    new_source,
    new_tokens,
    Some(strict_cursor),
  )
  let relaxed_cursor = make_reuse_cursor_with_edit(
    old_tree,
    edit,
    new_tokens,
    new_source,
    allow_left_adjacent_reuse=true,
  )
  let (new_tree, errors, relaxed_reuse_count) = parse_cst_recover_with_tokens(
    new_source,
    new_tokens,
    Some(relaxed_cursor),
  )
  let (full_tree, _) = parse_cst(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(strict_errors.length(), content="0")
  inspect(errors.length(), content="0")
  inspect(relaxed_reuse_count > strict_reuse_count, content="true")
}

///|
test "incremental reuse: preserves prior diagnostic messages on reused invalid subtree" {
  let source = "(x) =>"
  let tokens = @lexer.tokenize(source)
  let (old_tree, old_errors) = parse_cst(source)
  inspect(old_errors.length() > 0, content="true")

  let cursor = make_reuse_cursor(old_tree, 99, 99, tokens, source)
  let (_, errors, reuse_count) = parse_cst_recover_with_tokens(
    source,
    tokens,
    Some(cursor),
    prev_diagnostics=Some(old_errors),
  )
  inspect(reuse_count > 0, content="true")
  inspect(errors.length(), content=old_errors.length().to_string())
  inspect(errors.items()[0].message, content=old_errors.items()[0].message)
}

///|
test "parse_cst_recover_with_tokens: preserves prior diagnostic messages on reused invalid subtree" {
  let source = "(x) =>"
  let tokens = @lexer.tokenize(source)
  let (old_tree, old_errors) = parse_cst(source)
  inspect(old_errors.length() > 0, content="true")

  let cursor = make_reuse_cursor(old_tree, 99, 99, tokens, source)
  let (_, errors, reuse_count) = parse_cst_recover_with_tokens(
    source,
    tokens,
    Some(cursor),
    prev_diagnostics=Some(old_errors),
  )
  inspect(reuse_count > 0, content="true")
  inspect(errors.length(), content=old_errors.length().to_string())
  inspect(errors.items()[0].message, content=old_errors.items()[0].message)
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
  let cursor = make_reuse_cursor(old_tree, 10, 11, new_tokens, new_source)
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
