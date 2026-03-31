///|
/// Source trait: compact parseable text that roundtrips through the parser.
/// Delegates to the existing Pretty TermSym interpretation.
pub impl @pretty.Source for Term with to_source(self) {
  print_term(self)
}

///|
/// Precedence levels for parenthesization.
/// Higher number = tighter binding.
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
pub impl TermSym for PrettyLayout with int_lit(n) {
  { layout: num(n.to_string()), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with var(name) {
  { layout: ident(name), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with unit() {
  { layout: punc("()"), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with lam(x, body) {
  {
    layout: @pretty.group(
      kw("λ") +
      ident(x) +
      punc(".") +
      @pretty.nest(@pretty.line() + body.layout),
    ),
    prec: prec_lam,
  }
}

///|
pub impl TermSym for PrettyLayout with app(f, arg) {
  {
    layout: @pretty.group(
      wrap_if_needed(f, prec_app) +
      @pretty.nest(@pretty.line() + wrap_if_needed(arg, prec_atom)),
    ),
    prec: prec_app,
  }
}

///|
pub impl TermSym for PrettyLayout with bop(b, l, r) {
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
pub impl TermSym for PrettyLayout with if_then_else(cond, then_, else_) {
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
pub impl TermSym for PrettyLayout with module(defs, body) {
  let def_layouts : Array[@pretty.Layout[@pretty.SyntaxCategory]] = defs.map(
    fn(d) {
      let (name, val) = d
      kw("let") +
      @pretty.text(" ") +
      ident(name) +
      @pretty.text(" ") +
      op_text("=") +
      @pretty.text(" ") +
      @pretty.nest(val.layout)
    },
  )
  let defs_doc = @pretty.separate(@pretty.hardline(), def_layouts)
  let result = if def_layouts.is_empty() {
    body.layout
  } else {
    defs_doc + @pretty.hardline() + body.layout
  }
  { layout: result, prec: prec_top }
}

///|
pub impl TermSym for PrettyLayout with unbound(name) {
  { layout: err_text("<unbound: " + name + ">"), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with error_term(msg) {
  { layout: err_text("<error: " + msg + ">"), prec: prec_atom }
}

///|
pub impl TermSym for PrettyLayout with hole(_n) {
  { layout: err_text("_"), prec: prec_atom }
}

///|
/// Pretty trait: width-aware formatted layout with syntax annotations.
pub impl @pretty.Pretty for Term with to_layout(self) {
  let pl : PrettyLayout = replay(self)
  pl.layout
}

///|
pub impl @pretty.Printable for Term
