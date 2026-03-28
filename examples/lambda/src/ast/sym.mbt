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
pub(open) trait TermSym {
  int_lit(Int) -> Self
  var(VarName) -> Self
  lam(VarName, Self) -> Self
  app(Self, Self) -> Self
  bop(Bop, Self, Self) -> Self
  if_then_else(Self, Self, Self) -> Self
  module(Array[(VarName, Self)], Self) -> Self
  unit() -> Self
  unbound(VarName) -> Self
  error_term(String) -> Self
}

///|
/// Term is the identity interpretation: constructing via TermSym returns Term.
pub impl TermSym for Term with int_lit(n) { Int(n) }

///|
pub impl TermSym for Term with var(x) { Var(x) }

///|
pub impl TermSym for Term with lam(x, body) { Lam(x, body) }

///|
pub impl TermSym for Term with app(f, a) { App(f, a) }

///|
pub impl TermSym for Term with bop(op, l, r) { Bop(op, l, r) }

///|
pub impl TermSym for Term with if_then_else(c, t, e) { If(c, t, e) }

///|
pub impl TermSym for Term with module(defs, body) { Module(defs, body) }

///|
pub impl TermSym for Term with unit() { Unit }

///|
pub impl TermSym for Term with unbound(x) { Unbound(x) }

///|
pub impl TermSym for Term with error_term(msg) { Error(msg) }
