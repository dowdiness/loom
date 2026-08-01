///|
enum ConsumerError {
  MissingName(@diagnostic.SourceId)
}

///|
impl @diagnostic.ToDiagnostic for ConsumerError with fn to_diagnostic(self) {
  match self {
    MissingName(source_id) => {
      let range = try @diagnostic.TextRange::from_offsets(4, 8) catch {
        _ => abort("expected a valid consumer range")
      } noraise {
        range => range
      }
      let fix = try
        @diagnostic.DiagnosticFix(
          "insert a name",
          @diagnostic.FixApplicability::Always,
          [
            @diagnostic.TextReplacement(
              @diagnostic.SourceSpan(source_id, range),
              "main",
            ),
          ],
        )
      catch {
        _ => abort("expected a valid consumer fix")
      } noraise {
        fix => fix
      }
      @diagnostic.Diagnostic(
        origin=@diagnostic.DiagnosticOrigin("consumer"),
        severity=@diagnostic.DiagnosticSeverity::Error,
        code=Some(@diagnostic.DiagnosticCode("E-NAME")),
        message="missing entry-point name",
        labels=[
          @diagnostic.DiagnosticLabel(
            @diagnostic.LabelStyle::Primary,
            @diagnostic.SourceSpan(source_id, range),
            Some("name required here"),
          ),
        ],
        fixes=[fix],
      )
    }
  }
}

///|
struct MemoryResolver {
  source_id : @diagnostic.SourceId
  snapshot : @diagnostic.SourceSnapshot
}

///|
impl @diagnostic.SourceResolver for MemoryResolver with fn resolve_source(
  self,
  source_id,
) {
  if source_id == self.source_id {
    Some(self.snapshot)
  } else {
    None
  }
}

///|
test "external consumer converts renders and fixes a domain error" {
  let source_id = @diagnostic.SourceId("memory://main")
  let source = "let ____ = 1"
  let resolver = MemoryResolver::{
    source_id,
    snapshot: @diagnostic.SourceSnapshot(
      "main.mbt",
      source,
      @diagnostic.LineIndex::new(source),
    ),
  }
  let diagnostic = @diagnostic.ToDiagnostic::to_diagnostic(
    ConsumerError::MissingName(source_id),
  )
  inspect(diagnostic.origin().name(), content="consumer")
  inspect(
    diagnostic.render_plain(resolver),
    content=(
      #|error[E-NAME]: missing entry-point name
      #|--> main.mbt
      #|primary 1:5-1:9: name required here
      #|  1 | let ____ = 1
      #|    |     ^^^^
    ),
  )
  let fixed = try diagnostic.fixes()[0].apply(source_id, source) catch {
    _ => abort("expected the consumer fix to apply")
  } noraise {
    fixed => fixed
  }
  inspect(fixed, content="let main = 1")
}
