///|
struct PrettyConsumerResolver {
  resolve : (@diagnostic.SourceId) -> @diagnostic.SourceSnapshot?
}

///|
impl @diagnostic.SourceResolver for PrettyConsumerResolver with fn resolve_source(
  self,
  source_id,
) {
  (self.resolve)(source_id)
}

///|
test "external consumer renders one typed layout at wide and narrow widths" {
  let source_id = @diagnostic.SourceId("memory://main")
  let source = "let x = foo"
  let mut resolve_calls = 0
  let resolver = PrettyConsumerResolver::{
    resolve: requested => {
      resolve_calls = resolve_calls + 1
      if requested == source_id {
        Some(
          @diagnostic.SourceSnapshot(
            "src/main.mbt",
            source,
            @diagnostic.LineIndex::new(source),
          ),
        )
      } else {
        None
      }
    },
  }
  let range = try @diagnostic.TextRange::from_offsets(8, 11) catch {
    _ => abort("expected a valid consumer range")
  } noraise {
    range => range
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("consumer"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    code=Some(@diagnostic.DiagnosticCode("E100")),
    message="unexpected name",
    labels=[
      @diagnostic.DiagnosticLabel(
        @diagnostic.LabelStyle::Primary,
        @diagnostic.SourceSpan(source_id, range),
        Some("expected expression"),
      ),
    ],
    notes=["choose another expression"],
  )
  let options = try @diagnostic_pretty.DiagnosticPrettyOptions() catch {
    _ => abort("default pretty options must be valid")
  } noraise {
    options => options
  }
  let report = @diagnostic_pretty.layout(diagnostic, resolver, options)
  inspect(
    @pretty.render_string(report, width=80),
    content=(
      #|error[E100]: unexpected name
      #|--> src/main.mbt
      #|primary 1:9-1:12: expected expression
      #|  1 | let x = foo
      #|    |         ^^^
      #|= note: choose another expression
    ),
  )
  inspect(
    @pretty.render_string(report, width=18),
    content=(
      #|error[E100]:
      #|  unexpected name
      #|--> src/main.mbt
      #|primary 1:9-1:12:
      #|  expected expression
      #|  1 | let x = foo
      #|    |         ^^^
      #|= note:
      #|  choose another expression
    ),
  )
  inspect(resolve_calls, content="1")
  let spans = @pretty.render_spans(report, width=80)
  inspect(spans.length() > 0, content="true")
  inspect(
    spans.any(item => {
      item.1 ==
      @diagnostic_pretty.DiagnosticStyle::Severity(
        @diagnostic.DiagnosticSeverity::Error,
      )
    }),
    content="true",
  )
  inspect(
    spans.any(item => item.1 == @diagnostic_pretty.DiagnosticStyle::Primary),
    content="true",
  )
}
