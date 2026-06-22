///|
test "merge_diagnostics reports invalid shifted old diagnostic" {
  let old_diagnostics = DiagnosticSet::single(
    Diagnostic(
      source=DiagnosticSource::parser(),
      severity=Error,
      message="after",
      primary=Some(test_range(10, 11)),
      labels=[{ range: test_range(9, 10), message: Some("spans old end") }],
    ),
  )
  let merged = merge_diagnostics(
    old_diagnostics,
    0,
    10,
    DiagnosticSet::empty(),
    -10,
  )
  inspect(merged.length(), content="1")
  let diagnostic = merged.items()[0]
  inspect(diagnostic.format(), content="internal: diagnostic offset failed")
  debug_inspect(
    diagnostic.notes,
    content=(
      #|[
      #|  "old diagnostic after block",
      #|  "diagnostic build error preserved as InvalidTextRange(9, 0)",
      #|]
    ),
  )
}
