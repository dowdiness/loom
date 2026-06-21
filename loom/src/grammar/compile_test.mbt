///|
test "compile interns string rule refs to dense slots" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Ref("expr"),
    "expr": Expr::Emit(1, 10),
  }
  let compiled = compile(GrammarIr::GrammarIr(rules, root="source"))
  inspect(compiled.root_slot(), content="0")
  match compiled.rule(0) {
    CompiledExpr::RefSlot(1) => ()
    _ => fail("source should point at dense expr slot")
  }
}

///|
test "compile rejects unresolved refs before parsing" {
  let rules : Map[RuleName, Expr[Int, Int]] = { "source": Expr::Ref("missing") }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(MissingRef("missing")) => ()
    _ => fail("expected MissingRef(\"missing\")")
  }
}
