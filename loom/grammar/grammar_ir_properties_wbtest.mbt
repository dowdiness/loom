//! QuickCheck property tests for GrammarIr.
//!
//! Uses a safe generator (no Ref, no Pred-based nodes) to ensure
//! compile never raises and interpret never loops on empty context.

priv enum QcToken {
  A
  B
  C
  Eof
} derive(Eq, @debug.Debug)

impl @coreqc.Arbitrary for QcToken with arbitrary(_size, rs) {
  match rs.next_positive_int() % 4 {
    0 => A
    1 => B
    2 => C
    _ => Eof
  }
}

impl @qc.Shrink for QcToken with shrink(_self) {
  Iter::empty()
}

impl Show for QcToken with fn output(self, logger) {
  logger.write_string(
    match self {
      A => "A"
      B => "B"
      C => "C"
      Eof => "Eof"
    },
  )
}

impl @seam.IsTrivia for QcToken with fn is_trivia(_self) { false }

impl @seam.IsEof for QcToken with fn is_eof(self) {
  self == QcToken::Eof
}

impl @seam.ToRawKind for QcToken with fn to_raw(self) {
  match self {
    A => @seam.RawKind(1)
    B => @seam.RawKind(2)
    C => @seam.RawKind(3)
    Eof => @seam.RawKind(0)
  }
}

priv enum QcKind {
  Root
  NodeA
  NodeB
  Error
} derive(Eq, @debug.Debug)

impl @coreqc.Arbitrary for QcKind with arbitrary(_size, rs) {
  match rs.next_positive_int() % 4 {
    0 => Root
    1 => NodeA
    2 => NodeB
    _ => Error
  }
}

impl @qc.Shrink for QcKind with shrink(_self) {
  Iter::empty()
}

impl @seam.ToRawKind for QcKind with fn to_raw(self) {
  match self {
    Root => @seam.RawKind(10)
    NodeA => @seam.RawKind(11)
    NodeB => @seam.RawKind(12)
    Error => @seam.RawKind(99)
  }
}


fn gen_expr(size : Int, rs : @splitmix.RandomState) -> Expr[QcToken, QcKind] {
  let tk = fn() { QcToken::arbitrary(0, rs) }
  let kn = fn() { QcKind::arbitrary(0, rs) }
  if size <= 0 {
    match rs.next_positive_int() % 8 {
      0 => Expr::Emit(tk(), kn())
      1 => Expr::Expect(tk(), kn())
      2 => Expr::Fail("f")
      3 => Expr::Empty
      4 => Expr::EmitOr(tk(), kn(), "e")
      _ => Expr::ManualNewlineAppExpr
    }
  } else {
    match rs.next_positive_int() % 8 {
      0 => Expr::Node(kn(), gen_expr(size - 1, rs))
      1 => Expr::Emit(tk(), kn())
      2 => Expr::Expect(tk(), kn())
      3 => Expr::Fail("f")
      4 => Expr::Empty
      5 => Expr::EmitOr(tk(), kn(), "e")
      6 => Expr::Seq([gen_expr(size - 1, rs), gen_expr(size - 1, rs)])
      _ => Expr::EmitError("e")
    }
  }
}

impl @coreqc.Arbitrary for GrammarIr[QcToken, QcKind] with arbitrary(size, rs) {
  let rules : Map[String, Expr[QcToken, QcKind]] = {
    "source": gen_expr(size, rs),
  }
  GrammarIr::GrammarIr(rules, root="source")
}

impl @qc.Shrink for GrammarIr[QcToken, QcKind] with shrink(_self) {
  Iter::empty()
}

fn prop_compile(ir : GrammarIr[QcToken, QcKind]) -> Bool {
  try { let _ = compile(ir); true } catch { _ => false }
}

test "prop_compile_well_formed" {
  @qc.quick_check_fn(prop_compile, max_success=25, max_size=4)
}

test "prop_interpret_no_crash" {
  fn prop(ir : GrammarIr[QcToken, QcKind]) -> Bool {
    let pr = try {
      interpret(ir)
    } catch {
      _ => return true
    }
    let spec = @core.LanguageSpec::new(
      QcKind::Root,
      QcKind::Error,
      QcKind::Root,
      QcToken::Eof,
      parse_root=pr,
    )
    let ctx = @core.ParserContext::new(
      [@core.TokenInfo::new(QcToken::Eof, 0)],
      "",
      spec,
    )
    try {
      pr(ctx)
      true
    } catch {
      _ => false
    }
  }
  @qc.quick_check_fn(prop, max_success=15, max_size=3)
}
