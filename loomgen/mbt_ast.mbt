///|
/// MoonBit-source AST for the grammar emitter. Covers only what
/// `emit_compiled_expr` and `emit_grammar` produce — not a general-purpose
/// MoonBit AST. Rendered via `dowdiness/pretty`.

///|
pub(all) struct MbtModule {
  native_comments : Array[String]
  parser_context : String
  fns : Array[MbtFnDecl]
} derive(Eq, Debug)

///|
pub(all) struct MbtFnDecl {
  pub_fn : Bool
  name : String
  params : Array[MbtParam]
  return_type : String
  body : MbtBlock
} derive(Eq, Debug)

///|
pub(all) struct MbtParam {
  name : String
  type_ : String
} derive(Eq, Debug)

///|
pub(all) struct MbtBlock {
  stmts : Array[MbtStmt]
} derive(Eq, Debug)

///|
pub(all) enum MbtStmt {
  Let(String, MbtExpr)
  ExprStmt(MbtExpr)
  If(MbtExpr, MbtBlock, Array[MbtElseBranch])
  While(MbtExpr, MbtBlock)
} derive(Eq, Debug)


///|
pub(all) enum MbtElseBranch {
  ElseIf(MbtExpr, MbtBlock)
  Else(MbtBlock)
} derive(Eq, Debug)

///|
pub(all) enum MbtExpr {
  Var(String)
  Bool(Bool)
  StrLit(String)
  Call(String, Array[MbtExpr])
  MethodCall(MbtExpr, String, Array[MbtExpr])
  FieldAccess(MbtExpr, String)
  Pipe(MbtExpr, MbtExpr)
  BinOp(MbtExpr, String, MbtExpr)
  UnOp(String, MbtExpr)
  Block(MbtBlock)
  Closure(Array[MbtParam], MbtBlock)
  Array(Array[MbtExpr])
  Tuple(Array[MbtExpr])
  Match(MbtExpr, Array[MbtMatchArm])
  Continue
  Break
} derive(Eq, Debug)

///|
pub(all) struct MbtMatchArm {
  pat : MbtPat
  body : MbtExpr
} derive(Eq, Debug)

///|
pub(all) enum MbtPat {
  Wildcard
  Bind(String)
  Constructor(String, MbtPat)
} derive(Eq, Debug)

// ── annotation helpers ───────────────────────────────────────────

///|
fn kw(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  @pretty.annotate(@pretty.SyntaxCategory::Keyword, @pretty.text(s))
}

///|
fn ident(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  @pretty.annotate(@pretty.SyntaxCategory::Identifier, @pretty.text(s))
}

///|
fn punc(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  @pretty.annotate(@pretty.SyntaxCategory::Punctuation, @pretty.text(s))
}

///|
fn op(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  @pretty.annotate(@pretty.SyntaxCategory::Operator, @pretty.text(s))
}

// ── Pretty for MbtModule ─────────────────────────────────────────

pub impl @pretty.Pretty for MbtModule with fn to_layout(self) -> @pretty.Layout[@pretty.SyntaxCategory] {
  let docs : Array[@pretty.Layout[@pretty.SyntaxCategory]] = []
  // Native comment block (starts and ends with ///|, serves as parse_root's doc)
  if self.native_comments.length() > 0 {
    let comment_lines : Array[@pretty.Layout[@pretty.SyntaxCategory]] =
      [@pretty.text("///|")]
    for c in self.native_comments {
      let line = @pretty.text("/// consumers must hand-write `fn ") +
        @pretty.text(c) +
        @pretty.text("(ctx : ") +
        @pretty.text(self.parser_context) +
        @pretty.text(") -> Unit` in this file's package.")
      comment_lines.push(line)
    }
    comment_lines.push(@pretty.text("///|"))
    docs.push(@pretty.separate(@pretty.hardline(), comment_lines))
  } else {
    // Without natives, ///| serves directly as parse_root's doc-comment
    docs.push(@pretty.text("///|"))
  }
  // First function (parse_root) — no extra ///| needed
  if self.fns.length() > 0 {
    docs.push(self.fns[0].to_layout())
  }
  // Remaining functions (rules) — each preceded by ///| and blank line
  for i in 1..<self.fns.length() {
    docs.push(@pretty.text(""))
    docs.push(@pretty.text("///|"))
    docs.push(self.fns[i].to_layout())
  }
  @pretty.separate(@pretty.hardline(), docs)
}

// ── Pretty for MbtFnDecl ─────────────────────────────────────────

///|
pub impl @pretty.Pretty for MbtFnDecl with fn to_layout(self) -> @pretty.Layout[@pretty.SyntaxCategory] {
  let mut header : @pretty.Layout[@pretty.SyntaxCategory] = @pretty.empty()
  if self.pub_fn {
    header = kw("pub") + @pretty.text(" ") + kw("fn")
  } else {
    header = kw("fn")
  }
  let param_layout = parens_layout(self.params)
  header =
    header + @pretty.text(" ") + ident(self.name) + param_layout + @pretty.text(" ") + op("->") + @pretty.text(" ") +
    @pretty.text(self.return_type)
  header + @pretty.text(" ") + @pretty.char('{') + @pretty.nest(@pretty.hardline() + self.body.to_layout()) +
    @pretty.hardline() + @pretty.char('}')
}

// ── Pretty for MbtBlock ──────────────────────────────────────────

///|
pub impl @pretty.Pretty for MbtBlock with fn to_layout(self) -> @pretty.Layout[@pretty.SyntaxCategory] {
  let doc_layouts = self.stmts.map(fn(s) { s.to_layout() })
  @pretty.separate(@pretty.hardline(), doc_layouts)
}

// ── Pretty for MbtStmt ───────────────────────────────────────────

///|
pub impl @pretty.Pretty for MbtStmt with fn to_layout(self) -> @pretty.Layout[@pretty.SyntaxCategory] {
  match self {
    Let(name, expr) =>
      @pretty.group(
        kw("let") + @pretty.text(" ") + ident(name) + @pretty.text(" ") + op("=") + @pretty.text(" ") + expr.to_layout(),
      )
    ExprStmt(expr) => expr.to_layout()
    If(cond, then_blk, else_chain) => {
      let mut result = kw("if") + @pretty.text(" ") + @pretty.group(cond.to_layout()) + @pretty.text(" ") + blk_layout(then_blk)
      for el in else_chain {
        result = result + @pretty.text(" ") + el.to_layout()
      }
      result
    }
    While(cond, body) =>
      kw("while") + @pretty.text(" ") + @pretty.group(cond.to_layout()) + @pretty.text(" ") + blk_layout(body)
  }
}

// ── Pretty for MbtElseBranch ─────────────────────────────────────

///|
pub impl @pretty.Pretty for MbtElseBranch with fn to_layout(self) -> @pretty.Layout[@pretty.SyntaxCategory] {
  match self {
    ElseIf(cond, blk) =>
      kw("else") + @pretty.text(" ") + kw("if") + @pretty.text(" ") + @pretty.group(cond.to_layout()) + @pretty.text(" ") +
      blk_layout(blk)
    Else(blk) => kw("else") + @pretty.text(" ") + blk_layout(blk)
  }
}

// ── Pretty for MbtExpr ───────────────────────────────────────────

///|
pub impl @pretty.Pretty for MbtExpr with fn to_layout(self) -> @pretty.Layout[@pretty.SyntaxCategory] {
  match self {
    Var(name) => ident(name)
    Bool(b) => if b { kw("true") } else { kw("false") }
    StrLit(s) => @pretty.annotate(
      @pretty.SyntaxCategory::StringLit,
      @pretty.text(s),
    )
    Call(name, args) => {
      let arg_layouts = args.map(fn(a) { a.to_layout() })
      ident(name) + @pretty.parens(@pretty.separate(@pretty.text(", "), arg_layouts))
    }
    MethodCall(obj, name, args) => {
      let arg_layouts = args.map(fn(a) { a.to_layout() })
      obj.to_layout() + punc(".") + ident(name) + @pretty.parens(@pretty.separate(@pretty.text(", "), arg_layouts))
    }
    FieldAccess(obj, field) =>
      obj.to_layout() + punc(".") + @pretty.text(field)
    Pipe(left, right) =>
      left.to_layout() + @pretty.text(" ") + op("|>") + @pretty.text(" ") + right.to_layout()
    BinOp(lhs, s, rhs) => {
      let op_layout = match s {
        "==" | "!=" | "<" | ">" | "<=" | ">=" | "+" | "-" | "*" | "/" | "&&" | "||" =>
          @pretty.text(" ") + op(s) + @pretty.text(" ")
        _ => @pretty.text(" ") + op(s) + @pretty.text(" ")
      }
      // group so binary ops have a chance to break
      @pretty.group(lhs.to_layout() + op_layout + rhs.to_layout())
    }
    UnOp(s, expr) => {
      let inner = expr.to_layout()
      // Need parens when the inner expression is a BinOp to ensure correct
      // negation precedence: `!(a == b)` not `!a == b`
      let wrapped = match expr {
        BinOp(_, _, _) => punc("(") + inner + punc(")")
        _ => inner
      }
      op(s) + @pretty.group(wrapped)
    }
    Block(blk) => @pretty.char('{') + @pretty.nest(@pretty.hardline() + blk.to_layout()) + @pretty.hardline() + @pretty.char('}')
    Closure(params, body) => {
      let param_layout = parens_layout(params)
      @pretty.group(
        kw("fn") + param_layout + @pretty.text(" ") + @pretty.char('{') +
          @pretty.nest(@pretty.line() + body.to_layout()) + @pretty.line() + @pretty.char('}'),
      )
    }
    Array(items) =>
      @pretty.brackets(@pretty.separate(@pretty.text(", "), items.map(fn(e) { e.to_layout() })))
    Tuple(items) =>
      @pretty.parens(@pretty.separate(@pretty.text(", "), items.map(fn(e) { e.to_layout() })))
    Match(scrutinee, arms) => {
      let arm_layouts = arms.map(fn(arm) { arm.to_layout() })
      kw("match") + @pretty.text(" ") + scrutinee.to_layout() + @pretty.text(" ") + @pretty.char('{') +
        @pretty.nest(@pretty.hardline() + @pretty.separate(@pretty.hardline(), arm_layouts)) + @pretty.hardline() + @pretty.char('}')
    }
    Continue => kw("continue")

    Break => kw("break")
  }
}

// ── Pretty for MbtMatchArm ───────────────────────────────────────

///|
pub impl @pretty.Pretty for MbtMatchArm with fn to_layout(self) -> @pretty.Layout[@pretty.SyntaxCategory] {
  self.pat.to_layout() + @pretty.text(" ") + op("=>") + @pretty.text(" ") + self.body.to_layout()
}

// ── Pretty for MbtPat ──────────────────────────────────────────

///|
pub impl @pretty.Pretty for MbtPat with fn to_layout(self) -> @pretty.Layout[@pretty.SyntaxCategory] {
  match self {
    Wildcard => punc("_")
    Bind(name) => ident(name)
    Constructor(name, inner) =>
      ident(name) + parens_flat(inner.to_layout())
  }
}

// ── layout helpers ───────────────────────────────────────────────

///|
fn blk_layout(blk : MbtBlock) -> @pretty.Layout[@pretty.SyntaxCategory] {
  @pretty.char('{') + @pretty.nest(@pretty.hardline() + blk.to_layout()) + @pretty.hardline() + @pretty.char('}')
}

///|
fn parens_layout(params : Array[MbtParam]) -> @pretty.Layout[@pretty.SyntaxCategory] {
  let layouts = params.map(fn(p) {
    if p.type_.length() > 0 {
      ident(p.name) + @pretty.text(" : ") + @pretty.text(p.type_)
    } else {
      ident(p.name)
    }
  })
  punc("(") + @pretty.separate(@pretty.text(", "), layouts) + punc(")")
}


///|
fn parens_flat(inner : @pretty.Layout[@pretty.SyntaxCategory]) -> @pretty.Layout[@pretty.SyntaxCategory] {
  punc("(") + inner + punc(")")
}
