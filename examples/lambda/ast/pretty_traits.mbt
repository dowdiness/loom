///|
/// Source trait: compact parseable text that roundtrips through the parser.
/// Delegates to the SourceText TermSym interpretation via interpret.
pub impl @pretty.Source for Term with fn to_source(self) {
  print_term(self)
}

// Precedence levels for parenthesization (higher = tighter binding).
// Standard ML/lambda convention: application binds tighter than operators.
//   top (0) < if (1) < lam (2) < bop (3) < app (4) < atom (5)
// wrap_if_needed adds parens when a child's precedence is lower than
// the context requires (e.g., lambda inside application position).

///|
let prec_top : Int = 0

///|
let prec_if : Int = 1

///|
let prec_lam : Int = 2

///|
let prec_bop : Int = 3

///|
let prec_app : Int = 4

///|
let prec_atom : Int = 5

///|
/// SourceText: compact, minimal-parenthesized source-text interpretation.
/// Named `SourceText` (not `Source`) to avoid colliding with the `@pretty.Source`
/// trait that `Term` implements. Mirrors `PrettyLayout`'s precedence discipline:
/// each node reports its own `prec`; the parent wraps a child via `wrap_source`.
pub struct SourceText {
  repr : String
  prec : Int
}

///|
fn wrap_source(child : SourceText, ctx_prec : Int) -> String {
  if child.prec < ctx_prec {
    "(" + child.repr + ")"
  } else {
    child.repr
  }
}

///|
/// Single source of truth for binary-operator spelling, shared by both the
/// SourceText and PrettyLayout `bop` impls so a new operator (or a renamed
/// symbol) is updated in exactly one place.
fn bop_sym(op : Bop) -> String {
  match op {
    Plus => "+"
    Minus => "-"
  }
}

///|
pub impl TermSym for SourceText with fn int_lit(n) {
  { repr: n.to_string(), prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn variable(x) {
  { repr: x, prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn lam(x, body) {
  { repr: "(" + x + ") => " + body.repr, prec: prec_lam }
}

///|
pub impl TermSym for SourceText with fn app(f, a) {
  {
    repr: wrap_source(f, prec_app) + " " + wrap_source(a, prec_atom),
    prec: prec_app,
  }
}

///|
pub impl TermSym for SourceText with fn bop(op, l, r) {
  let sym = bop_sym(op)
  {
    repr: wrap_source(l, prec_bop) +
    " " +
    sym +
    " " +
    wrap_source(r, prec_bop + 1),
    prec: prec_bop,
  }
}

///|
pub impl TermSym for SourceText with fn if_then_else(c, t, e) {
  {
    repr: "if " + c.repr + " then " + t.repr + " else " + e.repr,
    prec: prec_if,
  }
}

///|
pub impl TermSym for SourceText with fn let_def(name, init) {
  { repr: "let " + name + " = " + init.repr, prec: prec_top }
}

///|
pub impl TermSym for SourceText with fn mod(defs, body) {
  let parts = [..defs.map(d => "let " + d.0 + " = " + d.1.repr), body.repr]
  { repr: "{ " + parts.join("\n") + " }", prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn unit() {
  { repr: "()", prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn unbound(x) {
  { repr: "<unbound: " + x + ">", prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn error_term(msg) {
  { repr: "<error: " + msg + ">", prec: prec_atom }
}

///|
pub impl TermSym for SourceText with fn hole(_n) {
  { repr: "_", prec: prec_atom }
}

///|
/// PrettyLayout: TermSym interpretation producing Layout[SyntaxCategory].
pub struct PrettyLayout {
  layout : @pretty.Layout[@pretty.SyntaxCategory]
  prec : Int
}

// Convention: all leaf text goes through a named wrapper (kw, ident, num,
// op_text, punc, err_text) so every token carries a SyntaxCategory annotation.
// To add new syntax, add a wrapper or use an existing one — never call
// @pretty.text directly for tokens that should be highlighted.

///|
fn tagged(
  cat : @pretty.SyntaxCategory,
  s : String,
) -> @pretty.Layout[@pretty.SyntaxCategory] {
  @pretty.annotate(cat, @pretty.text(s))
}

///|
fn kw(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  tagged(@pretty.SyntaxCategory::Keyword, s)
}

///|
fn ident(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  tagged(@pretty.SyntaxCategory::Identifier, s)
}

///|
fn num(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  tagged(@pretty.SyntaxCategory::Number, s)
}

///|
fn op_text(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  tagged(@pretty.SyntaxCategory::Operator, s)
}

///|
fn punc(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  tagged(@pretty.SyntaxCategory::Punctuation, s)
}

///|
fn err_text(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  tagged(@pretty.SyntaxCategory::Error, s)
}

///|
fn wrap_if_needed(
  child : PrettyLayout,
  ctx_prec : Int,
) -> @pretty.Layout[@pretty.SyntaxCategory] {
  if child.prec < ctx_prec {
    punc("(") + child.layout + punc(")")
  } else {
    child.layout
  }
}

///|
fn term_to_source(term : Term) -> String {
  (interpret(term) : SourceText).repr
}

///|
pub impl TermSym for PrettyLayout with fn int_lit(n) {
  { layout: num(n.to_string()), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with fn variable(name) {
  { layout: ident(name), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with fn unit() {
  { layout: punc("()"), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with fn lam(x, body) {
  {
    layout: @pretty.group(
      punc("(") +
      ident(x) +
      punc(")") +
      @pretty.text(" ") +
      op_text("=>") +
      @pretty.nest(@pretty.line() + body.layout),
    ),
    prec: prec_lam,
  }
}

///|
pub impl TermSym for PrettyLayout with fn app(f, arg) {
  {
    layout: @pretty.group(
      wrap_if_needed(f, prec_app) +
      @pretty.nest(@pretty.line() + wrap_if_needed(arg, prec_atom)),
    ),
    prec: prec_app,
  }
}

///|
pub impl TermSym for PrettyLayout with fn bop(b, l, r) {
  let sym = bop_sym(b)
  {
    layout: @pretty.group(
      wrap_if_needed(l, prec_bop) +
      @pretty.text(" ") +
      op_text(sym) +
      @pretty.nest(@pretty.line() + wrap_if_needed(r, prec_bop + 1)),
    ),
    prec: prec_bop,
  }
}

///|
pub impl TermSym for PrettyLayout with fn if_then_else(cond, then_, else_) {
  {
    layout: @pretty.group(
      kw("if") +
      @pretty.text(" ") +
      cond.layout +
      @pretty.nest(
        @pretty.line() +
        kw("then") +
        @pretty.text(" ") +
        then_.layout +
        @pretty.line() +
        kw("else") +
        @pretty.text(" ") +
        else_.layout,
      ),
    ),
    prec: prec_if,
  }
}

///|
pub impl TermSym for PrettyLayout with fn let_def(name, init) {
  {
    layout: @pretty.group(
      kw("let") +
      @pretty.text(" ") +
      ident(name) +
      @pretty.text(" ") +
      op_text("=") +
      @pretty.text(" ") +
      @pretty.nest(init.layout),
    ),
    prec: prec_top,
  }
}

///|
pub impl TermSym for PrettyLayout with fn mod(defs, body) {
  let def_layouts : Array[@pretty.Layout[@pretty.SyntaxCategory]] = defs.map(fn(
    d,
  ) {
    let (name, val) = d
    @pretty.group(
      kw("let") +
      @pretty.text(" ") +
      ident(name) +
      @pretty.text(" ") +
      op_text("=") +
      @pretty.text(" ") +
      @pretty.nest(val.layout),
    )
  })
  let defs_doc = @pretty.separate(@pretty.hardline(), def_layouts)
  let contents = if def_layouts.is_empty() {
    body.layout
  } else {
    defs_doc + @pretty.hardline() + body.layout
  }
  {
    layout: @pretty.group(
      punc("{") +
      @pretty.nest(@pretty.line() + contents) +
      @pretty.line() +
      punc("}"),
    ),
    prec: prec_atom,
  }
}

///|
pub impl TermSym for PrettyLayout with fn unbound(name) {
  { layout: err_text("<unbound: " + name + ">"), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with fn error_term(msg) {
  { layout: err_text("<error: " + msg + ">"), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with fn hole(_n) {
  { layout: err_text("_"), prec: prec_atom }
}

///|
/// Pretty trait: width-aware formatted layout with syntax annotations.
pub impl @pretty.Pretty for Term with fn to_layout(self) {
  (interpret(self) : PrettyLayout).layout
}

///|
pub impl @pretty.Printable for Term
