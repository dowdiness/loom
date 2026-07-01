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

///|
test "Native holds only a RuleName and stays structural data" {
  let a : Expr[Int, Int] = Expr::Native("parse_element_with_stack")
  let b : Expr[Int, Int] = Expr::Native("parse_element_with_stack")
  let c : Expr[Int, Int] = Expr::Native("other")
  inspect(a == b, content="true")
  inspect(a == c, content="false")
  match a {
    Expr::Native(name) => inspect(name, content="parse_element_with_stack")
    _ => fail("expected Native")
  }
  inspect(@debug.to_string(a), content="Native(\"parse_element_with_stack\")")
}
