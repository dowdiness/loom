///|
test "MarkdownIR recovery ignores foreign primary and local secondary labels" {
  let source_a = @core.SourceId("markdown-source-a")
  let source_b = @core.SourceId("markdown-source-b")
  let source = "[unclosed\n"
  let (cst, _) = try! parse_cst(source_a, source)
  let overlap = try! @core.TextRange::from_offsets(0, 1)
  let incoming = @core.Diagnostic::Diagnostic(
    origin=@core.DiagnosticOrigin("lexer"),
    severity=@core.DiagnosticSeverity::all()[0],
    code=Some(@core.DiagnosticCode("markdown-test.foreign-primary")),
    message="foreign primary must not select",
    labels=[
      @core.DiagnosticLabel::DiagnosticLabel(
        @core.LabelStyle::Primary,
        @core.SourceSpan::SourceSpan(source_b, overlap),
        Some("foreign primary"),
      ),
      @core.DiagnosticLabel::DiagnosticLabel(
        @core.LabelStyle::Secondary,
        @core.SourceSpan::SourceSpan(source_a, overlap),
        Some("local secondary"),
      ),
    ],
  )
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_a,
    @seam.SyntaxNode::from_cst(cst),
    @core.DiagnosticSet::single(incoming),
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) => {
          let attached = paragraph.children()[index].diagnostics()
          inspect(attached.length(), content="1")
          inspect(
            attached[0].message(),
            content="recovered malformed Markdown: [",
          )
          inspect(attached[0].origin().name(), content="parser")
          match attached[0].labels() {
            [label] => {
              inspect(
                label.style() is @core.LabelStyle::Primary,
                content="true",
              )
              inspect(label.span().source_id() == source_a, content="true")
            }
            _ => fail("expected one fallback primary label")
          }
        }
        None => fail("expected recovered MarkdownIR child")
      }
    _ => fail("expected one paragraph")
  }
}

///|
test "MarkdownIR recovery preserves ordered styled labels from the current source" {
  let source_a = @core.SourceId("markdown-multi-label-a")
  let source_b = @core.SourceId("markdown-multi-label-b")
  let source = "[unclosed\n"
  let (cst, _) = try! parse_cst(source_a, source)
  let overlap = try! @core.TextRange::from_offsets(0, 1)
  let labels = [
    @core.DiagnosticLabel::DiagnosticLabel(
      @core.LabelStyle::Secondary,
      @core.SourceSpan::SourceSpan(source_b, overlap),
      Some("foreign secondary"),
    ),
    @core.DiagnosticLabel::DiagnosticLabel(
      @core.LabelStyle::Primary,
      @core.SourceSpan::SourceSpan(source_b, overlap),
      Some("foreign primary"),
    ),
    @core.DiagnosticLabel::DiagnosticLabel(
      @core.LabelStyle::Secondary,
      @core.SourceSpan::SourceSpan(source_a, overlap),
      Some("local secondary"),
    ),
    @core.DiagnosticLabel::DiagnosticLabel(
      @core.LabelStyle::Primary,
      @core.SourceSpan::SourceSpan(source_a, overlap),
      Some("local primary"),
    ),
  ]
  let incoming = @core.Diagnostic::Diagnostic(
    origin=@core.DiagnosticOrigin("lexer"),
    severity=@core.DiagnosticSeverity::all()[0],
    message="preserve all labels",
    labels~,
  )
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_a,
    @seam.SyntaxNode::from_cst(cst),
    @core.DiagnosticSet::single(incoming),
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) => {
          let recovered = paragraph.children()[index]
          let attached = recovered.diagnostics()
          inspect(attached == [incoming], content="true")
          let copied_labels = attached[0].labels()
          copied_labels.push(copied_labels[0])
          inspect(attached[0].labels().length(), content="4")
          attached.push(incoming)
          inspect(recovered.diagnostics().length(), content="1")
        }
        None => fail("expected recovered MarkdownIR child")
      }
    _ => fail("expected one paragraph")
  }
}

///|
test "MarkdownIR recovery uses positive half-open overlap in the current source" {
  let source_a = @core.SourceId("markdown-half-open-a")
  let source_b = @core.SourceId("markdown-half-open-b")
  let source = "[unclosed\n"
  let (cst, _) = try! parse_cst(source_a, source)
  let diagnostics = @core.DiagnosticSet::empty()
  diagnostics.push(
    @core.lexer_diagnostic_at(
      source_a, "zero-width start", 0, 0, "markdown-test.zero",
    ),
  )
  diagnostics.push(
    @core.lexer_diagnostic_at(
      source_a, "positive local overlap", 0, 1, "markdown-test.positive",
    ),
  )
  diagnostics.push(
    @core.lexer_diagnostic_at(
      source_a, "zero-width end", 1, 1, "markdown-test.zero",
    ),
  )
  diagnostics.push(
    @core.lexer_diagnostic_at(
      source_b, "foreign numeric overlap", 0, 1, "markdown-test.foreign",
    ),
  )
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_a,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  match ir.children() {
    [paragraph] =>
      match paragraph.children().search_by(child => child.is_recovered()) {
        Some(index) =>
          match paragraph.children()[index].diagnostics() {
            [diagnostic] =>
              inspect(diagnostic.message(), content="positive local overlap")
            _ => fail("expected only the positive current-source diagnostic")
          }
        None => fail("expected recovered MarkdownIR child")
      }
    _ => fail("expected one paragraph")
  }
}
