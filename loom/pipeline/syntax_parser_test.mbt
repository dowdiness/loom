// SyntaxParser tests.
//
// The test language produces a one-token CST whose token text is the source
// length. It has no meaningful AST: `SyntaxParser` only publishes source,
// syntax, diagnostics, and reuse-count views.

///|
fn syntax_test_language() -> @incremental.ImperativeLanguage[Unit] {
  let full_parse = fn(
    s : String,
  ) -> (@seam.SyntaxNode, @core.DiagnosticSet, Int) {
    let cst = @seam.build_tree(
      [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
      @seam.RawKind(0),
    ) catch {
      _ => abort("build_tree failed in syntax test language")
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
  let incremental_parse = fn(
    s : String,
    _old : @seam.SyntaxNode,
    _edit : @core.Edit,
  ) -> (@seam.SyntaxNode, @core.DiagnosticSet, Int) {
    let (syntax, diagnostics, _) = full_parse(s)
    (syntax, diagnostics, 1)
  }
  @incremental.ImperativeLanguage::new(full_parse~, incremental_parse~, to_ast=fn(
    _syntax,
  ) {
    ()
  })
}

///|
test "SyntaxParser::new publishes initial source / syntax / diagnostics" {
  let parser = SyntaxParser::new("hello", syntax_test_language())
  inspect(parser.source().read_or_abort(), content="hello")
  debug_inspect(parser.diagnostics().read_or_abort().format(), content="[]")
  inspect(parser.snapshot().read_or_abort().source, content="hello")
  inspect(parser.snapshot().read_or_abort().reuse_count, content="0")
  ignore(parser.syntax_tree().read_or_abort())
}

///|
test "SyntaxParser::set_source updates syntax and diagnostics" {
  let parser = SyntaxParser::new("ok", syntax_test_language())
  parser.set_source("@bad")
  inspect(parser.source().read_or_abort(), content="@bad")
  debug_inspect(
    parser.diagnostics().read_or_abort().format(),
    content=(
      #|["lex error: @bad"]
    ),
  )
  parser.set_source("recovered")
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  ignore(parser.syntax_tree().read_or_abort())
}

///|
test "SyntaxParser::apply_edit advances source and reuse count" {
  let parser = SyntaxParser::new("abc", syntax_test_language())
  parser.apply_edit(@core.Edit::new(0, 3, 6), "abcdef")
  inspect(parser.source().read_or_abort(), content="abcdef")
  inspect(parser.snapshot().read_or_abort().reuse_count, content="1")
}

///|
test "SyntaxParser::diagnostics is isolated from snapshot diagnostic mutation" {
  let parser = SyntaxParser::new("abc", syntax_test_language())
  let snapshot = parser.snapshot().read_or_abort()
  snapshot.diagnostics.push(@core.Diagnostic::lexer_error("external mutation"))
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
}

///|
test "SyntaxParser exposes its runtime for downstream derived cells" {
  let parser = SyntaxParser::new("xy", syntax_test_language())
  let rt = parser.runtime()
  let echo_derived : @incr.Derived[Int] = @incr.Derived(
    rt,
    fn() { parser.source().get_or_abort().length() },
    label="syntax-echo-length",
  )
  inspect(echo_derived.read_or_abort(), content="2")
  parser.set_source("hello")
  inspect(echo_derived.read_or_abort(), content="5")
}

///|
fn syntax_test_language_with_counter(
  parse_count : Ref[Int],
) -> @incremental.ImperativeLanguage[Unit] {
  let full_parse = fn(
    s : String,
  ) -> (@seam.SyntaxNode, @core.DiagnosticSet, Int) {
    parse_count.val = parse_count.val + 1
    let cst = @seam.build_tree(
      [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
      @seam.RawKind(0),
    ) catch {
      _ => abort("build_tree failed in syntax counter language")
    }
    (@seam.SyntaxNode::from_cst(cst), @core.DiagnosticSet::empty(), 0)
  }
  @incremental.ImperativeLanguage::new(
    full_parse~,
    incremental_parse=(s, _old, _edit) => full_parse(s),
    to_ast=fn(_syntax) { () },
  )
}

///|
test "SyntaxParser::set_source is a no-op when source is unchanged" {
  let parse_count : Ref[Int] = Ref(0)
  let parser = SyntaxParser::new(
    "abc",
    syntax_test_language_with_counter(parse_count),
  )
  inspect(parse_count.val, content="1")
  parser.set_source("abc")
  inspect(parse_count.val, content="1")
  parser.set_source("abcd")
  inspect(parse_count.val, content="2")
  parser.set_source("abcd")
  inspect(parse_count.val, content="2")
}
