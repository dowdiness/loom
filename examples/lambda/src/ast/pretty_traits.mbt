///|
/// Source trait: compact parseable text that roundtrips through the parser.
/// Delegates to the existing Pretty TermSym interpretation.
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
fn collect_lambda_params(term : Term) -> (Array[String], Term) {
  match term {
    Lam(param, body) => {
      let (rest, inner) = collect_lambda_params(body)
      let params = [param]
      for p in rest {
        params.push(p)
      }
      (params, inner)
    }
    _ => ([], term)
  }
}

///|
fn params_to_source(params : Array[String]) -> String {
  "(" + params.join(", ") + ")"
}

///|
fn def_to_source(name : String, init : Term) -> String {
  let (params, body) = collect_lambda_params(init)
  if params.is_empty() {
    "let " + name + " = " + term_to_source(init)
  } else {
    "fn " +
    name +
    params_to_source(params) +
    " { " +
    term_to_source(body) +
    " }"
  }
}

///|
fn term_to_source_with_prec(term : Term, ctx_prec : Int) -> String {
  let text = match term {
    Int(n) => n.to_string()
    Var(name) => name
    Lam(_, _) => {
      let (params, body) = collect_lambda_params(term)
      params_to_source(params) +
      " => " +
      term_to_source_with_prec(body, prec_lam)
    }
    App(f, arg) =>
      "(" +
      term_to_source_with_prec(f, prec_app) +
      " " +
      term_to_source_with_prec(arg, prec_atom) +
      ")"
    Bop(op, left, right) => {
      let sym = match op {
        Plus => "+"
        Minus => "-"
      }
      "(" +
      term_to_source_with_prec(left, prec_bop) +
      " " +
      sym +
      " " +
      term_to_source_with_prec(right, prec_bop + 1) +
      ")"
    }
    If(cond, then_, else_) =>
      "if " +
      term_to_source(cond) +
      " then " +
      term_to_source(then_) +
      " else " +
      term_to_source(else_)
    LetDef(name, init) => def_to_source(name, init)
    Module(defs, body) => {
      let parts = defs.map(fn(d) { def_to_source(d.0, d.1) })
      parts.push(term_to_source(body))
      parts.join("\n")
    }
    Unit => "()"
    Unbound(name) => "<unbound: " + name + ">"
    Error(msg) => "<error: " + msg + ">"
    Hole(_) => "_"
  }
  let prec = match term {
    Lam(_, _) => prec_lam
    If(_, _, _) => prec_if
    Bop(_, _, _) => prec_bop
    App(_, _) => prec_app
    Int(_) | Var(_) | Unit | Unbound(_) | Error(_) | Hole(_) => prec_atom
    LetDef(_, _) | Module(_, _) => prec_top
  }
  if prec < ctx_prec {
    "(" + text + ")"
  } else {
    text
  }
}

///|
fn term_to_source(term : Term) -> String {
  term_to_source_with_prec(term, prec_top)
}

///|
fn params_to_layout(
  params : Array[String],
) -> @pretty.Layout[@pretty.SyntaxCategory] {
  @pretty.separate(punc(",") + @pretty.text(" "), params.map(ident))
}

///|
fn def_to_layout(
  name : String,
  init : Term,
) -> @pretty.Layout[@pretty.SyntaxCategory] {
  let (params, body) = collect_lambda_params(init)
  if params.is_empty() {
    @pretty.group(
      kw("let") +
      @pretty.text(" ") +
      ident(name) +
      @pretty.text(" ") +
      op_text("=") +
      @pretty.text(" ") +
      term_to_pretty_layout(init).layout,
    )
  } else {
    let body_layout = term_to_pretty_layout(body).layout
    @pretty.group(
      kw("fn") +
      @pretty.text(" ") +
      ident(name) +
      punc("(") +
      params_to_layout(params) +
      punc(")") +
      @pretty.text(" ") +
      punc("{") +
      @pretty.nest(@pretty.line() + body_layout) +
      @pretty.line() +
      punc("}"),
    )
  }
}

///|
fn term_to_pretty_layout(term : Term) -> PrettyLayout {
  match term {
    Int(n) => PrettyLayout::int_lit(n)
    Var(name) => PrettyLayout::variable(name)
    Lam(_, _) => {
      let (params, body) = collect_lambda_params(term)
      let body_layout = term_to_pretty_layout(body)
      {
        layout: @pretty.group(
          punc("(") +
          params_to_layout(params) +
          punc(")") +
          @pretty.text(" ") +
          op_text("=>") +
          @pretty.nest(@pretty.line() + body_layout.layout),
        ),
        prec: prec_lam,
      }
    }
    App(f, arg) =>
      PrettyLayout::app(term_to_pretty_layout(f), term_to_pretty_layout(arg))
    Bop(op, left, right) =>
      PrettyLayout::bop(
        op,
        term_to_pretty_layout(left),
        term_to_pretty_layout(right),
      )
    If(cond, then_, else_) =>
      PrettyLayout::if_then_else(
        term_to_pretty_layout(cond),
        term_to_pretty_layout(then_),
        term_to_pretty_layout(else_),
      )
    LetDef(name, init) => { layout: def_to_layout(name, init), prec: prec_top }
    Module(defs, body) => {
      let def_layouts = defs.map(fn(d) { def_to_layout(d.0, d.1) })
      let defs_doc = @pretty.separate(@pretty.hardline(), def_layouts)
      let body_doc = term_to_pretty_layout(body).layout
      let layout = if def_layouts.is_empty() {
        body_doc
      } else {
        defs_doc + @pretty.hardline() + body_doc
      }
      { layout, prec: prec_top }
    }
    Unit => PrettyLayout::unit()
    Unbound(name) => PrettyLayout::unbound(name)
    Error(msg) => PrettyLayout::error_term(msg)
    Hole(n) => PrettyLayout::hole(n)
  }
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
  let sym = match b {
    Plus => "+"
    Minus => "-"
  }
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
    kw("let") +
    @pretty.text(" ") +
    ident(name) +
    @pretty.text(" ") +
    op_text("=") +
    @pretty.text(" ") +
    @pretty.nest(val.layout)
  })
  let defs_doc = @pretty.separate(@pretty.hardline(), def_layouts)
  let result = if def_layouts.is_empty() {
    body.layout
  } else {
    defs_doc + @pretty.hardline() + body.layout
  }
  { layout: result, prec: prec_top }
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
  let pl = term_to_pretty_layout(self)
  pl.layout
}

///|
pub impl @pretty.Printable for Term
