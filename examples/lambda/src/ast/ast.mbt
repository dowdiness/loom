// Ast types for Lambda Calculus

///|
pub type VarName = String

///|
pub(all) enum Bop {
  Plus
  Minus
} derive(Show, Eq, FromJson, ToJson, Debug)

///|
pub(all) enum ModuleItem {
  Def(String, Term)
  Expr(Term)
} derive(Show, Eq, ToJson, Debug)

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
  // Module — interleaved definitions and expressions
  Module(Array[ModuleItem])
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
      Module(items) => {
        let parts : Array[String] = []
        for item in items {
          match item {
            Def(name, init) => parts.push("let " + name + " = " + go(init))
            Expr(expr) => parts.push(go(expr))
          }
        }
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
