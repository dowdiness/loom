///|
/// MoonBit-source AST for the grammar emitter. Only the expression types
/// needed by `emit_grammar_ir.mbt` to construct GrammarIr data literals.
/// Rendered to breakable layouts via `dowdiness/pretty`.
///
/// The 6 remaining variants (Var, StrLit, Call, Tuple, Array, Record) are
/// the only ones `emit_grammar_ir.mbt` constructs. Other variants were
/// removed together with the parser code generator (`emit_grammar.mbt`).

pub enum MbtExpr {
  Var(String)
  StrLit(String)
  Call(String, Array[MbtExpr])
  Tuple(Array[MbtExpr])
  Array(Array[MbtExpr])
  Record(String, Array[(String, MbtExpr)])
} derive(Eq, Debug)

// ── annotation helper ──────────────────────────────────────────────

fn ident(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  @pretty.annotate(@pretty.SyntaxCategory::Identifier, @pretty.text(s))
}

// ── Breakable layout for deeply nested expressions ─────────────────

/// Render MbtExpr to a Layout that uses hardline breaks at every
/// Call/Array boundary, producing multi-line output suitable for
/// deeply nested constructor expressions (e.g. grammar-ir rules).
pub fn MbtExpr::to_breakable_layout(
  self : MbtExpr,
) -> @pretty.Layout[@pretty.SyntaxCategory] {
  match self {
    Var(name) => ident(name)
    StrLit(s) =>
      @pretty.annotate(@pretty.SyntaxCategory::StringLit, @pretty.text(s))
    Call(name, args) =>
      if args.length() == 0 {
        ident(name)
      } else {
        let arg_layouts = args.map(fn(a : MbtExpr) { a.to_breakable_layout() })
        ident(name) +
        @pretty.text("(") +
        @pretty.nest(
          @pretty.hardline() +
          @pretty.separate(
            @pretty.hardline(),
            arg_layouts.map(fn(l) { l + @pretty.text(",") }),
          ),
        ) +
        @pretty.hardline() +
        @pretty.text(")")
      }
    Tuple(items) =>
      @pretty.parens(
        @pretty.separate(
          @pretty.text(", "),
          items.map(fn(e : MbtExpr) { e.to_breakable_layout() }),
        ),
      )
    Array(items) => {
      let layouts = items.map(fn(e : MbtExpr) {
        e.to_breakable_layout() + @pretty.text(",")
      })
      @pretty.text("[") +
      @pretty.nest(
        @pretty.hardline() + @pretty.separate(@pretty.hardline(), layouts),
      ) +
      @pretty.hardline() +
      @pretty.text("]")
    }
    Record(type_name, fields) => {
      let field_layouts = fields.map(fn(f : (String, MbtExpr)) {
        let (name, expr) = f
        ident(name) +
        @pretty.text(": ") +
        expr.to_breakable_layout() +
        @pretty.text(",")
      })
      @pretty.text(type_name) +
      @pretty.text("::{") +
      @pretty.nest(
        @pretty.hardline() + @pretty.separate(@pretty.hardline(), field_layouts),
      ) +
      @pretty.hardline() +
      @pretty.char('}')
    }
  }
}
