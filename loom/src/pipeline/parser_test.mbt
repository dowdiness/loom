// Parser[Ast] tests.
//
// TestLang design (produces ImperativeLanguage directly so we can
// exercise Parser end-to-end):
// - Lexer diagnostic: source starts with "@".
// - Successful parse builds a one-token CST whose token text is the
//   source length as a string — same-length sources parse to equal
//   SyntaxNodes so Eq-based backdating can be verified.
// - Ast = String: the token text.
//
// Derived reads in tests use `read_or_abort()` outside the graph. Inside
// another Derived closure, use `get_or_abort()` so the dependency is tracked
// without allocating a one-shot watch. The reactive attachment path
// (derived-inside-derived) is covered by the runtime test below.

///|
fn test_imperative_language() -> @incremental.ImperativeLanguage[String] {
  let full_parse = fn(
    s : String,
  ) -> (@seam.SyntaxNode, @core.DiagnosticSet, Int) {
    let cst = @seam.build_tree(
      [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
      @seam.RawKind(0),
    ) catch {
      _ => abort("build_tree failed in TestLang")
    }
    let diagnostics = match s {
      [.. "@", ..] =>
        @core.DiagnosticSet::single(
          @core.Diagnostic::lexer_error("lex error: " + s),
        )
      _ => @core.DiagnosticSet::empty()
    }
    (@seam.SyntaxNode::from_cst(cst), diagnostics, 0)
  }
  // Tests don't exercise incremental reuse — fall through to full_parse.
  let incremental_parse = fn(
    s : String,
    _old : @seam.SyntaxNode,
    _edit : @core.Edit,
  ) -> (@seam.SyntaxNode, @core.DiagnosticSet, Int) {
    full_parse(s)
  }
  let to_ast = fn(n : @seam.SyntaxNode) -> String {
    match n.tokens() {
      [t, ..] => t.text()
      [] => ""
    }
  }
  @incremental.ImperativeLanguage::new(full_parse~, incremental_parse~, to_ast~)
}

///|
test "Parser::new publishes initial source / ast / diagnostics" {
  let parser = Parser::new("hello", test_imperative_language())
  inspect(parser.source().read_or_abort(), content="hello")
  inspect(parser.ast().read_or_abort(), content="5")
  debug_inspect(parser.diagnostics().read_or_abort().format(), content="[]")
  inspect(parser.snapshot().read_or_abort().source, content="hello")
  ignore(parser.syntax_tree().read_or_abort())
}

///|
test "Parser::set_source updates all four views atomically" {
  let parser = Parser::new("hi", test_imperative_language())
  inspect(parser.ast().read_or_abort(), content="2")
  parser.set_source("world!")
  inspect(parser.source().read_or_abort(), content="world!")
  inspect(parser.ast().read_or_abort(), content="6")
  debug_inspect(parser.diagnostics().read_or_abort().format(), content="[]")
}

///|
test "Parser::set_source publishes lexer diagnostics with recovered syntax" {
  let parser = Parser::new("ok", test_imperative_language())
  parser.set_source("@bad")
  inspect(parser.source().read_or_abort(), content="@bad")
  inspect(parser.ast().read_or_abort(), content="4")
  debug_inspect(
    parser.diagnostics().read_or_abort().format(),
    content=(
      #|["lex error: @bad"]
    ),
  )
  ignore(parser.syntax_tree().read_or_abort())
}

///|
test "Parser recovers diagnostics on subsequent set_source" {
  let parser = Parser::new("ok", test_imperative_language())
  parser.set_source("@bad")
  debug_inspect(
    parser.diagnostics().read_or_abort().format(),
    content=(
      #|["lex error: @bad"]
    ),
  )
  parser.set_source("recovered")
  inspect(parser.ast().read_or_abort(), content="9")
  debug_inspect(parser.diagnostics().read_or_abort().format(), content="[]")
  ignore(parser.syntax_tree().read_or_abort())
}

///|
test "Parser::apply_edit advances source and ast" {
  let parser = Parser::new("abc", test_imperative_language())
  inspect(parser.ast().read_or_abort(), content="3")
  // Replace the whole document via an Edit covering the full range.
  parser.apply_edit(@core.Edit::new(0, 3, 6), "abcdef")
  inspect(parser.source().read_or_abort(), content="abcdef")
  inspect(parser.ast().read_or_abort(), content="6")
}

///|
test "Parser::diagnostics is isolated from snapshot diagnostic mutation" {
  let parser = Parser::new("abc", test_imperative_language())
  let snapshot = parser.snapshot().read_or_abort()
  snapshot.diagnostics.push(@core.Diagnostic::lexer_error("external mutation"))
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
}

///|
test "Parser exposes its runtime for downstream derived cells" {
  let parser = Parser::new("xy", test_imperative_language())
  let rt = parser.runtime()
  // A downstream derived cell reads parser.source() inside its closure and
  // establishes a dependency edge through the pass-through Derived view.
  let echo_derived : @incr.Derived[Int] = @incr.Derived::Derived(
    rt,
    fn() { parser.source().get_or_abort().length() },
    label="echo-length",
  )
  inspect(echo_derived.read_or_abort(), content="2")
  parser.set_source("hello")
  inspect(echo_derived.read_or_abort(), content="5")
}

///|
/// Variant of `test_imperative_language` that increments `parse_count`
/// every time the engine runs a parse. Use this to observe short-circuit
/// behavior in `Parser::set_source` — identical sources should not
/// trigger a second parse.
fn test_imperative_language_with_counter(
  parse_count : Ref[Int],
) -> @incremental.ImperativeLanguage[String] {
  let full_parse = fn(
    s : String,
  ) -> (@seam.SyntaxNode, @core.DiagnosticSet, Int) {
    parse_count.val = parse_count.val + 1
    let cst = @seam.build_tree(
      [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
      @seam.RawKind(0),
    ) catch {
      _ => abort("build_tree failed in counter lang")
    }
    (@seam.SyntaxNode::from_cst(cst), @core.DiagnosticSet::empty(), 0)
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
  )
}

///|
test "Parser::set_source is a no-op when source is unchanged" {
  // Editors / LSP flows routinely emit repeated identical snapshots.
  // Identity `set_source` must not rerun the engine — the engine still
  // holds the most recent tree, and tearing it down to reparse the same
  // text burns CPU and throws away incremental state for no gain.
  let parse_count : Ref[Int] = Ref(0)
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
