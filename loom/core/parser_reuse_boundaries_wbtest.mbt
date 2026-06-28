///|
test "ParserContext reuse: zero-width error leaf does not over-advance position" {
  fn grammar_with_placeholder(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_error_placeholder()
    })
    ctx.emit_token(KNum)
  }

  let src = "1 2"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_with_placeholder,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    // Must not run on reuse hit.
    ctx.emit_token(KNum)
    ctx.emit_error_placeholder()
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.at(TestTok::Num(2)), content="true")
}

///|
fn test_tokenize_with_zero_width_boundary(
  _src : String,
) -> Array[TokenInfo[TestTok]] {
  [
    TokenInfo::new(TestTok::Num(1), 1),
    TokenInfo::new(TestTok::Plus, 0),
    TokenInfo::new(TestTok::Ws, 1),
    TokenInfo::new(TestTok::Num(2), 1),
  ]
}

///|
fn test_tokenize_with_two_zero_width_boundaries(
  _src : String,
) -> Array[TokenInfo[TestTok]] {
  [
    TokenInfo::new(TestTok::Num(1), 1),
    TokenInfo::new(TestTok::Plus, 0),
    TokenInfo::new(TestTok::Plus, 0),
    TokenInfo::new(TestTok::Ws, 1),
    TokenInfo::new(TestTok::Num(2), 1),
  ]
}

///|
fn test_tokenize_numbers_with_zero_width_boundaries(
  src : String,
  boundary_count : Int,
) -> Array[TokenInfo[TestTok]] {
  let result : Array[TokenInfo[TestTok]] = []
  let mut i = 0
  while i < src.length() {
    let code = src.code_unit_at(i).to_int()
    if code == 32 {
      result.push(TokenInfo::new(TestTok::Ws, 1))
      i = i + 1
    } else if code >= 48 && code <= 57 {
      result.push(TokenInfo::new(TestTok::Num(code - 48), 1))
      for _ in 0..<boundary_count {
        result.push(TokenInfo::new(TestTok::Plus, 0))
      }
      i = i + 1
    } else {
      i = i + 1
    }
  }
  result
}

///|
fn test_tokenize_numbers_with_one_zero_width_boundary(
  src : String,
) -> Array[TokenInfo[TestTok]] {
  test_tokenize_numbers_with_zero_width_boundaries(src, 1)
}

///|
fn test_tokenize_numbers_with_two_zero_width_boundaries(
  src : String,
) -> Array[TokenInfo[TestTok]] {
  test_tokenize_numbers_with_zero_width_boundaries(src, 2)
}

///|
test "ParserContext reuse: zero-width lexer leaf at reused boundary advances position" {
  fn grammar_with_zero_width_boundary(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
    })
    ctx.emit_token(KNum)
  }

  let src = "1 2"
  let toks = test_tokenize_with_zero_width_boundary(src)
  let starts = build_starts(toks)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize_with_zero_width_boundary, grammar_with_zero_width_boundary,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    // Must not run on reuse hit.
    ctx.emit_token(KNum)
    ctx.emit_token(KPlus)
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.position, content="2")
  inspect(ctx.at(TestTok::Num(2)), content="true")
}

///|
test "ParserContext reuse: interned zero-width lexer boundary advances position" {
  fn grammar_with_zero_width_boundary(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
    })
    ctx.emit_token(KNum)
  }

  let src = "1 2"
  let toks = test_tokenize_with_zero_width_boundary(src)
  let starts = build_starts(toks)
  let old_ctx = ParserContext::new(toks, src, test_spec)
  grammar_with_zero_width_boundary(old_ctx)
  old_ctx.flush_trivia()
  let old_tree = old_ctx.events.build_tree_interned(
    test_spec.root_kind.to_raw(),
    @seam.Interner::new(),
    trivia_kinds=Some([test_spec.whitespace_kind.to_raw()]),
    error_kind=Some(test_spec.error_kind.to_raw()),
    incomplete_kind=Some(test_spec.incomplete_kind.to_raw()),
  ) catch {
    _ => abort("expected interned old tree")
  }
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    // Must not run on reuse hit.
    ctx.emit_token(KNum)
    ctx.emit_token(KPlus)
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.position, content="2")
  inspect(ctx.at(TestTok::Num(2)), content="true")
}

///|
test "ParserContext reuse: custom synthetic zero-width leaf is not a lexer boundary token" {
  fn grammar_with_custom_placeholder(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_zero_width(KPlus)
    })
    ctx.emit_token(KNum)
  }

  let src = "1 2"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_with_custom_placeholder,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    // Must not run on reuse hit.
    ctx.emit_token(KNum)
    ctx.emit_zero_width(KPlus)
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.position, content="1")
  inspect(ctx.at(TestTok::Num(2)), content="true")
}

///|
test "ParserContext reuse: custom synthetic zero-width leaf does not consume lexer token" {
  fn grammar_with_custom_placeholder(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_zero_width(KPlus)
    })
    ctx.emit_token(KPlus)
    ctx.emit_token(KNum)
  }

  let src = "1 2"
  let toks = test_tokenize_with_zero_width_boundary(src)
  let starts = build_starts(toks)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize_with_zero_width_boundary, grammar_with_custom_placeholder,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    // Must not run on reuse hit.
    ctx.emit_token(KNum)
    ctx.emit_zero_width(KPlus)
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.position, content="1")
  inspect(ctx.at(TestTok::Plus), content="true")
}

///|
test "ParserContext reuse: EOF recovery token is synthetic lexer context" {
  fn grammar_with_eof_recovery(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
    })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_with_eof_recovery,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    // Must not run on reuse hit.
    ctx.emit_token(KNum)
    ctx.emit_token(KPlus)
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.position, content="1")
  inspect(ctx.at_eof(), content="true")
}

///|
test "ParserContext reuse: extra zero-width token after empty owned boundary rejects reuse" {
  fn grammar_with_conditional_boundary_token(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      if ctx.at(TestTok::Plus) && ctx.peek_nth(1) == TestTok::Plus {
        ctx.emit_token(KPlus)
      }
    })
    ctx.emit_token(KPlus)
    ctx.emit_token(KNum)
  }

  let src = "1 2"
  let toks = test_tokenize_with_two_zero_width_boundaries(src)
  let starts = build_starts(toks)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize_with_zero_width_boundary, grammar_with_conditional_boundary_token,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    ctx.emit_token(KNum)
    if ctx.at(TestTok::Plus) && ctx.peek_nth(1) == TestTok::Plus {
      ctx.emit_token(KPlus)
    }
  })
  inspect(ctx.reuse_count, content="0")
  inspect(ctx.position, content="2")
  inspect(ctx.at(TestTok::Plus), content="true")
}

///|
test "ParserContext reuse: partial zero-width boundary match rejects reuse" {
  fn old_grammar_with_two_boundary_tokens(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
      ctx.emit_token(KPlus)
    })
    ctx.emit_token(KNum)
  }

  let src = "1 2"
  let toks = test_tokenize_with_zero_width_boundary(src)
  let starts = build_starts(toks)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize_with_two_zero_width_boundaries, old_grammar_with_two_boundary_tokens,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    ctx.emit_token(KNum)
    ctx.emit_token(KPlus)
  })
  inspect(ctx.reuse_count, content="0")
  inspect(ctx.position, content="2")
  inspect(ctx.at(TestTok::Num(2)), content="true")
}

///|
test "ParserContext reuse: extra zero-width boundary token rejects reuse" {
  fn grammar_consumes_boundary_tokens(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      while ctx.at(TestTok::Plus) {
        ctx.emit_token(KPlus)
      }
    })
    ctx.emit_token(KNum)
  }

  let src = "1 2"
  let toks = test_tokenize_with_two_zero_width_boundaries(src)
  let starts = build_starts(toks)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize_with_zero_width_boundary, grammar_consumes_boundary_tokens,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    ctx.emit_token(KNum)
    while ctx.at(TestTok::Plus) {
      ctx.emit_token(KPlus)
    }
  })
  inspect(ctx.reuse_count, content="0")
  inspect(ctx.position, content="3")
  inspect(ctx.at(TestTok::Num(2)), content="true")
}

///|
test "ParserContext reuse: partial zero-width RepeatGroup boundary match rejects reuse" {
  fn grammar_repeated_boundary_nodes(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    while !ctx.at_eof() {
      ctx.node(KExpr, fn() {
        ctx.emit_token(KNum)
        while ctx.at(TestTok::Plus) {
          ctx.emit_token(KPlus)
        }
      })
    }
  }

  let src = "1 1 1 1 1 1 1 1 1"
  let toks = test_tokenize_numbers_with_one_zero_width_boundary(src)
  let starts = build_starts(toks)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize_numbers_with_two_zero_width_boundaries, grammar_repeated_boundary_nodes,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  inspect(ctx.try_reuse_repeat_group(), content="false")
  inspect(ctx.reuse_count, content="0")
  inspect(ctx.position, content="0")
}

///|
test "ParserContext reuse: extra zero-width RepeatGroup boundary token rejects reuse" {
  fn grammar_repeated_boundary_nodes(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    while !ctx.at_eof() {
      ctx.node(KExpr, fn() {
        ctx.emit_token(KNum)
        while ctx.at(TestTok::Plus) {
          ctx.emit_token(KPlus)
        }
      })
    }
  }

  let src = "1 1 1 1 1 1 1 1 1"
  let toks = test_tokenize_numbers_with_two_zero_width_boundaries(src)
  let starts = build_starts(toks)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize_numbers_with_one_zero_width_boundary, grammar_repeated_boundary_nodes,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  inspect(ctx.try_reuse_repeat_group(), content="false")
  inspect(ctx.reuse_count, content="0")
  inspect(ctx.position, content="0")
}

///|
test "ParserContext reuse: zero-width lexer leaf owned by following subtree is not consumed" {
  fn grammar_with_following_boundary_token(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
    ctx.emit_token(KPlus)
    ctx.emit_token(KNum)
  }

  let src = "1 2"
  let toks = test_tokenize_with_zero_width_boundary(src)
  let starts = build_starts(toks)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize_with_zero_width_boundary, grammar_with_following_boundary_token,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    // Must not run on reuse hit.
    ctx.emit_token(KNum)
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.position, content="1")
  inspect(ctx.at(TestTok::Plus), content="true")
}

///|
test "ParserContext reuse: replays prior diagnostics for reused error subtree" {
  fn grammar_with_error(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
      ctx.error("expected number after +")
      ctx.emit_error_placeholder()
    })
  }

  let src = "1 +"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, old_errors) = parse_with(
    src, test_spec, test_tokenize, grammar_with_error,
  )
  inspect(old_errors.length(), content="1")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_errors)
  ctx.node(KExpr, fn() {
    ctx.emit_token(KNum)
    ctx.emit_token(KPlus)
    ctx.error("expected number after +")
    ctx.emit_error_placeholder()
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(ctx.diagnostics.items()[0].message, content="expected number after +")
  inspect(diagnostic_start(ctx.diagnostics.items()[0]), content="3")
  inspect(diagnostic_end(ctx.diagnostics.items()[0]), content="3")
}

///|
test "ParserContext reuse: synthesizes diagnostics when prior list is unavailable" {
  fn grammar_with_error(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
      ctx.error("expected number after +")
      ctx.emit_error_placeholder()
    })
  }

  let src = "1 +"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_with_error,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.node(KExpr, fn() {
    ctx.emit_token(KNum)
    ctx.emit_token(KPlus)
    ctx.error("expected number after +")
    ctx.emit_error_placeholder()
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(ctx.diagnostics.items()[0].message, content="reused syntax error")
  inspect(diagnostic_start(ctx.diagnostics.items()[0]), content="3")
  inspect(diagnostic_end(ctx.diagnostics.items()[0]), content="3")
}

///|
test "ParserContext reuse: synthesizes diagnostics for incomplete-kind node" {
  fn grammar_with_incomplete_node(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.error("expected Plus, got TokEof")
      // Grammar models incompleteness as a node, not a token.
      ctx.node(KIncomplete, fn() { () })
    })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_with_incomplete_node,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  // Intentionally omit set_reuse_diagnostics(...): force synthesis path.
  grammar_with_incomplete_node(ctx)
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(ctx.diagnostics.items()[0].message, content="reused syntax error")
  inspect(diagnostic_start(ctx.diagnostics.items()[0]), content="1")
  inspect(diagnostic_end(ctx.diagnostics.items()[0]), content="1")
}

///|
test "ParserContext reuse: excludes boundary diagnostics at reused node end" {
  fn grammar_two_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  }

  let src = "1 2"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_two_nodes,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let old_diags = DiagnosticSet::empty()
  old_diags.push(
    test_parser_diagnostic("inside-first-node", 0, 1, TestTok::Num(1)),
  )
  old_diags.push(
    test_parser_diagnostic("boundary-next-sibling", 1, 1, TestTok::Ws),
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_diags)
  ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(ctx.diagnostics.items()[0].message, content="inside-first-node")
}

///|
test "ParserContext reuse: preserves EOF ctx.error without placeholder" {
  fn grammar_eof_error_no_placeholder(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      // EOF diagnostic without an error placeholder leaf.
      ctx.error("expected trailing token")
    })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, old_errors) = parse_with(
    src, test_spec, test_tokenize, grammar_eof_error_no_placeholder,
  )
  inspect(old_errors.length(), content="1")
  inspect(diagnostic_start(old_errors.items()[0]), content="1")
  inspect(diagnostic_end(old_errors.items()[0]), content="1")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_errors)
  grammar_eof_error_no_placeholder(ctx)
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(ctx.diagnostics.items()[0].message, content="expected trailing token")
  inspect(diagnostic_start(ctx.diagnostics.items()[0]), content="1")
  inspect(diagnostic_end(ctx.diagnostics.items()[0]), content="1")
}

///|
test "ParserContext reuse: does not duplicate EOF boundary diagnostics from later sibling" {
  fn grammar_with_trailing_eof_error(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
    // Zero-width sibling at EOF that owns this diagnostic.
    ctx.node(KExpr, fn() {
      ctx.error("missing trailing expression")
      ctx.emit_error_placeholder()
    })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, old_errors) = parse_with(
    src, test_spec, test_tokenize, grammar_with_trailing_eof_error,
  )
  inspect(old_errors.length(), content="1")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )

  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_errors)
  // First node should reuse; second node is at EOF and executes body.
  grammar_with_trailing_eof_error(ctx)

  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(
    ctx.diagnostics.items()[0].message,
    content="missing trailing expression",
  )
  inspect(diagnostic_start(ctx.diagnostics.items()[0]), content="1")
  inspect(diagnostic_end(ctx.diagnostics.items()[0]), content="1")
}

///|
test "ParserContext reuse: incomplete-kind sibling owns EOF boundary diagnostic" {
  fn grammar_with_incomplete_sibling(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
    ctx.node(KExpr, fn() {
      ctx.error("missing trailing expression")
      // Zero-width incomplete node; no incomplete token leaf.
      ctx.node(KIncomplete, fn() { () })
    })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, old_errors) = parse_with(
    src, test_spec, test_tokenize, grammar_with_incomplete_sibling,
  )
  inspect(old_errors.length(), content="1")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_errors)
  // First node must not claim sibling-owned boundary error.
  ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="0")
  // Second node executes at EOF and emits its own diagnostic.
  ctx.node(KExpr, fn() {
    ctx.error("missing trailing expression")
    ctx.node(KIncomplete, fn() { () })
  })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(
    ctx.diagnostics.items()[0].message,
    content="missing trailing expression",
  )
  inspect(diagnostic_start(ctx.diagnostics.items()[0]), content="1")
  inspect(diagnostic_end(ctx.diagnostics.items()[0]), content="1")
}

///|
test "ParserContext reuse: later EOF emission replaces replayed stale got_token" {
  fn grammar_with_trailing_eof_error(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
    ctx.node(KExpr, fn() {
      ctx.error("missing trailing expression")
      ctx.emit_error_placeholder()
    })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_with_trailing_eof_error,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  // Simulate replayed stale token evidence for the same logical diagnostic.
  let stale_diags = DiagnosticSet::single(
    test_parser_diagnostic("missing trailing expression", 1, 1, TestTok::Ws),
  )

  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(stale_diags)
  grammar_with_trailing_eof_error(ctx)

  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(
    ctx.diagnostics.items()[0].message,
    content="missing trailing expression",
  )
  inspect(diagnostic_token_raw(ctx.diagnostics.items()[0]), content="7")
}

///|
test "ParserContext push_diagnostic_unique deduplicates by parser message and span" {
  let src = "1"
  let (toks, _starts) = test_tokenize_with_starts(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  let added = ctx.push_diagnostic_unique(
    test_parser_diagnostic("same logical error", 1, 1, TestTok::Ws),
  )
  let updated = ctx.push_diagnostic_unique(
    test_parser_diagnostic("same logical error", 1, 1, TestTok::TokEof),
  )
  inspect(added, content="true")
  inspect(updated, content="false")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(diagnostic_token_raw(ctx.diagnostics.items()[0]), content="7")
  inspect(ctx.too_many_errors(1), content="true")
}

///|
test "ReuseCursor::try_reuse: post-damage node is not reused when source shrinks" {
  fn grammar_two_numbers(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected first number")
      }
    })
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected second number")
      }
    })
  }

  let old_src = "123 4"
  let new_src = "1 4"
  let (old_tree, _) = parse_with(
    old_src, test_spec, test_tokenize, grammar_two_numbers,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0, // old damage start (replace "123")
    3, // old damage end
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_src.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_toks[i].len,
      )
    },
    test_spec,
  )
  // Second KExpr node starts at old offset 3 (space+Num(4), trivia folded in).
  // In the new source it would sit at offset 2 (space+Num(4) after "1 ").
  // seek_node_at(2, KExpr) finds nothing in the old tree → reuse correctly fails.
  let result = cursor.try_reuse(test_kind_raw(KExpr), 2, 2)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse: post-damage node is not reused when source grows" {
  fn grammar_two_numbers(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected first number")
      }
    })
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected second number")
      }
    })
  }

  let old_src = "1 4"
  let new_src = "123 4"
  let (old_tree, _) = parse_with(
    old_src, test_spec, test_tokenize, grammar_two_numbers,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0, // old damage start (replace "1")
    1, // old damage end
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_src.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_toks[i].len,
      )
    },
    test_spec,
  )
  // Second KExpr node starts at old offset 1 (space+Num(4), trivia folded in).
  // In the new source it would sit at offset 4 (space+Num(4) after "123 ").
  // seek_node_at(4, KExpr) finds nothing in the old tree → reuse correctly fails.
  let result = cursor.try_reuse(test_kind_raw(KExpr), 4, 2)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse: reuses multiple undamaged post-damage nodes" {
  fn grammar_four_numbers(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected first number")
      }
    })
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected second number")
      }
    })
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected third number")
      }
    })
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected fourth number")
      }
    })
  }

  let old_src = "1 2 3 4"
  let new_src = "9 2 3 4"
  let (old_tree, _) = parse_with(
    old_src, test_spec, test_tokenize, grammar_four_numbers,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0, // first number changed from 1 -> 9
    1,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_src.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_toks[i].len,
      )
    },
    test_spec,
  )
  // Second KExpr starts at offset 1 (space+Num(2)); token_pos=2 is the index of
  // Num(2) in new_toks (indices 0=Num(9), 1=space, 2=Num(2), …).
  // Third KExpr starts at offset 3 (space+Num(3)); token_pos=4 is Num(3).
  // Both nodes are outside damage [0,1) and unchanged → both reused.
  let second = cursor.try_reuse(test_kind_raw(KExpr), 1, 2)
  match second {
    Some(n) => cursor.advance_past(n)
    None => ()
  }
  let third = cursor.try_reuse(test_kind_raw(KExpr), 3, 4)
  inspect(second is Some(_), content="true")
  inspect(third is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse: rejects integer boundary merge by follow-token check" {
  fn grammar_two_numbers(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected first number")
      }
    })
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected second number")
      }
    })
  }

  let old_src = "12 34"
  let new_src = "12 3"
  let (old_tree, _) = parse_with(
    old_src, test_spec, test_tokenize, grammar_two_numbers,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    3, // old second token span [3,5) changed from 34 -> 3
    5,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_src.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_toks[i].len,
      )
    },
    test_spec,
  )
  // Leading token matches (12), but follow token changed (34 -> 3), so reuse
  // must be rejected by trailing_context_matches.
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is None, content="true")
}

///|
test "ParserContext reuse: replays diagnostics for incomplete subtree at EOF" {
  fn grammar_incomplete_at_eof(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      // Simulate expect() at EOF: diagnostic + incomplete placeholder
      ctx.error("expected Plus, got TokEof")
      ctx.emit_incomplete_placeholder()
    })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, old_errors) = parse_with(
    src, test_spec, test_tokenize, grammar_incomplete_at_eof,
  )
  inspect(old_errors.length(), content="1")

  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99, // no damage — force reuse
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_errors)
  grammar_incomplete_at_eof(ctx)
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  inspect(
    ctx.diagnostics.items()[0].message,
    content="expected Plus, got TokEof",
  )
}

///|
test "ParserContext reuse: replays structured diagnostic code and token evidence" {
  fn grammar_structured_eof(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.report_at_current(
        message="missing plus",
        code=Some(DiagnosticCode("parse.expected.plus")),
      )
      ctx.emit_incomplete_placeholder()
    })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, old_errors) = parse_with(
    src, test_spec, test_tokenize, grammar_structured_eof,
  )
  inspect(old_errors.length(), content="1")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_errors)
  grammar_structured_eof(ctx)

  inspect(ctx.reuse_count, content="1")
  inspect(ctx.diagnostics.length(), content="1")
  let diagnostic = ctx.diagnostics.items()[0]
  inspect(diagnostic.message, content="missing plus")
  inspect(diagnostic_code_value(diagnostic), content="parse.expected.plus")
  inspect(diagnostic_start(diagnostic), content="1")
  inspect(diagnostic_end(diagnostic), content="1")
  inspect(diagnostic_token_raw(diagnostic), content="7")
}

///|
test "ParserContext reuse: incomplete node followed by reusable sibling" {
  fn grammar_two_nodes_incomplete(
    ctx : ParserContext[TestTok, TestKind],
  ) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_incomplete_placeholder()
    })
    ctx.node(KExpr, fn() {
      match ctx.peek() {
        Num(_) => ctx.emit_token(KNum)
        _ => ()
      }
    })
  }

  let src = "1 2"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_two_nodes_incomplete,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  // First node has incomplete → reused
  ctx.node(KExpr, fn() {
    ctx.emit_token(KNum)
    ctx.emit_incomplete_placeholder()
  })
  inspect(ctx.reuse_count, content="1")
  // Second node → also reused
  ctx.node(KExpr, fn() {
    match ctx.peek() {
      Num(_) => ctx.emit_token(KNum)
      _ => ()
    }
  })
  inspect(ctx.reuse_count, content="2")
}
