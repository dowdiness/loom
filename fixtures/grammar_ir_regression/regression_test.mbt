///|
/// Regression test: verify the generated GrammarIr compiles against
/// @grammar's compile function. This guards against wrong constructor
/// names, arity mismatches, or type param changes in the generated output.
/// If the generated output has a syntax error, `@grammar.compile` fails
/// with an error message showing the mismatch — catching it here before it
/// ships to a consumer.
test "compile-regression: generated GrammarIr compiles without raising" {
  let ir = fixture_grammar_ir
  let _ = @grammar.compile(ir)
}
