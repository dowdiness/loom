// Ast types for Lambda Calculus

///|
pub type VarName = String

///|
pub(all) enum Bop {
  Plus
  Minus
} derive(Show, Eq, FromJson, ToJson)

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
  // Let binding (non-recursive)
  Let(VarName, Term, Term)
  // Error term for malformed/missing nodes
  Error(String)
} derive(Show, Eq)

///|
pub fn print_term(term : Term) -> String {
  fn go(t : Term) -> String {
    match t {
      Int(i) => i.to_string()
      Var(x) => x
      Lam(x, t) => "(λ" + x + ". " + go(t) + ")"
      App(t1, t2) => "(" + go(t1) + " " + go(t2) + ")"
      Bop(Plus, t1, t2) => "(" + go(t1) + " + " + go(t2) + ")"
      Bop(Minus, t1, t2) => "(" + go(t1) + " - " + go(t2) + ")"
      If(t1, t2, t3) => "if " + go(t1) + " then " + go(t2) + " else " + go(t3)
      Let(x, init, body) => "let " + x + " = " + go(init) + " in " + go(body)
      Error(msg) => "<error: " + msg + ">"
    }
  }

  go(term)
}

///|
test "print_term - error variant" {
  inspect(print_term(Term::Error("missing body")), content="<error: missing body>")
  inspect(print_term(Term::Error("")), content="<error: >")
}
