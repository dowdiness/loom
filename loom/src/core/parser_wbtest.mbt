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
  let result : Result[TextRange, DiagnosticBuildError] = try? TextRange::from_offsets(
    start, end,
  )
  match result {
    Ok(range) => range
    Err(_) => abort("expected valid test range")
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

// Integration test: minimal two-token language (integers and '+')
// Kept in _wbtest.mbt so test types don't appear in pkg.generated.mbti.

///|
// Test language: integers and '+' only (with whitespace)
enum TestTok {
  Num(Int)
  Plus
  Ws
  TokEof
} derive(Eq, Debug)

///|
impl Show for TestTok with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
impl @seam.IsTrivia for TestTok with fn is_trivia(self) {
  self == Ws
}

///|
impl @seam.IsEof for TestTok with fn is_eof(self) {
  self == TokEof
}

///|
impl @seam.ToRawKind for TestTok with fn to_raw(self) {
  let n = match self {
    Num(_) => 0
    Plus => 1
    Ws => 4
    TokEof => 7
  }
  @seam.RawKind(n)
}

///|
enum TestKind {
  KNum
  KPlus
  KExpr
  KRoot
  KWs
  KErr
  KIncomplete
} derive(Debug)

///|
fn test_kind_raw(k : TestKind) -> @seam.RawKind {
  let n = match k {
    KNum => 0
    KPlus => 1
    KExpr => 2
    KRoot => 3
    KWs => 4
    KErr => 5
    KIncomplete => 6
  }
  @seam.RawKind(n)
}

///|
impl @seam.ToRawKind for TestKind with fn to_raw(self) {
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
      result.push({ token: TestTok::Ws, len: i - start })
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
      result.push({ token: TestTok::Num(n), len: i - start })
    } else if code == 43 {
      // '+'
      result.push({ token: TestTok::Plus, len: 1 })
      i = i + 1
    } else {
      i = i + 1
    }
  }
  result
}

///|
/// Tokenize and compute starts in one call.
fn test_tokenize_with_starts(
  src : String,
) -> (Array[TokenInfo[TestTok]], Array[Int]) {
  let toks = test_tokenize(src)
  let starts = build_starts(toks)
  (toks, starts)
}

///|
let test_spec : LanguageSpec[TestTok, TestKind] = {
  whitespace_kind: KWs,
  error_kind: KErr,
  incomplete_kind: KIncomplete,
  root_kind: KRoot,
  eof_token: TestTok::TokEof,
  parse_root: fn(_) { () },
  reuse_size_threshold: 64,
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
          if !ctx.at_eof() {
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
  inspect(errors.items()[0].message, content="expected number")
}

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
    trivia_kind=Some(test_spec.whitespace_kind.to_raw()),
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
    get_reparser: kind => {
      if kind == test_kind_raw(KExpr) {
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
