///|
test "emit_token: at EOF emits zero-width token and diagnostic instead of abort" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  ctx.finish_node()
  inspect(ctx.diagnostics.length(), content="1")
  inspect(ctx.diagnostics.items()[0].message.contains("EOF"), content="true")
}

///|
test "emit_token: at EOF after consuming all tokens emits diagnostic" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  ctx.emit_token(KPlus)
  ctx.finish_node()
  inspect(ctx.diagnostics.length(), content="1")
  inspect(ctx.at_eof(), content="true")
}

///|
test "finish_node: unbalanced close does not abort" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.finish_node()
  inspect(ctx.open_nodes, content="0")
}

///|
test "finish_node: double close does not abort" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  ctx.finish_node()
  ctx.finish_node()
  inspect(ctx.open_nodes, content="0")
}

///|
test "parse_with: unclosed node is auto-closed with diagnostic" {
  let (tree, errors) = parse_with("1", test_spec, test_tokenize, fn(ctx) {
    ctx.start_node(KExpr)
    ctx.emit_token(KNum)
  })
  inspect(tree.text_len, content="1")
  let has_unclosed = errors
    .items()
    .iter()
    .any(fn(e) { e.message.contains("unclosed") })
  inspect(has_unclosed, content="true")
}

///|
test "parse_tokens_indexed: unclosed node is auto-closed with diagnostic" {
  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let spec = LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    parse_root=fn(ctx) {
      ctx.start_node(KExpr)
      ctx.emit_token(KNum)
    },
  )
  let (_, errors, _) = parse_tokens_indexed(
    src,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) { starts[i] + toks[i].len },
    spec,
  )
  let has_unclosed = errors
    .items()
    .iter()
    .any(fn(e) { e.message.contains("unclosed") })
  inspect(has_unclosed, content="true")
}

///|
test "reparse_block offsets new structured diagnostics and drops stale block diagnostics" {
  fn emit_num_or_error(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    match ctx.peek() {
      Num(_) => ctx.emit_token(KNum)
      _ => {
        ctx.report_expected(
          expected="number",
          code=Some(DiagnosticCode("parse.expected.number")),
        )
        ctx.emit_error_placeholder()
      }
    }
  }

  fn emit_plus_or_error(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    if ctx.at(Plus) {
      ctx.emit_token(KPlus)
    } else {
      ctx.report_expected(
        expected="Plus",
        code=Some(DiagnosticCode("parse.expected.plus")),
      )
      ctx.emit_error_placeholder()
    }
  }

  fn parse_expr(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      emit_num_or_error(ctx)
      emit_plus_or_error(ctx)
      emit_num_or_error(ctx)
    })
  }

  fn grammar(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() { emit_num_or_error(ctx) })
    parse_expr(ctx)
  }

  let old_src = "0 1 + 2"
  let new_src = "0 1    2"
  let (old_tree, _) = parse_with(old_src, test_spec, test_tokenize, grammar)
  let old_syntax = @seam.SyntaxNode::from_cst(old_tree)
  let old_diagnostics = DiagnosticSet::empty()
  old_diagnostics.push(
    test_parser_diagnostic("before old block", 0, 1, TestTok::Num(0)),
  )
  old_diagnostics.push(
    test_parser_diagnostic("inside old block", 2, 3, TestTok::Num(1)),
  )
  old_diagnostics.push(
    test_parser_diagnostic("after old block", 7, 7, TestTok::TokEof),
  )
  let block_spec : BlockReparseSpec[TestTok, TestKind] = {
    is_reparseable: kind => kind == test_kind_raw(KExpr),
    get_reparser: fn(node, _, _) {
      if node.kind() == test_kind_raw(KExpr) {
        Some(parse_expr)
      } else {
        None
      }
    },
    is_balanced: _ => true,
  }
  let lex = fn(source : String) -> LexResult[TestTok] {
    let (tokens, starts) = test_tokenize_with_starts(source)
    LexResult::with_starts(tokens, starts, diagnostics=DiagnosticSet::empty())
  }
  let result = reparse_block(
    old_syntax,
    new_src,
    Edit::new(4, 1, 2),
    lex,
    test_spec,
    block_spec,
    old_diagnostics,
  )
  let diagnostics = match result {
    Some((_, diagnostics)) => diagnostics
    None => abort("expected block reparse result")
  }

  inspect(
    has_diagnostic_message(diagnostics, "before old block"),
    content="true",
  )
  inspect(
    has_diagnostic_message(diagnostics, "inside old block"),
    content="false",
  )
  let after = find_diagnostic_by_message(diagnostics, "after old block")
  inspect(diagnostic_start(after), content="8")
  inspect(diagnostic_end(after), content="8")
  inspect(diagnostic_token_start(after), content="8")
  inspect(diagnostic_token_end(after), content="8")

  let expected = find_diagnostic_by_message(diagnostics, "expected Plus")
  inspect(diagnostic_code_value(expected), content="parse.expected.plus")
  inspect(diagnostic_start(expected), content="7")
  inspect(diagnostic_end(expected), content="8")
  inspect(diagnostic_token_raw(expected), content="0")
  inspect(diagnostic_token_start(expected), content="7")
  inspect(diagnostic_token_end(expected), content="8")
}

///|
test "peek_nth: 0 equals peek" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.peek_nth(0) == ctx.peek(), content="true")
}

///|
test "peek_nth: returns second non-trivia token" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.peek_nth(0), content="Num(1)")
  inspect(ctx.peek_nth(1), content="Plus")
  inspect(ctx.peek_nth(2), content="Num(2)")
}

///|
test "peek_nth: past end returns eof" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.peek_nth(5), content="TokEof")
}

///|
test "peek_nth: skips trivia between tokens" {
  let src = "1   +   2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.peek_nth(0), content="Num(1)")
  inspect(ctx.peek_nth(1), content="Plus")
  inspect(ctx.peek_nth(2), content="Num(2)")
}

///|
test "checkpoint/restore: rewinds position and events" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let cp = ctx.checkpoint()
  ctx.emit_token(KNum)
  inspect(ctx.position > 0, content="true")
  inspect(ctx.events.length() > 0, content="true")
  ctx.restore(cp)
  inspect(ctx.position, content="0")
  inspect(ctx.peek(), content="Num(1)")
  inspect(ctx.events.length(), content="1")
  ctx.finish_node()
}

///|
test "checkpoint/restore: removes diagnostics added after checkpoint" {
  let src = "+"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let cp = ctx.checkpoint()
  ctx.error("speculative error")
  inspect(ctx.diagnostics.length(), content="1")
  ctx.restore(cp)
  inspect(ctx.diagnostics.length(), content="0")
  ctx.finish_node()
}

///|
test "lookahead: rewinds position, events, and diagnostics" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let result = ctx.lookahead(() => {
    ctx.emit_token(KNum)
    ctx.error("lookahead error")
    ctx.at_eof()
  })
  inspect(result, content="false")
  inspect(ctx.position, content="0")
  inspect(ctx.peek(), content="Num(1)")
  inspect(ctx.events.length(), content="1")
  inspect(ctx.diagnostics.length(), content="0")
  ctx.finish_node()
}

///|
test "checkpoint/restore: speculative parse picks successful branch" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let cp = ctx.checkpoint()
  ctx.emit_token(KNum)
  let branch_a_ok = ctx.at_eof()
  if !branch_a_ok {
    ctx.restore(cp)
  }
  if !branch_a_ok {
    test_grammar(ctx)
  }
  ctx.finish_node()
  inspect(ctx.diagnostics.length(), content="0")
  inspect(ctx.at_eof(), content="true")
}

///|
test "emit_token: EOF placeholder is emitted after trailing trivia" {
  let (tree, _) = parse_with("   ", test_spec, test_tokenize, fn(ctx) {
    ctx.emit_token(KNum)
  })
  inspect(tree.children.length(), content="2")
  match tree.children[0] {
    @seam.CstElement::Token(t) =>
      inspect(t.kind == test_kind_raw(KWs), content="true")
    _ => inspect(false, content="true")
  }
  match tree.children[1] {
    @seam.CstElement::Token(t) => {
      inspect(t.kind == test_kind_raw(KNum), content="true")
      inspect(t.text_len(), content="0")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "checkpoint/restore: restores reuse cursor and reuse_count" {
  fn grammar_one_expr(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_one_expr,
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
  let cp = ctx.checkpoint()

  ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  inspect(ctx.reuse_count, content="1")

  ctx.restore(cp)
  inspect(ctx.reuse_count, content="0")
  inspect(ctx.position, content="0")

  ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.at_eof(), content="true")
}

///|
test "lookahead: restores reuse cursor and reuse count" {
  fn grammar_one_expr(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  }

  let src = "1"
  let (toks, starts) = test_tokenize_with_starts(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_one_expr,
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
  let reused = ctx.lookahead(() => {
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
    ctx.reuse_count
  })
  inspect(reused, content="1")
  inspect(ctx.reuse_count, content="0")
  inspect(ctx.position, content="0")

  ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.at_eof(), content="true")
}

// ─── at_adjacent ──────────────────────────────────────────────────────────────

///|
test "at_adjacent: true when next token is contiguous with consumed prefix" {
  let src = "1+ 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  inspect(ctx.at_adjacent(TestTok::Plus), content="true")
  ctx.finish_node()
}

///|
test "at_adjacent: false when trivia separates next token" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  // Trivia-insensitive at() still sees the Plus, but adjacency is broken.
  inspect(ctx.at(TestTok::Plus), content="true")
  inspect(ctx.at_adjacent(TestTok::Plus), content="false")
  ctx.finish_node()
}

///|
test "at_adjacent: false when next token differs even if contiguous" {
  let src = "1+2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  inspect(ctx.at_adjacent(TestTok::Num(2)), content="false")
  ctx.finish_node()
}

///|
test "at_adjacent: false at EOF" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  inspect(ctx.at_adjacent(TestTok::Plus), content="false")
  ctx.finish_node()
}

///|
test "at_adjacent: start of input counts as adjacent" {
  let src = "+1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.at_adjacent(TestTok::Plus), content="true")
}

///|
test "at_adjacent: leading trivia at start of input breaks adjacency" {
  let src = " +1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.at_adjacent(TestTok::Plus), content="false")
}

///|
test "at_adjacent: false across unrepresented source gap (located tokens)" {
  // Simulates LexResult::from_located_tokens without gap_token: blank gaps
  // are skipped, so "1 +" lexes to [Num@[0,1), Plus@[2,3)] with no Ws token.
  let src = "1 +"
  let toks = [TestTok::Num(1), TestTok::Plus]
  let starts = [0, 2]
  let ends = [1, 3]
  let ctx : ParserContext[TestTok, TestKind] = ParserContext::new_indexed(
    2,
    i => toks[i],
    i => starts[i],
    i => ends[i],
    src,
    test_spec,
  )
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  inspect(ctx.at_adjacent(TestTok::Plus), content="false")
  ctx.finish_node()
}

///|
test "at_adjacent: false on leading unrepresented gap at start of input" {
  let src = " +"
  let toks = [TestTok::Plus]
  let ctx : ParserContext[TestTok, TestKind] = ParserContext::new_indexed(
    1,
    i => toks[i],
    _ => 1,
    _ => 2,
    src,
    test_spec,
  )
  inspect(ctx.at_adjacent(TestTok::Plus), content="false")
}

///|
test "at_adjacent: flushed trivia still breaks adjacency" {
  // A grammar or recovery path may call the public flush_trivia() before
  // the whitespace-sensitive check; the emitted trivia must still count
  // as separation.
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  ctx.flush_trivia()
  inspect(ctx.at_adjacent(TestTok::Plus), content="false")
  ctx.finish_node()
}

///|
test "at_adjacent: flush_trivia with no trivia keeps adjacency" {
  let src = "1+ 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  ctx.flush_trivia()
  inspect(ctx.at_adjacent(TestTok::Plus), content="true")
  ctx.finish_node()
}

///|
test "at_adjacent: flushed zero-width trivia still breaks adjacency" {
  // from_located_tokens preserves zero-width tokens, so a grammar can have
  // a virtual/zero-length trivia separator. Offsets agree across it
  // (B.start == A.end), so only the token stream reveals the separation —
  // and flush_trivia must not change at_adjacent's answer.
  let src = "1+"
  let toks = [TestTok::Num(1), TestTok::Ws, TestTok::Plus]
  let starts = [0, 1, 1]
  let ends = [1, 1, 2]
  let ctx : ParserContext[TestTok, TestKind] = ParserContext::new_indexed(
    3,
    i => toks[i],
    i => starts[i],
    i => ends[i],
    src,
    test_spec,
  )
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  inspect(ctx.at_adjacent(TestTok::Plus), content="false")
  ctx.flush_trivia()
  inspect(ctx.at_adjacent(TestTok::Plus), content="false")
  ctx.finish_node()
}

///|
test "at_adjacent: leading trivia consumed by emit_token keeps adjacency" {
  // emit_token flushes the LEADING trivia of the token it consumes; that
  // trivia sits before the previous token, not between it and the next.
  let src = " 1+2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.emit_token(KNum)
  inspect(ctx.at_adjacent(TestTok::Plus), content="true")
  ctx.finish_node()
}

///|
test "reparse_block selector decline widens to parent" {
  fn parse_nested_expr(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
      ctx.node(KExpr, fn() {
        ctx.emit_token(KNum)
        ctx.emit_token(KPlus)
        ctx.emit_token(KNum)
        ctx.emit_token(KPlus)
        ctx.emit_token(KNum)
      })
    })
  }

  let (old_tree, _) = parse_with(
    "1+2+3+4", test_spec, test_tokenize, parse_nested_expr,
  )
  let seen : Array[Int] = []
  let seen_texts : Array[String] = []
  let seen_token_counts : Array[Int] = []
  let block_spec : BlockReparseSpec[TestTok, TestKind] = {
    is_reparseable: kind => kind == test_kind_raw(KExpr),
    get_reparser: fn(node, candidate_text, tokens) {
      seen.push(node.start())
      seen_texts.push(candidate_text)
      seen_token_counts.push(tokens.length())
      if node.start() == 2 {
        None
      } else {
        Some(parse_nested_expr)
      }
    },
    is_balanced: _ => true,
  }
  let lex = fn(source : String) -> LexResult[TestTok] {
    let (tokens, starts) = test_tokenize_with_starts(source)
    LexResult::with_starts(tokens, starts, diagnostics=DiagnosticSet::empty())
  }
  let result = reparse_block(
    @seam.SyntaxNode::from_cst(old_tree),
    "1+2+9+4",
    Edit::new(4, 1, 1),
    lex,
    test_spec,
    block_spec,
    DiagnosticSet::empty(),
  )
  inspect(result is Some(_), content="true")
  inspect(seen.length(), content="2")
  inspect(seen[0], content="2")
  inspect(seen[1], content="0")
  inspect(seen_texts[0], content="2+9+4")
  inspect(seen_texts[1], content="1+2+9+4")
  inspect(seen_token_counts[0], content="5")
}

///|
test "reparse_block selected failure does not widen" {
  fn parse_nested_expr(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
      ctx.node(KExpr, fn() {
        ctx.emit_token(KNum)
        ctx.emit_token(KPlus)
        ctx.emit_token(KNum)
        ctx.emit_token(KPlus)
        ctx.emit_token(KNum)
      })
    })
  }

  let (old_tree, _) = parse_with(
    "1+2+3+4", test_spec, test_tokenize, parse_nested_expr,
  )
  let seen : Array[Int] = []
  let block_spec : BlockReparseSpec[TestTok, TestKind] = {
    is_reparseable: kind => kind == test_kind_raw(KExpr),
    get_reparser: fn(node, _, _) {
      seen.push(node.start())
      if node.start() == 2 {
        Some(fn(_) {  })
      } else {
        Some(parse_nested_expr)
      }
    },
    is_balanced: _ => true,
  }
  let lex = fn(source : String) -> LexResult[TestTok] {
    let (tokens, starts) = test_tokenize_with_starts(source)
    LexResult::with_starts(tokens, starts, diagnostics=DiagnosticSet::empty())
  }
  let result = reparse_block(
    @seam.SyntaxNode::from_cst(old_tree),
    "1+2+3+4",
    Edit::new(3, 1, 1),
    lex,
    test_spec,
    block_spec,
    DiagnosticSet::empty(),
  )
  inspect(result is None, content="true")
  inspect(seen.length(), content="1")
  inspect(seen[0], content="2")
}

///|
test "reparse_block balance failure does not widen" {
  fn parse_nested_expr(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
      ctx.node(KExpr, fn() {
        ctx.emit_token(KNum)
        ctx.emit_token(KPlus)
        ctx.emit_token(KNum)
        ctx.emit_token(KPlus)
        ctx.emit_token(KNum)
      })
    })
  }

  let (old_tree, _) = parse_with(
    "1+2+3+4", test_spec, test_tokenize, parse_nested_expr,
  )
  let selector_calls : Array[Int] = []
  let block_spec : BlockReparseSpec[TestTok, TestKind] = {
    is_reparseable: kind => kind == test_kind_raw(KExpr),
    get_reparser: fn(node, _, _) {
      selector_calls.push(node.start())
      Some(parse_nested_expr)
    },
    is_balanced: tokens => {
      match tokens {
        [first, ..] => first.token != TestTok::Num(2)
        [] => false
      }
    },
  }
  let lex = fn(source : String) -> LexResult[TestTok] {
    let (tokens, starts) = test_tokenize_with_starts(source)
    LexResult::with_starts(tokens, starts, diagnostics=DiagnosticSet::empty())
  }
  let result = reparse_block(
    @seam.SyntaxNode::from_cst(old_tree),
    "1+2+9+4",
    Edit::new(4, 1, 1),
    lex,
    test_spec,
    block_spec,
    DiagnosticSet::empty(),
  )
  inspect(result is None, content="true")
  inspect(selector_calls.length(), content="0")
}
