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
  let (tree, _) = try! parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_parse_item_nodes,
  )
  tree
}

///|
fn test_reuse_cursor(
  old_tree : @seam.CstNode,
  new_src : String,
  damage_start : Int32,
  damage_end : Int32,
  new_damage_end~ : Int32 = damage_end,
  allow_left_adjacent_reuse~ : Bool = false,
  reuse_size_threshold~ : Int32 = 0,
) -> ReuseCursor[TestTok, TestKind] {
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      new_src.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
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
  let (tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    0,
    tree.text_len(),
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  inspect(cursor.is_reuse_disabled(), content="true")
}

///|
test "ReuseCursor::new: not globally disabled with partial damage" {
  let src = "1 + 2"
  let (tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    2,
    3,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  inspect(cursor.is_reuse_disabled(), content="false")
}

///|
test "ReuseCursor::explain_reuse_rejection: reports root damage disable" {
  let src = "1+2"
  let old_tree = test_parse_item_tree(src)
  let cursor = test_reuse_cursor(old_tree, src, 0, old_tree.text_len())
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
  let (old_tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse: returns None when globally disabled" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0,
    old_tree.text_len(),
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="false")
}

///|
test "ReuseCursor::try_reuse: returns None when node overlaps damage" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    1,
    3,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
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
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(edited)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    1,
    1,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      edited.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
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
    SourceId("parser-reuse-source"),
    old_src,
    test_spec,
    test_tokenize,
    grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let edit = Edit::delete(1, 2)
  let strict_cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new_with_edit(
    old_tree,
    edit,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      new_src.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
      )
    },
    test_spec,
    reuse_size_threshold=0,
  )
  let relaxed_cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new_with_edit(
    old_tree,
    edit,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      new_src.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
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
    SourceId("parser-reuse-source"),
    old_src,
    test_spec,
    test_tokenize,
    grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let edit = Edit::delete(1, 2)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new_with_edit(
    old_tree,
    edit,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      new_src.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
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
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(edited)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    2,
    2,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      edited.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
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
    SourceId("parser-reuse-source"),
    old_src,
    test_spec,
    test_tokenize,
    grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let edit = Edit::replace(2, 4, 2)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new_with_edit(
    old_tree,
    edit,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      new_src.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
      )
    },
    test_spec,
  )
  let second = cursor.try_reuse(test_kind_raw(KExpr), 2, 2)
  inspect(second is Some(_), content="true")
}

///|
test "ReuseCursor::advance_past: updates current_offset" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  cursor.advance_past(old_tree)
  inspect(cursor.current_offset, content="5")
}

///|
test "new_follow_token_with_pos: finds first non-trivia token at or after offset" {
  let src = "1 + 2"
  let (tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  let result = new_follow_token_with_pos(cursor, 2)
  debug_inspect(result.map(fn(pair) { pair.0 }), content="Some(Plus)")
}

///|
test "new_follow_token_with_pos: skips leading trivia" {
  let src = "1 + 2"
  let (tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  let result = new_follow_token_with_pos(cursor, 1)
  debug_inspect(result.map(fn(pair) { pair.0 }), content="Some(Plus)")
}

///|
test "new_follow_token_with_pos: returns None past end of tokens" {
  let src = "1 + 2"
  let (tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  let result = new_follow_token_with_pos(cursor, 5)
  inspect(result.map(fn(pair) { pair.0 }) is None, content="true")
}

///|
test "old_follow_token: finds first non-trivia token at or after offset" {
  let src = "1 + 2"
  let (tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  let result = old_follow_token(cursor, 1)
  inspect(result is Some(_), content="true")
  let tok = result.unwrap()
  inspect(tok.start, content="2")
  inspect(tok.text, content="+")
}

///|
test "old_follow_token: returns None past end of tree" {
  let src = "42"
  let (tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  let result = old_follow_token(cursor, 99)
  inspect(result is Some(_), content="false")
}

///|
test "old_follow_token: a snapshot answers the same lookups" {
  let src = "1 + 2"
  let (tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    src,
    test_spec,
    test_tokenize,
    test_grammar,
  )
  let (toks, starts) = test_tokenize_with_starts(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    i => toks[i].token,
    i => starts[i],
    fn(i) { src.legacy_view(start=starts[i], end=starts[i] + toks[i].len) },
    test_spec,
  )
  let snap = cursor.snapshot()
  let _ = old_follow_token(cursor, 0)
  let result = old_follow_token(snap, 2)
  inspect(result is Some(_), content="true")
  let tok = result.unwrap()
  inspect(tok.text, content="+")
}

///|
test "old-token lookups: the walk and the table agree at every offset" {
  for case in [(RegularNodes, 4), (RepeatGroups, 12)] {
    let (shape, items) = case
    let fixture = zero_width_bench_fixture(shape, PlainOldTree, items, 2)
    let spec = zero_width_boundary_spec(fixture.use_repeat_groups, 0)
    let walk = zero_width_bench_cursor(fixture, spec)
    let table = zero_width_bench_cursor(fixture, spec)
    walk.old_token_walks_left.val = 2147483647
    table.old_token_walks_left.val = 0
    for offset = -1
        offset <= fixture.old_tree.text_len() + 1
        offset = offset + 1 {
      assert_eq(old_follow_token(walk, offset), old_follow_token(table, offset))
      assert_eq(
        walk.old_zero_width_tokens_at_boundary(offset),
        table.old_zero_width_tokens_at_boundary(offset),
      )
    }
    assert_true(walk.old_tokens.val is None)
    assert_true(table.old_tokens.val is Some(_))
  }
}

///|
fn old_token_lookup_grammar(ctx : ParserContext[TestTok, TestKind]) -> Unit {
  while !ctx.at_eof() {
    match ctx.peek() {
      Num(_) =>
        ctx.node(KExpr, fn() {
          ctx.node(KComment, fn() {  })
          ctx.emit_token(KNum)
          ctx.emit_zero_width(KPlus)
          while ctx.at(TestTok::Plus) {
            ctx.node(KExpr, fn() { ctx.emit_token(KPlus) })
          }
          ctx.node(KComment, fn() { ctx.emit_zero_width(KPlus) })
        })
      _ => ctx.bump_error()
    }
  }
}

///|
fn old_token_lookup_spec() -> LanguageSpec[TestTok, TestKind] {
  LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    parse_root=old_token_lookup_grammar,
    reuse_size_threshold=0,
  )
}

///|
/// Each item wraps its zero-width tokens in nodes of their own, opens and
/// closes with empty or zero-width-only nodes, and leaves trivia as the first
/// token at some offsets, so the walk's node-skipping and trivia filtering
/// must match the table exactly.
test "old-token lookups: the walk and the table agree on nested zero-width nodes" {
  let spec = old_token_lookup_spec()
  for mode in [PlainOldTree, TokenInternedOldTree, FullyInternedOldTree] {
    for zw in [0, 1, 3] {
      let src = zero_width_source([1, 2, 3, 4], [1, 3, 2])
      let counts = [zw, 0, zw, 2]
      let tokens = zero_width_tokenize_with_boundaries(src, counts)
      let ctx = ParserContext::new(
        SourceId("old-token-lookup"),
        tokens,
        src,
        spec,
      )
      (spec.parse_root)(ctx)
      let tree = zero_width_build_tree_from_events(ctx, spec, mode)
      let starts = build_starts(tokens)
      let mk = fn() {
        ReuseCursor::new(
          tree,
          99,
          99,
          tokens.length(),
          i => tokens[i].token,
          i => starts[i],
          fn(i) {
            src.legacy_view(start=starts[i], end=starts[i] + tokens[i].len)
          },
          spec,
        )
      }
      let walk = mk()
      let table = mk()
      walk.old_token_walks_left.val = 2147483647
      table.old_token_walks_left.val = 0
      let mut zw_hits = 0
      for offset = -2; offset <= tree.text_len() + 2; offset = offset + 1 {
        assert_eq(
          old_follow_token(walk, offset),
          old_follow_token(table, offset),
        )
        let a = walk.old_zero_width_tokens_at_boundary(offset)
        assert_eq(a, table.old_zero_width_tokens_at_boundary(offset))
        zw_hits = zw_hits + a.length()
      }
      assert_eq(zw_hits, 2 * zw + 2)
    }
  }
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
  let item_spec : LanguageSpec[TestTok, TestKind] = LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    parse_root=grammar_item_nodes,
    reuse_size_threshold=64,
    trivia_kinds_spec=[KWs],
  )
  let old_src = "1+2+3"
  let new_src = "1+3"
  let (old_tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    old_src,
    item_spec,
    test_tokenize,
    grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    2,
    4,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      new_src.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
      )
    },
    item_spec,
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
  let item_spec : LanguageSpec[TestTok, TestKind] = LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    parse_root=grammar_item_nodes,
    reuse_size_threshold=64,
    trivia_kinds_spec=[KWs],
  )
  let old_src = "1 + 2 + 3"
  let new_src = "2 + 3"
  let (old_tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    old_src,
    item_spec,
    test_tokenize,
    grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  // Delete old range [0,4) ("1 + "), which shifts trailing nodes left by 4.
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0,
    4,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      new_src.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
      )
    },
    item_spec,
    new_damage_end=0,
  )
  let (tree, _, reuse_count) = parse_tokens_indexed(
    SourceId("parser-reuse-source"),
    new_src,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    i => new_starts[i] + new_toks[i].len,
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
  let item_spec : LanguageSpec[TestTok, TestKind] = LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    parse_root=grammar_item_nodes,
    reuse_size_threshold=64,
    trivia_kinds_spec=[KWs],
  )
  let old_src = "1+2+3"
  let new_src = "2+3"
  let (old_tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    old_src,
    item_spec,
    test_tokenize,
    grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  // Delete first two bytes [0,2) to shift remaining nodes left.
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0,
    2,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      new_src.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
      )
    },
    item_spec,
    new_damage_end=0,
  )
  let (_, _, reuse_count) = parse_tokens_indexed(
    SourceId("parser-reuse-source"),
    new_src,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    i => new_starts[i] + new_toks[i].len,
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
  let item_spec : LanguageSpec[TestTok, TestKind] = LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    parse_root=grammar_item_nodes,
    reuse_size_threshold=64,
    trivia_kinds_spec=[KWs],
  )
  let old_src = "1+2+3"
  let new_src = "1+2"
  let (old_tree, _) = parse_with(
    SourceId("parser-reuse-source"),
    old_src,
    item_spec,
    test_tokenize,
    grammar_item_nodes,
  )
  let (new_toks, new_starts) = test_tokenize_with_starts(new_src)
  // Delete tail [3,5) (\"+3\") to keep prefix structure intact.
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    3,
    5,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    fn(i) {
      new_src.legacy_view(
        start=new_starts[i],
        end=new_starts[i] + new_toks[i].len,
      )
    },
    item_spec,
    new_damage_end=3,
  )
  let (_, _, reuse_count) = parse_tokens_indexed(
    SourceId("parser-reuse-source"),
    new_src,
    new_toks.length(),
    i => new_toks[i].token,
    i => new_starts[i],
    i => new_starts[i] + new_toks[i].len,
    item_spec,
    cursor=Some(cursor),
  )
  // Conservative left-boundary policy excludes the final node ending at the
  // damage boundary, so one unaffected prefix node is still expected to be
  // reused.
  inspect(reuse_count >= 1, content="true")
}

///|
/// Regression: old context token filtering and first_source_backed_token skip ALL trivia
/// kinds, not just the primary whitespace_kind.
/// Constructs a node with tokens of kinds: Whitespace (raw=4), Comment (raw=8),
/// Plus (raw=1), and asserts both trivia kinds are filtered out.
test "multi-trivia: old context tokens exclude all trivia kinds" {
  let ws_kind = @seam.RawKind(4) // primary trivia (like KWs)
  let cmt_kind = @seam.RawKind(8) // secondary trivia (e.g., CommentToken)
  let plus_kind = @seam.RawKind(1) // non-trivia (like KPlus)
  let err_kind = @seam.RawKind(5) // error kind, like KErr
  let inc_kind = @seam.RawKind(6) // incomplete
  let trivia_kinds = [ws_kind, cmt_kind]

  // Build: CommentToken, WhitespaceToken, PlusToken, PlusToken
  // Trivia come first so first_source_backed_token must skip them.
  let cmt_tok = @seam.CstToken::CstToken(cmt_kind, "/* comment */")
  let ws_tok = @seam.CstToken::CstToken(ws_kind, " ")
  let plus_tok1 = @seam.CstToken::CstToken(plus_kind, "+")
  let plus_tok2 = @seam.CstToken::CstToken(plus_kind, "+")
  let policy = @seam.CstMetadataPolicy::new(
    trivia_kinds,
    error_kind=Some(err_kind),
    incomplete_kind=Some(inc_kind),
  )
  let node = @seam.CstNode::new(
    @seam.RawKind(3), // root
    [
      @seam.CstElement::Token(cmt_tok),
      @seam.CstElement::Token(ws_tok),
      @seam.CstElement::Token(plus_tok1),
      @seam.CstElement::Token(plus_tok2),
    ],
    policy~,
  )

  // Verify token_count excludes both trivia kinds (2 tokens out of 4)
  inspect(node.token_count(), content="2")

  // Verify only the non-trivia tokens count as old lexer context
  let mut context_tokens = 0
  for child in node.children() {
    match child {
      @seam.CstElement::Token(token) =>
        if is_old_context_token(token, trivia_kinds, err_kind, inc_kind) {
          context_tokens = context_tokens + 1
          // Use @debug.to_string for RawKind comparison (no Show instance)
          inspect(@debug.to_string(token.kind), content="RawKind(1)")
        }
      @seam.CstElement::Node(_) => ()
    }
  }
  inspect(context_tokens, content="2")

  // Verify first_source_backed_token skips both trivia kinds
  let first = first_source_backed_token(node, trivia_kinds)
  inspect(first is Some(_), content="true")
  match first {
    Some(tok) => inspect(@debug.to_string(tok.kind), content="RawKind(1)")
    None => ()
  }
}

///|
/// Regression: flush_trivia emits each trivia token using its actual raw kind,
/// not spec.whitespace_kind.to_raw(). Previously all trivia was rewritten to the
/// primary whitespace kind, making multi-trivia filtering ineffective for
/// generated grammars.
test "flush_trivia: emits trivia tokens with their actual raw kind" {
  let multi_spec : LanguageSpec[TestTok, TestKind] = LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    parse_root=fn(ctx) {
      ctx.start_node(KExpr)
      ctx.emit_token(KNum)
      ctx.finish_node()
    },
    reuse_size_threshold=64,
    trivia_kinds_spec=[KWs, KComment],
  )
  // Source with Comment, Ws, then Num: "/*c*/ 42"
  let source = "/*c*/ 42"
  // Token ranges computed from source:
  //   Comment "/*c*/" @ 0-5
  //   Ws " "      @ 5-6
  //   Num "42"    @ 6-8
  let token_count = 3
  let get_token : (Int32) -> TestTok = fn(i) {
    match i {
      0 => TestTok::Comment
      1 => TestTok::Ws
      2 => TestTok::Num(42)
      _ => TestTok::TokEof
    }
  }
  let get_start : (Int32) -> Int32 = fn(i) {
    match i {
      0 => 0
      1 => 5
      2 => 6
      _ => 0
    }
  }
  let get_end : (Int32) -> Int32 = fn(i) {
    match i {
      0 => 5
      1 => 6
      2 => 8
      _ => 0
    }
  }
  let (tree, _, _) = parse_tokens_indexed(
    SourceId("parser-reuse-source"),
    source,
    token_count,
    get_token,
    get_start,
    get_end,
    multi_spec,
  )
  // Walk the CST looking for trivia leaf tokens. Should find both RawKind(4)=Ws
  // and RawKind(8)=Comment. If flush_trivia still rewrites to whitespace_kind,
  // only RawKind(4) would appear.
  let ws_raw = test_kind_raw(KWs)
  let cmt_raw = test_kind_raw(KComment)
  let mut found_ws = false
  let mut found_cmt = false
  // Walk all tokens recursively (SyntaxNode::tokens() only walks direct children)
  fn visit_tokens(node : @seam.SyntaxNode) -> Unit {
    for child in node.all_children() {
      match child {
        @seam.SyntaxElement::Token(tok) => {
          let k = tok.kind()
          if k == ws_raw {
            found_ws = true
          } else if k == cmt_raw {
            found_cmt = true
          }
        }
        @seam.SyntaxElement::Node(n) => visit_tokens(n)
      }
    }
  }
  visit_tokens(@seam.SyntaxNode::from_cst(tree))
  inspect(found_ws, content="true")
  inspect(found_cmt, content="true")
}
