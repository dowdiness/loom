///|
test "GrammarIr stores open string rule namespace" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Ref("expr"),
    "expr": Expr::Empty,
  }
  let ir = GrammarIr::GrammarIr(rules, root="source")
  inspect(ir.root, content="source")
  match ir.rules.get("expr") {
    Some(Expr::Empty) => ()
    _ => fail("expected expr rule")
  }
}

///|
test "IR has no closure predicate escape hatch" {
  let alt : Alt[Int, Int] = Alt::{ starts: Pred::IsToken(1), body: Expr::Empty }
  match alt.starts {
    Pred::IsToken(1) => ()
    _ => fail("expected reified start predicate")
  }
}
