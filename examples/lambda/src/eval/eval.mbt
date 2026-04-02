// Lambda Calculus Evaluator
//
// A tree-walking interpreter for the untyped lambda calculus with integers.
// This is a classic "environment-based" evaluator: instead of substituting
// variables in the syntax tree (as in textbook reduction), we carry an
// environment — a mapping from variable names to their values — and look
// up variables at evaluation time.
//
// The language supports:
//   - Integer literals and arithmetic (+, -)
//   - Lambda abstractions (anonymous functions) and application
//   - Conditionals (if-then-else, C-style: 0 is falsy, nonzero is truthy)
//   - Let-bindings via Module (sequential definitions + body expression)
//
// Key design choices:
//   - Closures capture the environment at the point of lambda creation,
//     giving us lexical (static) scoping. This means a function always sees
//     the variables that were in scope when it was defined, not when it's called.
//   - Evaluation is strict (call-by-value): arguments are fully evaluated
//     before being passed to functions.
//   - A fuel parameter prevents infinite loops (e.g., the omega combinator
//     (λx. x x)(λx. x x)) by bounding recursion depth.

///|
/// The result of evaluating a lambda term.
///
/// In the lambda calculus, every expression reduces to a value:
/// - `VInt` — an integer (the only "primitive" type in our language)
/// - `VClosure` — a function value, capturing the environment where it was
///   defined (this is what makes lexical scoping work)
/// - `VUnit` — the unit value (for definition-only modules with no body)
pub(all) enum Value {
  VInt(Int)
  VClosure(Env, @ast.VarName, @ast.Term)
  VUnit
} derive(Show, Eq, Debug)

///|
/// Why evaluation got stuck.
///
/// Unlike a total language, our evaluator can fail. These cases correspond
/// to programs that are syntactically valid but semantically meaningless:
/// - `Unbound` — a variable was used but never defined (name resolution error)
/// - `TypeMismatch` — a value was used in the wrong context (e.g., `5 + (λx.x)`)
/// - `Incomplete` — the program contains a hole (placeholder for missing code)
/// - `ParseError` — the AST contains an error node from the parser
/// - `Divergence` — evaluation exceeded the fuel limit (probable infinite loop)
pub(all) suberror StuckReason {
  Unbound(@ast.VarName)
  TypeMismatch(String)
  Incomplete
  ParseError
  Divergence
} derive(Show)

///|
/// An environment maps variable names to their values.
///
/// Environments form an immutable chain: `extend` creates a new environment
/// that shadows one binding without mutating the parent. This is essential
/// for closures — when a closure captures an environment, later mutations
/// to the "same" scope must not affect the captured bindings.
pub struct Env {
  bindings : Map[String, Value]
} derive(Show, Eq, Debug)

///|
pub fn Env::empty() -> Env {
  { bindings: {} }
}

///|
pub fn Env::lookup(self : Env, name : String) -> Value? {
  self.bindings.get(name)
}

///|
/// Create a new environment with one additional binding.
///
/// Uses `Map::copy()` to ensure the new environment is independent of the
/// original. Without the copy, MoonBit's mutable Map would alias the
/// original, and later `extend` calls would retroactively modify closures
/// that captured the old environment — breaking lexical scoping.
pub fn Env::extend(self : Env, name : String, value : Value) -> Env {
  let new_bindings = self.bindings.copy()
  new_bindings[name] = value
  { bindings: new_bindings }
}

///|
/// Evaluate a lambda term in the given environment.
///
/// This is a recursive descent over the `Term` AST. Each branch corresponds
/// to one syntactic form of the lambda calculus. The structure follows the
/// standard "big-step operational semantics" — each case says how to reduce
/// a term directly to a value.
///
/// `fuel` is a recursion depth limit, not a precise computation budget.
/// Sibling subexpressions (e.g., both operands of `Bop`) each receive
/// `fuel - 1` independently — total work can exceed `fuel` for wide trees.
/// This is intentional: fuel prevents divergence (omega combinator), not
/// precise resource bounding. For strict budgets, use wall-clock time or
/// node counts (like egg's Runner).
pub fn eval(
  env : Env,
  term : @ast.Term,
  fuel? : Int = 1000,
) -> Value raise StuckReason {
  if fuel <= 0 {
    raise Divergence
  }
  match term {
    // --- Atoms: these evaluate to themselves or look up a value ---
    Int(n) => VInt(n)
    Unit => VUnit
    Var(x) =>
      match env.lookup(x) {
        Some(v) => v
        None => raise Unbound(x)
      }
    // --- Error nodes: the AST contains incomplete or broken fragments ---
    Hole(_) => raise Incomplete
    Error(_) => raise ParseError
    Unbound(x) => raise Unbound(x)
    // --- Lambda: captures the current environment to form a closure ---
    // A lambda doesn't evaluate its body yet — it just packages up
    // "the code + the environment" for later application.
    Lam(x, body) => VClosure(env, x, body)
    // --- Binary operators: strict evaluation of both operands ---
    Bop(op, a, b) => {
      let va = eval(env, a, fuel=fuel - 1)
      let vb = eval(env, b, fuel=fuel - 1)
      match (op, va, vb) {
        (Plus, VInt(na), VInt(nb)) => VInt(na + nb)
        (Minus, VInt(na), VInt(nb)) => VInt(na - nb)
        (Plus, _, _) => raise TypeMismatch("add: expected integer")
        (Minus, _, _) => raise TypeMismatch("minus: expected integer")
      }
    }
    // --- Conditional: evaluate condition, then take one branch ---
    // Only the taken branch is evaluated (short-circuit).
    // No boolean type — 0 is falsy, any other integer is truthy.
    If(cond, then_branch, else_branch) => {
      let vc = eval(env, cond, fuel=fuel - 1)
      match vc {
        VInt(0) => eval(env, else_branch, fuel=fuel - 1)
        VInt(_) => eval(env, then_branch, fuel=fuel - 1)
        _ => raise TypeMismatch("if: expected integer condition")
      }
    }
    // --- Application: the heart of the lambda calculus ---
    // 1. Evaluate the function expression to get a closure
    // 2. Evaluate the argument to get a value (strict/call-by-value)
    // 3. Extend the closure's captured environment with the parameter binding
    // 4. Evaluate the closure body in that extended environment
    //
    // Note: we extend the CLOSURE's environment (lexical scoping), not the
    // caller's environment. This is what makes closures work correctly.
    App(func, arg) => {
      let vf = eval(env, func, fuel=fuel - 1)
      let va = eval(env, arg, fuel=fuel - 1)
      match vf {
        VClosure(closure_env, param, body) => {
          let ext = closure_env.extend(param, va)
          eval(ext, body, fuel=fuel - 1)
        }
        _ => raise TypeMismatch("app: expected function")
      }
    }
    // --- Module: sequential let-bindings ---
    // `let x = e1; let y = e2; body` is represented as Module(defs, body).
    // Each definition is evaluated in order, and each binding becomes visible
    // to subsequent definitions (but not earlier ones — no mutual recursion).
    Module(defs, body) => {
      let mut current_env = env
      for def in defs {
        let (name, expr) = def
        let v = eval(current_env, expr, fuel=fuel - 1)
        current_env = current_env.extend(name, v)
      }
      eval(current_env, body, fuel=fuel - 1)
    }
  }
}
