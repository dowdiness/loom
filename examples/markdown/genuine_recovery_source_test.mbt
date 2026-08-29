///|
fn genuine_recovery_source_ir(
  source_id : @core.SourceId,
  source : String,
  diagnostics? : @core.DiagnosticSet = @core.DiagnosticSet::empty(),
) -> MarkdownIR {
  let error = try! @seam.CstNode::new_unclassified(
    @seam.ToRawKind::to_raw(SyntaxKind::ErrorNode),
    [
      @seam.CstElement::Token(
        @seam.CstToken::CstToken(
          @seam.ToRawKind::to_raw(SyntaxKind::TextToken),
          source.view(),
        ),
      ),
    ],
  )
  let root = try! @seam.CstNode::new_unclassified(
    @seam.ToRawKind::to_raw(SyntaxKind::DocumentNode),
    [@seam.CstElement::Node(error)],
  )
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(root),
    diagnostics,
  )
}

///|
test "genuine parser recovery preserves exact source and separates diagnostics" {
  let source_id = @core.SourceId("markdown-genuine-recovery-source")
  let source = "𐐀<unexpected>"
  let ir = genuine_recovery_source_ir(source_id, source)
  match ir.children() {
    [recovered] => {
      match recovered.view() {
        Recovered(value~) => assert_eq(value, source)
        _ => fail("expected one recovered semantic node")
      }
      assert_eq(recovered.origin().start(), 0)
      assert_eq(recovered.origin().end(), source.length())
      match recovered.diagnostics() {
        [diagnostic] =>
          assert_eq(
            diagnostic.format(),
            "recovered malformed Markdown [0," +
            source.length().to_string() +
            "]",
          )
        _ => fail("expected one recovery diagnostic")
      }
    }
    _ => fail("expected one recovered document child")
  }
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(ir),
    "𐐀&lt;unexpected&gt;",
  )
  let mdast = experimental_markdown_ir_to_mdast_json(ir).stringify()
  assert_true(mdast.contains("mdastRecovered"))
  assert_true(mdast.contains("\"value\":\"𐐀<unexpected>\""))
  assert_eq(experimental_markdown_ir_preserve_rewrite(ir, source), source)
  assert_eq(
    experimental_markdown_ir_local_transform_rewrite(
      ir,
      source,
      target_origin=ir.children()[0].origin(),
      replacement_text="replacement",
    ),
    "replacement",
  )
  assert_eq(experimental_markdown_ir_canonical_format(source_id, ir), source)
  match experimental_markdown_ir_canonical_format_checked(source_id, ir) {
    Err(OpaqueNode(Recovered, Some(_))) => ()
    _ => fail("checked formatting must reject genuine recovery")
  }
}

///|
test "genuine parser recovery keeps an incoming diagnostic reason" {
  let source_id = @core.SourceId("markdown-genuine-recovery-diagnostic")
  let source = "unexpected"
  let diagnostic = @core.lexer_diagnostic_at(
    source_id,
    "specific parser reason",
    0,
    source.length(),
    "specific-recovery",
  )
  let ir = genuine_recovery_source_ir(
    source_id,
    source,
    diagnostics=@core.DiagnosticSet::single(diagnostic),
  )
  match ir.children() {
    [recovered] => {
      match recovered.view() {
        Recovered(value~) => assert_eq(value, source)
        _ => fail("expected recovered semantic node")
      }
      match recovered.diagnostics() {
        [attached] =>
          assert_eq(
            attached.format(),
            "specific parser reason [0," + source.length().to_string() + "]",
          )
        _ => fail("expected the incoming diagnostic")
      }
    }
    _ => fail("expected one recovered document child")
  }
}
