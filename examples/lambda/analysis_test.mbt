///|
fn count_lambda_diagnostics(
  diagnostics : Array[@lambda.LambdaDiagnostic],
  phase : @lambda.LambdaDiagnosticPhase,
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
  diagnostics : Array[@lambda.LambdaDiagnostic],
  phase : @lambda.LambdaDiagnosticPhase,
) -> String {
  for diagnostic in diagnostics {
    if diagnostic.phase() == phase {
      return diagnostic.message()
    }
  }
  abort("missing lambda diagnostic phase")
}

///|
fn lambda_analysis_test_source_id() -> @core.SourceId {
  @core.SourceId::SourceId("lambda-analysis-test")
}

///|
test "LambdaAnalysis: clean source has no diagnostics" {
  let analysis = @lambda.LambdaAnalysis::LambdaAnalysis(
    lambda_analysis_test_source_id(),
    "1 + 2",
  )
  inspect(analysis.diagnostics().length(), content="0")
}

///|
test "LambdaAnalysis: parse error includes parser diagnostic" {
  let analysis = @lambda.LambdaAnalysis::LambdaAnalysis(
    lambda_analysis_test_source_id(),
    "(x) =>",
  )
  let diagnostics = analysis.diagnostics()
  inspect(count_lambda_diagnostics(diagnostics, ParsePhase) > 0, content="true")
}

///|
test "LambdaAnalysis: parse diagnostic preserves structured payload" {
  let analysis = @lambda.LambdaAnalysis::LambdaAnalysis(
    lambda_analysis_test_source_id(),
    "(x) =>",
  )
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
  let analysis = @lambda.LambdaAnalysis::LambdaAnalysis(
    lambda_analysis_test_source_id(),
    "x + 1",
  )
  let diagnostics = analysis.diagnostics()
  inspect(count_lambda_diagnostics(diagnostics, TypecheckPhase), content="1")
  inspect(
    first_lambda_message(diagnostics, TypecheckPhase),
    content="unbound variable: x",
  )
}

///|
test "LambdaAnalysis: edit-to-clean recomputes diagnostics" {
  let analysis = @lambda.LambdaAnalysis::LambdaAnalysis(
    lambda_analysis_test_source_id(),
    "x + 1",
  )
  inspect(analysis.diagnostics().length(), content="1")
  analysis.set_source("1 + 2")
  inspect(analysis.diagnostics().length(), content="0")
}

///|
test "LambdaAnalysis: apply_edit recomputes diagnostics" {
  let analysis = @lambda.LambdaAnalysis::LambdaAnalysis(
    lambda_analysis_test_source_id(),
    "x + 1",
  )
  inspect(analysis.diagnostics().length(), content="1")
  analysis.apply_edit(@core.Edit::new(0, 5, 5), "1 + 2")
  inspect(analysis.diagnostics().length(), content="0")
}

///|
test "LambdaAnalysis: diagnostics survive Runtime::gc" {
  let analysis = @lambda.LambdaAnalysis::LambdaAnalysis(
    lambda_analysis_test_source_id(),
    "(x) =>",
  )
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
  let parser = @loom.new_parser(
    lambda_analysis_test_source_id(),
    "1 + 2",
    @lambda.lambda_grammar,
  )
  let analysis = @lambda.attach_lambda_analysis(parser)
  ignore(analysis.diagnostics())
  analysis.dispose()
  parser.set_source("42")
  inspect(parser.ast().read_or_abort() |> @ast.print_term, content="42")
}
