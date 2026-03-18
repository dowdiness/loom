// Ast types for Lambda Calculus

///|
pub type VarName = String

///|
pub(all) enum Bop {
  Plus
  Minus
} derive(Show, Eq, FromJson, ToJson, Debug)

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
} derive(Show, Eq, ToJson, Debug)

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
      Module(defs, body) => {
        let parts : Array[String] = []
        for def in defs {
          parts.push("let " + def.0 + " = " + go(def.1))
        }
        parts.push(go(body))
        parts.join("\n")
      }
      Unit => "()"
      Unbound(x) => "<unbound: " + x + ">"
      Error(msg) => "<error: " + msg + ">"
    }
  }

  go(term)
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
