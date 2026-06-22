// Generic parser infrastructure — parser diagnostics and recovery placeholders

///|
/// Build a parser diagnostic for a known token span. The token payload is
/// erased immediately so consumers never need to re-tokenize for evidence.
fn[T : @seam.ToRawKind] make_parser_diagnostic(
  msg : String,
  start : Int,
  end : Int,
  token : T,
  code? : DiagnosticCode? = None,
) -> Diagnostic {
  let (primary, notes) : (TextRange?, Array[String]) = try
    TextRange::from_offsets(start, end)
  catch {
    error =>
      (
        None,
        ["invalid diagnostic range preserved as " + @debug.to_string(error)],
      )
  } noraise {
    range => (Some(range), [])
  }
  let evidence = primary.map(range => { kind: token.to_raw(), range })
  Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    code~,
    message=msg,
    primary~,
    notes~,
    token=evidence,
  )
}

///|
/// Report an already-structured diagnostic through parser diagnostic
/// collection. Equivalent parser diagnostics refresh token evidence instead of
/// creating duplicates.
pub fn[T, K] ParserContext::report(
  self : ParserContext[T, K],
  diagnostic : Diagnostic,
) -> Unit {
  let _ = self.push_diagnostic_unique(diagnostic)
}

///|
/// Report a parser error with an explicit optional range.
pub fn[T, K] ParserContext::report_error(
  self : ParserContext[T, K],
  message~ : String,
  code? : DiagnosticCode? = None,
  range? : TextRange? = None,
) -> Unit {
  self.report(
    Diagnostic(
      source=DiagnosticSource::parser(),
      severity=Error,
      code~,
      message~,
      primary=range,
    ),
  )
}

///|
/// Report a parser error at the current non-trivia token, or at EOF when no
/// token remains. The token type is erased through `ToRawKind`.
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::report_at_current(
  self : ParserContext[T, K],
  message~ : String,
  code? : DiagnosticCode? = None,
) -> Unit {
  let diagnostic = self
    .current_token_position()
    .map_or_else(
      () => {
        let eof = self.source.length()
        make_parser_diagnostic(message, eof, eof, self.spec.eof_token, code~)
      },
      pos => {
        make_parser_diagnostic(
          message,
          (self.get_start)(pos),
          (self.get_end)(pos),
          (self.get_token)(pos),
          code~,
        )
      },
    )
  let _ = self.push_diagnostic_unique(diagnostic)
}

///|
/// Report a simple "expected ..." parser diagnostic at the current token.
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::report_expected(
  self : ParserContext[T, K],
  expected~ : String,
  code? : DiagnosticCode? = None,
) -> Unit {
  self.report_at_current(message="expected " + expected, code~)
}

///|
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] ParserContext::error(
  self : ParserContext[T, K],
  msg : String,
) -> Unit {
  self.report_at_current(message=msg)
}

///|
/// Consume the current token and emit it as an error token (for error recovery).
/// Automatically flushes leading trivia before the token.
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] ParserContext::bump_error(
  self : ParserContext[T, K],
) -> Unit {
  self.flush_trivia()
  let text = self.text_at(self.position)
  self.events.push(@seam.ParseEvent::Token(self.spec.error_kind.to_raw(), text))
  self.position = self.position + 1
}

///|
/// Emit a zero-width token (no source text consumed, position unchanged).
/// Use this for synthetic tokens inserted during error recovery when the
/// grammar needs to represent a missing token without consuming input.
pub fn[T, K : @seam.ToRawKind] ParserContext::emit_zero_width(
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  self.events.push_parser_synthetic_zero_width_token(kind.to_raw())
}

///|
/// Emit a zero-width error placeholder (no source text consumed).
/// Shorthand for emit_zero_width(spec.error_kind). Use this in grammar code
/// to represent a missing or erroneous token without consuming input.
pub fn[T, K : @seam.ToRawKind] ParserContext::emit_error_placeholder(
  self : ParserContext[T, K],
) -> Unit {
  self.emit_zero_width(self.spec.error_kind)
}

///|
/// Emit a zero-width incomplete placeholder (no source text consumed).
/// Use this when the grammar expects more input but has reached EOF.
/// Distinct from emit_error_placeholder: signals "incomplete input" rather
/// than "unexpected token", enabling IDE consumers to show different UX
/// (e.g. grey indicator vs red squiggly).
pub fn[T, K : @seam.ToRawKind] ParserContext::emit_incomplete_placeholder(
  self : ParserContext[T, K],
) -> Unit {
  self.emit_zero_width(self.spec.incomplete_kind)
}
