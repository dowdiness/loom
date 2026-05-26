///|
fn count_lambda_diagnostics(
  diagnostics : Array[LambdaDiagnostic],
  phase : LambdaDiagnosticPhase,
) -> Int {
  let mut count = 0
  for diagnostic in diagnostics {
    if diagnostic.phase() == phase {
      count = count + 1
    }
  }
  count
}

///|
fn first_lambda_message(
  diagnostics : Array[LambdaDiagnostic],
  phase : LambdaDiagnosticPhase,
) -> String {
  for diagnostic in diagnostics {
    if diagnostic.phase() == phase {
      return diagnostic.message()
    }
  }
  abort("missing lambda diagnostic phase")
}

///|
test "LambdaAnalysis: clean source has no diagnostics" {
  let analysis = LambdaAnalysis::LambdaAnalysis("1 + 2")
  inspect(analysis.diagnostics().length(), content="0")
}

///|
test "LambdaAnalysis: parse error includes parser diagnostic" {
  let analysis = LambdaAnalysis::LambdaAnalysis("λx.")
  let diagnostics = analysis.diagnostics()
  inspect(count_lambda_diagnostics(diagnostics, ParsePhase) > 0, content="true")
}

///|
test "LambdaAnalysis: parse diagnostic preserves structured payload" {
  let analysis = LambdaAnalysis::LambdaAnalysis("λx.")
  let diagnostics = analysis.diagnostics()
  let mut saw_parser_diagnostic = false
  for diagnostic in diagnostics {
    match diagnostic {
      ParseDiagnostic(parser_diagnostic) =>
        saw_parser_diagnostic = parser_diagnostic.format().length() > 0
      TypecheckDiagnostic(_) => ()
    }
  }
  inspect(saw_parser_diagnostic, content="true")
}

///|
test "LambdaAnalysis: type error includes typecheck diagnostic" {
  let analysis = LambdaAnalysis::LambdaAnalysis("x + 1")
  let diagnostics = analysis.diagnostics()
  inspect(count_lambda_diagnostics(diagnostics, TypecheckPhase), content="1")
  inspect(
    first_lambda_message(diagnostics, TypecheckPhase),
    content="unbound variable: x",
  )
}

///|
test "LambdaAnalysis: edit-to-clean recomputes diagnostics" {
  let analysis = LambdaAnalysis::LambdaAnalysis("x + 1")
  inspect(analysis.diagnostics().length(), content="1")
  analysis.set_source("1 + 2")
  inspect(analysis.diagnostics().length(), content="0")
}

///|
test "LambdaAnalysis: apply_edit recomputes diagnostics" {
  let analysis = LambdaAnalysis::LambdaAnalysis("x + 1")
  inspect(analysis.diagnostics().length(), content="1")
  analysis.apply_edit(@core.Edit::new(0, 5, 5), "1 + 2")
  inspect(analysis.diagnostics().length(), content="0")
}

///|
test "LambdaAnalysis: diagnostics survive Runtime::gc" {
  let analysis = LambdaAnalysis::LambdaAnalysis("λx.")
  inspect(
    count_lambda_diagnostics(analysis.diagnostics(), ParsePhase) > 0,
    content="true",
  )
  analysis.parser.runtime().gc()
  analysis.set_source("1 + 2")
  inspect(analysis.diagnostics().length(), content="0")
}

///|
test "LambdaAnalysis: dispose does not dispose parser" {
  let parser = @loom.new_parser("1 + 2", lambda_grammar)
  let analysis = attach_lambda_analysis(parser)
  ignore(analysis.diagnostics())
  analysis.dispose()
  parser.set_source("42")
  inspect(parser.ast().read_or_abort() |> @ast.print_term, content="42")
}
