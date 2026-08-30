// SyntaxParser tests.
//
// The test language produces a one-token CST whose token text is the source
// length. It has no meaningful AST: `SyntaxParser` only publishes source,
// syntax, diagnostics, and reuse-count views.

///|
#warnings("-unused_error_type")
fn syntax_test_language() -> @incremental.ImperativeLanguage[Unit] {
  let full_parse = fn(_source_id : @core.SourceId, s : String) raise Failure {
    let cst = @seam.build_tree(
      [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
      @seam.RawKind(0),
      policy=@seam.CstMetadataPolicy::unclassified(),
    ) catch {
      _ => abort("build_tree failed in syntax test language")
    }
    let diagnostics = match s {
      [.. "@", ..] =>
        @core.DiagnosticSet::single(@core.lexer_diagnostic("lex error: " + s))
      _ => @core.DiagnosticSet::empty()
    }
    (@seam.SyntaxNode::from_cst(cst), diagnostics, 0)
  }
  let incremental_parse = fn(
    source_id : @core.SourceId,
    s : String,
    _old : @seam.SyntaxNode,
    _edit : @core.Edit,
  ) raise Failure {
    let (syntax, diagnostics, _) = full_parse(source_id, s)
    (syntax, diagnostics, 1)
  }
  @incremental.ImperativeLanguage::new(full_parse~, incremental_parse~, to_ast=_syntax => {
    ()
  })
}

///|
test "SyntaxParser::new publishes initial source / syntax / diagnostics" {
  let source_id = @core.SourceId("pipeline-syntax-initial-source")
  let parser = SyntaxParser::new(source_id, "hello", syntax_test_language())
  inspect(parser.source().read_or_abort(), content="hello")
  debug_inspect(parser.diagnostics().read_or_abort().format(), content="[]")
  let snapshot = parser.snapshot().read_or_abort()
  inspect(snapshot.source_id.value(), content="pipeline-syntax-initial-source")
  inspect(snapshot.source, content="hello")
  inspect(snapshot.reuse_count, content="0")
  inspect(
    snapshot.copy().source_id.value(),
    content="pipeline-syntax-initial-source",
  )
  ignore(parser.syntax_tree().read_or_abort())
}

///|
test "SyntaxParser::set_source updates syntax and diagnostics" {
  let source_id = @core.SourceId("pipeline-syntax-update-source")
  let parser = SyntaxParser::new(source_id, "ok", syntax_test_language())
  parser.set_source("@bad")
  inspect(parser.source().read_or_abort(), content="@bad")
  inspect(
    parser.snapshot().read_or_abort().source_id.value(),
    content="pipeline-syntax-update-source",
  )
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
  let source_id = @core.SourceId("pipeline-syntax-edit-source")
  let parser = SyntaxParser::new(source_id, "abc", syntax_test_language())
  parser.apply_edit(@core.Edit::new(0, 3, 6), "abcdef")
  inspect(parser.source().read_or_abort(), content="abcdef")
  inspect(
    parser.snapshot().read_or_abort().source_id.value(),
    content="pipeline-syntax-edit-source",
  )
  inspect(parser.snapshot().read_or_abort().reuse_count, content="1")
}

///|
test "SyntaxParser::diagnostics is isolated from snapshot diagnostic mutation" {
  let source_id = @core.SourceId("pipeline-syntax-defensive-source")
  let parser = SyntaxParser::new(source_id, "abc", syntax_test_language())
  let snapshot = parser.snapshot().read_or_abort()
  snapshot.diagnostics.push(@core.lexer_diagnostic("external mutation"))
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
}

///|
test "SyntaxParser exposes its runtime for downstream derived cells" {
  let source_id = @core.SourceId("pipeline-syntax-runtime-source")
  let parser = SyntaxParser::new(source_id, "xy", syntax_test_language())
  let rt = parser.runtime()
  let echo_derived : @incr.Derived[Int] = @incr.Derived(
    rt,
    () => parser.source().get_or_abort().length(),
    label="syntax-echo-length",
  )
  inspect(echo_derived.read_or_abort(), content="2")
  parser.set_source("hello")
  inspect(echo_derived.read_or_abort(), content="5")
}

///|
#warnings("-unused_error_type")
fn syntax_test_language_with_counter(
  parse_count : Ref[Int],
) -> @incremental.ImperativeLanguage[Unit] {
  let full_parse = fn(_source_id : @core.SourceId, s : String) raise Failure {
    parse_count.val = parse_count.val + 1
    let cst = @seam.build_tree(
      [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
      @seam.RawKind(0),
      policy=@seam.CstMetadataPolicy::unclassified(),
    ) catch {
      _ => abort("build_tree failed in syntax counter language")
    }
    (@seam.SyntaxNode::from_cst(cst), @core.DiagnosticSet::empty(), 0)
  }
  @incremental.ImperativeLanguage::new(
    full_parse~,
    incremental_parse=fn(source_id, s, _old, _edit) raise Failure {
      full_parse(source_id, s)
    },
    to_ast=_syntax => (),
  )
}

///|
test "SyntaxParser::apply_changes delegates one validated transition" {
  let parse_count : Ref[Int] = Ref(0)
  let parser = SyntaxParser::new(
    @core.SourceId("pipeline-syntax-multi-range"),
    "abcd",
    syntax_test_language_with_counter(parse_count),
  )
  let changes = @text_change.ChangeSet::ChangeSet(source_length=4, changes=[
    @text_change.TextChange::ReplaceRange(start=0, delete_len=1, inserted="A"),
    @text_change.TextChange::ReplaceRange(start=3, delete_len=1, inserted="D"),
  ])
  parser.apply_changes(changes, "AbcD")
  inspect(parser.source().read_or_abort(), content="AbcD")
  inspect(parser.snapshot().read_or_abort().reuse_count, content="0")
  inspect(parse_count.val, content="2")
}

///|
test "SyntaxParser::set_source is a no-op when source is unchanged" {
  let parse_count : Ref[Int] = Ref(0)
  let source_id = @core.SourceId("pipeline-syntax-noop-source")
  let parser = SyntaxParser::new(
    source_id,
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
