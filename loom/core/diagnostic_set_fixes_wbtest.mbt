///|
test "parser diagnostic identity includes fix candidates" {
  let source_id = SourceId("main")
  let range = try TextRange::from_offsets(0, 1) catch {
    _ => abort("expected a valid parser fix range")
  } noraise {
    range => range
  }
  let make_diagnostic = replacement => {
    let fix = try
      DiagnosticFix("candidate", Always, [
        TextReplacement(SourceSpan(source_id, range), replacement),
      ])
    catch {
      _ => abort("expected a valid parser fix")
    } noraise {
      fix => fix
    }
    Diagnostic(
      origin=DiagnosticOrigin("parser"),
      severity=Error,
      message="same parser error",
      fixes=[fix],
    )
  }
  inspect(
    parser_diagnostic_same_key(make_diagnostic("A"), make_diagnostic("B")),
    content="false",
  )
}

///|
test "LexError converts through the public ToDiagnostic trait" {
  let diagnostic = @diagnostic.ToDiagnostic::to_diagnostic(
    LexError("unexpected character"),
  )
  inspect(diagnostic.origin().name(), content="lexer")
  inspect(diagnostic.severity() is Error, content="true")
  inspect(
    diagnostic.code().map(code => code.value()) == Some("lex-error"),
    content="true",
  )
  inspect(diagnostic.message(), content="unexpected character")
  inspect(diagnostic.labels().length(), content="0")
}
