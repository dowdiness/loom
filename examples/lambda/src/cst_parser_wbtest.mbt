///|
test "panic finish_node without matching start_node" {
  let ctx = @core.ParserContext::new([], "", lambda_spec)
  ctx.finish_node()
}

///|
test "parse_cst: raises with offending token, not EOF" {
  // Regression guard: parse_cst must preserve the offending token in
  // ParseError. "λ.x" is missing a parameter; the Dot at offset 1 is the
  // offending token.
  let _ = parse_cst("λ.x") catch {
    ParseError(_, token) => {
      inspect(token == @token.EOF, content="false")
      inspect(token == @token.Dot, content="true")
      return
    }
    _ => {
      // Any error other than ParseError is a test failure
      inspect(false, content="true")
      return
    }
  }
  // Only reached if parse_cst didn't raise — should not happen
  inspect(false, content="true")
}

///|
test "reuse fires: VarRef unchanged after identifier edit" {
  // Old: "x + y"  →  New: "z + y"  (damage [0,1): only "x" changed)
  // VarRef("y") at [3,5) is outside damage and text is unchanged → reused.
  // reuse_count > 0 confirms the cursor path is live, not a stub.
  let old_source = "x + y"
  let (old_tree, _) = parse_cst_recover(old_source)
  let new_source = "z + y"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 0, 1, new_tokens)
  let (new_tree, errors, reuse_count) = parse_cst_with_cursor(
    new_source, new_tokens, cursor,
  )
  let (full_tree, _) = parse_cst_recover(new_source)
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
  let (old_tree, _) = parse_cst_recover(old_source)
  let new_source = "λz.y"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 2, 3, new_tokens)
  let (new_tree, errors, reuse_count) = parse_cst_with_cursor(
    new_source, new_tokens, cursor,
  )
  let (full_tree, _) = parse_cst_recover(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
  inspect(reuse_count > 0, content="true")
}

///|
test "parse_cst_with_cursor: identifier boundary merge matches full reparse" {
  // Old: "x y" -> New: "xy" (space deleted at [1,2) in old source).
  // Reuse must not produce a stale split; result must match full reparse.
  let old_source = "x y"
  let (old_tree, _) = parse_cst_recover(old_source)
  let new_source = "xy"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 1, 2, new_tokens)
  let (new_tree, errors, _reuse_count) = parse_cst_with_cursor(
    new_source, new_tokens, cursor,
  )
  let (full_tree, _) = parse_cst_recover(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
}

///|
test "parse_cst_with_cursor: integer boundary merge matches full reparse" {
  // Old: "1 2" -> New: "12" (space deleted at [1,2) in old source).
  // Reuse must not keep two stale IntLiteral nodes.
  let old_source = "1 2"
  let (old_tree, _) = parse_cst_recover(old_source)
  let new_source = "12"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 1, 2, new_tokens)
  let (new_tree, errors, _reuse_count) = parse_cst_with_cursor(
    new_source, new_tokens, cursor,
  )
  let (full_tree, _) = parse_cst_recover(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
}

///|
test "parse_cst_with_cursor: preserves prior diagnostic messages on reused invalid subtree" {
  let source = "λ.x"
  let tokens = @lexer.tokenize(source)
  let (old_tree, old_errors) = parse_cst_recover(source)
  inspect(old_errors.length(), content="1")
  inspect(old_errors[0].message, content="Expected parameter after λ")

  let cursor = make_reuse_cursor(old_tree, 99, 99, tokens)
  let (_, errors, reuse_count) = parse_cst_with_cursor(
    source,
    tokens,
    cursor,
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
  let (old_tree, old_errors) = parse_cst_recover(source)
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
test "reuse fires: let init IntLiteral reused after body edit" {
  // Old: "let x = 1 in y"  →  New: "let x = 1 in z"  (damage [13,14))
  // IntLiteral(1) at [8,9) is outside damage and text is unchanged.
  // Its TRAILING context token is InKeyword("in").  Without InKeyword
  // in syntax_kind_to_token_kind, trailing_context_matches returns false
  // and IntLiteral(1) is never reused — a regression on every let-body edit.
  let old_source = "let x = 1 in y"
  let (old_tree, _) = parse_cst_recover(old_source)
  let new_source = "let x = 1 in z"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 13, 14, new_tokens)
  let (new_tree, errors, reuse_count) = parse_cst_with_cursor(
    new_source, new_tokens, cursor,
  )
  let (full_tree, _) = parse_cst_recover(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
  inspect(reuse_count > 0, content="true")
}
