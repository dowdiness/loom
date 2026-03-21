///|
test "debug output - simple" {
  let term : Term = App(Lam("x", Var("x")), Int(42))
  inspect(
    @debug.to_string(term),
    content=(
      #|App(Lam("x", Var("x")), Int(42))
    ),
  )
}

///|
test "debug output - complex nested" {
  // let f = λx. x + 1 in f 2
  let term : Term = Module([
    ModuleItem::Def("f", Lam("x", Bop(Plus, Var("x"), Int(1)))),
    ModuleItem::Expr(App(Var("f"), Int(2))),
  ])
  inspect(
    @debug.to_string(term),
    content=(
      #|Module(
      #|  [
      #|    Def("f", Lam("x", Bop(Plus, Var("x"), Int(1)))),
      #|    Expr(App(Var("f"), Int(2))),
      #|  ],
      #|)
    ),
  )
}
