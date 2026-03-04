// Whitebox tests for the core parser — ParserContext, LanguageSpec, ReuseCursor.
// These tests access package-private symbols (e.g. new_follow_token) and define
// test-only types (TestTok, TestKind) that must not appear in the public interface.

///|
test "TokenInfo stores token with position" {
  let info : TokenInfo[String] = { token: "hello", start: 0, end: 5 }
  inspect(info.start, content="0")
  inspect(info.end, content="5")
  inspect(info.token, content="hello")
}

///|
test "Diagnostic stores message, position, and token" {
  let d : Diagnostic[String] = {
    message: "unexpected token",
    start: 3,
    end: 7,
    got_token: "bad",
  }
  inspect(d.message, content="unexpected token")
  inspect(d.got_token, content="bad")
}

///|
fn make_test_fixtures() -> (
  LanguageSpec[String, TestKind],
  Array[TokenInfo[String]],
) {
  let spec : LanguageSpec[String, TestKind] = {
    token_is_eof: fn(t) { t == "EOF" },
    token_is_trivia: fn(_) { false },
    tokens_equal: fn(a, b) { a == b },
    print_token: fn(t) { t },
    whitespace_kind: KWs,
    error_kind: KErr,
    root_kind: KRoot,
    eof_token: "EOF",
    cst_token_matches: fn(_, _, _) { false },
    parse_root: _ => (),
  }
  let tokens = [
    { token: "a", start: 0, end: 1 },
    { token: "b", start: 1, end: 2 },
  ]
  (spec, tokens)
}

///|
test "ParserContext can be constructed" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect(ctx.position, content="0")
}

///|
test "peek returns current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect(ctx.peek(), content="a")
}

///|
test "peek returns eof when past end" {
  let (spec, _) = make_test_fixtures()
  let ctx = ParserContext::new([], "", spec)
  inspect(ctx.peek(), content="EOF")
}

///|
test "peek skips trivia tokens" {
  let spec : LanguageSpec[String, TestKind] = {
    token_is_eof: fn(t) { t == "EOF" },
    token_is_trivia: fn(t) { t == " " },
    tokens_equal: fn(a, b) { a == b },
    print_token: fn(t) { t },
    whitespace_kind: KWs,
    error_kind: KErr,
    root_kind: KRoot,
    eof_token: "EOF",
    cst_token_matches: fn(_, _, _) { false },
    parse_root: _ => (),
  }
  let tokens = [
    { token: " ", start: 0, end: 1 },
    { token: " ", start: 1, end: 2 },
    { token: "x", start: 2, end: 3 },
  ]
  let ctx = ParserContext::new(tokens, "  x", spec)
  inspect(ctx.peek(), content="x")
}

///|
test "at matches current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect(ctx.at("a"), content="true")
  inspect(ctx.at("b"), content="false")
}

///|
struct FooView {
  node : @seam.SyntaxNode
}

///|
impl AstView for FooView with syntax_node(self) {
  self.node
}

///|
test "AstView: a concrete impl exposes its SyntaxNode" {
  let cst = @seam.CstNode::new(@seam.RawKind(0), [])
  let syn = @seam.SyntaxNode::from_cst(cst)
  let v : FooView = { node: syn }
  inspect(v.syntax_node() == syn, content="true")
}

// Integration test: minimal two-token language (integers and '+')
// Kept in _wbtest.mbt so test types don't appear in pkg.generated.mbti.

///|
// Test language: integers and '+' only (with whitespace)
enum TestTok {
  Num(Int)
  Plus
  Ws
  TokEof
} derive(Eq, Show)

///|
enum TestKind {
  KNum
  KPlus
  KExpr
  KRoot
  KWs
  KErr
} derive(Show)

///|
fn test_kind_raw(k : TestKind) -> @seam.RawKind {
  let n = match k {
    KNum => 0
    KPlus => 1
    KExpr => 2
    KRoot => 3
    KWs => 4
    KErr => 5
  }
  @seam.RawKind(n)
}

///|
impl @seam.ToRawKind for TestKind with to_raw(self) {
  test_kind_raw(self)
}

///|
fn test_tokenize(src : String) -> Array[TokenInfo[TestTok]] {
  let result : Array[TokenInfo[TestTok]] = []
  let mut i = 0
  while i < src.length() {
    let code = src.code_unit_at(i).to_int()
    if code == 32 {
      // space
      let start = i
      while i < src.length() && src.code_unit_at(i).to_int() == 32 {
        i = i + 1
      }
      result.push({ token: TestTok::Ws, start, end: i })
    } else if code >= 48 && code <= 57 {
      // digit
      let start = i
      let mut n = code - 48
      i = i + 1
      while i < src.length() {
        let d = src.code_unit_at(i).to_int()
        if d >= 48 && d <= 57 {
          n = n * 10 + d - 48
          i = i + 1
        } else {
          break
        }
      }
      result.push({ token: TestTok::Num(n), start, end: i })
    } else if code == 43 {
      // '+'
      result.push({ token: TestTok::Plus, start: i, end: i + 1 })
      i = i + 1
    } else {
      i = i + 1
    }
  }
  result
}

///|
let test_spec : LanguageSpec[TestTok, TestKind] = {
  token_is_eof: fn(t) { t == TestTok::TokEof },
  token_is_trivia: fn(t) { t == TestTok::Ws },
  tokens_equal: fn(a, b) { a == b },
  print_token: fn(t) { t.to_string() },
  whitespace_kind: KWs,
  error_kind: KErr,
  root_kind: KRoot,
  eof_token: TestTok::TokEof,
  cst_token_matches: fn(raw, text, tok) {
    if raw != test_kind_raw(KNum) {
      return false
    }
    match tok {
      Num(n) => n.to_string() == text
      _ => false
    }
  },
  parse_root: fn(_) { () },
}

///|
fn test_grammar(ctx : ParserContext[TestTok, TestKind]) -> Unit {
  let mark = ctx.mark()
  match ctx.peek() {
    TestTok::Num(_) => ctx.emit_token(KNum)
    _ => {
      ctx.error("expected number")
      return
    }
  }
  if ctx.at(TestTok::Plus) {
    ctx.start_at(mark, KExpr)
    while ctx.at(TestTok::Plus) {
      ctx.emit_token(KPlus)
      match ctx.peek() {
        TestTok::Num(_) => ctx.emit_token(KNum)
        _ => {
          ctx.error("expected number after +")
          // Consume the unexpected token to prevent the loop from spinning
          // on repeated non-Num tokens. Guard against EOF to avoid emitting
          // empty error tokens past end of input.
          if not(ctx.at_eof()) {
            ctx.bump_error()
          }
        }
      }
    }
    ctx.finish_node()
  }
}

///|
test "parse_with: simple number" {
  let (tree, errors) = parse_with("42", test_spec, test_tokenize, test_grammar)
  inspect(errors.length(), content="0")
  inspect(tree.text_len, content="2")
}

///|
test "parse_with: addition expression" {
  let (tree, errors) = parse_with(
    "1 + 2 + 3", test_spec, test_tokenize, test_grammar,
  )
  inspect(errors.length(), content="0")
  inspect(tree.text_len, content="9")
}

///|
test "parse_with: records errors on bad input" {
  let (_, errors) = parse_with("+", test_spec, test_tokenize, test_grammar)
  inspect(errors.length(), content="1")
  inspect(errors[0].message, content="expected number")
}

///|
// ─── ReuseCursor[T, K] tests ─────────────────────────────────────────────────

///|
test "ReuseCursor::new: globally disabled when damage covers root" {
  let (tree, _) = parse_with("42", test_spec, test_tokenize, test_grammar)
  let toks = test_tokenize("42")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    0,
    tree.text_len,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  inspect(cursor.is_reuse_disabled(), content="true")
}

///|
test "ReuseCursor::new: not globally disabled with partial damage" {
  let (tree, _) = parse_with("1 + 2", test_spec, test_tokenize, test_grammar)
  let toks = test_tokenize("1 + 2")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    2,
    3,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  inspect(cursor.is_reuse_disabled(), content="false")
}

///|
test "ReuseCursor::try_reuse: returns Some for undamaged node" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let toks = test_tokenize(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse: returns None when globally disabled" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let toks = test_tokenize(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0,
    old_tree.text_len,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="false")
}

///|
test "ReuseCursor::try_reuse: returns None when node overlaps damage" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let toks = test_tokenize(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    1,
    3,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="false")
}

///|
test "ReuseCursor::advance_past: updates current_offset" {
  let src = "1 + 2"
  let (old_tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let toks = test_tokenize(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  cursor.advance_past(old_tree)
  inspect(cursor.current_offset, content="5")
}

///|
test "new_follow_token: finds first non-trivia token at or after offset" {
  let src = "1 + 2"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let toks = test_tokenize(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let result = new_follow_token(cursor, 2)
  inspect(result, content="Some(Plus)")
}

///|
test "new_follow_token: skips leading trivia" {
  let src = "1 + 2"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let toks = test_tokenize(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let result = new_follow_token(cursor, 1)
  inspect(result, content="Some(Plus)")
}

///|
test "new_follow_token: returns None past end of tokens" {
  let src = "1 + 2"
  let (tree, _) = parse_with(src, test_spec, test_tokenize, test_grammar)
  let toks = test_tokenize(src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let result = new_follow_token(cursor, 5)
  inspect(result, content="None")
}

///|
test "LanguageSpec cst_token_matches callback is stored and callable" {
  let num_raw = test_kind_raw(KNum)
  let spec = LanguageSpec::new(
    fn(t) { t == TestTok::TokEof },
    fn(t) { t == TestTok::Ws },
    fn(a, b) { a == b },
    fn(t) { t.to_string() },
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    cst_token_matches=fn(raw, text, tok) {
      if raw != num_raw {
        return false
      }
      match tok {
        Num(n) => n.to_string() == text
        _ => false
      }
    },
  )
  inspect(
    (spec.cst_token_matches)(num_raw, "42", TestTok::Num(42)),
    content="true",
  )
  inspect(
    (spec.cst_token_matches)(num_raw, "42", TestTok::Num(99)),
    content="false",
  )
  inspect(
    (spec.cst_token_matches)(num_raw, "42", TestTok::Plus),
    content="false",
  )
}

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
  let toks = test_tokenize(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_with_placeholder,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
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
  let toks = test_tokenize(src)
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
    fn(i) { toks[i].start },
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
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message, content="expected number after +")
  inspect(ctx.errors[0].start, content="3")
  inspect(ctx.errors[0].end, content="3")
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
  let toks = test_tokenize(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_with_error,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
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
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message, content="reused syntax error")
  inspect(ctx.errors[0].start, content="3")
  inspect(ctx.errors[0].end, content="3")
}

///|
test "ParserContext reuse: excludes boundary diagnostics at reused node end" {
  fn grammar_two_nodes(ctx : ParserContext[TestTok, TestKind]) -> Unit {
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
    ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  }

  let src = "1 2"
  let toks = test_tokenize(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_two_nodes,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let old_diags = [
    {
      message: "inside-first-node",
      start: 0,
      end: 1,
      got_token: TestTok::Num(1),
    },
    {
      message: "boundary-next-sibling",
      start: 1,
      end: 1,
      got_token: TestTok::Ws,
    },
  ]
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_diags)
  ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message, content="inside-first-node")
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
  let toks = test_tokenize(src)
  let (old_tree, old_errors) = parse_with(
    src, test_spec, test_tokenize, grammar_eof_error_no_placeholder,
  )
  inspect(old_errors.length(), content="1")
  inspect(old_errors[0].start, content="1")
  inspect(old_errors[0].end, content="1")
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_errors)
  grammar_eof_error_no_placeholder(ctx)
  inspect(ctx.reuse_count, content="1")
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message, content="expected trailing token")
  inspect(ctx.errors[0].start, content="1")
  inspect(ctx.errors[0].end, content="1")
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
  let toks = test_tokenize(src)
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
    fn(i) { toks[i].start },
    test_spec,
  )

  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(old_errors)
  // First node should reuse; second node is at EOF and executes body.
  grammar_with_trailing_eof_error(ctx)

  inspect(ctx.reuse_count, content="1")
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message, content="missing trailing expression")
  inspect(ctx.errors[0].start, content="1")
  inspect(ctx.errors[0].end, content="1")
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
  let toks = test_tokenize(src)
  let (old_tree, _) = parse_with(
    src, test_spec, test_tokenize, grammar_with_trailing_eof_error,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { toks[i].start },
    test_spec,
  )
  // Simulate a replayed stale token payload for the same logical diagnostic.
  let stale_diags = [
    {
      message: "missing trailing expression",
      start: 1,
      end: 1,
      got_token: TestTok::Ws,
    },
  ]

  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  ctx.set_reuse_diagnostics(stale_diags)
  grammar_with_trailing_eof_error(ctx)

  inspect(ctx.reuse_count, content="1")
  inspect(ctx.errors.length(), content="1")
  inspect(ctx.errors[0].message, content="missing trailing expression")
  inspect(ctx.errors[0].got_token, content="TokEof")
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
  let new_toks = test_tokenize(new_src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0, // old damage start (replace "123")
    3, // old damage end
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_toks[i].start },
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
  let new_toks = test_tokenize(new_src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0, // old damage start (replace "1")
    1, // old damage end
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_toks[i].start },
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
  let new_toks = test_tokenize(new_src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    0, // first number changed from 1 -> 9
    1,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_toks[i].start },
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
  let new_toks = test_tokenize(new_src)
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    3, // old second token span [3,5) changed from 34 -> 3
    5,
    new_toks.length(),
    fn(i) { new_toks[i].token },
    fn(i) { new_toks[i].start },
    test_spec,
  )
  // Leading token matches (12), but follow token changed (34 -> 3), so reuse
  // must be rejected by trailing_context_matches.
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is None, content="true")
}
