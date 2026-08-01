///|
test "push_offset_diagnostic reports invalid shifted diagnostic" {
  let source_id = SourceId("block-reparse-source")
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Error,
    message="after",
    labels=[
      DiagnosticLabel(
        LabelStyle::Primary,
        SourceSpan(source_id, test_range(10, 11)),
        None,
      ),
      DiagnosticLabel(
        LabelStyle::Secondary,
        SourceSpan(source_id, test_range(9, 10)),
        Some("spans old end"),
      ),
    ],
  )
  let after = try TextOffset(10) catch {
    _ => abort("expected valid diagnostic shift boundary")
  } noraise {
    offset => offset
  }
  let merged = DiagnosticSet::empty()
  push_offset_diagnostic(
    merged, diagnostic, source_id, -10, after, "old diagnostic after block",
  )
  inspect(merged.length(), content="1")
  let diagnostic = merged.items()[0]
  inspect(diagnostic.format(), content="internal: diagnostic offset failed")
  debug_inspect(
    diagnostic.notes(),
    content=(
      #|[
      #|  "old diagnostic after block",
      #|  "diagnostic build error preserved as InvalidTextRange(9, 0)",
      #|]
    ),
  )
}
