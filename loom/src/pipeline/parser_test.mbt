// Parser[Ast] tests.
//
// TestLang design (produces ImperativeLanguage directly so we can
// exercise Parser end-to-end):
// - Lex error: source starts with "@".
// - Successful parse builds a one-token CST whose token text is the
//   source length as a string — same-length sources parse to equal
//   SyntaxNodes so Eq-based backdating can be verified.
// - Ast = String: on success, the token text; on lex error, "error: <msg>".
//
// Memo reads in tests use `rt.read(memo)` — Memo::get() aborts when called
// outside a tracked context (i.e. outside another memo closure). The
// reactive attachment path (memo-inside-memo) is covered by the runtime
// test below.

///|
fn test_imperative_language() -> @incremental.ImperativeLanguage[String] {
  let last_diags : Ref[Array[String]] = { val: [] }
  let full_parse = fn(s : String) -> @incremental.ParseOutcome {
    match s {
      [.. "@", ..] => {
        last_diags.val = ["lex error: " + s]
        @incremental.ParseOutcome::LexError("lex error: " + s)
      }
      _ => {
        last_diags.val = []
        let cst = @seam.build_tree(
          [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
          @seam.RawKind(0),
        ) catch {
          _ => abort("build_tree failed in TestLang")
        }
        @incremental.ParseOutcome::Tree(@seam.SyntaxNode::from_cst(cst), 0)
      }
    }
  }
  // Tests don't exercise incremental reuse — fall through to full_parse.
  let incremental_parse = fn(
    s : String,
    _old : @seam.SyntaxNode,
    _edit : @core.Edit,
  ) -> @incremental.ParseOutcome {
    full_parse(s)
  }
  let to_ast = fn(n : @seam.SyntaxNode) -> String {
    match n.tokens() {
      [t, ..] => t.text()
      [] => ""
    }
  }
  let on_lex_error = fn(msg : String) -> String { "error: " + msg }
  let get_diagnostics = fn() -> Array[String] { last_diags.val.copy() }
  @incremental.ImperativeLanguage::new(
    full_parse~,
    incremental_parse~,
    to_ast~,
    on_lex_error~,
    get_diagnostics~,
  )
}

///|
test "Parser::new publishes initial source / ast / diagnostics" {
  let parser = Parser::new("hello", test_imperative_language())
  let rt = parser.runtime()
  inspect(rt.read(parser.source()), content="hello")
  inspect(rt.read(parser.ast()), content="5")
  inspect(rt.read(parser.diagnostics()), content="[]")
  guard rt.read(parser.syntax_tree()) is Some(_) else {
    abort("expected initial syntax tree")
  }
}

///|
test "Parser::set_source updates all four views atomically" {
  let parser = Parser::new("hi", test_imperative_language())
  let rt = parser.runtime()
  inspect(rt.read(parser.ast()), content="2")
  parser.set_source("world!")
  inspect(rt.read(parser.source()), content="world!")
  inspect(rt.read(parser.ast()), content="6")
  inspect(rt.read(parser.diagnostics()), content="[]")
}

///|
test "Parser::set_source routes lex failure to on_lex_error" {
  let parser = Parser::new("ok", test_imperative_language())
  let rt = parser.runtime()
  parser.set_source("@bad")
  inspect(rt.read(parser.source()), content="@bad")
  inspect(rt.read(parser.ast()), content="error: lex error: @bad")
  inspect(
    rt.read(parser.diagnostics()),
    content=(
      #|["lex error: @bad"]
    ),
  )
  guard rt.read(parser.syntax_tree()) is None else {
    abort("expected None after lex error")
  }
}

///|
test "Parser recovers from lex error on subsequent set_source" {
  let parser = Parser::new("ok", test_imperative_language())
  let rt = parser.runtime()
  parser.set_source("@bad")
  inspect(
    rt.read(parser.diagnostics()),
    content=(
      #|["lex error: @bad"]
    ),
  )
  parser.set_source("recovered")
  inspect(rt.read(parser.ast()), content="9")
  inspect(rt.read(parser.diagnostics()), content="[]")
  guard rt.read(parser.syntax_tree()) is Some(_) else {
    abort("expected syntax tree after recovery")
  }
}

///|
test "Parser::apply_edit advances source and ast" {
  let parser = Parser::new("abc", test_imperative_language())
  let rt = parser.runtime()
  inspect(rt.read(parser.ast()), content="3")
  // Replace the whole document via an Edit covering the full range.
  parser.apply_edit(@core.Edit::new(0, 3, 6), "abcdef")
  inspect(rt.read(parser.source()), content="abcdef")
  inspect(rt.read(parser.ast()), content="6")
}

///|
test "Parser exposes its runtime for downstream memos" {
  let parser = Parser::new("xy", test_imperative_language())
  let rt = parser.runtime()
  // A downstream memo reads parser.source() inside its closure and
  // establishes a dependency edge through the pass-through Memo view.
  let echo_memo : @incr.Memo[Int] = @incr.Memo::new(
    rt,
    fn() { parser.source().get().length() },
    label="echo-length",
  )
  inspect(rt.read(echo_memo), content="2")
  parser.set_source("hello")
  inspect(rt.read(echo_memo), content="5")
}

///|
/// Variant of `test_imperative_language` that increments `parse_count`
/// every time the engine runs a parse. Use this to observe short-circuit
/// behavior in `Parser::set_source` — identical sources should not
/// trigger a second parse.
fn test_imperative_language_with_counter(
  parse_count : Ref[Int],
) -> @incremental.ImperativeLanguage[String] {
  let full_parse = fn(s : String) -> @incremental.ParseOutcome {
    parse_count.val = parse_count.val + 1
    let cst = @seam.build_tree(
      [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
      @seam.RawKind(0),
    ) catch {
      _ => abort("build_tree failed in counter lang")
    }
    @incremental.ParseOutcome::Tree(@seam.SyntaxNode::from_cst(cst), 0)
  }
  @incremental.ImperativeLanguage::new(
    full_parse~,
    incremental_parse=(s, _old, _edit) => full_parse(s),
    to_ast=fn(n) {
      match n.tokens() {
        [t, ..] => t.text()
        [] => ""
      }
    },
    on_lex_error=fn(msg) { "error: " + msg },
    get_diagnostics=fn() { [] },
  )
}

///|
test "Parser::set_source is a no-op when source is unchanged" {
  // Editors / LSP flows routinely emit repeated identical snapshots.
  // Identity `set_source` must not rerun the engine — the engine still
  // holds the most recent tree, and tearing it down to reparse the same
  // text burns CPU and throws away incremental state for no gain.
  let parse_count : Ref[Int] = Ref::new(0)
  let parser = Parser::new(
    "abc",
    test_imperative_language_with_counter(parse_count),
  )
  // `Parser::new` primes the engine with one full parse.
  inspect(parse_count.val, content="1")
  parser.set_source("abc")
  inspect(parse_count.val, content="1")
  parser.set_source("abc")
  inspect(parse_count.val, content="1")
  // A real change still flows through.
  parser.set_source("abcd")
  inspect(parse_count.val, content="2")
  // And another identity after the change still short-circuits.
  parser.set_source("abcd")
  inspect(parse_count.val, content="2")
}
