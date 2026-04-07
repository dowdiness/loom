// Ast types for Lambda Calculus

///|
pub type VarName = String

///|
pub(all) enum Bop {
  Plus
  Minus
} derive(Eq, FromJson, ToJson, Debug)

///|
pub impl Show for Bop with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) enum Term {
  // Integer
  Int(Int)
  // Variable
  Var(VarName)
  // Lambda abstraction
  Lam(VarName, Term)
  // Application
  App(Term, Term)
  // Binary operation
  Bop(Bop, Term, Term)
  // If-then-else
  If(Term, Term, Term)
  // Module — flattened definitions with a body expression
  Module(Array[(VarName, Term)], Term)
  // Unit — terminal for definition-only source files
  Unit
  // Unbound variable — semantic error from name resolution
  Unbound(VarName)
  // Error term for malformed/missing nodes
  Error(String)
  // Hole — placeholder for deleted or incomplete nodes
  Hole(Int)
} derive(Eq, ToJson, Debug)

///|
pub impl Show for Term with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn print_term(term : Term) -> String {
  (replay(term) : Pretty).repr
}

///|
test "print_term - unbound variant" {
  inspect(print_term(Term::Unbound("x")), content="<unbound: x>")
}

///|
test "print_term - error variant" {
  inspect(
    print_term(Term::Error("missing body")),
    content="<error: missing body>",
  )
  inspect(print_term(Term::Error("")), content="<error: >")
}
