// Whitebox tests for recovery combinators.
// Reuses TestTok, TestKind, test_spec, test_tokenize from parser_wbtest.mbt.

// ─── expect ───────────────────────────────────────────────────────────────────

///|
test "expect: consumes matching token and returns true" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect(TestTok::Num(1), KNum)
  ctx.finish_node()
  inspect(ok, content="true")
  inspect(ctx.errors.length(), content="0")
}

///|
test "expect: emits placeholder and diagnostic on mismatch" {
  let src = "+ 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect(TestTok::Num(1), KNum)
  // Token should NOT be consumed — still at "+"
  inspect(ok, content="false")
  inspect(ctx.errors.length(), content="1")
  // Auto-generated message includes Show of both tokens
  inspect(
    ctx.errors[0].message.contains("expected") &&
    ctx.errors[0].message.contains("Plus"),
    content="true",
  )
  // Position unchanged — "+" is still the current token
  inspect(ctx.at(TestTok::Plus), content="true")
  ctx.finish_node()
}

///|
test "expect: at EOF emits placeholder with eof in message" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect(TestTok::Num(1), KNum)
  inspect(ok, content="false")
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message.contains("TokEof"), content="true")
  ctx.finish_node()
}

///|
test "expect: at EOF emits incomplete_kind placeholder, not error_kind" {
  let (tree, errors) = parse_with("", test_spec, test_tokenize, fn(ctx) {
    let _ = ctx.expect(TestTok::Num(1), KNum)
  })
  inspect(errors.length(), content="1")
  // The placeholder token should be KIncomplete, not KErr
  let mut found_incomplete = false
  for child in tree.children {
    match child {
      @seam.CstElement::Token(t) =>
        if t.kind == test_kind_raw(KIncomplete) {
          found_incomplete = true
        }
      _ => ()
    }
  }
  inspect(found_incomplete, content="true")
}

///|
test "expect: non-EOF mismatch emits error_kind placeholder, not incomplete" {
  let (tree, errors) = parse_with("+ 2", test_spec, test_tokenize, fn(ctx) {
    let _ = ctx.expect(TestTok::Num(1), KNum)
  })
  inspect(errors.length(), content="1")
  // The placeholder token should be KErr, not KIncomplete
  let mut found_error = false
  for child in tree.children {
    match child {
      @seam.CstElement::Token(t) =>
        if t.kind == test_kind_raw(KErr) && t.text_len() == 0 {
          found_error = true
        }
      _ => ()
    }
  }
  inspect(found_error, content="true")
}

// ─── skip_until ───────────────────────────────────────────────────────────────

///|
test "skip_until: skips to sync token" {
  // "1 + 2" — skip until we see Num(2)
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until(t => {
    match t {
      Num(2) => true
      _ => false
    }
  })
  inspect(skipped, content="2") // Num(1) and Plus
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}

///|
test "skip_until: returns 0 when already at sync point" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until(t => {
    match t {
      Num(_) => true
      _ => false
    }
  })
  inspect(skipped, content="0")
  inspect(ctx.at(TestTok::Num(1)), content="true")
  ctx.finish_node()
}

///|
test "skip_until: skips to EOF when no sync found" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until(_t => false) // nothing is sync
  inspect(skipped, content="3") // Num(1), Plus, Num(2)
  inspect(ctx.at_eof(), content="true")
  ctx.finish_node()
}

///|
test "skip_until: returns 0 on empty input" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until(_t => false)
  inspect(skipped, content="0")
  ctx.finish_node()
}

// ─── skip_until_balanced ──────────────────────────────────────────────────────

///|
test "skip_until_balanced: stops at close at depth 0" {
  // "1 + 2" — treat Plus as close, no open tokens
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until_balanced(
    _t => false, // no open
    t => t == TestTok::Plus, // Plus is close
  )
  inspect(skipped, content="1") // skipped Num(1)
  inspect(ctx.at(TestTok::Plus), content="true") // Plus not consumed
  ctx.finish_node()
}

///|
test "skip_until_balanced: respects nesting depth" {
  // "1 + + 2" — tokens: [Num(1), Plus, Plus, Num(2)]
  // is_open = Num(1), is_close = Plus
  //   Num(1) → open, depth=1, skip
  //   Plus → close, depth=0, skip
  //   Plus → close at depth 0, BREAK
  //   → skipped 2, now at second Plus
  let src = "1 + + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until_balanced(
    t => {
      match t {
        Num(1) => true
        _ => false
      }
    },
    t => t == TestTok::Plus,
  )
  inspect(skipped, content="2") // Num(1) and first Plus
  inspect(ctx.at(TestTok::Plus), content="true") // second Plus not consumed
  ctx.finish_node()
}

// ─── node_with_recovery ───────────────────────────────────────────────────────

///|
test "node_with_recovery: success path — no recovery" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.node_with_recovery(
    KExpr,
    () => {
      ctx.emit_token(KNum)
      true
    },
    _t => true,
  )
  ctx.finish_node()
  inspect(ctx.errors.length(), content="0")
  inspect(ctx.at_eof(), content="true")
}

///|
test "node_with_recovery: failure triggers skip_until" {
  // "1 + + 2" — parse Num, then fail, recover at second Num
  let src = "1 + + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  ctx.node_with_recovery(
    KExpr,
    () => {
      ctx.emit_token(KNum) // consume "1"
      ctx.error("expected end of expression") // signal failure → triggers recovery
      false
    },
    t => {
      match t {
        Num(_) => true // sync at next number
        _ => false
      }
    },
  )
  // After recovery: "+" "+" were skipped, now at Num(2)
  inspect(ctx.at(TestTok::Num(2)), content="true")
  inspect(ctx.errors.length(), content="1")
  ctx.finish_node()
}

// ─── expect_and_recover ───────────────────────────────────────────────────────

///|
test "expect_and_recover: immediate match" {
  let src = "+ 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect_and_recover(TestTok::Plus, KPlus, t => {
    match t {
      Num(_) => true
      _ => false
    }
  })
  inspect(ok, content="true")
  inspect(ctx.errors.length(), content="0")
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}

///|
test "expect_and_recover: skips garbage then finds expected" {
  // "1 + 2" — expect Plus, but Num(1) is first. Skip Num(1), find Plus.
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect_and_recover(TestTok::Plus, KPlus, t => {
    match t {
      Num(2) => true // Num(2) is also a sync point
      _ => false
    }
  })
  inspect(ok, content="true") // found Plus after skipping Num(1)
  inspect(ctx.errors.length(), content="1") // diagnostic recorded
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}

///|
test "expect_and_recover: gives up when expected not found" {
  // "1 2" — expect Plus, skip Num(1), reach Num(2) = sync. Plus not found.
  let src = "1 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let ok = ctx.expect_and_recover(TestTok::Plus, KPlus, t => {
    match t {
      Num(2) => true
      _ => false
    }
  })
  inspect(ok, content="false") // gave up
  inspect(ctx.errors.length(), content="1")
  // Num(2) is still available (sync point not consumed)
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}

///|
test "expect_and_recover: at EOF emits incomplete_kind placeholder" {
  let (tree, errors) = parse_with("", test_spec, test_tokenize, fn(ctx) {
    let _ = ctx.expect_and_recover(TestTok::Plus, KPlus, _t => false)
  })
  inspect(errors.length(), content="1")
  let mut found_incomplete = false
  for child in tree.children {
    match child {
      @seam.CstElement::Token(t) =>
        if t.kind == test_kind_raw(KIncomplete) {
          found_incomplete = true
        }
      _ => ()
    }
  }
  inspect(found_incomplete, content="true")
}

// ─── emit_incomplete_placeholder ─────────────────────────────────────────────

///|
test "emit_incomplete_placeholder: emits incomplete_kind, not error_kind" {
  let (tree, _) = parse_with("", test_spec, test_tokenize, fn(ctx) {
    ctx.emit_incomplete_placeholder()
  })
  // parse_with wraps in KRoot; the incomplete token is a direct child
  let mut found_incomplete = false
  for child in tree.children {
    match child {
      @seam.CstElement::Token(t) =>
        if t.kind == test_kind_raw(KIncomplete) {
          found_incomplete = true
          inspect(t.kind == test_kind_raw(KErr), content="false")
          inspect(t.text_len(), content="0")
        }
      _ => ()
    }
  }
  inspect(found_incomplete, content="true")
}

///|
test "skip_until_progress: consumes one token when already at sync point" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until_progress(t => {
    match t {
      Num(_) => true
      _ => false
    }
  })
  inspect(skipped, content="1")
  inspect(ctx.at(TestTok::Plus), content="true")
  ctx.finish_node()
}

///|
test "skip_until_progress: returns 0 at EOF" {
  let src = ""
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until_progress(_t => false)
  inspect(skipped, content="0")
  ctx.finish_node()
}

///|
test "skip_until_progress: normal skip when not at sync" {
  let src = "1 + 2"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.start_node(KRoot)
  let skipped = ctx.skip_until_progress(t => {
    match t {
      Num(2) => true
      _ => false
    }
  })
  inspect(skipped, content="2")
  inspect(ctx.at(TestTok::Num(2)), content="true")
  ctx.finish_node()
}
