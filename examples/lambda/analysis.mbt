///|
/// Lambda-owned diagnostic phase for the analysis facade.
pub(all) enum LambdaDiagnosticPhase {
  ParsePhase
  TypecheckPhase
} derive(Eq, Debug)

///|
/// A lambda diagnostic produced by parser or type analysis.
pub(all) enum LambdaDiagnostic {
  ParseDiagnostic(@core.Diagnostic)
  TypecheckDiagnostic(@typecheck.TypeDiagnostic)
} derive(Eq, Debug)

///|
/// Build a lambda diagnostic from a parser diagnostic.
pub fn LambdaDiagnostic::from_parse(
  diagnostic : @core.Diagnostic,
) -> LambdaDiagnostic {
  ParseDiagnostic(diagnostic)
}

///|
/// Build a lambda diagnostic from a type-check diagnostic.
pub fn LambdaDiagnostic::from_typecheck(
  diagnostic : @typecheck.TypeDiagnostic,
) -> LambdaDiagnostic {
  TypecheckDiagnostic(diagnostic)
}

///|
/// Return the analysis phase that produced this diagnostic.
pub fn LambdaDiagnostic::phase(
  self : LambdaDiagnostic,
) -> LambdaDiagnosticPhase {
  match self {
    ParseDiagnostic(_) => ParsePhase
    TypecheckDiagnostic(_) => TypecheckPhase
  }
}

///|
/// Return a display-oriented diagnostic message.
pub fn LambdaDiagnostic::message(self : LambdaDiagnostic) -> String {
  match self {
    ParseDiagnostic(diagnostic) => diagnostic.format()
    TypecheckDiagnostic(diagnostic) => diagnostic.message
  }
}

///|
/// A lambda-owned analysis attachment over a unified parser.
///
/// The facade composes parser diagnostics with `attach_typecheck` results on
/// the parser's runtime. Its terminal diagnostics `Watch` keeps both the
/// parser diagnostic view and typecheck result reachable across `Runtime::gc()`
/// after the first `diagnostics()` read has recorded upstream dependencies.
/// This constructor registers but does not prime the watch.
///
/// `dispose()` tears down only the analysis/typecheck scopes; the parser remains
/// usable by its owner. If the parser must survive a later `Runtime::gc()` after
/// disposal, another owner must keep a watch/root for the needed parser views.
pub(all) struct LambdaAnalysis {
  parser : @loom.Parser[@ast.Term]
  typecheck : TypecheckAttachment
  scope : @incr.Scope
  watch : @incr.Watch[Array[LambdaDiagnostic]]
}

///|
/// Create a lambda analysis facade with a fresh parser for `source`.
pub fn LambdaAnalysis::LambdaAnalysis(source : String) -> LambdaAnalysis {
  attach_lambda_analysis(@loom.new_parser(source, lambda_grammar))
}

///|
/// Attach lambda analysis to an existing parser.
pub fn attach_lambda_analysis(
  parser : @loom.Parser[@ast.Term],
) -> LambdaAnalysis {
  let typecheck = attach_typecheck(parser)
  let scope = @incr.Scope::new(parser.runtime())
  let combined = scope.derived(
    fn() {
      let diagnostics : Array[LambdaDiagnostic] = []
      for diagnostic in parser.diagnostics().get_or_abort().items() {
        diagnostics.push(LambdaDiagnostic::from_parse(diagnostic))
      }
      for diagnostic in typecheck.result.get_or_abort().all_diagnostics {
        diagnostics.push(LambdaDiagnostic::from_typecheck(diagnostic))
      }
      diagnostics
    },
    label="lambda_analysis_diagnostics",
  )
  let watch = scope.add_watch(combined.watch())
  { parser, typecheck, scope, watch }
}

///|
/// Read the current combined parser + typecheck diagnostics.
pub fn LambdaAnalysis::diagnostics(
  self : LambdaAnalysis,
) -> Array[LambdaDiagnostic] {
  self.watch.read_or_abort().copy()
}

///|
/// Read the current typecheck result.
pub fn LambdaAnalysis::typecheck_result(
  self : LambdaAnalysis,
) -> @typecheck.ModuleTypeResult {
  self.typecheck.get()
}

///|
/// Replace the parser source and publish a coherent analysis update.
pub fn LambdaAnalysis::set_source(
  self : LambdaAnalysis,
  source : String,
) -> Unit {
  self.parser.set_source(source)
}

///|
/// Apply an incremental parser edit and publish a coherent analysis update.
pub fn LambdaAnalysis::apply_edit(
  self : LambdaAnalysis,
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  self.parser.apply_edit(edit, new_source)
}

///|
/// Dispose analysis-owned scopes. Does not dispose the parser.
pub fn LambdaAnalysis::dispose(self : LambdaAnalysis) -> Unit {
  self.scope.dispose()
  self.typecheck.dispose()
}
