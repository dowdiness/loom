///|
test "GrammarIr stores open string rule namespace" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Ref("expr"),
    "expr": @grammar.Expr::Empty,
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  inspect(ir.root, content="source")
  match ir.rules.get("expr") {
    Some(@grammar.Expr::Empty) => ()
    _ => fail("expected expr rule")
  }
}

///|
test "IR has no closure predicate escape hatch" {
  let alt : @grammar.Alt[Int, Int] = @grammar.Alt::{
    starts: @grammar.Pred::IsToken(1),
    body: @grammar.Expr::Empty,
  }
  match alt.starts {
    @grammar.Pred::IsToken(1) => ()
    _ => fail("expected reified start predicate")
  }
}

///|
test "Native holds only a RuleName and stays structural data" {
  let a : @grammar.Expr[Int, Int] = @grammar.Expr::Native(
    "parse_element_with_stack",
  )
  let b : @grammar.Expr[Int, Int] = @grammar.Expr::Native(
    "parse_element_with_stack",
  )
  let c : @grammar.Expr[Int, Int] = @grammar.Expr::Native("other")
  inspect(a == b, content="true")
  inspect(a == c, content="false")
  match a {
    @grammar.Expr::Native(name) =>
      inspect(name, content="parse_element_with_stack")
    _ => fail("expected Native")
  }
  inspect(@debug.to_string(a), content="Native(\"parse_element_with_stack\")")
}
