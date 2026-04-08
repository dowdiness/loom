// loom/examples/lambda/src/ast/sym.mbt
//
// This file is the SINGLE SOURCE OF TRUTH for Term's recursive structure.
// Three things live here, and they must stay in sync:
//
//   1. TermSym trait + replay     — tagless final algebra and fold
//   2. children_of                — which fields are recursive children
//   3. rebuild_from               — inverse of children_of
//
// When adding a new Term variant, update all three in this file.
// The roundtrip test in sym_test.mbt verifies: rebuild_from(t, children_of(t)) == t
//
// Other files DELEGATE to these functions:
//   - proj_traits_mechanical.mbt  — TreeNode::children calls children_of
//   - canopy/lang/lambda/proj/    — rebuild_kind calls rebuild_from
//
// See also: docs/architecture/extensible-asts.md

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
  variable(VarName) -> Self
  lam(VarName, Self) -> Self
  app(Self, Self) -> Self
  bop(Bop, Self, Self) -> Self
  if_then_else(Self, Self, Self) -> Self
  mod(Array[(VarName, Self)], Self) -> Self
  unit() -> Self
  /// Name that failed name resolution. Implement as abort() if you only
  /// process well-resolved trees.
  unbound(VarName) -> Self
  /// Parse-error recovery node. Implement as abort() if you only process
  /// syntactically valid trees.
  error_term(String) -> Self
  /// Typed hole placeholder. Implement as abort() if you only process
  /// complete programs.
  hole(Int) -> Self
}

///|
/// Term is the identity interpretation: constructing via TermSym returns Term.
pub impl TermSym for Term with int_lit(n) {
  Int(n)
}

///|
pub impl TermSym for Term with variable(x) {
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
pub impl TermSym for Term with mod(defs, body) {
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
pub impl TermSym for Term with hole(n) {
  Hole(n)
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
pub impl TermSym for Pretty with variable(x) {
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
pub impl TermSym for Pretty with mod(defs, body) {
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
pub impl TermSym for Pretty with hole(_n) {
  { repr: "_" }
}

///|
/// Extracts the immediate child Terms from a variant.
/// This encodes which fields of each constructor are recursive (children)
/// vs non-recursive (data like variable names, operators, literals).
/// Inverse of `rebuild_from`. Source of truth for TreeNode::children.
pub fn children_of(term : Term) -> Array[Term] {
  match term {
    Lam(_, body) => [body]
    App(f, a) => [f, a]
    Bop(_, l, r) => [l, r]
    If(c, t, e) => [c, t, e]
    Module(defs, body) => {
      let result = defs.map(fn(d) { d.1 })
      result.push(body)
      result
    }
    _ => []
  }
}

///|
/// Reconstructs a Term from a shape (for non-child data) and new children.
/// Inverse of `children_of`. Source of truth for rebuild_kind in projection.
/// If `children` has fewer elements than the shape expects, missing positions
/// are filled with `Error("missing")` — this is error-tolerant, not strict.
pub fn rebuild_from(shape : Term, children : Array[Term]) -> Term {
  fn child(i : Int) -> Term {
    if i < children.length() {
      children[i]
    } else {
      Error("missing")
    }
  }

  match shape {
    Lam(param, _) => Lam(param, child(0))
    App(_, _) => App(child(0), child(1))
    Bop(op, _, _) => Bop(op, child(0), child(1))
    If(_, _, _) => If(child(0), child(1), child(2))
    Module(old_defs, _) =>
      if children.length() >= 1 {
        let last = children.length() - 1
        let new_defs : Array[(VarName, Term)] = []
        for i in 0..<last {
          let name = if i < old_defs.length() { old_defs[i].0 } else { "_" }
          new_defs.push((name, children[i]))
        }
        Module(new_defs, children[last])
      } else {
        Module([], Error("missing"))
      }
    _ => shape
  }
}

///|
/// Converts a concrete Term into any TermSym interpretation.
/// This is the single site updated when a new Term variant is added.
/// Callers use type ascription: (replay(term) : Pretty)
pub fn[T : TermSym] replay(term : Term) -> T {
  match term {
    Int(n) => T::int_lit(n)
    Var(x) => T::variable(x)
    Lam(x, body) => T::lam(x, replay(body))
    App(f, a) => T::app(replay(f), replay(a))
    Bop(op, l, r) => T::bop(op, replay(l), replay(r))
    If(c, t, e) => T::if_then_else(replay(c), replay(t), replay(e))
    Module(defs, body) => {
      let mapped : Array[(String, T)] = defs.map(fn(d) { (d.0, replay(d.1)) })
      T::mod(mapped, replay(body))
    }
    Unit => T::unit()
    Unbound(x) => T::unbound(x)
    Error(msg) => T::error_term(msg)
    Hole(n) => T::hole(n)
  }
}
