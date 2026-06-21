///|
test "minimal grammar IR exposes rules" {
  let ir = GrammarIr::{
    source: Expr::Empty,
    definition: Expr::Empty,
    expression: Expr::Empty,
    binary: Expr::Empty,
    application: Expr::Empty,
    atom: Expr::Empty,
    param_list: Expr::Empty,
  }
  match ir.rule(RuleId::Source) {
    Expr::Empty => ()
    _ => fail("expected Empty rule")
  }
}
