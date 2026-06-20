///|
// ─── ReuseCursor[T, K] tests ─────────────────────────────────────────────────

///|
fn test_parse_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
  while !ctx.at_eof() {
    match ctx.peek() {
      Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
      _ => ctx.emit_token(KPlus)
    }
  }
}

///|
fn test_parse_item_tree(src : String) -> @seam.CstNode {
  let (tree, _) = parse_with(
    src, test_spec, test_tokenize, test_parse_item_nodes,
  )
  tree
}

///|
fn test_reuse_cursor(
  old_tree : @seam.CstNode,
  new_src : String,
  damage_start : Int,
  damage_end : Int,
  new_damage_end? : Int = damage_end,
  allow_left_adjacent_reuse? : Bool = false,
  reuse_size_threshold? : Int = 0,
) -> ReuseCursor[TestTok, TestKind] {
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
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
    reuse_size_threshold~,
    allow_left_adjacent_reuse~,
    new_damage_end~,
  )
}

///|
test "ReuseCursor::new: globally disabled when damage covers root" {
  let src = "42"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    0,
    tree.text_len,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  inspect(cursor.is_reuse_disabled(), content="true")
}

///|
test "ReuseCursor::new: not globally disabled with partial damage" {
  let src = "1 + 2"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    2,
    3,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  inspect(cursor.is_reuse_disabled(), content="false")
}

///|
test "ReuseCursor::explain_reuse_rejection: reports root damage disable" {
  let src = "1+2"
  let old_tree = test_parse_item_tree(src)
  let cursor = test_reuse_cursor(old_tree, src, 0, old_tree.text_len)
  let reason = cursor.explain_reuse_rejection(test_kind_raw(KExpr), 0, 0)
  inspect(reason == Some(ReuseRejectGloballyDisabled), content="true")
}

///|
test "ReuseCursor::explain_reuse_rejection: reports edited offset" {
  let old_tree = test_parse_item_tree("1+2")
  let cursor = test_reuse_cursor(old_tree, "1++2", 1, 1, new_damage_end=2)
  let reason = cursor.explain_reuse_rejection(test_kind_raw(KExpr), 1, 1)
  inspect(reason == Some(ReuseRejectEditedOffset), content="true")
}

///|
test "ReuseCursor::explain_reuse_rejection: reports missing candidate" {
  let src = "1+2"
  let old_tree = test_parse_item_tree(src)
  let cursor = test_reuse_cursor(old_tree, src, 99, 99)
  let reason = cursor.explain_reuse_rejection(test_kind_raw(KPlus), 0, 0)
  inspect(reason == Some(ReuseRejectNoCandidate), content="true")
}

///|
test "ReuseCursor::explain_reuse_rejection: reports size policy rejection" {
  let src = "1+2"
  let old_tree = test_parse_item_tree(src)
  let cursor = test_reuse_cursor(old_tree, src, 99, 99, reuse_size_threshold=99)
  let reason = cursor.explain_reuse_rejection(test_kind_raw(KExpr), 0, 0)
  inspect(reason == Some(ReuseRejectBelowSizeThreshold), content="true")
}

///|
test "ReuseCursor::explain_reuse_rejection: reports damage overlap" {
  let src = "1+2"
  let old_tree = test_parse_item_tree(src)
  let cursor = test_reuse_cursor(old_tree, src, 1, 2)
  let reason = cursor.explain_reuse_rejection(test_kind_raw(KExpr), 0, 0)
  inspect(reason == Some(ReuseRejectDamageOverlap), content="true")
}

///|
test "ReuseCursor::explain_reuse_rejection: reports leading token mismatch" {
  let old_tree = test_parse_item_tree("1+2")
  let cursor = test_reuse_cursor(old_tree, "9+2", 99, 99)
  let reason = cursor.explain_reuse_rejection(test_kind_raw(KExpr), 0, 0)
  inspect(reason == Some(ReuseRejectLeadingTokenMismatch), content="true")
}

///|
test "ReuseCursor::explain_reuse_rejection: reports follow token mismatch" {
  let old_tree = test_parse_item_tree("1+2")
  let cursor = test_reuse_cursor(
    old_tree,
    "1 2",
    1,
    2,
    new_damage_end=2,
    allow_left_adjacent_reuse=true,
  )
  let reason = cursor.explain_reuse_rejection(test_kind_raw(KExpr), 0, 0)
  inspect(reason == Some(ReuseRejectFollowTokenMismatch), content="true")
}

///|
test "ReuseCursor::explain_reuse_rejection: returns None for accepted reuse" {
  let src = "1+2"
  let old_tree = test_parse_item_tree(src)
  let cursor = test_reuse_cursor(old_tree, src, 99, 99)
  let reason = cursor.explain_reuse_rejection(test_kind_raw(KExpr), 0, 0)
  inspect(reason is None, content="true")
}

///|
test "ReuseCursor::try_reuse: returns Some for undamaged node" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
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
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse: returns None when globally disabled" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0,
    old_tree.text_len,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="false")
}

///|
test "ReuseCursor::try_reuse: returns None when node overlaps damage" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    1,
    3,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="false")
}

///|
test "ReuseCursor::try_reuse: keeps left-adjacent node conservative for insertion" {
  fn grammar_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    while !ctx.at_eof() {
      match ctx.peek() {
        Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        _ => ctx.emit_token(KPlus)
      }
    }
  }
  let src = "1+2"
  let edited = "1 +2"
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(edited)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    1,
    1,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      edited.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_toks[i].len,
      )
    },
    test_spec,
    reuse_size_threshold=0,
    new_damage_end=2,
  )
  // Node "1" ends at the insertion point (1); conservatively, do not reuse it.
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse: can opt into left-adjacent reuse for safe deletion" {
  fn grammar_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    while !ctx.at_eof() {
      match ctx.peek() {
        Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        _ => ctx.emit_token(KPlus)
      }
    }
  }
  let old_src = "1 +2"
  let new_src = "1+2"
  let (old_tree, _) = parse_with(
    old_src, test_spec, test_tokenize, grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let edit = Edit::delete(1, 2)
  let strict_cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new_with_edit(
    old_tree,
    edit,
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
    reuse_size_threshold=0,
  )
  let relaxed_cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new_with_edit(
    old_tree,
    edit,
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
    reuse_size_threshold=0,
    allow_left_adjacent_reuse=true,
  )
  // Node "1" ends at old damage_start (1). Strict mode rejects it; deletion
  // opt-in accepts it because the follow token remains "+".
  inspect(
    strict_cursor.try_reuse(test_kind_raw(KExpr), 0, 0) is None,
    content="true",
  )
  let result = relaxed_cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse: rejects token merge with left-adjacent deletion opt-in" {
  fn grammar_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    while !ctx.at_eof() {
      match ctx.peek() {
        Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        _ => ctx.emit_token(KPlus)
      }
    }
  }
  let old_src = "1+2"
  let new_src = "12"
  let (old_tree, _) = parse_with(
    old_src, test_spec, test_tokenize, grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let edit = Edit::delete(1, 2)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new_with_edit(
    old_tree,
    edit,
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
    reuse_size_threshold=0,
    allow_left_adjacent_reuse=true,
  )
  // Deleting "+" merges the surrounding digits into a different token. The
  // follow-token check still rejects reuse even when the boundary is relaxed.
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse: allows right-adjacent node for insertion" {
  fn grammar_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    while !ctx.at_eof() {
      match ctx.peek() {
        Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        _ => ctx.emit_token(KPlus)
      }
    }
  }
  let src = "1+2"
  let edited = "1+ 2"
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(edited)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    2,
    2,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      edited.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_toks[i].len,
      )
    },
    test_spec,
    reuse_size_threshold=0,
    new_damage_end=3,
  )
  // Node "2" starts at damage_end (2). Right-adjacent reuse remains allowed.
  let result = cursor.try_reuse(test_kind_raw(KExpr), 3, 3)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::new_with_edit: maps delete edit back to reusable shifted node" {
  fn grammar_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    while !ctx.at_eof() {
      match ctx.peek() {
        Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        _ => ctx.emit_token(KPlus)
      }
    }
  }
  let old_src = "1+2+3"
  let new_src = "1+3"
  let (old_tree, _) = parse_with(
    old_src, test_spec, test_tokenize, grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cache = OldTokenCache::empty()
  let edit = Edit::replace(2, 4, 2)
  cache.apply_source_edit(edit)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new_with_edit(
    old_tree,
    edit,
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
    old_token_cache=cache,
  )
  let second = cursor.try_reuse(test_kind_raw(KExpr), 2, 2)
  inspect(second is Some(_), content="true")
}

///|
test "ReuseCursor::advance_past: updates current_offset" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
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
  cursor.advance_past(old_tree)
  inspect(cursor.current_offset, content="5")
}

///|
test "new_follow_token_with_pos: finds first non-trivia token at or after offset" {
  let src = "1 + 2"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
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
  let result = new_follow_token_with_pos(cursor, 2)
  debug_inspect(result.map(fn(pair) { pair.0 }), content="Some(Plus)")
}

///|
test "new_follow_token_with_pos: skips leading trivia" {
  let src = "1 + 2"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
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
  let result = new_follow_token_with_pos(cursor, 1)
  debug_inspect(result.map(fn(pair) { pair.0 }), content="Some(Plus)")
}

///|
test "new_follow_token_with_pos: returns None past end of tokens" {
  let src = "1 + 2"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
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
  let result = new_follow_token_with_pos(cursor, 5)
  inspect(result.map(fn(pair) { pair.0 }) is None, content="true")
}

///|
test "old_follow_token_lazy: finds first non-trivia token at or after offset" {
  let src = "1 + 2"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
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
  let result = old_follow_token_lazy(cursor, 1)
  inspect(result is Some(_), content="true")
  let tok = result.unwrap()
  inspect(tok.start, content="2")
  inspect(tok.text, content="+")
}

///|
test "old_follow_token_lazy: returns None past end of tree" {
  let src = "42"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
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
  let result = old_follow_token_lazy(cursor, 99)
  inspect(result is Some(_), content="false")
}

///|
test "old_follow_token_lazy: cache is shared across snapshots" {
  let src = "1 + 2"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
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
  // Snapshot before materializing the cache
  let snap = cursor.snapshot()
  // Materialize via the original cursor
  let _ = old_follow_token_lazy(cursor, 0)
  // The snapshot should see the same materialized cache
  let result = old_follow_token_lazy(snap, 2)
  inspect(result is Some(_), content="true")
  let tok = result.unwrap()
  inspect(tok.text, content="+")
}

///|
test "ReuseCursor::try_reuse: reuses unaffected nodes across middle deletion" {
  fn grammar_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    while !ctx.at_eof() {
      match ctx.peek() {
        Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        _ => ctx.emit_token(KPlus)
      }
    }
  }
  let item_spec : LanguageSpec[TestTok, TestKind] = {
    whitespace_kind: KWs,
    error_kind: KErr,
    incomplete_kind: KIncomplete,
    root_kind: KRoot,
    eof_token: TestTok::TokEof,
    parse_root: grammar_item_nodes,
    reuse_size_threshold: 64,
  }
  let old_src = "1+2+3"
  let new_src = "1+3"
  let (old_tree, _) = parse_with(
    old_src, item_spec, test_tokenize, grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cache = OldTokenCache::empty()
  cache.apply_edit(2, 4, 2)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    2,
    4,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_src.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_toks[i].len,
      )
    },
    item_spec,
    old_token_cache=cache,
    new_damage_end=2,
  )
  // Node for "3" shifts left after deletion and should be reusable.
  // Probe directly without consuming "1" first.
  let second = cursor.try_reuse(test_kind_raw(KExpr), 2, 2)
  inspect(second is Some(_), content="true")
}

///|
test "parse_tokens_indexed: parse with middle deletion can still reuse shifted nodes" {
  fn grammar_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    while !ctx.at_eof() {
      match ctx.peek() {
        Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        _ => ctx.emit_token(KPlus)
      }
    }
  }
  let item_spec : LanguageSpec[TestTok, TestKind] = {
    whitespace_kind: KWs,
    error_kind: KErr,
    incomplete_kind: KIncomplete,
    root_kind: KRoot,
    eof_token: TestTok::TokEof,
    parse_root: grammar_item_nodes,
    reuse_size_threshold: 64,
  }
  let old_src = "1 + 2 + 3"
  let new_src = "2 + 3"
  let (old_tree, _) = parse_with(
    old_src, item_spec, test_tokenize, grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cache = OldTokenCache::empty()
  // Delete old range [0,4) ("1 + "), which shifts trailing nodes left by 4.
  cache.apply_edit(0, 4, 0)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0,
    4,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_src.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_toks[i].len,
      )
    },
    item_spec,
    old_token_cache=cache,
    new_damage_end=0,
  )
  let (tree, _, reuse_count) = parse_tokens_indexed(
    new_src,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) { new_starts[i] + new_toks[i].len },
    item_spec,
    cursor=Some(cursor),
  )
  inspect(reuse_count > 0, content="true")
  match tree.first_token(fn(r) { r == test_kind_raw(KWs) }) {
    Some(tok) => {
      inspect(tok.text(), content="2")
      inspect(
        physical_equal(tok.unsafe_backing_source(), new_src),
        content="true",
      )
      inspect(tok.start_offset(), content="0")
    }
    None => abort("expected first token")
  }
}

///|
test "parse_tokens_indexed: parse with prefix deletion reuses shifted descendants" {
  fn grammar_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    while !ctx.at_eof() {
      match ctx.peek() {
        Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        _ => ctx.emit_token(KPlus)
      }
    }
  }
  let item_spec : LanguageSpec[TestTok, TestKind] = {
    whitespace_kind: KWs,
    error_kind: KErr,
    incomplete_kind: KIncomplete,
    root_kind: KRoot,
    eof_token: TestTok::TokEof,
    parse_root: grammar_item_nodes,
    reuse_size_threshold: 64,
  }
  let old_src = "1+2+3"
  let new_src = "2+3"
  let (old_tree, _) = parse_with(
    old_src, item_spec, test_tokenize, grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cache = OldTokenCache::empty()
  // Delete first two bytes [0,2) to shift remaining nodes left.
  cache.apply_edit(0, 2, 0)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0,
    2,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_src.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_toks[i].len,
      )
    },
    item_spec,
    old_token_cache=cache,
    new_damage_end=0,
  )
  let (_, _, reuse_count) = parse_tokens_indexed(
    new_src,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) { new_starts[i] + new_toks[i].len },
    item_spec,
    cursor=Some(cursor),
  )
  // Conservative left-boundary policy excludes the node ending at the damage
  // boundary, so one prefix subtree is still expected to be reusable.
  inspect(reuse_count >= 1, content="true")
}

///|
test "parse_tokens_indexed: parse with suffix deletion reuses unaffected prefix nodes" {
  fn grammar_item_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    while !ctx.at_eof() {
      match ctx.peek() {
        Num(_) => ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        _ => ctx.emit_token(KPlus)
      }
    }
  }
  let item_spec : LanguageSpec[TestTok, TestKind] = {
    whitespace_kind: KWs,
    error_kind: KErr,
    incomplete_kind: KIncomplete,
    root_kind: KRoot,
    eof_token: TestTok::TokEof,
    parse_root: grammar_item_nodes,
    reuse_size_threshold: 64,
  }
  let old_src = "1+2+3"
  let new_src = "1+2"
  let (old_tree, _) = parse_with(
    old_src, item_spec, test_tokenize, grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cache = OldTokenCache::empty()
  // Delete tail [3,5) (\"+3\") to keep prefix structure intact.
  cache.apply_edit(3, 5, 3)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    3,
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
    item_spec,
    old_token_cache=cache,
    new_damage_end=3,
  )
  let (_, _, reuse_count) = parse_tokens_indexed(
    new_src,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_starts[i] },
    fn(i) { new_starts[i] + new_toks[i].len },
    item_spec,
    cursor=Some(cursor),
  )
  // Conservative left-boundary policy excludes the final node ending at the
  // damage boundary, so one unaffected prefix node is still expected to be
  // reused.
  inspect(reuse_count >= 1, content="true")
}
