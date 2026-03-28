// loom/examples/lambda/src/ast/sym.mbt

///|
/// Symantics for lambda calculus: a pub(open) trait whose implementations
/// are interpretations of the language. The name follows Kiselyov's Finally
/// Tagless convention — "Sym" = Symantics (syntax + semantics collapsed).
///
/// Each method corresponds to one Term constructor. Leaf constructors take
/// no Self input and are called as T::method(args) in generic contexts.
/// Branch constructors receive Self inputs from recursive calls.
///
/// pub(open) is required so downstream packages (e-graph, type checker,
/// future languages) can implement this trait without touching this file.
///
/// ## Why unbound and error_term are part of this trait
///
/// Terms always arrive from the parser, which may produce Unbound (a name
/// that failed name resolution) or Error (a recovery node for a parse error).
/// Including them here keeps replay total — every Term value is convertible
/// to any interpretation without a partial match. Interpreters that only
/// run on well-typed trees (e.g. an evaluator after type checking) can
/// implement these two methods as abort().
pub(open) trait TermSym {
  int_lit(Int) -> Self
  var(VarName) -> Self
  lam(VarName, Self) -> Self
  app(Self, Self) -> Self
  bop(Bop, Self, Self) -> Self
  if_then_else(Self, Self, Self) -> Self
  module(Array[(VarName, Self)], Self) -> Self
  unit() -> Self
  /// Name that failed name resolution. Implement as abort() if you only
  /// process well-resolved trees.
  unbound(VarName) -> Self
  /// Parse-error recovery node. Implement as abort() if you only process
  /// syntactically valid trees.
  error_term(String) -> Self
}

///|
/// Term is the identity interpretation: constructing via TermSym returns Term.
pub impl TermSym for Term with int_lit(n) {
  Int(n)
}

///|
pub impl TermSym for Term with var(x) {
  Var(x)
}

///|
pub impl TermSym for Term with lam(x, body) {
  Lam(x, body)
}

///|
pub impl TermSym for Term with app(f, a) {
  App(f, a)
}

///|
pub impl TermSym for Term with bop(op, l, r) {
  Bop(op, l, r)
}

///|
pub impl TermSym for Term with if_then_else(c, t, e) {
  If(c, t, e)
}

///|
pub impl TermSym for Term with module(defs, body) {
  Module(defs, body)
}

///|
pub impl TermSym for Term with unit() {
  Unit
}

///|
pub impl TermSym for Term with unbound(x) {
  Unbound(x)
}

///|
pub impl TermSym for Term with error_term(msg) {
  Error(msg)
}

///|
/// Pretty-printing interpretation: replays a Term as its source text.
/// pub(all) exposes the repr field for cross-package access.
pub(all) struct Pretty {
  repr : String
}

///|
pub impl TermSym for Pretty with int_lit(n) {
  { repr: n.to_string() }
}

///|
pub impl TermSym for Pretty with var(x) {
  { repr: x }
}

///|
pub impl TermSym for Pretty with lam(x, body) {
  { repr: "(λ\{x}. \{body.repr})" }
}

///|
pub impl TermSym for Pretty with app(f, a) {
  { repr: "(\{f.repr} \{a.repr})" }
}

///|
pub impl TermSym for Pretty with bop(op, l, r) {
  let sym = match op {
    Plus => "+"
    Minus => "-"
  }
  { repr: "(\{l.repr} \{sym} \{r.repr})" }
}

///|
pub impl TermSym for Pretty with if_then_else(c, t, e) {
  { repr: "if \{c.repr} then \{t.repr} else \{e.repr}" }
}

///|
pub impl TermSym for Pretty with module(defs, body) {
  let parts : Array[String] = defs.map(fn(d) { "let \{d.0} = \{d.1.repr}" })
  parts.push(body.repr)
  { repr: parts.join("\n") }
}

///|
pub impl TermSym for Pretty with unit() {
  { repr: "()" }
}

///|
pub impl TermSym for Pretty with unbound(x) {
  { repr: "<unbound: \{x}>" }
}

///|
pub impl TermSym for Pretty with error_term(msg) {
  { repr: "<error: \{msg}>" }
}

///|
/// Converts a concrete Term into any TermSym interpretation.
/// This is the single site updated when a new Term variant is added.
/// Callers use type ascription: (replay(term) : Pretty)
pub fn[T : TermSym] replay(term : Term) -> T {
  match term {
    Int(n) => T::int_lit(n)
    Var(x) => T::var(x)
    Lam(x, body) => T::lam(x, replay(body))
    App(f, a) => T::app(replay(f), replay(a))
    Bop(op, l, r) => T::bop(op, replay(l), replay(r))
    If(c, t, e) => T::if_then_else(replay(c), replay(t), replay(e))
    Module(defs, body) => {
      let mapped : Array[(String, T)] = defs.map(fn(d) { (d.0, replay(d.1)) })
      T::module(mapped, replay(body))
    }
    Unit => T::unit()
    Unbound(x) => T::unbound(x)
    Error(msg) => T::error_term(msg)
  }
}
