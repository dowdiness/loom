// Whitebox tests for the core parser — ParserContext, LanguageSpec, ReuseCursor.
// These tests access package-private symbols (e.g. new_follow_token_with_pos) and define
// test-only types (TestTok, TestKind) that must not appear in the public interface.

///|
test "TokenInfo stores token with length" {
  let info : TokenInfo[String] = { token: "hello", len: 5 }
  inspect(info.len, content="5")
  inspect(info.token, content="hello")
}

///|
test "Diagnostic stores message and primary range" {
  let range = test_range_or_abort(3, 7)
  let d = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    message="unexpected token",
    primary=Some(range),
  )
  inspect(d.message, content="unexpected token")
  inspect(d.format(), content="unexpected token [3,7]")
}

///|
fn test_range_or_abort(start : Int, end : Int) -> TextRange {
  try TextRange::from_offsets(start, end) catch {
    _ => abort("expected valid test range")
  } noraise {
    range => range
  }
}

///|
fn test_parser_diagnostic(
  message : String,
  start : Int,
  end : Int,
  token : TestTok,
) -> Diagnostic {
  let range = test_range_or_abort(start, end)
  Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    message~,
    primary=Some(range),
    token=Some({ kind: token.to_raw(), range }),
  )
}

///|
fn diagnostic_start(diagnostic : Diagnostic) -> Int {
  match diagnostic.primary {
    Some(range) => range.start().value()
    None => abort("expected diagnostic primary range")
  }
}

///|
fn diagnostic_end(diagnostic : Diagnostic) -> Int {
  match diagnostic.primary {
    Some(range) => range.end().value()
    None => abort("expected diagnostic primary range")
  }
}

///|
fn diagnostic_token_raw(diagnostic : Diagnostic) -> Int {
  match diagnostic.token {
    Some(evidence) => {
      let @seam.RawKind(kind) = evidence.kind
      kind
    }
    None => abort("expected diagnostic token evidence")
  }
}

///|
fn diagnostic_token_start(diagnostic : Diagnostic) -> Int {
  match diagnostic.token {
    Some(evidence) => evidence.range.start().value()
    None => abort("expected diagnostic token evidence")
  }
}

///|
fn diagnostic_token_end(diagnostic : Diagnostic) -> Int {
  match diagnostic.token {
    Some(evidence) => evidence.range.end().value()
    None => abort("expected diagnostic token evidence")
  }
}

///|
fn diagnostic_code_value(diagnostic : Diagnostic) -> String {
  match diagnostic.code {
    Some(code) => code.value()
    None => abort("expected diagnostic code")
  }
}

///|
fn find_diagnostic_by_message(
  diagnostics : DiagnosticSet,
  message : String,
) -> Diagnostic {
  for diagnostic in diagnostics.items() {
    if diagnostic.message == message {
      return diagnostic
    }
  }
  abort("expected diagnostic with message: " + message)
}

///|
fn has_diagnostic_message(
  diagnostics : DiagnosticSet,
  message : String,
) -> Bool {
  diagnostics.items().iter().any(diagnostic => diagnostic.message == message)
}

///|
fn make_test_fixtures() -> (
  LanguageSpec[TestTok, TestKind],
  Array[TokenInfo[TestTok]],
) {
  let spec : LanguageSpec[TestTok, TestKind] = {
    whitespace_kind: KWs,
    error_kind: KErr,
    incomplete_kind: KErr,
    root_kind: KRoot,
    eof_token: TestTok::TokEof,
    parse_root: _ => (),
    reuse_size_threshold: 64,
    trivia_kinds_spec: [KWs],
  }
  let tokens = [
    { token: TestTok::Plus, len: 1 },
    { token: TestTok::Num(42), len: 2 },
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
test "lex_mode defaults to 0" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect(ctx.lex_mode(), content="0")
}

///|
test "set_lex_mode updates the current lex mode" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  ctx.set_lex_mode(3)
  inspect(ctx.lex_mode(), content="3")
}

///|
test "checkpoint/restore preserves lex mode" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  ctx.set_lex_mode(7)
  let cp = ctx.checkpoint()
  ctx.set_lex_mode(42)
  ctx.restore(cp)
  inspect(ctx.lex_mode(), content="7")
}

///|
test "lookahead: restores lex mode and preserves callback result" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  ctx.set_lex_mode(7)
  let result = ctx.lookahead(() => {
    ctx.set_lex_mode(42)
    "observed"
  })
  inspect(result, content="observed")
  inspect(ctx.lex_mode(), content="7")
}

///|
test "peek returns current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect(ctx.peek(), content="Plus")
}

///|
test "peek returns eof when past end" {
  let (spec, _) = make_test_fixtures()
  let ctx = ParserContext::new([], "", spec)
  inspect(ctx.peek(), content="TokEof")
}

///|
// Relocated from examples/lambda (loom#251): exercises core's finish_node
// underflow guard via the private open_nodes counter, so it belongs to core.
test "finish_node without matching start_node is ignored" {
  let (spec, _) = make_test_fixtures()
  let ctx = ParserContext::new([], "", spec)
  ctx.finish_node()
  inspect(ctx.open_nodes, content="0")
}

///|
test "token_text_at returns token text and empty string for invalid index" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  inspect(ctx.token_text_at(0), content="+")
  inspect(ctx.token_text_at(1), content="42")
  inspect(ctx.token_text_at(-1), content="")
  inspect(ctx.token_text_at(2), content="")
}

///|
test "token_text_at handles lone surrogate without crash" {
  // Lone high surrogate (0xD800) — invalid UTF-16 but possible in CRDT text
  let surrogate = (0xD800).unsafe_to_char().to_string()
  let source = "a" + surrogate + "b"
  let (spec, _) = make_test_fixtures()
  let tokens : Array[TokenInfo[TestTok]] = [
    { token: TestTok::Plus, len: 1 }, // "a"
    { token: TestTok::Plus, len: 1 }, // surrogate
    { token: TestTok::Plus, len: 1 }, // "b"
  ]
  let ctx = ParserContext::new(tokens, source, spec)
  // Must not crash — preserves the exact code unit round-trip
  inspect(ctx.token_text_at(0), content="a")
  let surrogate_text = ctx.token_text_at(1)
  inspect(surrogate_text.length(), content="1")
  inspect(surrogate_text == surrogate, content="true")
  inspect(surrogate_text.code_unit_at(0).to_int(), content="55296") // 0xD800
  inspect(ctx.token_text_at(2), content="b")
}

///|
test "token_text_at handles token spans that split surrogate pairs" {
  let source = "😀"
  let (spec, _) = make_test_fixtures()
  let tokens : Array[TokenInfo[TestTok]] = [
    { token: TestTok::Plus, len: 1 },
    { token: TestTok::Plus, len: 1 },
  ]
  let ctx = ParserContext::new(tokens, source, spec)
  let high = ctx.token_text_at(0)
  let low = ctx.token_text_at(1)
  inspect(high.length(), content="1")
  inspect(high.code_unit_at(0).to_int(), content="55357")
  inspect(low.length(), content="1")
  inspect(low.code_unit_at(0).to_int(), content="56832")
}

///|
test "current_token_text and current_token_range skip trivia" {
  let src = "  42"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.current_token_text(), content="42")
  let range = ctx.current_token_range()
  inspect(range.start, content="2")
  inspect(range.end, content="4")
  ctx.emit_token(KNum)
  inspect(ctx.current_token_text(), content="")
  let eof_range = ctx.current_token_range()
  inspect(eof_range.start, content="4")
  inspect(eof_range.end, content="4")
}

///|
test "ParserContext::too_many_errors tracks parser diagnostics" {
  let src = "+"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  inspect(ctx.too_many_errors(1), content="false")
  ctx.report_expected(expected="number")
  inspect(ctx.too_many_errors(1), content="true")
  inspect(ctx.too_many_errors(2), content="false")
}

///|
test "emit_current_token uses token raw kind" {
  let (tree, errors) = parse_with(" +", test_spec, test_tokenize, fn(ctx) {
    ctx.emit_current_token()
  })
  inspect(errors.length(), content="0")
  let root = @seam.SyntaxNode::from_cst(tree)
  guard root.find_token(@seam.RawKind(1)) is Some(token) else {
    fail("expected emitted plus token")
  }
  inspect(token.text(), content="+")
}

///|
test "ParserContext::report records explicit structured diagnostic" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.report_error(
    message="manual parser diagnostic",
    code=Some(DiagnosticCode("parse.manual")),
    range=Some(test_range_or_abort(0, 1)),
  )
  inspect(ctx.diagnostics.length(), content="1")
  let diagnostic = ctx.diagnostics.items()[0]
  inspect(diagnostic.message, content="manual parser diagnostic")
  inspect(diagnostic_code_value(diagnostic), content="parse.manual")
  inspect(diagnostic_start(diagnostic), content="0")
  inspect(diagnostic_end(diagnostic), content="1")
  inspect(diagnostic.token is None, content="true")
}

///|
test "ParserContext::report_at_current attaches current token evidence" {
  let src = "  +"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.report_at_current(
    message="current token diagnostic",
    code=Some(DiagnosticCode("parse.current")),
  )
  inspect(ctx.diagnostics.length(), content="1")
  let diagnostic = ctx.diagnostics.items()[0]
  inspect(diagnostic.message, content="current token diagnostic")
  inspect(diagnostic_code_value(diagnostic), content="parse.current")
  inspect(diagnostic_start(diagnostic), content="2")
  inspect(diagnostic_end(diagnostic), content="3")
  inspect(diagnostic_token_raw(diagnostic), content="1")
  inspect(diagnostic_token_start(diagnostic), content="2")
  inspect(diagnostic_token_end(diagnostic), content="3")
}

///|
test "ParserContext::report_at_current attaches EOF token evidence" {
  let src = "1"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.emit_token(KNum)
  ctx.report_at_current(
    message="missing trailing expression",
    code=Some(DiagnosticCode("parse.eof")),
  )
  inspect(ctx.diagnostics.length(), content="1")
  let diagnostic = ctx.diagnostics.items()[0]
  inspect(diagnostic_code_value(diagnostic), content="parse.eof")
  inspect(diagnostic_start(diagnostic), content="1")
  inspect(diagnostic_end(diagnostic), content="1")
  inspect(diagnostic_token_raw(diagnostic), content="7")
  inspect(diagnostic_token_start(diagnostic), content="1")
  inspect(diagnostic_token_end(diagnostic), content="1")
}

///|
test "ParserContext::report_expected uses current token evidence" {
  let src = "+"
  let toks = test_tokenize(src)
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.report_expected(
    expected="number",
    code=Some(DiagnosticCode("parse.expected.number")),
  )
  inspect(ctx.diagnostics.length(), content="1")
  let diagnostic = ctx.diagnostics.items()[0]
  inspect(diagnostic.message, content="expected number")
  inspect(diagnostic_code_value(diagnostic), content="parse.expected.number")
  inspect(diagnostic_start(diagnostic), content="0")
  inspect(diagnostic_end(diagnostic), content="1")
  inspect(diagnostic_token_raw(diagnostic), content="1")
}

///|
test "peek skips trivia tokens" {
  let (spec, _) = make_test_fixtures()
  let tokens : Array[TokenInfo[TestTok]] = [
    { token: TestTok::Ws, len: 1 },
    { token: TestTok::Ws, len: 1 },
    { token: TestTok::Plus, len: 1 },
  ]
  let ctx = ParserContext::new(tokens, "  +", spec)
  inspect(ctx.peek(), content="Plus")
}

///|
test "at matches current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  inspect(ctx.at(TestTok::Plus), content="true")
  inspect(ctx.at(TestTok::Num(42)), content="false")
}

///| Assert that the current open node kind equals `expected`.

///|
/// Fails with a descriptive message on mismatch or when no node is open.
fn assert_current_kind(
  ctx : ParserContext[TestTok, TestKind],
  expected : TestKind,
) -> Unit {
  match ctx.current_node_kind() {
    Some(k) =>
      if k.to_raw() != test_kind_raw(expected) {
        abort(
          "expected current node kind " +
          @debug.to_string(expected) +
          ", got " +
          @debug.to_string(k.to_raw()),
        )
      }
    None =>
      abort(
        "expected current node kind " +
        @debug.to_string(expected) +
        ", got None",
      )
  }
}

///|
/// Assert that no node is currently open.
fn assert_no_current_kind(ctx : ParserContext[TestTok, TestKind]) -> Unit {
  match ctx.current_node_kind() {
    None => ()
    Some(k) =>
      abort("expected no open node, got " + @debug.to_string(k.to_raw()))
  }
}
// ─── current_node_kind ─────────────────────────────────────────────────────────

///|
test "current_node_kind: returns None when no nodes open" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  assert_no_current_kind(ctx)
}

///|
test "current_node_kind: returns Some(kind) after start_node" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KExpr)
  assert_current_kind(ctx, KExpr)
}

///|
test "current_node_kind: returns innermost node kind with nesting" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  ctx.start_node(KNum)
  assert_current_kind(ctx, KNum)
}

///|
test "current_node_kind: returns parent kind after finish_node" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  ctx.finish_node()
  assert_current_kind(ctx, KRoot)
}

///|
test "current_node_kind: returns None after all nodes finished" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.finish_node()
  assert_no_current_kind(ctx)
}

///|
test "current_node_kind: preserves full stack after checkpoint/restore" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  let cp = ctx.checkpoint()
  ctx.start_node(KNum)
  ctx.finish_node() // finishes KNum
  ctx.restore(cp)
  assert_current_kind(ctx, KExpr)
  ctx.finish_node()
  assert_current_kind(ctx, KRoot)
}

// ─── peek_index ────────────────────────────────────────────────────────────────

///|
test "peek_index(0): returns current raw token including trivia" {
  let (spec, _) = make_test_fixtures()
  let tokens : Array[TokenInfo[TestTok]] = [
    { token: TestTok::Ws, len: 1 },
    { token: TestTok::Plus, len: 1 },
  ]
  // peek() skips trivia, peek_index(0) doesn't
  let ctx = ParserContext::new(tokens, " +", spec)
  inspect(ctx.peek(), content="Plus")
  inspect(ctx.peek_index(0), content="Ws")
}

///|
test "peek_index(1): returns next raw token" {
  let (spec, _) = make_test_fixtures()
  let tokens : Array[TokenInfo[TestTok]] = [
    { token: TestTok::Ws, len: 1 },
    { token: TestTok::Plus, len: 1 },
    { token: TestTok::Num(42), len: 2 },
  ]
  let ctx = ParserContext::new(tokens, " +42", spec)
  inspect(ctx.peek_index(1), content="Plus")
  inspect(ctx.peek_index(2), content="Num(42)")
}

///|
test "peek_index(3) past end returns eof_token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  inspect(ctx.peek_index(3), content="TokEof")
}

///|
test "peek_index(-1): negative n returns token at current position" {
  let (spec, _) = make_test_fixtures()
  let tokens : Array[TokenInfo[TestTok]] = [
    { token: TestTok::Ws, len: 1 },
    { token: TestTok::Plus, len: 1 },
  ]
  let ctx = ParserContext::new(tokens, " +", spec)
  // Negative n is clamped to 0, so peek_index(-1) == peek_index(0)
  inspect(ctx.peek_index(-1), content="Ws")
  inspect(ctx.peek_index(0), content="Ws")
}

///|
test "peek_index(0) same as peek for non-trivia current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  // When current raw token is non-trivia, peek and peek_index(0) agree
  inspect(ctx.peek(), content="Plus")
  inspect(ctx.peek_index(0), content="Plus")
}

///|
test "peek_index returns trivia tokens that peek skips" {
  let (spec, _) = make_test_fixtures()
  let tokens : Array[TokenInfo[TestTok]] = [
    { token: TestTok::Ws, len: 2 },
    { token: TestTok::Ws, len: 1 },
    { token: TestTok::Plus, len: 1 },
    { token: TestTok::Ws, len: 1 },
    { token: TestTok::Num(42), len: 2 },
  ]
  let ctx = ParserContext::new(tokens, "  + 42", spec)
  // peek_index shows raw positions: [Ws, Ws, Plus, Ws, Num(42)]
  // peek skips trivia and is at Plus immediately
  inspect(ctx.peek(), content="Plus")
  inspect(ctx.peek_index(0), content="Ws")
  inspect(ctx.peek_index(1), content="Ws")
  inspect(ctx.peek_index(2), content="Plus")
  inspect(ctx.peek_index(3), content="Ws")
  inspect(ctx.peek_index(4), content="Num(42)")
}

// ─── finish_nodes_until ────────────────────────────────────────────────────────

///|
test "finish_nodes_until: returns true when current node matches" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  // Current node is KExpr — finish_nodes_until(KExpr) should match it
  // and finish nothing above it
  let found = ctx.finish_nodes_until(KExpr)
  inspect(found, content="true")
  // KExpr is matched but NOT closed — the matching node is preserved
  assert_current_kind(ctx, KExpr)
  ctx.finish_node() // close KExpr
  assert_current_kind(ctx, KRoot)
}

///|
test "finish_nodes_until: returns true when ancestor matches" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  ctx.start_node(KNum)
  // Finish nodes until KExpr — should close KNum, keep KExpr and KRoot
  let found = ctx.finish_nodes_until(KExpr)
  inspect(found, content="true")
  // KExpr is preserved, KNum was closed
  assert_current_kind(ctx, KExpr)
}

///|
test "finish_nodes_until: returns false when kind not in ancestor chain" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  ctx.start_node(KNum)
  // KPlus is not in the ancestor chain — returns false after closing all nodes
  let found = ctx.finish_nodes_until(KPlus)
  inspect(found, content="false")
  // All nodes were exhausted without finding KPlus
  inspect(ctx.open_nodes, content="0")
  assert_no_current_kind(ctx)
}

///|
test "finish_nodes_until: returns false when no nodes open" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  let found = ctx.finish_nodes_until(KRoot)
  inspect(found, content="false")
  inspect(ctx.open_nodes, content="0")
}

///|
test "finish_nodes_until: closes all nodes above match, preserves matching" {
  // Deep nesting: KRoot → KExpr → KNum → KPlus → KWs
  // finish_nodes_until(KExpr) should close KWs, KPlus, KNum
  // and leave KExpr and KRoot open
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  ctx.start_node(KNum)
  ctx.start_node(KPlus)
  ctx.start_node(KWs)
  let found = ctx.finish_nodes_until(KExpr)
  inspect(found, content="true")
  // KExpr is preserved
  assert_current_kind(ctx, KExpr)
}

///|
test "finish_nodes_until: combined with checkpoint restores node stack" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  let cp = ctx.checkpoint()
  // Speculative: start some nodes, try to finish until KRoot
  ctx.start_node(KNum)
  ctx.start_node(KPlus)
  let found = ctx.finish_nodes_until(KRoot)
  inspect(found, content="true")
  // Restore — node_stack should be reconstructed correctly
  ctx.restore(cp)
  assert_current_kind(ctx, KExpr)
  ctx.finish_node()
  assert_current_kind(ctx, KRoot)
}

///|
test "finish_nodes_until: lookahead restores node stack" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  let found = ctx.lookahead(() => {
    // Start some nodes, then finish until KRoot.
    ctx.start_node(KNum)
    ctx.start_node(KPlus)
    ctx.finish_nodes_until(KRoot)
  })
  inspect(found, content="true")
  assert_current_kind(ctx, KExpr)
  ctx.finish_node()
  assert_current_kind(ctx, KRoot)
}

// ─── finish_nodes_until_inclusive ───────────────────────────────────────────────

///|
test "finish_nodes_until_inclusive: closes current matching node" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  // KExpr matches — finish_nodes_until_inclusive should close it
  let found = ctx.finish_nodes_until_inclusive(KExpr)
  inspect(found, content="true")
  // KExpr was closed — KRoot is now the current node
  assert_current_kind(ctx, KRoot)
  ctx.finish_node()
  assert_no_current_kind(ctx)
}

///|
test "finish_nodes_until_inclusive: closes ancestor and all nodes above" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  ctx.start_node(KNum)
  ctx.start_node(KPlus)
  // KExpr matches — closes KPlus, KNum, and KExpr itself
  let found = ctx.finish_nodes_until_inclusive(KExpr)
  inspect(found, content="true")
  // KRoot is now the only open node
  assert_current_kind(ctx, KRoot)
}

///|
test "finish_nodes_until_inclusive: closes root node when it matches" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  ctx.start_node(KNum)
  // KRoot matches — closes KNum, KExpr, and KRoot
  let found = ctx.finish_nodes_until_inclusive(KRoot)
  inspect(found, content="true")
  inspect(ctx.open_nodes, content="0")
  assert_no_current_kind(ctx)
}

///|
test "finish_nodes_until_inclusive: returns false when kind not found" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  ctx.start_node(KRoot)
  ctx.start_node(KExpr)
  ctx.start_node(KNum)
  let found = ctx.finish_nodes_until_inclusive(KPlus)
  inspect(found, content="false")
  // All nodes were exhausted
  inspect(ctx.open_nodes, content="0")
  assert_no_current_kind(ctx)
}

///|
test "finish_nodes_until_inclusive: returns false when no nodes open" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "+42", spec)
  let found = ctx.finish_nodes_until_inclusive(KRoot)
  inspect(found, content="false")
  inspect(ctx.open_nodes, content="0")
}

///|
struct FooView {
  node : @seam.SyntaxNode
}

///|
impl AstView for FooView with fn syntax_node(self) {
  self.node
}

///|
test "AstView: a concrete impl exposes its SyntaxNode" {
  let cst = @seam.CstNode::new(@seam.RawKind(0), [])
  let syn = @seam.SyntaxNode::from_cst(cst)
  let v : FooView = { node: syn }
  inspect(v.syntax_node() == syn, content="true")
}
